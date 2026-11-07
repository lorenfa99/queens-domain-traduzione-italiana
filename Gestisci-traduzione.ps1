[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action = 'Install',
    [string]$GamePath,
    [switch]$NonInteractive,
    [switch]$AccettaVersioneNonVerificata
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SteamLibraries {
    $roots = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $entry = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($null -eq $entry) { continue }
        foreach ($name in @('SteamPath', 'InstallPath')) {
            if ($null -ne $entry.PSObject.Properties[$name] -and $entry.$name) {
                [void]$roots.Add([string]$entry.$name)
            }
        }
    }
    foreach ($variable in @('ProgramFiles(x86)', 'ProgramFiles')) {
        $directory = [Environment]::GetEnvironmentVariable($variable)
        if ($directory) { [void]$roots.Add((Join-Path $directory 'Steam')) }
    }
    $libraries = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($steam in $roots) {
        if (-not (Test-Path -LiteralPath $steam -PathType Container)) { continue }
        [void]$libraries.Add($steam)
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $vdf -PathType Leaf)) { continue }
        $raw = Get-Content -LiteralPath $vdf -Raw
        foreach ($match in [regex]::Matches($raw, '"path"\s+"([^"]+)"')) {
            [void]$libraries.Add($match.Groups[1].Value.Replace('\\', '\'))
        }
    }
    return @($libraries)
}

function Test-GameRoot([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Path 'QueensDomain.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Path 'QueensDomain\Content\Paks\QueensDomain-WindowsNoEditor.pak') -PathType Leaf)
}

function Find-GameRoot([string]$RequestedPath) {
    if ($RequestedPath) {
        $path = $RequestedPath.Trim().Trim('"')
        if (-not (Test-GameRoot $path)) {
            throw 'Cartella non valida. Scegli la cartella che contiene QueensDomain.exe.'
        }
        return (Resolve-Path -LiteralPath $path).ProviderPath
    }
    $found = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($library in (Get-SteamLibraries)) {
        $manifest = Join-Path $library 'steamapps\appmanifest_1799840.acf'
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
        $match = [regex]::Match((Get-Content -LiteralPath $manifest -Raw), '"installdir"\s+"([^"]+)"')
        if (-not $match.Success) { continue }
        $leaf = $match.Groups[1].Value
        if ($leaf -in @('.', '..') -or $leaf.IndexOfAny([char[]]'\/:') -ge 0) { continue }
        $path = Join-Path (Join-Path $library 'steamapps\common') $leaf
        if (Test-GameRoot $path) { [void]$found.Add((Resolve-Path -LiteralPath $path).ProviderPath) }
    }
    if ($found.Count -eq 1) { return @($found)[0] }
    if ($NonInteractive) { throw 'Installazione non individuata in modo univoco: specifica -GamePath.' }
    Write-Host 'Su Steam: Queen''s Domain > Gestisci > Sfoglia i file locali.'
    foreach ($path in $found) { Write-Host ('Installazione trovata: ' + $path) }
    $answer = Read-Host 'Incolla il percorso della cartella del gioco'
    if ([string]::IsNullOrWhiteSpace($answer)) { throw 'Operazione annullata.' }
    return Find-GameRoot $answer
}

function Get-Sha256([string]$Path) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}

function Get-PreviousVersion($Manifest, [string]$Hash) {
    $property = $Manifest.PSObject.Properties['previous_overlays']
    if ($null -eq $property) { return $null }
    $match = @($property.Value | Where-Object { $_.sha256 -ceq $Hash })
    if ($match.Count -eq 0) { return $null }
    return [string]$match[0].version
}

try {
    $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mod.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $filename = 'QueensDomain_Italian_P.pak'
    if ($manifest.overlay.filename -cne $filename -or $manifest.overlay.sha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'Manifest della traduzione non valido: scarica nuovamente lo ZIP completo.'
    }
    $expected = [string]$manifest.overlay.sha256
    $source = Join-Path $PSScriptRoot ('QueensDomain\Content\Paks\' + $filename)
    if ($Action -eq 'Install' -and (-not (Test-Path -LiteralPath $source -PathType Leaf) -or (Get-Sha256 $source) -cne $expected)) {
        throw 'File della traduzione mancante o danneggiato: estrai nuovamente tutto lo ZIP.'
    }
    $game = Find-GameRoot $GamePath
    $running = @(Get-Process | Where-Object { $_.ProcessName -like 'QueensDomain*' })
    if ($running.Count -gt 0) { throw 'Chiudi Queen''s Domain prima di installare o rimuovere la traduzione.' }
    $paks = Join-Path $game 'QueensDomain\Content\Paks'
    $target = Join-Path $paks $filename
    Write-Host ('Gioco: ' + $game)

    if ($Action -eq 'Uninstall') {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            Write-Host 'Traduzione gia assente. Nessun file modificato.'
            exit 0
        }
        $installed = Get-Sha256 $target
        if ($installed -cne $expected -and $null -eq (Get-PreviousVersion $manifest $installed)) {
            # Not a known version of this translation: keep it instead of deleting it.
            $backup = $target + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
            [IO.File]::Move($target, $backup)
            Write-Host ('Il file presente era diverso dalle versioni note: l''ho spostato in ' + (Split-Path -Leaf $backup) + ' invece di eliminarlo.')
        }
        else {
            Remove-Item -LiteralPath $target
        }
        Write-Host 'Traduzione rimossa. Il pacchetto originale e i salvataggi sono invariati.'
        exit 0
    }

    $vanilla = Join-Path $paks 'QueensDomain-WindowsNoEditor.pak'
    $vanillaHash = Get-Sha256 $vanilla
    $compatible = @($manifest.compatible_vanilla_paks | Where-Object { $_.sha256 -ceq $vanillaHash })
    if ($compatible.Count -gt 1) {
        throw 'Manifest della traduzione non valido: scarica nuovamente lo ZIP completo.'
    }
    $installed = $null
    if (Test-Path -LiteralPath $target) {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw 'QueensDomain_Italian_P.pak e una cartella: rimuovila a mano e riprova.'
        }
        $installed = Get-Sha256 $target
        if ($installed -ceq $expected) {
            Write-Host 'Questa traduzione e gia installata. Nessun file modificato.'
            exit 0
        }
    }
    if ($compatible.Count -eq 0) {
        # A game update changes the vanilla pak hash. The overlay only replaces the text file, so installing
        # is allowed after an explicit confirmation; new or changed strings may simply stay in English.
        $known = (@($manifest.compatible_vanilla_paks | ForEach-Object { [string]$_.game_version }) -join ', ')
        Write-Host 'ATTENZIONE: questa versione del gioco non e ancora verificata per la traduzione.' -ForegroundColor Yellow
        Write-Host ('Versioni verificate: ' + $known + '. Impronta del pacchetto del gioco: ' + $vanillaHash.Substring(0, 16) + '.')
        Write-Host 'La traduzione dovrebbe funzionare anche dopo un aggiornamento minore, ma i testi nuovi o'
        Write-Host 'modificati dall''aggiornamento possono comparire in inglese.'
        Write-Host 'Nessun file originale viene modificato e puoi rimuovere la traduzione con Disinstalla.cmd.'
        Write-Host 'Controlla su GitHub se esiste una versione piu recente.'
        if (-not $AccettaVersioneNonVerificata) {
            if ($NonInteractive) {
                throw 'Versione del gioco non verificata. Nessun file copiato: per installare comunque usa -AccettaVersioneNonVerificata.'
            }
            $answer = [string](Read-Host 'Vuoi installare comunque? Scrivi S per continuare, qualunque altro tasto per annullare')
            if ($answer.Trim() -notmatch '^(s|si)$') { throw 'Operazione annullata. Nessun file copiato.' }
        }
    }
    $temporary = Join-Path $paks ('.qd-italiano-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $previous = $null
    $backup = $null
    try {
        [IO.File]::Copy($source, $temporary, $false)
        if ((Get-Sha256 $temporary) -cne $expected) { throw 'Verifica della copia non riuscita.' }
        if ($null -eq $installed) {
            # File.Move refuses an existing destination; a concurrent file is preserved.
            [IO.File]::Move($temporary, $target)
        }
        else {
            # An older version (or another file with this name) is replaced; only unknown content is kept as a backup.
            $previous = Get-PreviousVersion $manifest $installed
            if ($null -eq $previous) { $backup = $target + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') }
            # PowerShell turns $null into an empty string; [NullString] passes a real null (no backup).
            if ($null -eq $backup) { [IO.File]::Replace($temporary, $target, [NullString]::Value) }
            else { [IO.File]::Replace($temporary, $target, $backup) }
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary }
    }
    if ($null -ne $previous) { Write-Host ('Sostituita la versione precedente della traduzione (' + $previous + ').') }
    elseif ($null -ne $backup) { Write-Host ('Il file presente era diverso dalle versioni note: ne ho conservato una copia in ' + (Split-Path -Leaf $backup) + '.') }
    if ($compatible.Count -eq 1) {
        Write-Host ('Traduzione installata per la versione ' + $compatible[0].game_version + '.')
    }
    else {
        Write-Host 'Traduzione installata (versione del gioco non verificata). Se noti problemi, segnalali su GitHub.'
    }
    Write-Host 'Avvia il gioco e seleziona English (puo apparire come Italiano).'
    Write-Host 'Il pacchetto originale e i salvataggi non sono stati modificati.'
    exit 0
}
catch {
    Write-Host ('ERRORE: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'I file originali del gioco non sono stati sostituiti.'
    exit 1
}
