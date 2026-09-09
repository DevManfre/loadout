# CLAUDE.md — loadout

## What this repo is

A guide, **not a plugin.** Loadout documents how to set up your own Claude Code well:
which skills, sub-agents, workflows and third-party integrations are worth carrying,
what each one costs in context, and what to skip. It runs no marketplace, publishes no
plugin manifest and vendors nothing — every asset is installed from its own upstream
source.

**No application code.** The product is the documentation plus the assets loadout
writes itself. Token economy is a feature, not a side effect: an asset that costs more
context than it saves does not belong here, however good its own README looks.

The install path is deliberately one block. `scripts/install-all.sh` sets up the whole
loadout in a single run — plugin entries through the Claude Code CLI, third-party
binaries through a package manager, loadout's own assets by plain copy — printing each
always-on token cost and asking before paying it. A loadout is carried whole; it is not
a shopping list.

## Layout

```
skills/<name>/SKILL.md          loadout's own skills (+ references/, scripts/ as needed)
agents/<name>.md                loadout's own sub-agent definitions
workflows/<name>.md             loadout's own workflow scripts / recipes
integrations/<name>/            third-party guides (plugins, binaries, MCP servers)
scripts/install-all.sh          one-block install of the whole loadout
scripts/validate.sh             structural validation
docs/                           longer-form guides
README.md                       canonical guide + catalog (English)
README-it.md                    Italian mirror
.claude/skills/                 THIS repo's own tooling — never shipped
```

Hard boundary: anything under `.claude/` is workspace tooling. It never appears in the
README catalog and is never installed by `install-all.sh`. Anything under `skills/`,
`agents/`, `workflows/`, `integrations/` is part of the guide and must be reachable
from the README catalog.

## Invariants

- No app code, no runtime beyond bash/node helper scripts under `scripts/`.
- No plugin manifest, no marketplace index. If a plugin path is needed, point at the
  upstream marketplace that already carries the asset — do not re-publish it.
- Every catalog entry states its upstream, license, version inspected, measured token
  cost, per-item verdict and gotchas. Costs are measured on a real repository, never
  copied from an upstream README.
- Every shipped asset is self-documenting: valid frontmatter (`name`, `description`),
  explicit trigger conditions, no assumptions about the user's machine.
- Adding, renaming, or removing a catalog entry is one commit covering the entry,
  `scripts/install-all.sh`, and the README catalog (all languages).
- `skills/` names are the public API. Renaming one breaks installs — treat it as a
  breaking change (`💥`) and say so in the commit body.

## Docs

`README.md` is canonical and written in English. `README-it.md` must mirror it
section for section. Never hand-edit one language alone — use the **readme-sync**
skill, which propagates in cascade to every `README-<lang>.md`.

## Commits

English only. Format `<gitmoji> <SCOPE> - <subject>`. Use the **commit-convention**
skill; it holds the gitmoji meanings and the scope rules.

## Build / test

None — no package manifest. Validation is structural, via `scripts/validate.sh`:
frontmatter parses, every path the README names resolves, every integration documents
itself and is reachable from the catalog, and the language mirrors stay in parity.
