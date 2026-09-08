# loadout

[English](README.md) · [Italiano](README-it.md)

Loadout — a meta repository: a centralized toolkit for supercharging AI coding agents (Claude Code for the moment). No app code, just curated, documented, ready-to-install skills, specialized sub-agents, workflows, and third-party integrations that optimize token usage and model interaction.

## Install

Add the marketplace once:

```
/plugin marketplace add DevManfre/loadout
```

Then install any catalog entry by name:

```
/plugin install <name>@loadout
```

The same command covers every kind of asset — loadout's own skills and sub-agents,
a curated third-party plugin, or an MCP server. Third-party binaries are the one
exception: a plugin cannot run a package manager, so those ship with an install script.
An entry carried as documentation only, like `superpowers`, is read rather than
installed through loadout — its value lives in the catalog's Docs column, not in the
install command.

## Catalog

### Integrations

| Name | What it does | Always-on cost | Docs |
|---|---|---|---|
| superpowers | Process skills: brainstorming gate, red/green TDD, systematic debugging, subagent-driven development, skill authoring | ~800 tokens per session start, `/clear` and compaction | [guide](integrations/superpowers/README.md) |
