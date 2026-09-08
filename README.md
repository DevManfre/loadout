# loadout

[English](README.md) · [Italiano](README-it.md)

Loadout — a meta repository: a centralized toolkit for supercharging AI coding agents (Claude Code for the moment). No app code, just curated, documented, ready-to-install skills, specialized sub-agents, workflows, and third-party integrations that optimize token usage and model interaction.

## Install

Add the marketplace once:

```
/plugin marketplace add DevManfre/loadout
```

Then install any catalog entry by name.

### One specific asset

```
/plugin install superpowers@loadout
```

Weigh it before you commit to it — this prints the entry's component inventory and its
projected token cost:

```
claude plugin details superpowers
```

Keep it to a single repo instead of your whole account with `--scope`
(`user` is the default, `project` writes to the repo, `local` stays private to you):

```
claude plugin install superpowers@loadout --scope project
```

### Everything

No single command installs a whole marketplace, and that is the point: cost is per
asset, so you pay it one deliberate call at a time.

```
claude plugin install loadout@loadout
claude plugin install superpowers@loadout
```

Installed something that turns out too heavy? Drop it from context without uninstalling:

```
/plugin disable superpowers
```

### What the command covers

The same command covers every kind of asset — loadout's own skills and sub-agents,
a curated third-party plugin, or an MCP server. Third-party binaries are the one
exception: a plugin cannot run a package manager, so those install themselves — `graphify`
is one, and its guide carries the commands. An entry carried as documentation only, like
`superpowers`, is read rather than installed through loadout — its value lives in the
catalog's Docs column, not in the install command.

## Catalog

### Integrations

| Name | What it does | Always-on cost | Docs |
|---|---|---|---|
| superpowers | Process skills: brainstorming gate, red/green TDD, systematic debugging, subagent-driven development, skill authoring | ~800 tokens per session start, `/clear` and compaction | [guide](integrations/superpowers/README.md) |
| graphify | Local tree-sitter code graph: `explain` a symbol, trace a `path` between two, query the graph instead of grepping | ~340 tokens per session, plus ~48–105 per read or grep while a graph exists | [guide](integrations/graphify/README.md) |
