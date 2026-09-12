# ui-ux-pro-max

Un plugin di design che risponde con dati invece che con prosa. Dove `frontend-design`
argomenta il gusto in circa 2.350 token di corpo, questo spedisce un database locale — 79
stili, 192 palette con profili di ragionamento, 74 abbinamenti di font, 119 linee guida
UX, 105 icone, 25 tipi di grafico, 22 stack di implementazione — e uno script Python che
lo interroga. I 3,1 MB di CSV e JSON non entrano mai nella finestra di contesto: il
modello esegue `search.py`, legge le poche centinaia di caratteri che tornano e decide.
L'architettura è tutta qui, ed è il motivo per cui un asset di queste dimensioni risulta
sostenibile.

Il prezzo sono le sette skill. Il plugin espone ogni directory sotto `.claude/skills/`,
quindi installare quella che ti serve installa anche `brand`, `slides` e `banner-design`, e
le loro descrizioni vengono caricate che tu faccia slide o no. Sono ~683 token fissi, la
cifra sempre attiva più alta di questo catalogo, contro i ~70 di `frontend-design` e i
~560 di `impeccable`. Niente nel plugin permette di rimettere fuori sei skill su sette.

| | |
|---|---|
| Upstream | https://github.com/nextlevelbuilder/ui-ux-pro-max-skill |
| Autore | nextlevelbuilder |
| Licenza | MIT (`LICENSE`, e `"license": "MIT"` in `.claude-plugin/plugin.json`) |
| Versione ispezionata | v2.13.0, commit `7f69fed6a271`, ispezionato il 2026-09-12 |
| Contenuti | 7 skill, 0 comandi, 0 agent, 0 hook |

## Installazione

Non sta nella directory ufficiale di Anthropic, quindi il marketplace va aggiunto prima:

```bash
claude plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill
claude plugin install ui-ux-pro-max@ui-ux-pro-max-skill
```

`scripts/loadout install` esegue esattamente quei due comandi, insieme al resto di loadout.

Per toglierlo dal contesto senza disinstallarlo:

```bash
claude plugin disable ui-ux-pro-max
```

Lo script di ricerca ha bisogno di Python 3.x e di nient'altro — ogni import è libreria
standard (`argparse`, `csv`, `json`, `difflib`, `urllib.parse`, …) e a runtime non c'è
alcuna chiamata di rete. Senza Python i corpi delle skill si caricano lo stesso e il
database resta irraggiungibile, cioè sparisce tutto il valore: per questo `python3` è
portato come dipendenza `warn` e non `block`.

## Consumo di token

Tre budget, misurati qui al pin indicato sopra. I token sono caratteri ÷ 4, arrotondati.

**Sempre attivo, per sessione.** Pagato prima che tu scriva qualcosa. `plugin.json` punta
`skills` su `./.claude/skills/`, quindi tutte e sette finiscono nell'indice.

| Skill | descrizione | ≈ token |
|---|---|---|
| `design` | 639 car | ~159 |
| `ui-ux-pro-max` | 497 car | ~124 |
| `ui-styling` | 489 car | ~122 |
| `banner-design` | 445 car | ~111 |
| `design-system` | 276 car | ~69 |
| `brand` | 183 car | ~45 |
| `slides` | 140 car | ~35 |
| **Totale, nomi compresi** | **2.735 car** | **~683** |

**Per tool call o per prompt.** Zero. Il plugin non spedisce alcuna directory `hooks/`,
quindi non scatta niente su `Edit`, su `Write`, su un prompt o su una compaction.

**A richiesta.** I corpi si caricano solo all'invocazione della skill, e i due file di
reference grossi solo quando il corpo dice al modello di leggerli.

| File | dimensione | ≈ token |
|---|---|---|
| `ui-ux-pro-max/SKILL.md` | 15,9 KB | ~3.980 |
| `design/SKILL.md` | 13,3 KB | ~3.337 |
| `ui-styling/SKILL.md` | 10,6 KB | ~2.656 |
| `design-system/SKILL.md` | 7,4 KB | ~1.853 |
| `banner-design/SKILL.md` | 7,0 KB | ~1.752 |
| `brand/SKILL.md` | 3,5 KB | ~878 |
| `slides/SKILL.md` | 1,7 KB | ~429 |
| `ui-ux-pro-max/references/quick-reference.md` | 24,5 KB | ~6.130 |
| `ui-ux-pro-max/references/pro-rules.md` | 10,9 KB | ~2.730 |

**Per ricerca, che è la cifra che si ripete davvero.** Misurata sulla query
`"developer tooling catalog site"`:

| Invocazione | output | ≈ token |
|---|---|---|
| `--design-system -p "<nome>"` (formato di default) | 8.015 car di box drawing e colore ANSI | ~2.000 nominali, di più nella pratica |
| `--design-system -p "<nome>" -f markdown` | 2.981 car | ~745 |
| `--domain style` | 419 car | ~105 |
| `--stack react` | 367 car | ~92 |

Il formato di default disegna una cornice in caratteri box Unicode e colora i campioni con
escape ANSI. Entrambi tokenizzano male — una sequenza di `═` e un `\x1b[38;2;30;41;59m`
costano molto più di quanto suggerisca il conteggio caratteri — quindi il divario di 2,7×
qui sopra è un minimo, non la cifra reale. Aggiungi `-f markdown` a ogni chiamata.

**Cosa ottieni in cambio.** Una palette, un abbinamento di font e un pattern di layout
scelti da un catalogo invece che improvvisati, in ~105 token per una query di dominio
mirata. Il risparmio è un secondo giro di generazione evitato: quando una pagina torna con
la direzione visiva sbagliata la correzione è una riscrittura, migliaia di token più il
giro di review che l'ha chiesta. Il pareggio al prezzo sempre attivo è circa una
riscrittura evitata ogni sette sessioni; al prezzo invocato una singola query `--domain` si
ripaga subito. La forma in cui non conviene è una macchina che spedisce soprattutto
backend: ~683 token a sessione non comprano niente in una giornata senza UI.

## Verdetto, voce per voce

| Skill | Dimensione | Verdetto | Perché |
|---|---|---|---|
| ui-ux-pro-max | 15,9 KB | Tieni se spedisci UI | Il database e il contratto di query sono la voce. Tutto il resto qui è un satellite. |
| design | 13,3 KB | Situazionale — pagina o flusso interi | Si sovrappone a `ui-ux-pro-max` su stile e palette; conviene invocarla per nome quando si imposta una schermata intera, non per il fix di un componente. |
| ui-styling | 10,6 KB | Situazionale — lavoro legato allo stack | Rende quando lo stack di implementazione è uno dei 22 che conosce. Su uno stack non elencato degrada a consigli generici. |
| design-system | 7,4 KB | Situazionale — architettura dei token | Invocala quando token, scale e theming sono il deliverable. Altrimenti l'output della skill principale porta già le decisioni. |
| banner-design | 7,0 KB | Salta | Formati di banner per adv e social. Niente nel lavoro di questo repo la tocca, e costa ~111 token a sessione portarla. |
| brand | 3,5 KB | Salta | Regole di logo, framework di voce, template di brand guideline. La metà utile della brand identity sta dietro il tier premium dell'upstream. |
| slides | 1,7 KB | Salta | Presentazioni. La più economica delle tre con ~35 token, e comunque inutilizzata. |

Tre Salta su cui non si può agire: il plugin non ha un interruttore per singola skill. Il
verdetto è registrato perché i ~191 token che costano siano una spesa nota, non una
sorpresa.

## Interazione con il resto di loadout

Incontra `frontend-design` e `impeccable`, e i tre non fanno lo stesso mestiere.
`frontend-design` scrive il brief e argomenta sulla direzione prima che il codice esista.
`ui-ux-pro-max` risponde al brief con valori precisi — questa palette, questo abbinamento,
questo pattern. Il detector `PostToolUse` di `impeccable` controlla il risultato dopo ogni
edit. Brief, decisione, cancello.

| Voce | Sempre attivo | Hook |
|---|---|---|
| frontend-design | ~70 | nessuno |
| impeccable | ~560 | `PostToolUse`, `Stop` |
| ui-ux-pro-max | ~683 | nessuno |
| tutte e tre | ~1.313 | 2 |

Portarle tutte e tre costa ~1.313 token a sessione e nessun hook in più. Se è troppo,
l'ordine in cui lasciarle fuori è `ui-ux-pro-max` per prima su una macchina backend,
`impeccable` per prima quando il consiglio conta più dell'imposizione, e `frontend-design`
per ultima — a ~70 token sta sotto la soglia di rumore in ogni caso.

`ui-ux-pro-max` non aggiunge nulla al conteggio degli hook. I plugin di questo catalogo che
fanno scattare hook restano caveman (`SessionStart`, `UserPromptSubmit`), superpowers
(`SessionStart`) e impeccable (`PostToolUse`, `Stop`).

## Trappole

- **Il database manca il bersaglio sui prodotti di nicchia.** `"developer tooling catalog
  site" --domain style` restituisce `Found: 0 results` e propone `analog, tool` come
  termini più vicini. Il catalogo è costruito attorno a categorie di prodotto consumer. Il
  corpo della skill gestisce la cosa onestamente — impone un solo tentativo più stretto e
  poi una dichiarazione esplicita che nessuna corrispondenza è stata trovata — ma il giro
  sprecato è reale, e su un prodotto abbastanza insolito ogni query finisce così.
- **Il formato di output di default è quello caro.** Box drawing più colore ANSI, 2,7× i
  caratteri di `-f markdown` per lo stesso contenuto e peggio sotto il tokenizer. Niente ti
  avverte; aggiungi il flag.
- **Sette skill, una sola installazione.** `plugin.json` imposta
  `"skills": "./.claude/skills/"`, quindi `brand`, `slides` e `banner-design` finiscono
  nell'indice a ogni sessione, che la macchina faccia banner o no. ~191 dei ~683 token non
  comprano nulla su una macchina da sviluppo.
- **Le descrizioni citano i numeri del proprio database.** La descrizione della skill
  principale elenca "79 searchable styles (50 active), 192 product palettes…". Quei numeri
  non aiutano il modello a instradare verso la skill, allungano la stringa sempre attiva e
  cambiano a ogni release — il che vuol dire che le cifre di questa guida vanno rimisurate
  a ogni pin, non solo i totali.
- **Circa 9,6 MiB su disco.** `.claude/skills/` pesa 10.046.170 byte, di cui 3,1 MB sono la
  `data/` della skill principale (`google-fonts.csv` 747 KB,
  `phosphor-icons-upstream.json` 824 KB). Niente di tutto questo è contesto, tutto è tempo
  di clone e di update.
- **Esiste un tier premium.** Generazione di brand identity, design del logo, iconografia
  custom e l'architettura scalabile dei token si pagano a parte. Quanto misurato sopra è la
  metà MIT, che è la metà che questo catalogo porta.
- **Python non è opzionale nella pratica.** Senza `python3` i corpi si caricano lo stesso e
  ogni query fallisce, quindi paghi ~683 token a sessione per consigli che la skill stessa
  dice al modello di non usare senza verifica.
