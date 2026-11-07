# Queen's Domain — Traduzione italiana

Traduzione italiana non ufficiale di **Queen's Domain** per PC, versione Steam.
Copre **2.277 voci di testo**: menu, dialoghi, descrizioni e documenti.

**[Scarica la traduzione (.zip)](https://github.com/lorenfa99/queens-domain-traduzione-italiana/releases/download/v1.0.0-beta.4/QueensDomain-Traduzione-Italiana-v1.0.0-beta.4.zip)**

## Installazione

1. Chiudi il gioco, scarica lo ZIP ed estrailo.
2. Fai doppio clic su **`Installa.cmd`**: trova l'installazione Steam e copia la mod.
   Se non la trova, incolla il percorso aperto da Steam → **Gestisci → Sfoglia i file locali**.
3. Avvia il gioco e seleziona la lingua **English**, che può apparire come **Italiano**.

In alternativa, copia la cartella **`QueensDomain`** dello ZIP nella cartella del gioco:
il file deve finire in `QueensDomain\Content\Paks\QueensDomain_Italian_P.pak`.
Il pacchetto originale del gioco non viene sostituito.

Per rimuovere la mod, chiudi il gioco e avvia **`Disinstalla.cmd`**, oppure elimina
soltanto `QueensDomain_Italian_P.pak` dalla cartella `Paks`.

## Aggiornamento da una versione precedente

Chiudi il gioco e rimuovi la vecchia traduzione con **`Disinstalla.cmd` della
versione precedente**. Poi estrai il nuovo ZIP e avvia `Installa.cmd`.
Se non hai più il vecchio pacchetto, rimuovi soltanto il file
`QueensDomain_Italian_P.pak` della precedente traduzione dalla cartella `Paks`,
quindi installa la nuova versione.

## Compatibilità e segnalazioni

**v1.0.0-beta.4 — beta.** Verificata offline sulle versioni del gioco **13464, 13480 e 13540**;
il controllo completo nel gioco è ancora in corso. L'installer verifica la versione
dei file prima di copiare la mod. Se il gioco è stato aggiornato e la versione non è ancora verificata, l'installer avvisa e chiede
conferma: la traduzione dovrebbe funzionare, ma i testi nuovi o modificati dall'aggiornamento possono
restare in inglese.

Per segnalare errori di testo o impaginazione, [apri una segnalazione](https://github.com/lorenfa99/queens-domain-traduzione-italiana/issues)
con schermata, luogo/menu e versione del gioco.

## Metodo

La lavorazione linguistica segue una **pipeline interamente automatizzata di agenti IA**,
coordinati da un agente orchestratore:

1. **Preparazione — Claude Opus 5.5 in Claude Code:** analisi di inglese e contesto,
   definizione di stile, glossario e profili dei personaggi.
2. **Traduzione — GPT-6.1 Sol in Codex:** lavoro in piccoli lotti, ciascuno con fonte,
   regole condivise e contesto pertinente.
3. **Revisione indipendente:** un altro agente, in un contesto nuovo senza la
   conversazione del traduttore, confronta inglese e italiano. Un agente dedicato
   risolve i problemi; ogni testo modificato torna a revisione.
4. **Passate finali:** controlli separati su coerenza dell'intero corpus e fluidità
   italiana, seguiti da ulteriori revisioni delle modifiche e verifiche automatiche
   di identità, segnaposto, markup, font e pacchetto finale.
5. **Revisione aggiuntiva — Gemini 4 Argon:** ulteriore confronto tra inglese e italiano.
   Le proposte sono state verificate in Codex e sono state integrate tre correzioni
   mirate. I testi modificati hanno completato una nuova revisione indipendente
   e i controlli locali di coerenza e fluidità.

Un harness conserva versioni, segnalazioni e correzioni per ogni voce e blocca la
build se mancano fasi o controlli obbligatori.

Progetto di [lorenfa99](https://github.com/lorenfa99), assistito da IA e non affiliato
agli autori del gioco. Il repository distribuisce la mod e gli strumenti di installazione.
