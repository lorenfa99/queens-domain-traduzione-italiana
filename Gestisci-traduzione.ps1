[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action = 'Install',
    [string]$GamePath,
    [switch]$NonInteractive
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
        if ((Get-Sha256 $target) -cne $expected) {
            throw 'Il file presente appartiene a una versione diversa o e stato modificato. Conservato senza rimuoverlo; usa il relativo disinstallatore.'
        }
        Remove-Item -LiteralPath $target
        Write-Host 'Traduzione rimossa. Il pacchetto originale e i salvataggi sono invariati.'
        exit 0
    }

    $vanilla = Join-Path $paks 'QueensDomain-WindowsNoEditor.pak'
    $vanillaHash = Get-Sha256 $vanilla
    $compatible = @($manifest.compatible_vanilla_paks | Where-Object { $_.sha256 -ceq $vanillaHash })
    if ($compatible.Count -ne 1) {
        throw 'Questa versione del gioco non e ancora verificata per la mod. Nessun file copiato: controlla gli aggiornamenti della traduzione su GitHub.'
    }
    if (Test-Path -LiteralPath $target) {
        if ((Get-Sha256 $target) -ceq $expected) {
            Write-Host 'Questa traduzione e gia installata. Nessun file modificato.'
            exit 0
        }
        throw 'Esiste gia un altro QueensDomain_Italian_P.pak. Non e stato sovrascritto: rimuovi la precedente versione con il suo disinstallatore.'
    }
    $temporary = Join-Path $paks ('.qd-italiano-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::Copy($source, $temporary, $false)
        if ((Get-Sha256 $temporary) -cne $expected) { throw 'Verifica della copia non riuscita.' }
        # File.Move refuses an existing destination; a concurrent file is preserved.
        [IO.File]::Move($temporary, $target)
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary }
    }
    Write-Host ('Traduzione installata per la versione ' + $compatible[0].game_version + '.')
    Write-Host 'Avvia il gioco e seleziona English (puo apparire come Italiano).'
    Write-Host 'Il pacchetto originale e i salvataggi non sono stati modificati.'
    exit 0
}
catch {
    Write-Host ('ERRORE: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'I file originali del gioco non sono stati sostituiti.'
    exit 1
}
