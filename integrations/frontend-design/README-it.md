# frontend-design

Il file di gusto che Anthropic usa per le interfacce generate. È una skill sola e nient'altro
— niente hook, niente sub-agent, niente comandi, nessun binario — quindi è la voce di
design più economica di questo catalogo. Il corpo è un'argomentazione più che una
checklist: progetta partendo dalla materia del brief, spendi l'audacia in un punto solo,
pianifica i token prima di scrivere CSS, evita i cinque grappoli visivi su cui le pagine
generate dall'AI continuano ad atterrare. Nomina persino la spia che qui conta di più — lo
sfondo crema caldo con accento terracotta vicino a `#D97757`, che è il colore di
interazione di Claude e quindi si legge come una firma su qualsiasi brief che non l'abbia
chiesto.

Il compromesso è insolitamente pulito. Il costo sempre attivo è una descrizione di skill,
circa 70 token, e il corpo da 9,4 KB si carica solo quando il modello lavora davvero sulla
UI. Quello che non ottieni è l'imposizione: niente ispeziona il risultato dopo. Questo è
un prompt, non un detector.

| | |
|---|---|
| Upstream | https://github.com/anthropics/claude-plugins-official/tree/main/plugins/frontend-design |
| Autore | Anthropic (Prithvi Rajasekaran, Alexander Bricken) |
| Licenza | Apache-2.0 (`LICENSE`, più `skills/frontend-design/LICENSE.txt`) |
| Versione ispezionata | pin del plugin `3deb821cb71c` (non viene pubblicato alcun campo version), ispezionato il 2026-09-12 |
| Contenuti | 1 skill, 0 comandi, 0 agent, 0 hook |

## Installazione

Sta nella directory ufficiale di Anthropic, che la CLI conosce già, quindi non va aggiunto
prima nessun marketplace:

```bash
claude plugin install frontend-design@claude-plugins-official
```

`scripts/install-all.sh` esegue esattamente quel comando, insieme al resto di loadout.

Per toglierlo dal contesto senza disinstallarlo:

```bash
claude plugin disable frontend-design
```

Non ha file di configurazione, né variabili d'ambiente, né download a runtime.

## Consumo di token

Tre budget, misurati qui al pin indicato sopra. I token sono caratteri ÷ 4, arrotondati.

**Sempre attivo, per sessione.** Pagato prima che tu scriva qualcosa.

| Sorgente | caratteri | ≈ token |
|---|---|---|
| Descrizione della skill nell'indice delle skill (1 skill) | 279 | ~70 |
| Descrizioni dei sub-agent nell'indice degli agent | nessuna | 0 |
| Iniezione `SessionStart` | nessuna | 0 |
| **Totale** | **279** | **~70** |

**Per tool call o per prompt.** Zero. Il plugin non spedisce alcuna directory `hooks/`,
quindi non scatta niente su `Edit`, su `Write`, su un prompt o su una compaction.

**Su richiesta.** Il corpo entra in contesto solo quando la skill viene invocata.

| File | dimensione | ≈ token |
|---|---|---|
| `skills/frontend-design/SKILL.md` | 9,4 KB | ~2.350 |

**Cosa ottieni in cambio.** Un piano di design che non è quello di default. Il risparmio
misurabile è una riscrittura evitata: quando una pagina torna indietro perché sa di
template, la correzione non è quasi mai un ritocco, è un secondo passaggio su palette,
tipografia e layout — diverse migliaia di token di generazione più il giro di review che
li ha chiesti. Il pareggio arriva a circa una riscrittura evitata ogni venti sessioni al
prezzo sempre attivo, o una per sessione al prezzo di invocazione. La forma di sessione in
cui non rende è il brief che già fissa la direzione visiva: la skill dice che le parole del
brief vincono sempre, quindi le resta poco da decidere.

Nota che la lista di calibrazione è la parte che invecchia. Descrive l'aspetto del design
generato a questo pin; via via che i grappoli si spostano, una lista non aggiornata inizia
a sterzare via da cose che non sono più spie.

## Verdetto, voce per voce

| Skill | Dimensione | Verdetto | Perché |
|---|---|---|---|
| frontend-design | 9,4 KB | Tieni se generi UI | ~70 token di costo fisso stanno sotto la soglia di rumore, e il corpo si carica solo sul lavoro di UI. La sezione sui default estetici è la parte che nessuna quantità di prompt riproduce a basso costo. |

## Interazione con il resto di loadout

Si sovrappone a **impeccable**, e i due non competono: questo scrive il brief, quello
controlla il risultato. `frontend-design` gira prima che il codice esista e discute di
palette, tipografia e layout; il detector `PostToolUse` di impeccable gira dopo ogni
modifica e segnala testo in gradiente, aloni a offset zero, contrasto sotto WCAG AA e
deriva dal design system. Se ne porti uno solo, porta questo su una macchina che spedisce
soprattutto lavoro backend — sono ~70 token contro i ~560 di impeccable — e porta
impeccable quando la qualità della UI va imposta invece che consigliata. Portarli entrambi
costa ~630 token per sessione e nessun hook in più.

Si sovrappone alla descrizione della skill di impeccable solo a livello di indice: entrambe
le descrizioni vengono caricate, nessuno dei due corpi lo è, quindi la sovrapposizione
costa i ~70 token.

`frontend-design` non aggiunge nulla al conto degli hook. I plugin di questo catalogo che
fanno scattare hook restano caveman (`SessionStart`, `UserPromptSubmit`), superpowers
(`SessionStart`) e impeccable (`PostToolUse`, `Stop`).

## Trappole

- **Non c'è una versione.** `plugin.json` pubblica un nome e un autore e nessun campo
  version, quindi la CLI pinna per commit e `status` mostra una stringa esadecimale, non un
  tag. Confronta i pin facendo il diff della skill, non leggendo un numero.
- **Il pin si muove sotto di te, e il corpo cresce.** Il pin precedente in cache su questa
  macchina, `3da105324a27`, porta un corpo da 8,3 KB contro i 9,4 KB attuali — circa il 14%
  in più di costo su richiesta a parità di descrizione da 279 caratteri. La cifra sempre
  attiva è stabile; quella di invocazione no.
- **L'invocazione automatica è una dichiarazione dell'upstream, non una garanzia.** Il
  README dice che Claude usa la skill automaticamente per il lavoro frontend; ciò che la
  fa scattare davvero è la descrizione che combacia con la richiesta. Un prompt del tipo
  «sistema questo CSS» può non caricarla mai. Chiamala per nome quando il design conta.
- **Due licenze, stessi termini.** La radice del plugin e la directory della skill portano
  ciascuna un testo Apache-2.0. Concordano; il duplicato esiste perché la skill resti
  licenziata se viene copiata fuori dal plugin.
- **Non ti impedirà di spedire un default.** Niente verifica l'output. Se vuoi un cancello
  invece che un consiglio, è il mestiere di impeccable, o di un hook tuo — vedi
  `skills/hook-recipes/SKILL.md`.
