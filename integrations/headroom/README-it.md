# headroom

Un proxy di compressione che si mette tra l'agente e le API. Ogni altra voce di questo
catalogo spende contesto per risparmiare lavoro; headroom è l'unica che non spende
contesto affatto — non compare mai nella finestra, perché lavora sul filo. Le richieste
passano attraverso un proxy HTTP locale che riduce output dei tool, log, risultati di
ricerca, contenuti di file e cronologia della conversazione prima che raggiungano il
modello, sostituendo il volume rimosso con un marcatore breve e un hash che il modello può
spendere token per riespandere.

Lo scambio quindi non è contesto contro capacità, come è ovunque altrove qui. È *token
contro tempo reale e fedeltà*: la riduzione misurata su questa macchina è reale ma
modesta, la latenza che costa è grossa, e la compressione è lossy sulla prosa — inclusa la
prosa nei file che l'agente rilegge. Questa guida è documentata in modo inusualmente
solido perché il proxy era già in funzione mentre veniva scritta, quindi ogni cifra qui
sotto viene dallo `/stats` dell'istanza in esecuzione, non dal README upstream.

| | |
|---|---|
| Upstream | https://github.com/headroomlabs-ai/headroom |
| Autore | Headroom Contributors (headroomlabs-ai) |
| Licenza | Apache-2.0, con un `NOTICE` che elenca componenti di terze parti MIT (tiktoken, Pydantic) |
| Versione ispezionata | `v0.37.0` (commit `e67b3c8a2944`, 2026-09-06); l'istanza misurata qui riporta `0.27.0` |
| Contenuto | Workspace Rust più package Python e SDK TypeScript: CLI `headroom`, proxy HTTP, server MCP (4 tool), 5 directory di plugin di cui `headroom-agent-hooks` è quella per Claude Code — solo hook, nessuna skill, nessun sub-agent |

## Installazione

Nello stesso package arrivano quattro forme, e vale la pena portarne solo la prima. Il
proxy non richiede modifiche al codice né plugin:

```bash
uv tool install --python 3.13 "headroom-ai[proxy]"
headroom proxy --port 8787
export ANTHROPIC_BASE_URL=http://127.0.0.1:8787
```

Python 3.13 è l'interprete raccomandato: la tile dei dollari della dashboard dipende da
LiteLLM, che non si installa su 3.14+. `[all]` tira dentro anche il compressore ML e gli
extra memory, vector e image — un'installazione molto più grossa per una strategia che,
come misurato sotto, contribuisce quasi nulla.

Sotto WSL il proxy gira di solito sull'host Windows, quindi la variabile punta
all'indirizzo dell'host invece che a loopback, e l'URL porta un namespace di progetto che
tiene separati i risparmi complessivi per progetto:

```bash
export ANTHROPIC_BASE_URL=http://172.27.176.1:8787/p/<project>
```

Per spegnerlo per una sessione basta togliere la variabile — nessuna disinstallazione,
nessun riavvio di niente tranne l'agente:

```bash
unset ANTHROPIC_BASE_URL
```

Il plugin per Claude Code è una forma separata e opzionale. Non porta skill né sub-agent;
tutto il suo contenuto sono due hook che eseguono `headroom init hook ensure` per avviare
il runtime:

```bash
claude plugin marketplace add headroomlabs-ai/headroom
claude plugin install headroom@headroom-marketplace
```

## Consumo di token

Tre budget, come sempre. Ciò che rende diversa questa voce è che il primo è vuoto.

**Sempre attivo, per sessione.** La forma proxy non costa assolutamente nulla: nessuna
voce nell'indice delle skill, nessuna descrizione di sub-agent, nessuna iniezione
`SessionStart`. Non sta nella finestra di contesto, quindi non c'è niente da pagare prima
che tu scriva.

| Forma | Costo di contesto sempre attivo |
|---|---|
| Proxy (`ANTHROPIC_BASE_URL`) | **nessuno** — il processo è fuori dalla finestra |
| Plugin Claude Code (`headroom-agent-hooks`) | nessuna skill, nessun agent; due hook il cui stdout non era misurabile qui (la CLI non è nel PATH di questo guest WSL, dato che il proxy gira lato host) |
| Server MCP (`headroom mcp serve`) | 4 definizioni di tool, 2.099 caratteri a spazi compattati · **~525 token**, pagati ogni sessione che il modello li chiami o no |

L'hook `SessionStart` del plugin dichiara il matcher `startup|resume`, quindi a differenza
di superpowers e caveman **non** si riattiva su `/clear` né in compaction. Il suo hook
`PreToolUse` matcha `Bash|PowerShell`, quindi gira una volta per chiamata di shell — un
costo di latenza, non di token.

**Per richiesta.** Ogni blocco compresso viene sostituito da un marcatore della forma
`[175 items compressed to 138. Retrieve more: hash=26420830ad95b10f417448c3]` — 75
caratteri, ~19 token, contro un risparmio molto più grande. Se poi il modello recupera
l'originale, il risparmio viene restituito e si aggiunge un giro di andata e ritorno. I
contatori complessivi su questa macchina mostrano che succede continuamente: 15.783
compressioni contro 16.148 recuperi, un tasso di recupero di **1,02 per compressione**.

Il prezzo per richiesta misurabile è tempo, non token:

| Tempi (questa istanza, 631 richieste) | Valore |
|---|---|
| Overhead aggiunto, media | 2.186 ms |
| Overhead aggiunto, min / max | 1,39 ms / 30.189 ms |
| `compressor:mixed`, media | 5.590 ms |
| `compressor:kompress` (ML), media | 2.264 ms |
| `compressor:smart_crusher` / `search` / `diff`, media | 31–65 ms |

L'upstream pubblicizza "0.21 ms p50". Quella cifra è una singola chiamata di SmartCrusher
su un payload JSON da 10K token, non la pipeline del proxy con le strategie text e ML
attive, e il divario tra le due è di quattro ordini di grandezza.

**Cosa ti restituisce.** Misurato, su traffico Claude Code reale attraverso questo proxy:

| Finestra | Richieste | Token di input prima | Risparmiati | Rapporto | Dollari |
|---|---|---|---|---|---|
| Questa sessione | 631 | 65,79 M | 1,99 M | **3,02 %** | 9,93 $ su 173,65 $ |
| Complessivo, questo progetto | 69.523 | 6,86 B | 317,5 M | **4,42 %** | 1.339 $ su 10.088 $ |
| Per richiesta compressa | 485 | — | — | 4,8 % medio, 19,7 % migliore (33.226 → 26.692) | — |

La maggior parte delle richieste viene lasciata in pace, e le ragioni vale la pena
leggerle: 4.551 blocchi erano troppo piccoli per valerne la pena, 2.420 avevano un
rapporto troppo scarso, 604 erano protetti perché stavano dietro un breakpoint di cache,
459 venivano da tool esclusi, 273 erano già compressi. Quel router è la ragione per cui
l'aggregato si ferma intorno al 4 % invece del 21–57 % che il README upstream cita per
scenari scelti a mano.

Anche da dove vengono davvero i risparmi non è dove ti aspetteresti:

| Strategia | Chiamate | Token risparmiati |
|---|---|---|
| text | 465 | 34.761 |
| tabular | 22 | 22.360 |
| kompress (ML) | 63 | 3.499 |
| code_aware | 226 | 2.527 |
| smart_crusher | 73 | 432 |
| search / diff / log | 33 | 459 |

Ventidue blocchi tabellari hanno risparmiato nove volte quello che hanno fatto 226
compressioni code-aware.

**Punto di pareggio.** Con zero costo di contesto sempre attivo, qualsiasi rapporto
positivo si ripaga in token — l'aritmetica che decide le altre voci di questo catalogo qui
non si applica. La domanda è se il ~4 % in meno sulla bolletta di input valga i ~2,2 s
aggiunti a ogni richiesta. Su run autonomi lunghi in cui il vincolo stringente è la
finestra di contesto stessa, sì: 317 M di token sono headroom reale contro il limite, che
è il nome vero del prodotto e il suo argomento vero. Sul lavoro interattivo è una tassa su
ogni turno per qualche punto percentuale.

Un altro numero tiene onesta la pretesa sui dollari: sulla stessa istanza il prompt caching
ha risparmiato 313,81 $ mentre la compressione ne ha risparmiati 9,93. La dashboard riporta
entrambi, e il 97 % dei soldi è arrivato da un meccanismo che Claude Code usa già da solo.
Il contributo di headroom lì è difensivo — il suo CacheAligner ha protetto 604 blocchi
dietro i breakpoint e ha registrato solo 11 cache bust.

## Verdetto, per componente

| Componente | Verdetto | Perché |
|---|---|---|
| Proxy HTTP | Keep — è il prodotto | Zero costo di contesto, riduzione di input misurata al 3–4,4 %, una env var per accenderlo e una per spegnerlo. Tutto il resto qui è opzionale attorno a lui. |
| CacheAligner | Keep | Segnala i contenuti che rompono la cache invece di riscriverli. 604 blocchi protetti, 11 bust. Comprimere attraverso un breakpoint costerebbe più di quanto risparmia, e questo è ciò che lo impedisce. |
| SmartCrusher (JSON) + tabular | Keep | Il rapporto per chiamata migliore di tutto l'insieme, e le strategie abbastanza rapide da non farsi sentire: 22 chiamate tabular, 22.360 token. |
| Recupero CCR + hash | Situational | Rende la compressione reversibile, che è ciò che la rende sicura. Ma i recuperi complessivi superano le compressioni 1,02:1 — su quel traffico il modello ripaga la maggior parte del risparmio più un giro di andata e ritorno. Da guardare in `/stats`, non da dare per scontato. |
| code_aware (AST) | Situational | 226 chiamate per 2.527 token: il 36 % delle compressioni, lo 0,8 % dei risparmi. Innocuo, ma non è il motivo per cui installeresti questo. |
| Modello ML Kompress | Skip | 2.264 ms di media per 3.499 token. L'extra `[ml]` è il grosso dell'installazione e il grosso della latenza. Lascialo fuori da `[proxy]`. |
| Server MCP (4 tool) | Skip | ~525 token sempre attivi, e inverte il design: il modello deve ricordarsi di chiamare `headroom_compress` invece che la compressione avvenga e basta. Il proxy lo fa già gratis. |
| Plugin Claude Code | Skip | Non contribuisce skill né capacità — due hook che avviano un runtime che puoi avviare da te. Il matcher `PreToolUse` significa che scatta a ogni chiamata Bash per farlo. |
| `headroom wrap <agent>` | Situational | Imposta l'ambiente per te. Utile una volta, poi la variabile la sai. |
| Dashboard (`/stats`, `/dashboard`) | Keep, situational | La ragione per cui questa guida ha numeri. Leggila prima di credere a qualsiasi pretesa sulla compressione, questa inclusa. |
| `headroom learn` / extra memory, vector, image | Skip | Prodotti adiacenti impacchettati nello stesso package. Non è per questo che si porta il proxy. |
| Beacon anonimo | Skip — spegnilo | Attivo per default upstream. Vedi i gotcha. |

## Interazione con il resto del loadout

Niente nel catalogo si sovrappone a questo, perché niente altro nel catalogo lavora a
questo livello. Le tre storie di compressione in loadout sono complementari e vale la pena
essere precisi su quale è quale: caveman riduce l'**output** che il modello scrive,
graphify evita che le **letture** avvengano del tutto rispondendo da un grafo, e headroom
riduce l'**input** già in viaggio verso le API. Solo headroom non paga contesto per il
privilegio.

Cambia anche la contabilità delle altre. Le iniezioni `SessionStart` di superpowers e
caveman si riattivano a ogni compaction, e quelle iniezioni ripetute viaggiano attraverso
il proxy come qualsiasi altra cosa — ma stanno dietro un breakpoint di cache, quindi
finiscono nei 604 blocchi protetti e non vengono compresse. Il costo degli hook misurato
in quelle due guide si paga per intero, con o senza questa voce.

Il numero di hook non cambia se prendi la forma raccomandata: il proxy non aggiunge hook.
Installa il plugin opzionale e ti ritrovi con un terzo plugin che porta hook, e un hook
`PreToolUse` a ogni chiamata di shell, senza alcun beneficio di contesto.

## Gotcha

- **La compressione è lossy sulla prosa, inclusi i file che leggi.** Mentre questa guida
  veniva scritta, `cat scripts/install-all.sh` è tornato attraverso il proxy con articoli
  e riempitivi tolti dai commenti e blocchi sostituiti da `[175 items compressed to 138.
  Retrieve more: hash=…]`. Output di shell, contenuti di file e risultati di ricerca sono
  tutti bersagli validi. Non modificare mai un file partendo da una lettura compressa:
  recupera per hash, o leggi a pezzi piccoli, che il router lascia in pace come "too
  small".
- **Il proxy è un singolo punto di rottura davanti alle API.** La stessa istanza ha
  registrato un 502, due 503 e una richiesta fallita su 1.218 chiamate in ingresso. Quando
  è giù, l'agente è giù finché non togli `ANTHROPIC_BASE_URL`.
- **Il suo stesso rate limiter può strozzarti.** I default sono 60 richieste e 100k token
  al minuto; 11 richieste sono state limitate con `429` su questa istanza. Quello è
  headroom che rifiuta traffico, non Anthropic.
- **La telemetria è attiva per default.** Un beacon anonimo riporta rapporti, contatori,
  ID di provider e modello, OS e architettura — non prompt né codice. Si disattiva con
  `HEADROOM_BEACON=off`, `DO_NOT_TRACK=1` o `--offline`. Era spento sull'istanza misurata
  qui; è stata una scelta, non il default.
- **Il recupero può cancellare il risparmio.** `headroom_read` e gli hash CCR permettono
  al modello di ritirare gli originali, e i contatori complessivi qui mostrano che lo fa
  poco più di una volta per compressione. Un rapporto di compressione nella dashboard non
  è un risparmio finché non guardi il tasso di recupero accanto.
- **La latenza pubblicizzata non è la latenza della pipeline.** "0.21 ms p50" è una
  singola strategia JSON isolata. L'overhead medio aggiunto misurato qui è 2.186 ms, con
  un massimo di 30 s.
- **Gli originali finiscono in cache su disco, non cifrati.** Su questa istanza sotto
  `/root/.headroom/`, il che significa anche che il proxy girava come root in un
  container. La compressione è locale e niente viene mandato via per essere compresso, ma
  gli originali in chiaro finiscono in un file.
- **Il pin va alla deriva in silenzio e il repository è grande.** HEAD è `v0.37.0`; il
  proxy in esecuzione è `0.27.0`, dieci minor versioni indietro, e `headroom update
  --check` è l'unica cosa che te lo dirà. Un clone shallow del sorgente pesa 104 MB.
- **macOS Intel non ha wheel nativo.** Apple Silicon e Linux sono coperti; Intel richiede
  Docker o un ONNX Runtime di sistema.
