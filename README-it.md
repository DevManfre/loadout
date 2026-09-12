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
    #  entry           cost/session           status
 ▸  1 [x] superpowers     ~800                   ready
    2 [x] graphify        ~340 +48-105/toolcall  ready
    3 [x] headroom        none                   ready
    4 [x] frontend-design ~70                    ready
    5 [x] ui-ux-pro-max   ~683                   ready
    6 [^] caveman         ~2,480 +60/prompt      update: 84cc3c14fa1e → v2.6.0
    7 [=] impeccable      ~560 +0-475/edit       installed @ v4.3.1

↑/↓ move · Space toggle · d=why · a=all · n=none · Enter=apply 5 · q=quit
```

`▸` indica la riga corrente: le frecce la spostano, Space la toggla, `d` la spiega, e
le cifre togglano ancora per numero. Il menu si ridisegna sul posto — niente copie che
scorrono — e colora la colonna status (verde ready, giallo auto-install, rosso
bloccata). I colori rispettano `NO_COLOR`; su una pipe, con `TERM=dumb` o con
`LOADOUT_PLAIN_MENU=1` lo stesso menu ripiega sul prompt numerato a righe, dove una
risposta può togglare più righe (`1 3`).

Una voce bloccata resta numerata ma non può essere selezionata; `d` sulla sua riga
stampa cosa manca, perché la voce ne ha bisogno, come risolverlo e quanto costa
saltarla.

Un solo menu risponde a tutte e tre le domande su una voce: `[ ]`/`[x]` non è
installata, `[=]` è installata e aggiornata, `[^]` è installata ma indietro rispetto a
quello che l'upstream pubblica ora, con entrambi i pin sulla sua riga. Una riga di
aggiornamento è selezionabile ma mai preselezionata — un aggiornamento sposta qualcosa
che già funziona fuori dal pin misurato da questo catalogo — e Invio applica
installazioni e aggiornamenti nella stessa passata, stampando ogni pin che sta per
spostare e chiedendo conferma una volta sola per l'insieme. `d` su una riga di
aggiornamento stampa i tre pin che decidono: installato, upstream, e quello su cui il
catalogo ha misurato il prezzo della voce.

Una voce che gira dove questa macchina non arriva — headroom dietro un proxy, in un
container o sull'host Windows — viene misurata sul pin che il suo endpoint `/health`
dichiara, quindi ottiene anch'essa una riga `[^]`. Quella riga è di sola lettura: nomina
entrambi i pin e dice di aggiornarla dove gira, perché da qui non si può.
`scripts/loadout status` stampa lo stesso pin come `remote 0.27.0`.

Il controllo sull'upstream parte all'apertura del menu: un `git ls-remote` per ogni
plugin, l'indice dei pacchetti per ogni pacchetto, ogni chiamata con un tetto di tempo
e tutte insieme — circa un secondo in totale, e non viene ricordato da nessuna parte.
`--offline` (o `LOADOUT_NO_NET=1`) lo salta, e lo stesso vale per un upstream
irraggiungibile: la voce resta una normale riga `[=]` invece di dichiararsi aggiornata
o indietro.

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
| `--offline` | Non chiede mai all'upstream cosa pubblica — nessuna riga di aggiornamento |

Ogni comando è idempotente. Un plugin, un binario o un asset già installato viene
segnalato e saltato, quindi rieseguirlo copre solo quello che manca.

### Aggiornamento

`scripts/loadout update` non aggiorna mai in silenzio. Per ogni voce installata
stampa il pin su disco, il pin che l'upstream pubblica ora, il pin misurato dal
catalogo e quanto costa quel pin, avvisa se sei già fuori dal pin misurato, e dichiara
quando il pin su cui l'aggiornamento atterra è uno che questo catalogo non ha misurato
— prima di chiedere conferma. caveman è la voce agli atti sul perché quel gate esiste: la stessa
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
| impeccable | Plugin di fluenza progettuale: 23 comandi di design con nome, più un detector compilato che segnala testo in gradiente, aloni a offset zero, contrasti insufficienti e deriva dal design system dopo ogni modifica | Finding meccanici e verificabili al momento della modifica invece che in fase di review, così un componente non viene rifatto dopo che un umano lo ha definito fatto dall'AI. L'unica voce con hook di questo catalogo senza costo su `SessionStart` | ~560 token per sessione, più 0 sulle modifiche non-UI, ~70 su un file UI pulito e ~475 su uno con tre finding | [guida](integrations/impeccable/README-it.md) |
| frontend-design | Il file di gusto frontend di Anthropic: una skill sola che argomenta per un piano di design radicato nella materia del brief, e nomina i cinque grappoli visivi su cui le pagine generate continuano ad atterrare — compresa la palette terracotta su crema che è l'accento di Claude | Un primo passaggio che non sa di template, così la pagina non viene rifatta dalla palette in su dopo che la review la definisce fatta dall'AI. Niente hook, niente agent, nessun binario: il corpo si carica solo sul lavoro di UI | ~70 token per sessione; corpo da ~2.350 token caricato solo all'invocazione | [guida](integrations/frontend-design/README-it.md) |
| ui-ux-pro-max | Database di design locale interrogato da uno script: 79 stili, 192 palette con profili di ragionamento, 74 abbinamenti di font, 119 linee guida UX, 25 tipi di grafico, 22 stack — 3,1 MB di CSV e JSON che non entrano mai nel contesto | Valori precisi invece che improvvisati — questa palette, questo abbinamento, questo pattern — per ~105 token a query mirata, così la pagina non viene rifatta quando la direzione si rivela sbagliata. Niente hook, e il database resta fuori dalla finestra | ~683 token per sessione, il più alto qui: il plugin espone sette skill e non esiste un interruttore per singola skill | [guida](integrations/ui-ux-pro-max/README-it.md) |

### Asset propri

Installati dallo stesso script, come copia semplice della directory — nessun indice di
plugin in mezzo.

| Nome | Cosa fa | Cosa ti restituisce | Costo sempre attivo | Documentazione |
|---|---|---|---|---|
| hook-recipes | Trasforma un'istruzione ripetuta in un hook applicato dall'harness: quali regole si prestano, i quattro dettagli di contratto per cui la maggior parte degli hook in circolazione non scatta mai, sei ricette testate e una sonda che esegue un handler contro un payload sintetico | Una regola spostata da `CLAUDE.md` a un hook smette di essere pagata in ogni sessione — il risparmio è la cancellazione, e la sonda è ciò che rende sicuro cancellare. Misurato qui: le sei ricette costano 0 token quando passano e ~22–55 quando scattano | ~41 token (descrizione); il corpo da ~1.610 token, una pagina di ricette e uno script shell si caricano solo all'invocazione | [guida](skills/hook-recipes/SKILL.md) |
| token-economy | Verifica ogni componente di una configurazione Claude Code per costo in token — misurato via script, mai a occhio — e fissa le regole di design per scrivere skill, agent e file CLAUDE.md snelli fin dall'inizio | Un report di audit prezzato in token sempre attivi con una colonna di rischio per rilievo; un solo rilievo applicato ripaga tipicamente centinaia di volte il costo della skill. Misurato qui: il CLAUDE.md di questo repo è sceso da una lista di regole a un indice da ~430 token usando le sue dimensioni | ~43 token (descrizione); il corpo da ~1.790 token, una pagina di reference e due script shell si caricano solo all'invocazione | [guida](skills/token-economy/SKILL.md) |

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
