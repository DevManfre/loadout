# caveman

Un plugin di stile. Non dà all'agente una nuova capacità — cambia il modo in cui l'agente
*scrive*: articoli, riempitivi, convenevoli e giri di parole spariscono, i frammenti sono
ammessi, i termini tecnici, il codice e i messaggi di errore restano esatti. Il risparmio
sta sul lato **output** del conto, e si paga con un costo permanente sul lato input: un
hook `SessionStart` che inietta il regolamento, un hook `UserPromptSubmit` che rimette un
promemoria a ogni turno, e un indice delle skill che tra le due revisioni misurate qui è
quadruplicato.

Se valga la pena portarselo dietro è interamente una questione di questo scambio, e i
numeri qui sotto sono l'unico modo onesto di rispondere.

| | |
|---|---|
| Upstream | https://github.com/JuliusBrussee/caveman |
| Autore | Julius Brussee |
| Licenza | MIT per `skills/`, BSL 1.1 per i componenti proxy/wrap (`LICENSING.md`); GitHub segnala l'intero repository come `NOASSERTION` |
| Versione ispezionata | `v2.6.0` (2026-09-04), e il pin più vecchio `84cc3c14fa1e` (2026-04-18) per confronto |
| Contenuto (`v2.6.0`) | 20 skill, 6 comandi, 3 sub-agent, 2 hook (`SessionStart`, `UserPromptSubmit`), marketplace manifest proprio |

## Installazione

Questo non è nella directory ufficiale di Anthropic, quindi va prima aggiunto il suo
marketplace. `scripts/install-all.sh` esegue entrambi i comandi per te:

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin install caveman@caveman
```

`claude plugin install` fissa la HEAD del marketplace del giorno in cui lo esegui. Qui
quel pin conta più che in qualsiasi altra voce del catalogo — vedi la tabella dei token,
dove due pin dello stesso plugin differiscono di un fattore tre.

Spegnilo per una sessione senza disinstallarlo:

```text
stop caveman
```

Oppure toglilo del tutto dal contesto:

```bash
claude plugin disable caveman
```

## Economia dei token

Tre budget. Ogni cifra è stata misurata eseguendo gli hook del plugin e contando i byte
che emettono, sulle due revisioni indicate sopra — niente è copiato dal README upstream.

**Sempre attivo, per sessione.** Lo paghi prima di aver scritto qualsiasi cosa.

| Fonte | `84cc3c14fa1e` | `v2.6.0` |
|---|---|---|
| Descrizioni delle skill nell'indice | 1.281 caratteri · ~320 token (5 skill) | 3.213 caratteri · ~800 token (20 skill) |
| Descrizioni dei sub-agent nell'indice | nessuna | ~1.000 caratteri · ~250 token (3 agent `cavecrew`) |
| Iniezione del regolamento da `SessionStart` | 1.847 caratteri · ~460 token | 5.290 caratteri · ~1.320 token |
| Sollecito statusline da `SessionStart`, finché non configurata | assente | ~450 caratteri · ~110 token |
| **Totale** | **~780 token** | **~2.480 token** |

L'hook `SessionStart` non dichiara alcun matcher, quindi scatta a ogni origine: avvio,
ripresa, `/clear` **e ogni compaction**. In una sessione lunga lo paghi più volte.

**Per singolo prompt.** È il costo che sfugge a tutti, ed è incondizionato finché il file
di stato esiste.

| Revisione | Iniettato a ogni prompt | ≈ token |
|---|---|---|
| `84cc3c14fa1e` | 122 caratteri | ~30 |
| `v2.6.0` | 245 caratteri | ~60 |

Una sessione da 40 turni su `v2.6.0` spende ~2,4k token solo di rinforzo, oltre ai ~2,5k
già pagati all'avvio e di nuovo a ogni compaction.

**Su richiesta.** I corpi delle skill entrano in contesto solo se invocati, e su `v2.6.0`
non sono piccoli: `caveman-setup` 10,5 KB, `caveman-learn` 9,2 KB, `caveman` stessa 7,0 KB,
`caveman-discover` 5,3 KB. Le sei skill di processo da una pagina (`investigate-first`,
`lean-build`, `migration`, `safe-refactor`, `surgical-patch`, `verify-and-stop`) stanno
sui ~700–1.100 byte l'una.

**Cosa ti restituisce.** L'upstream misura 10 task e riporta l'output che scende da una
media di 1.214 token a 294 — un taglio del 65%, nel migliore dei casi 87%, nel peggiore
22% — e, va riconosciuto, documenta i casi in cui perde in `docs/HONEST-NUMBERS.md`.
Loadout non ha riprodotto quel benchmark: il dato sull'output è dell'upstream, i costi in
input qui sopra sono nostri.

L'aritmetica che decide: l'output deve ridursi di più di ~2,5k token per sessione più ~60
per turno perché il plugin vada in pari sui soli token. In una sessione di risposte lunghe
e discorsive è facile. In una sessione di tool call, diff e conferme brevi — la forma che
il lavoro con un agente ha davvero — l'output è già asciutto e non c'è niente da tagliare:
paghi il costo in input e non torna indietro nulla. La vittoria affidabile è la
leggibilità e la velocità, non la fattura.

## Verdetto, per singola skill

Misurato su `v2.6.0`.

| Skill | Dimensione | Verdetto | Perché |
|---|---|---|---|
| caveman | 7,0 KB | Tenere — è il plugin | La modalità stessa. Tutto il resto le gira intorno ed è opzionale. |
| caveman-help | 2,2 KB | Tenere | Scheda di riferimento una tantum, nessuno stato persistente. Costa poco. |
| caveman-review | 2,6 KB | Tenere | Una riga per rilievo: posizione, problema, correzione. I commenti di review sono esattamente il caso di output verboso su cui la compressione funziona. |
| caveman-compress | 4,7 KB | Situazionale | Comprime `CLAUDE.md` e altri file di memoria sul posto. Risparmio in input reale e permanente — ma riscrive la tua fonte di verità e tiene solo un backup `.original.md`. Leggi il diff. |
| verify-and-stop | 0,7 KB | Situazionale | Si sovrappone a `superpowers:verification-before-completion`, che è più severa. Ridondante se porti superpowers. |
| investigate-first | 0,7 KB | Situazionale | Stesso rapporto con `superpowers:systematic-debugging`. |
| surgical-patch / safe-refactor / lean-build / migration | ~0,7–1,1 KB l'una | Situazionale | Spinte di processo sottili. Innocue a questa dimensione, ma ripetono terreno che superpowers copre già meglio. |
| caveman-explore | 2,0 KB | Situazionale | Si sovrappone all'agent `Explore` integrato e, se lo porti, alle query sul grafo di graphify. |
| cavecrew + 3 agent `cavecrew-*` | 3,6 KB + ~4,5 KB | Situazionale, costoso | Un intero strato di delega a sub-agent innestato su un plugin di stile. Paga il costo dell'indice degli agent a ogni sessione, che tu deleghi o no. |
| caveman-commit | 2,4 KB | Saltare in questo repo | Scrive Conventional Commits. Il formato di questo repo è `<gitmoji> <SCOPE> - <subject>`: usa la skill **commit-convention**. |
| caveman-setup | 10,5 KB | Saltare | Il corpo più grande del set, ed esiste per configurare il plugin. Semmai, eseguila a mano una volta. |
| caveman-learn | 9,2 KB | Saltare | Secondo corpo più grande, materiale didattico più che capacità operativa. |
| caveman-stats / caveman-manage / caveman-optimize / caveman-discover / caveman-evidence-review | 1,0–5,3 KB | Saltare | Autogestione del plugin e scoperta dell'ecosistema. Contesto speso sullo strumento invece che sul tuo lavoro. |

## Interazione con il resto di loadout

Ora due hook `SessionStart` scattano insieme: superpowers inietta ~800 token di
`using-superpowers`, caveman ne inietta ~1,3k di regolamento. Entrambi ripartono su
`/clear` e a ogni compaction, quindi una sessione con molte compaction paga ogni volta
~2,1k token di preambolo di stile e processo. È la ragione principale per pensarci prima
di aggiungere un terzo plugin con hook.

I due non si contendono il comportamento: superpowers governa *cosa succede dopo*, caveman
governa *come è formulato il risultato*. La regola Auto-Clarity di caveman abbandona già
il registro compresso per gli avvisi di sicurezza, le conferme di azioni irreversibili e
le sequenze in più passi, cioè esattamente dove stanno i gate di superpowers.

Contro gli asset di loadout: `commit-convention` batte `caveman-commit` — il formato di
casa non è Conventional Commits, e caveman per sue stesse regole scrive comunque commit,
PR e testi delle issue in inglese normale. Contro graphify: nessuna sovrapposizione,
strato diverso.

## Trappole

- **L'hook per-prompt non si ferma da solo.** Finché `~/.claude/.caveman-active` esiste,
  ogni singolo messaggio utente si porta dietro il promemoria. Dire "stop caveman" rimuove
  il file; disinstallare il plugin non serve, e disabilitarlo non equivale a cancellare il
  file di stato.
- **`SessionStart` non ha matcher.** Scatta ad avvio, ripresa, `/clear` e a ogni
  compaction — lo stesso comportamento di iniezione ripetuta di superpowers, raddoppiato.
- **Aggiornare il pin triplica il costo sempre attivo.** Tra `84cc3c14fa1e` di aprile e
  `v2.6.0` le skill sono passate da 5 a 20, sono comparsi tre sub-agent e il costo per
  sessione è andato da ~780 a ~2.480 token. Niente ti avvisa: `claude plugin update` se lo
  prende e basta.
- **Ti sollecita a configurare una statusline.** Finché `statusLine` non è impostata in
  `settings.json`, l'hook aggiunge ~450 caratteri che chiedono all'agente di proporsi
  spontaneamente per configurarla. O la configuri, o accetti la richiesta ricorrente.
- **Licenza mista.** `skills/` è MIT secondo `LICENSING.md`, ma il repository distribuisce
  anche componenti BSL 1.1 e GitHub risolve l'intero repository come `NOASSERTION`.
  Irrilevante per usare il plugin, rilevante nel momento in cui qualcuno ne copia il codice.
- **Il repository non è più piccolo.** `v2.6.0` porta un modulo Go, un proxy, un server MCP
  e uno strato di navigazione. `claude plugin install` clona tutto; in contesto arrivano
  solo skill, agent e hook, ma il costo su disco è reale.
- **Il 65% è una misura solo sull'output.** L'upstream lo dice chiaramente. I token di input
  e di ragionamento non cambiano, e con questo plugin salgono.
