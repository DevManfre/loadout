# loadout

[English](README.md) · [Italiano](README-it.md)

Loadout — un meta repository: un toolkit centralizzato per potenziare gli agenti AI di coding (per ora Claude Code). Nessun codice applicativo, solo skill curate, documentate e pronte da installare, sub-agent specializzati, workflow e integrazioni di terze parti che ottimizzano il consumo di token e l'interazione con il modello.

## Installazione

Aggiungi il marketplace una volta sola:

```
/plugin marketplace add DevManfre/loadout
```

Poi installa qualsiasi voce del catalogo per nome.

### Un singolo asset

```
/plugin install superpowers@loadout
```

Valutalo prima di adottarlo — questo comando stampa l'inventario dei componenti della
voce e il suo costo in token previsto:

```
claude plugin details superpowers
```

Limitalo a un singolo repository invece che a tutto il tuo account con `--scope`
(`user` è il default, `project` scrive nel repository, `local` resta privato):

```
claude plugin install superpowers@loadout --scope project
```

### Tutto quanto

Nessun comando installa un marketplace intero, ed è voluto: il costo è per asset,
quindi lo paghi una chiamata deliberata alla volta.

```
claude plugin install loadout@loadout
claude plugin install superpowers@loadout
```

Hai installato qualcosa che si rivela troppo pesante? Toglilo dal contesto senza
disinstallarlo:

```
/plugin disable superpowers
```

### Cosa copre il comando

Lo stesso comando copre ogni tipo di asset — le skill e i sub-agent di loadout,
un plugin di terze parti curato, o un server MCP. I binari di terze parti sono la sola
eccezione: un plugin non può eseguire un package manager, quindi quelli vengono
distribuiti con uno script di installazione. Una voce portata solo come documentazione,
come `superpowers`, si legge invece di installarla tramite loadout — il suo valore sta
nella colonna Documentazione del catalogo, non nel comando di installazione.

## Catalogo

### Integrazioni

| Nome | Cosa fa | Costo sempre attivo | Documentazione |
|---|---|---|---|
| superpowers | Skill di processo: gate di brainstorming, TDD red/green, debugging sistematico, sviluppo guidato da subagent, creazione di skill | ~800 token per avvio sessione, `/clear` e compaction | [guida](integrations/superpowers/README-it.md) |
