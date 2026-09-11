# loadout

[English](README.md) · [Italiano](README-it.md)

Una guida per impostare al meglio il proprio Claude Code. Non un plugin, non un
framework: un insieme curato di skill, sub-agent, workflow e integrazioni di terze
parti, ognuna documentata con il contesto che costa davvero — misurato su un
repository reale, non copiato dal README upstream. Lo script di installazione mette
in piedi l'insieme completo in un blocco solo, perché un loadout è qualcosa che si
porta interamente: il menu si apre con ogni voce già selezionata e Invio le installa
tutte. Deselezionarne una è un atto deliberato, preso con il suo costo a schermo.

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

`scripts/install-all.sh` è uno shim di tre righe per `scripts/loadout install`,
tenuto così il blocco sopra non deve mai cambiare. Ogni comando vive sotto quell'unico
punto d'ingresso:

| Comando | Cosa fa |
|---|---|
| `install` | Scegli cosa installare, poi installalo |
| `update` | Aggiorna quello che è già installato |
| `status` | Cosa è installato, il suo pin, quanto costa |
| `doctor` | Report delle dipendenze; non cambia nulla |
| `remove <entry>` | Disinstalla una voce |
| `list` | Il catalogo così come lo vede `scripts/loadout` |

`install` apre un menu con ogni voce installabile già selezionata — Invio le installa
tutte. Deselezionarne una è un atto deliberato, preso con il suo costo già a schermo:

```
  #  entry        cost/session           status
  1 [x] superpowers  ~800                   ready
  2 [x] caveman      ~2,480 +60/prompt      ready
  3 [x] graphify     ~340 +48-105/toolcall  ready
  4 [x] headroom     none                   ready

toggle 1-4 · a=all · n=none · d <n>=why · Enter=install 4 · q=quit
>
```

Una voce bloccata resta numerata ma non può essere selezionata; `d <n>` stampa cosa
manca, perché la voce ne ha bisogno, come risolverlo e quanto costa saltarla.

Una dipendenza l'installer sa procurarsela da solo: **uv**. Una voce a cui manca solo
uv/pipx non è bloccata — la sua riga resta selezionabile e riporta `needs uv/pipx
(auto-install, asks first)`. Prima di installare una voce del genere, l'installer
stampa il comando esatto che sta per eseguire (lo script ufficiale di Astral,
`curl -LsSf https://astral.sh/uv/install.sh | sh`) e chiede conferma; Enter sul menu
non salta quel prompt, solo `--yes` lo fa. Rifiutare lascia la voce sul suo normale
percorso bloccato, e `--dry-run` stampa il comando senza eseguirlo. Tutto il resto —
git, Claude Code, Docker — resta da installare a mano.

| Opzione | Cosa fa |
|---|---|
| `--preset core\|full` | Limita il menu a un preset con nome (default: `full`) |
| `--only a,b` | Limita a queste voci |
| `--except a,b` | Tutto tranne queste voci |
| `--scope user\|project\|local` | Destinazione dell'installazione (default: `user`) |
| `-y`, `--yes` | Accetta in anticipo tutti i costi stampati (obbligatoria senza TTY) |
| `-n`, `--dry-run` | Stampa ogni passo e ogni costo, senza modificare nulla |

Ogni comando è idempotente. Un plugin, un binario o un asset già installato viene
segnalato e saltato, quindi rieseguirlo copre solo quello che manca.

### Aggiornamento

`scripts/loadout update` non aggiorna mai in silenzio. Per ogni voce installata
stampa il pin su disco, il pin misurato dal catalogo e quanto costa quel pin, avvisa
se sei già fuori dal pin misurato, e dichiara che un aggiornamento sposta a qualunque
cosa l'upstream pubblichi ora — un pin che questo catalogo non ha misurato — prima di
chiedere conferma. caveman è la voce agli atti sul perché quel gate esiste: la stessa
skill costava ~780 token a sessione sul pin `84cc3c14fa1e` e ~2.480 su `v2.6.0`, a un
solo numero di versione di distanza. `--yes` accetta in anticipo ogni gate.

Esegui `scripts/loadout doctor` in qualsiasi momento per vedere cosa manca e come
risolverlo, senza cambiare nulla.

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
| headroom | Proxy di compressione sul filo: riduce output dei tool, log, risultati di ricerca e cronologia prima che raggiungano le API, lasciando un hash da espandere a richiesta | L'unica voce che non costa contesto — non sta nella finestra. Misurato su questa macchina: 3,0% su una sessione da 66 M token, 4,42% su 6,86 B token complessivi (1.339 $). Si paga in latenza, ~2,2 s in più per richiesta | nessuno nella forma proxy; ~525 token se aggiungi il suo server MCP | [guida](integrations/headroom/README-it.md) |

### Asset propri

Ancora nessuno. `skills/`, `agents/` e `workflows/` sono la loro sede, e lo stesso
script di installazione li copia al loro posto appena arrivano.

## Struttura

```text
skills/<name>/SKILL.md          loadout's own skills
agents/<name>.md                loadout's own sub-agent definitions
workflows/<name>.md             loadout's own workflow scripts and recipes
integrations/<name>/            third-party guides (plugins, binaries, MCP servers)
scripts/loadout                 single entrypoint: install, update, status, doctor, remove, list
scripts/install-all.sh          one-block install of the whole loadout
scripts/lib/                    manifest, probe, ui and actions libraries
scripts/loadout.manifest        catalog data: one row per installable entry
scripts/loadout.deps            dependency registry: what each entry needs, why, how to fix it
scripts/validate.sh             structural validation
scripts/selftest.sh             test runner
docs/                           longer-form guides
```

Non c'è codice applicativo e non c'è build. La validazione è strutturale — ogni
percorso nominato dal catalogo si risolve, ogni asset è documentato, e i mirror di
lingua restano in parità:

```bash
scripts/validate.sh
```

`scripts/selftest.sh` è il test runner dell'installer stesso: esercita
`scripts/loadout` contro una macchina finta, senza accesso alla rete e senza
installazioni reali.

## Licenza

MIT. Vedi [LICENSE](LICENSE).
