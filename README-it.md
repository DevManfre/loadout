# loadout

[English](README.md) · [Italiano](README-it.md)

Una guida per impostare al meglio il proprio Claude Code. Non un plugin, non un
framework: un insieme curato di skill, sub-agent, workflow e integrazioni di terze
parti, ognuna documentata con il contesto che costa davvero — misurato su un
repository reale, non copiato dal README upstream. Lo script di installazione mette
in piedi l'insieme completo in un blocco solo, perché un loadout è qualcosa che si
porta interamente, non una lista della spesa da cui pescare un pezzo alla volta.

Qui non c'è nulla di vendorizzato. Ogni asset si installa dalla sua fonte upstream,
quindi mantieni gli aggiornamenti upstream e non perdi niente se leggi la guida
invece di adottarla.

## Installazione

Clona il repository ed esegui un solo script:

```bash
git clone https://github.com/DevManfre/loadout.git
cd loadout
scripts/install-all.sh
```

Lo script copre ogni percorso di installazione del catalogo — la CLI dei plugin di
Claude Code per le voci plugin, un package manager per i binari di terze parti che non
possono essere distribuiti come plugin, e una semplice copia per gli asset di loadout.
Non nasconde mai il prezzo: ogni passo stampa prima il suo costo in token sempre
attivo e chiede conferma prima di pagarlo.

È idempotente. Un plugin, un binario o un asset già installato viene segnalato e
saltato, quindi rieseguirlo copre solo quello che manca.

| Opzione | Cosa fa |
|---|---|
| `--dry-run` | Stampa ogni passo e ogni costo, senza modificare nulla |
| `--yes` | Accetta in anticipo tutti i costi stampati (obbligatoria senza TTY) |
| `--scope project` | Installa nel repository corrente invece che nel tuo profilo utente |
| `--skip-graphify` | Lascia fuori il code graph |

## Disinstallazione

Hai installato qualcosa che si rivela troppo pesante? Toglilo dal contesto senza
disinstallarlo:

```bash
/plugin disable superpowers
```

## Come si legge una pagina

Ogni voce del catalogo ha la sua guida, e tutte rispondono alle stesse domande nello
stesso ordine:

- **Upstream, autore, licenza, versione ispezionata** — cosa stai installando davvero.
- **Economia dei token** — divisa in costo sempre attivo, costo per chiamata di tool e
  costo su richiesta, con le dimensioni misurate sulla versione ispezionata.
- **Verdetto, per singola skill o per singolo comando** — tenere, situazionale o
  saltare, con la motivazione.
- **Interazione con il resto di loadout** — cosa si compone e cosa si sovrappone.
- **Trappole** — quello che la documentazione upstream non ti dice.

L'economia dei token è il senso di tutto l'esercizio. Un asset che costa più contesto
di quanto ne risparmi non appartiene a un loadout, per quanto bello sembri nel suo
README.

## Catalogo

### Integrazioni

| Nome | Cosa fa | Cosa ti restituisce | Costo sempre attivo | Documentazione |
|---|---|---|---|---|
| superpowers | Skill di processo: gate di brainstorming, TDD red/green, debugging sistematico, sviluppo guidato da subagent, creazione di skill | Elimina interi giri di implementazione buttati — niente viene costruito prima che tu approvi il design, niente viene dichiarato finito senza prove. Il più grosso spreco di token è un agente che costruisce bene la cosa sbagliata | ~800 token per avvio sessione, `/clear` e compaction | [guida](integrations/superpowers/README-it.md) |
| graphify | Grafo di codice locale via tree-sitter: `explain` di un simbolo, `path` tra due, interrogazione del grafo invece del grep | Un `explain` risponde a quello che altrimenti costa una spazzata di grep più qualche lettura di file intero, e `graphify explain` / `graphify path` girano come normali comandi di shell — nessun corpo di skill caricato. Il grafo si costruisce in locale, 0 crediti LLM sul codice | ~340 token per sessione, più ~48–105 per lettura o grep finché esiste un grafo | [guida](integrations/graphify/README-it.md) |
| caveman | Plugin di stile: toglie articoli, riempitivi e giri di parole dalla prosa dell'agente, lasciando esatti codice, percorsi ed errori | L'upstream misura l'output che scende da 1.214 a 294 token su 10 task (65%). Riduce solo l'output, quindi rende nelle sessioni discorsive e perde in quelle piene di tool call — l'aritmetica è nella guida | ~2.480 token per avvio sessione, `/clear` e compaction, più ~60 per prompt utente | [guida](integrations/caveman/README-it.md) |

### Asset propri

Ancora nessuno. `skills/`, `agents/` e `workflows/` sono la loro sede, e lo stesso
script di installazione li copia al loro posto appena arrivano.

## Struttura

```text
skills/<name>/SKILL.md          loadout's own skills
agents/<name>.md                loadout's own sub-agent definitions
workflows/<name>.md             loadout's own workflow scripts and recipes
integrations/<name>/            third-party guides (plugins, binaries, MCP servers)
scripts/install-all.sh          one-block install of the whole loadout
scripts/validate.sh             structural validation
docs/                           longer-form guides
```

Non c'è codice applicativo e non c'è build. La validazione è strutturale — ogni
percorso nominato dal catalogo si risolve, ogni asset è documentato, e i mirror di
lingua restano in parità:

```bash
scripts/validate.sh
```

## Licenza

MIT. Vedi [LICENSE](LICENSE).
