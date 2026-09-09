# loadout

[English](README.md) · [Italiano](README-it.md)

A guide to setting up your own Claude Code well. Not a plugin, not a framework: a
curated set of skills, sub-agents, workflows and third-party integrations, each one
documented with the context it actually costs — measured on a real repository, not
copied from an upstream README. The install script wires up the whole set in one
block, because a loadout is something you carry as a whole, not a shopping list you
pick from one item at a time.

Nothing here is vendored. Every asset is installed from its own upstream source, so
you keep upstream updates and lose nothing by reading the guide instead of adopting it.

## Install

Clone the repo and run one script:

```bash
git clone https://github.com/DevManfre/loadout.git
cd loadout
scripts/install-all.sh
```

The script covers every install path in the catalog — the Claude Code plugin CLI for
plugin entries, a package manager for third-party binaries that cannot be shipped as
plugins, and a plain copy for loadout's own assets. It never hides the price: every
step prints its always-on token cost first and asks before paying it.

It is idempotent. An already-installed plugin, binary or asset is reported and
skipped, so re-running only fills the gaps.

| Flag | What it does |
|---|---|
| `--dry-run` | Print every step and cost, change nothing |
| `--yes` | Accept every printed cost up front (required with no TTY) |
| `--scope project` | Install into the current repo instead of your user profile |
| `--skip-graphify` | Leave the code graph out |

## Uninstall

Installed something that turns out too heavy? Drop it from context without
uninstalling it:

```bash
/plugin disable superpowers
```

## How to read a page

Every catalog entry has its own guide, and they all answer the same questions in the
same order:

- **Upstream, author, license, version inspected** — what you are actually installing.
- **Token economy** — split into always-on cost, per-tool-call cost, and on-demand
  cost, with the sizes measured on the inspected version.
- **Verdict, per skill or per command** — keep, situational, or skip, with the reason.
- **Interaction with the rest of loadout** — what composes and what overlaps.
- **Gotchas** — what the upstream docs do not tell you.

Token economy is the point of the whole exercise. An asset that costs more context
than it saves does not belong in a loadout, however good it looks in its own README.

## Catalog

### Integrations

| Name | What it does | What you get back | Always-on cost | Docs |
|---|---|---|---|---|
| superpowers | Process skills: brainstorming gate, red/green TDD, systematic debugging, subagent-driven development, skill authoring | Kills whole wasted implementation runs — nothing gets built before you approve the design, nothing is called done without evidence. The single largest token sink is an agent building the wrong thing well | ~800 tokens per session start, `/clear` and compaction | [guide](integrations/superpowers/README.md) |
| graphify | Local tree-sitter code graph: `explain` a symbol, trace a `path` between two, query the graph instead of grepping | One `explain` answers what would otherwise cost a grep sweep plus a few full file reads, and `graphify explain` / `graphify path` run as plain shell commands — zero skill body loaded. Graph builds locally, 0 LLM credits on code | ~340 tokens per session, plus ~48–105 per read or grep while a graph exists | [guide](integrations/graphify/README.md) |
| caveman | Style plugin: drops articles, filler and hedging from the agent's prose, keeping code, paths and errors exact | Upstream measures output falling 1,214 → 294 tokens on 10 tasks (65%). It only shrinks output, so it pays off on explanatory sessions and loses on tool-call-heavy ones — the arithmetic is in the guide | ~2,480 tokens per session start, `/clear` and compaction, plus ~60 per user prompt | [guide](integrations/caveman/README.md) |

### Own assets

None yet. `skills/`, `agents/` and `workflows/` are their home, and the same install
script copies them into place once they land.

## Layout

```text
skills/<name>/SKILL.md          loadout's own skills
agents/<name>.md                loadout's own sub-agent definitions
workflows/<name>.md             loadout's own workflow scripts and recipes
integrations/<name>/            third-party guides (plugins, binaries, MCP servers)
scripts/install-all.sh          one-block install of the whole loadout
scripts/validate.sh             structural validation
docs/                           longer-form guides
```

There is no application code and no build. Validation is structural — every path the
catalog names resolves, every asset is documented, and the language mirrors stay in
parity:

```bash
scripts/validate.sh
```

## License

MIT. See [LICENSE](LICENSE).
