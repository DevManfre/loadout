# superpowers

Skill di processo per Claude Code: fa precedere il brainstorming a ogni lavoro creativo,
impone il TDD red/green, guida il debugging in modo sistematico invece che a tentativi,
fa eseguire l'implementazione tramite subagent con gate di revisione, e insegna al
modello a creare e testare nuove skill. Cambia *come* l'agente lavora, non aggiunge una
capacità.

| | |
|---|---|
| Upstream | https://github.com/obra/superpowers |
| Autore | Jesse Vincent |
| Licenza | MIT |
| Versione esaminata | 6.3.0 |
| Contenuto | 14 skill, 0 comandi, 0 agent, 1 hook `SessionStart` |

## Installazione

Tramite loadout:

```
/plugin marketplace add DevManfre/loadout
/plugin install superpowers@loadout
```

Direttamente dalla directory ufficiale di Anthropic, che lo distribuisce anch'essa:

```
/plugin install superpowers@claude-plugins-official
```

Entrambe le vie scaricano lo stesso repository upstream. Loadout non vendorizza nulla e
non aggiunge codice — quello che aggiunge è il conteggio dei costi e i verdetti per
singola skill qui sotto. Installalo dove preferisci; leggi questa pagina in ogni caso.

## Consumo di token

Un costo è incondizionato. L'hook `SessionStart` del plugin intercetta
`startup|clear|compact` e inietta il testo completo di `using-superpowers` — 3.1 KB,
circa 800 token — a ogni avvio di sessione, a ogni `/clear`, e dopo **ogni compaction**.
In una sessione lunga con più compaction lo paghi più volte.

Tutto il resto è a richiesta: il corpo di una skill entra nel contesto solo quando viene
invocata. Le dimensioni sotto sono del solo `SKILL.md`, e dell'intera directory quando
una skill porta con sé file di riferimento che può a sua volta richiamare.

| Skill | SKILL.md | ≈ token | Albero completo |
|---|---|---|---|
| brainstorming | 15.5 KB | ~3.9k | 80 KB |
| dispatching-parallel-agents | 6.1 KB | ~1.5k | 6 KB |
| executing-plans | 2.3 KB | ~0.6k | 2 KB |
| finishing-a-development-branch | 7.8 KB | ~1.9k | 8 KB |
| receiving-code-review | 6.2 KB | ~1.6k | 6 KB |
| requesting-code-review | 3.0 KB | ~0.7k | 9 KB |
| subagent-driven-development | 32.3 KB | ~8.1k | 57 KB |
| systematic-debugging | 9.5 KB | ~2.4k | 41 KB |
| test-driven-development | 9.0 KB | ~2.3k | 17 KB |
| using-git-worktrees | 6.8 KB | ~1.7k | 7 KB |
| using-superpowers | 3.1 KB | ~0.8k | 17 KB |
| verification-before-completion | 3.6 KB | ~0.9k | 4 KB |
| writing-plans | 7.1 KB | ~1.8k | 9 KB |
| writing-skills | 26.4 KB | ~6.6k | 107 KB |

Leggilo come un budget, non come un avvertimento. `verification-before-completion` costa
meno di mille token e può salvare un'intera sessione partita nella direzione sbagliata.
`writing-skills` ne costa settemila ed è un costo giustificato esattamente una volta per
ogni skill che scrivi.

## Verdetto skill per skill

| Skill | Dimensione | Verdetto | Perché |
|---|---|---|---|
| using-superpowers | 3.1 KB | Da tenere — non hai scelta | L'hook la inietta ogni sessione. È l'indice che fa scattare le altre. |
| brainstorming | 15.5 KB | Da tenere | La skill a più alta resa dell'insieme: blocca l'implementazione finché non approvi un intento dichiarato. La maggior parte del lavoro sprecato dell'agente nasce dal saltare questo passaggio. |
| verification-before-completion | 3.6 KB | Da tenere | Il guadagno reale più economico qui. Impone prove prima di ogni affermazione "funziona". |
| systematic-debugging | 9.5 KB | Da tenere | Trasforma il "provo una correzione e vedo" in un ciclo di ipotesi. Si ripaga al primo bug non ovvio. |
| test-driven-development | 9.0 KB | Da tenere, se hai un test runner | Red/green rigoroso. In un repo senza test da eseguire è solo attrito senza beneficio. |
| requesting-code-review | 3.0 KB | Da tenere | Piccola, e consegna al revisore un contesto costruito ad hoc invece dell'intero transcript. |
| receiving-code-review | 6.2 KB | Situazionale | Utile quando il feedback di revisione è sbagliato e altrimenti saresti d'accordo comunque. Da saltare se rivedi da solo il tuo lavoro. |
| writing-plans | 7.1 KB | Situazionale | Si ripaga su lavori multi-sessione. Overhead su una modifica a un solo file. |
| executing-plans | 2.3 KB | Situazionale | Solo dopo che `writing-plans` ha prodotto un piano. Abbastanza economica da essere gratuita. |
| subagent-driven-development | 32.3 KB | Situazionale, e costosa | Forte per piani lunghi con task indipendenti. Il costo di contesto singolo più alto dell'insieme — non invocarla per fare una sola cosa. |
| dispatching-parallel-agents | 6.1 KB | Situazionale | Si ripaga solo con task davvero indipendenti e senza stato condiviso. |
| using-git-worktrees | 6.8 KB | Situazionale | Vale la pena per lavori su feature che non devono disturbare il tuo workspace. Ignorala per modifiche che faresti comunque subito commit. |
| finishing-a-development-branch | 7.8 KB | Situazionale | Codifica la decisione merge/rebase/PR a fine branch. Da saltare se quella decisione è già abitudine. |
| writing-skills | 26.4 KB | Da saltare finché non scrivi una skill | Eccellente e molto grande. Invocala deliberatamente, mai di passaggio. |

## Interazione con loadout

Superpowers definisce il *processo*; gli asset propri di loadout fanno il lavoro di
dominio al suo interno. Quando entrambi si applicano, la skill di processo viene prima —
brainstorming, poi implementazione.

Precedenza, dalla più forte alla più debole: le tue istruzioni dirette, poi `CLAUDE.md` /
`AGENTS.md`, poi i workflow delle skill, poi il comportamento predefinito. Una convenzione
di repo in `CLAUDE.md` prevale su qualsiasi cosa prescriva una skill; è voluto, e
superpowers stessa lo dichiara.

In questo repository, `brainstorming` e `commit-convention` si compongono esattamente
così: brainstorming decide cosa si costruisce, `commit-convention` decide come viene
formulato il commit, e nessuna delle due prevale sull'altra.

## Insidie

- **L'hook scatta anche in compaction.** Non solo all'avvio. Le sessioni lunghe pagano
  ripetutamente l'iniezione di `using-superpowers`.
- **`brainstorming` è un gate rigido.** Rifiuterà di scrivere codice finché non hai
  approvato un intento dichiarato, anche per modifiche che consideri banali. È voluto,
  e talvolta è irritante.
- **Le skill si autoinvocano in modo aggressivo.** `using-superpowers` istruisce il
  modello a invocare una skill ogni volta che c'è anche una minima possibilità che si
  applichi. Aspettati più invocazioni di skill di quante ne sceglieresti a mano.
- **Scrive nel tuo repo.** L'hook `SessionStart` aggiunge una voce `.gitignore` per
  `docs/superpowers`, la sua directory scratch per spec e piani. Innocuo, ma appare come
  una modifica non tracciata su un albero pulito.
- **Nessun comando, nessun agent.** È tutto skill più quel singolo hook. Non c'è nessun
  comando slash da scoprire.
