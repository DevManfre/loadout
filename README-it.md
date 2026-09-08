# loadout

[English](README.md) · [Italiano](README-it.md)

Loadout — un meta repository: un toolkit centralizzato per potenziare gli agenti AI di coding (per ora Claude Code). Nessun codice applicativo, solo skill curate, documentate e pronte da installare, sub-agent specializzati, workflow e integrazioni di terze parti che ottimizzano il consumo di token e l'interazione con il modello.

## Installazione

Aggiungi il marketplace una volta sola:

```
/plugin marketplace add DevManfre/loadout
```

Poi installa qualsiasi voce del catalogo per nome:

```
/plugin install <name>@loadout
```

Lo stesso comando copre ogni tipo di asset — le skill e i sub-agent di loadout,
un plugin di terze parti curato, o un server MCP. I binari di terze parti sono la sola
eccezione: un plugin non può eseguire un package manager, quindi quelli vengono
distribuiti con uno script di installazione. Una voce portata solo come documentazione,
come `superpowers`, si legge invece di installarla tramite loadout — il suo valore sta
nella colonna Docs del catalogo, non nel comando di installazione.

## Catalogo

### Integrazioni

| Nome | Cosa fa | Costo sempre attivo | Documentazione |
|---|---|---|---|
| superpowers | Skill di processo: gate di brainstorming, TDD red/green, debugging sistematico, sviluppo guidato da subagent, creazione di skill | ~800 token per avvio sessione, `/clear` e compaction | [guida](integrations/superpowers/README-it.md) |
