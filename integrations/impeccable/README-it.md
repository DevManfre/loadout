# impeccable

Un plugin di fluenza progettuale. Non fa scrivere all'agente codice frontend che prima
non sapeva scrivere; dà a quel codice un vocabolario e un pavimento. Una sola skill
espone 23 comandi con nome — `polish`, `audit`, `typeset`, `colorize`, `layout`,
`critique` e gli altri — e un detector compilato gira dopo ogni modifica, a caccia delle
spie meccaniche della UI generata dall'AI: testo in gradiente, aloni colorati a offset
zero, contrasto sotto WCAG AA, deriva dal design system. Il compromesso è insolito per
questo catalogo. Il costo sempre attivo è basso, perché il plugin spedisce una sola
descrizione di skill e quattro descrizioni di sub-agent e non dichiara alcun hook
`SessionStart`. Quello che paghi è invece contato a modifica, e solo sui file che
sembrano UI. In una sessione backend costa ~560 token e poi non parla più; in una
sessione di lavoro frontend intenso può aggiungerne diverse migliaia.

| | |
|---|---|
| Upstream | https://github.com/pbakaus/impeccable |
| Autore | Paul Bakaus |
| Licenza | Apache-2.0 (`LICENSE`) |
| Versione ispezionata | plugin `v4.3.1`, commit del repo `cb56ed6` (2026-09-10), engine `0.1.5` |
| Contenuti | 1 skill (23 comandi), 4 sub-agent, 2 hook (`PostToolUse`, `Stop`), marketplace proprio, 39 documenti di reference, un binario di piattaforma scaricato |

## Installazione

Non è nella directory ufficiale di Anthropic, quindi va aggiunto prima il suo
marketplace. `scripts/install-all.sh` esegue entrambi i comandi al posto tuo:

```bash
claude plugin marketplace add pbakaus/impeccable
claude plugin install impeccable@impeccable
```

La prima volta che l'hook scatta scarica il binario dell'engine per la tua piattaforma
dal canale di release del progetto in `~/.impeccable/bin/<versione-engine>/` — circa
16 MB, e servono `curl` o `wget`. Punta `IMPECCABLE_HOME` altrove per spostare quella
cache, oppure `IMPECCABLE_BIN` a un binario preinstallato su una macchina senza uscita
di rete.

Spegni gli hook per un progetto senza disinstallare nulla, scrivendo
`.impeccable/config.json` nella radice del progetto:

```json
{ "hook": { "enabled": false } }
```

`{ "hook": { "quiet": true } }` tiene il detector ma elimina la conferma che stampa su
un file UI pulito — è la differenza fra pagare ~70 token per modifica UI e pagarne zero.
Oppure togli del tutto il plugin dal contesto:

```bash
claude plugin disable impeccable
```

## Consumo di token

Tre budget. Ogni cifra è stata prodotta qui eseguendo l'hook del plugin contro un
progetto di prova e contando i byte emessi, al pin indicato sopra. I token sono
caratteri ÷ 4, arrotondati.

**Sempre attivo, per sessione.** Pagato prima che tu scriva qualcosa.

| Sorgente | caratteri | ≈ token |
|---|---|---|
| Descrizione della skill nell'indice delle skill (1 skill) | 1.191 | ~300 |
| Descrizioni dei sub-agent nell'indice degli agent (4 agent) | 1.040 | ~260 |
| Iniezione `SessionStart` | nessuna | 0 |
| **Totale** | **2.231** | **~560** |

L'assenza di un hook `SessionStart` è la riga più importante di questa tabella. Ogni
altra voce del catalogo che porta hook ripaga il proprio costo di avvio a ogni `/clear`
e a ogni compaction; questa no.

**Per tool call.** L'hook `PostToolUse` ha matcher `Edit|Write`, quindi gira a ogni
singola modifica. Quanto costa dipende interamente da cosa è stato modificato:

| File modificato | Emesso | ≈ token |
|---|---|---|
| Qualsiasi estensione non rilevante per il design | 0 byte | 0 |
| `.ts` / `.js` senza alcun finding | 0 byte | 0 |
| File UI (`.tsx`, `.html`, `.css`, `.vue`, `.svelte`, …), pulito | 286 byte | ~70 |
| File UI, 3 finding (gradient-text, low-contrast, dark-glow) | 1.894 byte | ~475 |

Circa 1.000 byte del payload dei finding sono boilerplate fisso di triage; il resto
scala col numero di finding. L'hook `Stop` non dichiara matcher, quindi gira alla fine di
ogni turno con un budget di 30 secondi, ma deduplica rispetto a quanto il passaggio
per-modifica ha già riportato: misurato a **0 byte** su una sessione in cui ogni finding
era già emerso durante l'editing. Costa token solo quando dei finding sono stati
rimandati — che è il caso normale, dato che il passaggio per-modifica usa un set di
regole ridotto e rimanda a quel passaggio profondo i finding di gusto (ritmo del testo,
palette, cadenza del layout).

**Su richiesta.** Il corpo della skill si carica quando la skill viene invocata; ogni
comando tira esattamente un documento di reference.

| Sorgente | caratteri | ≈ token |
|---|---|---|
| Corpo di `SKILL.md` | 10.729 | ~2.700 |
| 39 documenti di reference, tutti quanti | 385.166 | ~96.000 |
| `new-work.md` | 53.325 | ~13.300 |
| `critique.md` | 42.682 | ~10.700 |
| `live.md` | 36.147 | ~9.000 |
| `document.md` | 27.428 | ~6.900 |
| `polish.md` | 6.632 | ~1.700 |
| `typeset.md` | 5.249 | ~1.300 |
| `colorize.md` | 4.537 | ~1.100 |
| `bolder.md` | 3.471 | ~870 |
| 4 corpi di sub-agent | 32.512 | ~8.100, nel contesto del sub-agent, non nel tuo |

La cifra da 96.000 non si paga mai in un colpo solo ed è elencata solo per mostrare la
dispersione. Quello che conta è che i comandi differiscono fra loro di un ordine di
grandezza: `bolder` è un errore di arrotondamento e `new-work` costa più dell'intero
CLAUDE.md di questo repo.

**Cosa ottieni in cambio.** I finding del detector sono meccanici e verificabili — un
rapporto di contrasto di 1,9:1 è un fatto, non un'opinione — e arrivano alla modifica
invece che in fase di review. La cosa che si evita è un giro di redesign: un agente che
rigenera un componente dopo che un umano ha detto "sembra fatto dall'AI" costa 3–8k
token di output più la lettura che segue. La galleria prima/dopo dell'upstream non è
riprodotta qui e nessuna sua affermazione è citata in questa guida.

**Punto di pareggio.** Una sessione frontend tipica da 20 modifiche UI, metà delle quali
con finding, costa `560 + 10×70 + 10×475` ≈ **6.000 token**. Si ripaga se evita che un
solo componente venga rifatto. Una sessione che non tocca alcun file UI costa ~560 token
e non restituisce nulla — la forma in cui questa voce è puro sovraccarico è il lavoro
backend o infrastrutturale, e lì la risposta giusta è `hook.enabled: false` nella config
di progetto, non la disinstallazione.

## Verdetto, per item

| Item | Dimensione | Verdetto | Perché |
|---|---|---|---|
| il detector `PostToolUse` | 0–1,9 KB per modifica | Keep | Silenzioso sui file non-UI, ~70 token su uno pulito. La parte più economica del plugin e l'unica che cambia il risultato senza che tu la chieda |
| `audit` | 8,5 KB | Keep | Passata sull'intera superficie di quanto il detector ha trovato, su richiesta |
| `polish` | 6,6 KB | Keep | Il verbo di default. Abbastanza economico da eseguirlo ripetutamente |
| `typeset` / `colorize` / `layout` | 4,5–5,2 KB | Keep | Una dimensione ciascuno, reference piccola, output concreto |
| `bolder` / `quieter` | 3,5–4,9 KB | Keep | Regolazione di intensità su un design esistente. I corpi più piccoli del set |
| `animate` / `delight` | 3,7–5,2 KB | Situational | Movimento e fronzoli sono la prima cosa da tagliare su uno strumento interno; valgono sulle superfici di brand |
| `init` | 11,4 KB | Situational | Conduce un'intervista di discovery e scrive `PRODUCT.md` e `DESIGN.md` nel tuo repo. Da eseguire una volta per progetto, a mano, o per niente |
| `critique` | 42,7 KB | Situational | ~10,7k token a invocazione. Vale per una review deliberata di una superficie; mai in loop |
| `new-work` | 53,3 KB | Situational | Il corpo più grande del set. È il percorso da zero — non lasciarlo caricare per una modifica a un componente esistente |
| `live` / `live-setup` | 36,1 + 8,2 KB | Situational | Scelta interattiva di varianti nel browser. Richiede un dev server attivo e il binario dell'engine; ~9k token prima di vedere qualcosa |
| `document` + `impeccable-documenter` | 27,4 + 3,1 KB | Skip | Genera un `DESIGN.md` dal codebase. Si sovrappone a quello che graphify già risponde sulla struttura, e loadout scrive i propri documenti a mano |
| `adapt.native` / `android` / `ios` | 3,8–8,4 KB | Skip | Target mobile nativi, fuori dallo scope frontend web che questo catalogo copre |
| `craft` | 0,5 KB | Skip | L'upstream lo marca come alias deprecato del normale flusso new-work |
| `impeccable-finish-reviewer` | 15,2 KB | Situational | Il sub-agent più grande. Gira nel proprio contesto, quindi non spende il tuo, ma è una seconda passata completa su lavoro già rivisto |

## Interazione col resto di loadout

È il terzo plugin con hook del catalogo, e il primo che non si aggiunge al preambolo di
sessione. superpowers e caveman scattano entrambi su `SessionStart` e insieme costano
~2,1k token a ogni compaction; impeccable aggiunge ~560 token una volta e nulla al
riscatto. Quello che aggiunge invece è un hook `PostToolUse` su `Edit|Write` accanto
all'iniezione per-lettura e per-grep di graphify — così una sessione che modifica file UI
ora paga graphify sulle letture e impeccable sulle scritture. Entrambi tacciono quando
non hanno nulla da dire, e nessuno dei due scatta sugli eventi dell'altro.

Verso superpowers: nessun conflitto, livello diverso. superpowers governa *se* il lavoro
parte e *se* è finito; impeccable giudica che aspetto ha il risultato. La sua passata
profonda su `Stop` e il gate di verifica di superpowers scattano entrambi a fine turno,
che è l'unico punto da tenere d'occhio se la latenza di turno inizia a pesare.

Verso caveman: nessuna. Caveman governa la prosa dell'agente, impeccable governa i pixel
dell'artefatto.

Verso graphify: nessuna sovrapposizione di capacità, ma `document` duplica terreno che
graphify già copre, ed è il motivo per cui sopra è marcato Skip.

## Gotcha

- **L'engine non è nel repository.** `claude plugin install` ti dà un launcher shell
  POSIX; la prima invocazione dell'hook scarica un binario di piattaforma da ~16 MB dal
  canale di release. Niente rete, o niente `curl`/`wget`, significa che il launcher esce
  con 127 ed entrambi gli hook sono morti — mentre la skill e i suoi documenti di
  reference continuano a funzionare. Per questo la dipendenza di questa voce è un `warn`,
  non un `block`.
- **Tre numeri di versione che non concordano.** `package.json` dice `4.1.0`, il manifest
  del plugin dice `4.3.1`, l'engine riporta `0.1.5`. Quello che determina il
  comportamento del detector è l'engine, ed è recuperato a runtime in base al file
  `VERSION` — quindi il comportamento può muoversi senza che il pin del plugin cambi.
- **Scrive dentro il tuo progetto.** `.impeccable/hook.cache.json` compare nella
  directory di lavoro alla prima scansione, e `init` si offrirà di aggiungere
  `PRODUCT.md` e `DESIGN.md` nella radice del repo. Aggiungi `.impeccable/` al
  `.gitignore` prima di installare.
- **L'hook `Stop` non ha matcher.** Gira alla fine di ogni turno con un timeout di 30
  secondi, anche quando finisce per non emettere nulla.
- **La passata per-modifica è deliberatamente incompleta.** Riporta solo il livello
  meccanico; i finding di gusto aspettano la passata su `Stop`. Impostare
  `hook.perEditRules: "all"` ripristina il set di regole completo a ogni modifica e
  moltiplica di conseguenza il costo per modifica.
- **Disco.** 2,2 MB di file di skill, più i 16 MB dell'engine fuori dalla directory del
  plugin, che disinstallare il plugin non rimuove.
