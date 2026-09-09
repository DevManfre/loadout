# graphify

Un indicizzatore locale di grafi di codice per Claude Code. Analizza un repository con
tree-sitter, scrive un knowledge graph in `graphify-out/` e poi risponde alle domande
strutturali (`explain`, `path`, `query`) interrogando quel grafo invece dei file.
Aggiunge una capacità invece di cambiare il modo in cui lavora l'agente: l'agente può
chiedere "chi chiama questa funzione" e ottenere una risposta che costa qualche centinaio
di token invece di una passata di grep più tre letture di file.

Non è un plugin di Claude Code. È un pacchetto Python con una CLI che scrive una skill,
una sezione di `CLAUDE.md` e due hook `PreToolUse` nella tua configurazione.

| | |
|---|---|
| Upstream | https://github.com/Graphify-Labs/graphify |
| Autore | Safi Shamsi |
| Licenza | Apache-2.0 (`LICENSE-MIT` e `NOTICE` sono distribuiti insieme) |
| Versione ispezionata | 0.9.56 (pacchetto PyPI `graphifyy`, CLI `graphify`) |
| Contenuto (Claude Code) | 1 skill (`SKILL.md` da 41 KB + 8 file di reference, 44 KB), 1 sezione di `CLAUDE.md`, 2 hook `PreToolUse`, 0 manifest di plugin |

## Installazione

Un plugin non può eseguire un package manager, quindi questo si installa da sé. `scripts/install-all.sh`
esegue per te i comandi qui sotto; loadout porta la contabilità dei costi e i verdetti, nient'altro.

```bash
uv tool install graphifyy        # or: pipx install graphifyy
graphify install                 # writes the skill + a CLAUDE.md pointer
```

`graphify install` da solo ti dà la skill `/graphify`. Il livello sempre attivo — le
regole graph-first in `CLAUDE.md` e i due hook che intercettano ogni lettura e ogni grep —
è un secondo comando, separato:

```bash
graphify claude install
```

Limitalo a un singolo repository invece che al tuo profilo utente con `--project`, che
scrive `.claude/skills/graphify/SKILL.md` nella directory corrente:

```bash
graphify install --project
```

Evita `pip install`: la skill risolve il proprio runtime Python attraverso
`graphify-out/.graphify_python`, e un pacchetto installato con `pip` fuori da un ambiente
isolato si manifesta come `ModuleNotFoundError: No module named 'graphify'`.

## Consumo di token

Tre budget distinti, e si comportano in modo diverso. Ogni cifra qui sotto è misurata
sulla versione 0.9.56, non stimata dal README upstream.

**Sempre attivo, per sessione.** Lo paghi che il grafo esista o no.

| Origine | Dimensione | ≈ token |
|---|---|---|
| Descrizione della skill nell'indice delle skill | 353 caratteri | ~90 |
| Puntatore in `CLAUDE.md` scritto da `graphify install` | 211 caratteri | ~55 |
| Regole in `CLAUDE.md` scritte da `graphify claude install` | 772 caratteri | ~195 |

Circa 340 token per sessione con il livello sempre attivo installato, ~145 senza. La
quota di `CLAUDE.md` viene reiniettata a ogni compaction, come qualsiasi altra memoria di
progetto.

**Per chiamata di tool, finché `graphify-out/graph.json` esiste.** Questo è il costo che
sfugge. Gli hook intercettano `Bash|Grep` e `Read|Glob`, quindi scattano sulle due azioni
più frequenti dell'agente, e il testo iniettato è un obbligo, non un suggerimento.

| Hook | Scatta su | Iniettato | ≈ token |
|---|---|---|---|
| `hook-guard search` | ogni comando di ricerca in Bash e ogni chiamata a Grep | 190 caratteri | ~48 |
| `hook-guard read` | ogni Read e Glob di codice indicizzato, fresco e interno al progetto | 400 caratteri | ~100 |
| `hook-guard read` (grafo stale) | come sopra, quando il file è cambiato dopo l'ultima build | 239 caratteri | ~60 |
| `hook-guard read --strict` | prima lettura di questo tipo nella sessione — un `deny` netto | 421 caratteri | ~105 |

Una sessione con 30 letture e 10 grep paga ~3,5k token solo di nudge. È il prezzo del
cambio di comportamento, e vale la pena pagarlo solo se poi l'agente interroga davvero il
grafo invece di leggere comunque.

**Su richiesta.** Il corpo della skill entra in contesto solo quando invochi `/graphify`.

| File | Dimensione | ≈ token |
|---|---|---|
| `SKILL.md` | 41,2 KB | ~10,3k |
| `references/query.md` | 13,5 KB | ~3,4k |
| `references/update.md` | 10,4 KB | ~2,6k |
| `references/extraction-spec.md` | 8,0 KB | ~2,0k |
| `references/exports.md` | 3,4 KB | ~0,8k |
| `references/transcribe.md` | 3,2 KB | ~0,8k |
| `references/add-watch.md` | 2,5 KB | ~0,6k |
| `references/github-and-merge.md` | 2,2 KB | ~0,5k |
| `references/hooks.md` | 1,3 KB | ~0,3k |

Il `SKILL.md` da 41 KB è il corpo di skill più costoso che loadout documenti. Invocare
`/graphify` costa più o meno quanto tre compaction di overhead sempre attivo: costruisci
il grafo deliberatamente e poi resta sulla CLI — `graphify explain` e `graphify path` sono
normali comandi di shell e non caricano la skill.

## Quanto costa davvero una build

Misurato sul repository di graphify stesso — 483 file di codice, `--code-only`, 4 worker
di estrazione, nessuna API key:

| | |
|---|---|
| Tempo reale, build a freddo | 4m 10s |
| Tempo reale, `graphify update .` dopo aver toccato un file | 41s |
| Grafo | 12.504 nodi, 26.145 archi, 639 community |
| `graph.json` | 15,4 MB |
| `GRAPH_REPORT.md` | 236 KB — **~59k token, non leggerlo mai intero** |
| `graphify-out/` su disco | 34 MB (17 MB di cache) |
| Crediti LLM per il codice | 0 — AST via tree-sitter, tutto in locale |

Il codice è gratis. Tutto il resto no: lo stesso repository contiene 368 documenti, 1
paper e 5 immagini, e l'estrazione si rifiuta di partire senza `GEMINI_API_KEY`,
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY` o equivalente, a meno di passare `--code-only`. Lo
slogan "0 crediti LLM" è vero per il codice e solo per il codice.

## Verdetto comando per comando

Dimensioni di output misurate, stesso repository e stesso grafo.

| Comando | Output | Verdetto | Perché |
|---|---|---|---|
| `graphify explain "<symbol>"` | 1,2 KB, ~290 token | Tienilo — è tutto il valore | 14 archi con direzione, confidenza `EXTRACTED`/`INFERRED` e `file:riga` per ognuno. Più economico e più completo di un grep più due letture di file. |
| `graphify path "<A>" "<B>" --undirected` | ~130 byte | Tienilo | Risponde a "come sono collegate queste due cose" in una riga. Passa `--undirected`, altrimenti ti dirà che non esiste un percorso dove esiste eccome. |
| `graphify update .` | — | Tienilo, ma eseguilo tu | 41s e sposta il grafo (12,5k → 15,5k nodi, 639 → 1008 community toccando un solo file). Economico in token, non in tempo. |
| `graphify query "<question>"` | 6,7 KB, ~1,7k token | Situazionale, e spesso in perdita | Si autotronca a un budget di ~2000 token. Su "how does the hook guard nudge the agent?" ha restituito 61 nodi su 190, in gran parte docstring di test; `grep -rn hook_guard --include=*.py` è costato 844 byte (~210 token) e ha risposto meglio. Usalo per orientarti in un repository sconosciuto, non per domande di cui sai già nominare il simbolo. |
| `GRAPH_REPORT.md` | 236 KB | Salta, se non lo affetti | A ~59k token è un evento per la finestra di contesto. La skill dice "solo per una review architetturale ampia" e lo dice seriamente. |
| `graph.html` | — | Tienilo, per gli umani | Costo in token zero: è un artefatto per il browser, non contesto dell'agente. Oltre i 5.000 nodi aggrega a livello di community. |
| Gli hook `PreToolUse` | ~48–105 token per chiamata di tool | Situazionale, misura prima di tenerli | Sono la differenza tra un grafo che possiedi e un grafo che l'agente usa. E tassano ogni lettura per il resto della sessione. Installali per progetto, non globalmente. |
| Modalità `--strict` | 421 caratteri, una volta per sessione | Situazionale | Nega la prima lettura grezza della sessione e reindirizza a `graphify query`. Non può mai bloccare l'agente, ma consuma un turno. |

## Interazione con loadout

graphify è una capacità, superpowers è un processo. Non si sovrappongono e si compongono
in una sola direzione: una skill di processo decide cosa costruire, graphify risponde alle
domande strutturali che emergono strada facendo. In pratica il grafo dà il meglio durante
`brainstorming` e `systematic-debugging`, dove la domanda è "cosa tocca questa cosa"
piuttosto che "cosa fa questa riga".

La precedenza non cambia: istruzioni dirette, poi `CLAUDE.md` / `AGENTS.md`, poi i
workflow delle skill, poi il comportamento di default. Nota che graphify si installa
*dentro* `CLAUDE.md`, il che lo mette un gradino sopra le preferenze di qualsiasi skill —
comprese le sue.

Questo repository è un cattivo candidato, e vale la pena dirlo chiaramente: loadout è
prosa e JSON, nessun codice applicativo. `--code-only` non indicizzerebbe quasi nulla, e
un'estrazione completa fatturerebbe tutto il catalogo tramite una API di modello.

## Trappole

- **Il pacchetto PyPI è `graphifyy`, con due y.** La CLI resta `graphify`. Gli altri
  pacchetti `graphify*` su PyPI non sono affiliati.
- **`uvx graphify …` fallisce.** `uv tool run` legge il nome del *pacchetto*:
  `uvx --from graphifyy graphify install`.
- **`graphify install` e `graphify claude install` sono due installazioni diverse.** La
  prima ti dà una skill da invocare. La seconda è il livello sempre attivo — regole in
  `CLAUDE.md` più i due hook. Installare solo la prima significa pagare ~145 token per
  sessione senza che cambi nulla finché non digiti `/graphify`.
- **Un grafo stale è peggio di nessun grafo.** L'hook di lettura ammorbidisce il testo
  quando il file di destinazione è cambiato dopo l'ultima build, ma il grafo continua a
  servire archi vecchi finché non lanci `graphify update .`. Il suo git hook
  (`graphify hook install`) ricostruisce al commit e al cambio di branch, il che copre i
  commit e non l'ora di editing che li precede.
- **`path` è diretto per default** e riporterà l'assenza di percorso tra una funzione e il
  suo stesso chiamante. `--undirected` è quasi sempre quello che vuoi.
- **L'estrazione si rifiuta di partire su un repository misto senza API key.** Esce
  elencando le chiavi che accetta. `--code-only` è la via gratuita: salta del tutto
  documenti, paper e immagini.
- **Le grammatiche mancanti falliscono in silenzio, per linguaggio.** Sul suo stesso
  repository, i file `.sql`, `.dm`, `.lisp`, `.robot` e `.resource` non hanno contribuito
  nulla al grafo — ognuno richiede il proprio extra (`graphifyy[sql]`, `[dm]`,
  `[commonlisp]`, `[robot]`). La build stampa un warning e tira avanti, quindi un
  linguaggio può essere silenziosamente assente da un grafo di cui ti fidi.
- **`graphify-out/` è 34 MB di artefatti di build.** Mettilo in `.gitignore` prima della
  prima build, non dopo.
