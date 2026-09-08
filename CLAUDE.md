# CLAUDE.md — loadout

## What this repo is

A meta repository. **No application code.** Loadout is a curated, documented toolkit
for supercharging AI coding agents (Claude Code first, other harnesses later):
ready-to-install skills, specialized sub-agents, workflows, and third-party
integrations that optimize token usage and model interaction.

The product is the assets themselves plus their documentation. Token economy is a
feature, not a side effect: an asset that costs more context than it saves does not
belong here.

## Layout (hybrid: flat dirs are the source of truth, the plugin index sits on top)

```
skills/<name>/SKILL.md          shipped skills (+ references/, scripts/ as needed)
agents/<name>.md                shipped sub-agent definitions
workflows/<name>.md             shipped workflow scripts / recipes
integrations/<name>/            third-party integrations (MCP servers, hooks, configs)
scripts/install.sh              manual install (copy/symlink into ~/.claude)
.claude-plugin/marketplace.json index over the flat dirs, for `/plugin marketplace add`
docs/                           longer-form guides
README.md                       canonical catalog + docs (English)
README-it.md                    Italian mirror
.claude/skills/                 THIS repo's own tooling — never shipped
```

Hard boundary: anything under `.claude/` is workspace tooling. It is never listed in
`marketplace.json` and never appears in the README catalog. Anything under `skills/`,
`agents/`, `workflows/`, `integrations/` is a distributed asset and must be reachable
both by manual copy and via the plugin index.

## Invariants

- No app code, no runtime beyond bash/node helper scripts under `scripts/`.
- Every shipped asset is self-documenting: valid frontmatter (`name`, `description`),
  explicit trigger conditions, no assumptions about the user's machine.
- Adding, renaming, or removing a shipped asset is a three-part change in one commit:
  the asset, `.claude-plugin/marketplace.json`, and the README catalog (all languages).
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

None yet — no package manifest. Validation is structural: frontmatter parses, paths
in the README and in `marketplace.json` resolve, no asset listed twice.
