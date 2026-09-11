# loadout

[English](README.md) · [Italiano](README-it.md)

A guide to setting up your own Claude Code well. Not a plugin, not a framework: a
curated set of skills, sub-agents, workflows and third-party integrations, each one
documented with the context it actually costs — measured on a real repository, not
copied from an upstream README. The install script wires up the whole set in one
block, because a loadout is something you carry as a whole: the menu opens with every
entry already selected and Enter takes all of it. Deselecting one is a deliberate act,
taken with its cost on screen.

Nothing here is vendored. Every asset is installed from its own upstream source, so
you keep upstream updates and lose nothing by reading the guide instead of adopting it.

## Install

Clone the repo and run one script:

```bash
git clone https://github.com/DevManfre/loadout.git
cd loadout
scripts/install-all.sh
```

`scripts/install-all.sh` is a three-line shim for `scripts/loadout install`, kept so
the block above never has to change. Every command lives under that one entrypoint:

| Command | What it does |
|---|---|
| `install` | Choose what to install, then install it |
| `update` | Upgrade what is already installed |
| `status` | What is installed, its pin, what it costs |
| `doctor` | Dependency report; changes nothing |
| `remove <entry>` | Uninstall one entry |
| `list` | The catalog as `scripts/loadout` sees it |

`install` opens a menu with every installable entry already selected — Enter installs
all of it. Deselecting one is a deliberate act, taken with its cost already on screen:

```
    #  entry        cost/session           status
 ▸  1 [x] superpowers  ~800                   ready
    2 [x] caveman      ~2,480 +60/prompt      ready
    3 [x] graphify     ~340 +48-105/toolcall  ready
    4 [x] headroom     none                   ready

↑/↓ move · Space toggle · d=why · a=all · n=none · Enter=install 4 · q=quit
```

`▸` marks the current row: arrows move it, Space toggles it, `d` explains it, and the
digits still toggle by number. The menu redraws in place — no scrolling copies of
itself — and colors the status column (green ready, yellow auto-install, red blocked).
Colors respect `NO_COLOR`; on a pipe, with `TERM=dumb` or with `LOADOUT_PLAIN_MENU=1`
the same menu falls back to a line-based numbered prompt where one reply may toggle
several rows (`1 3`).

A blocked entry stays numbered but cannot be toggled; `d` on its row prints what it is
missing, why the entry needs it, how to fix it, and what skipping it costs.

One dependency the installer can provide for itself: **uv**. An entry missing only
uv/pipx is not blocked — its row stays selectable and reads `needs uv/pipx
(auto-install, asks first)`. Before installing such an entry, the installer prints the
exact command it is about to run (the official Astral script,
`curl -LsSf https://astral.sh/uv/install.sh | sh`) and asks; Enter on the menu does not
waive that prompt, only `--yes` does. Declining leaves the entry on its normal blocked
path, and `--dry-run` prints the command without running it. Everything else — git,
Claude Code, Docker — stays yours to install.

| Flag | What it does |
|---|---|
| `--preset core\|full` | Restrict the menu to a named preset (default: `full`) |
| `--only a,b` | Restrict to these entries |
| `--except a,b` | Everything but these entries |
| `--scope user\|project\|local` | Install target (default: `user`) |
| `-y`, `--yes` | Accept every printed cost up front (required with no TTY) |
| `-n`, `--dry-run` | Print every step and cost, change nothing |

Every command is idempotent. An already-installed plugin, binary or asset is reported
and skipped, so re-running only fills the gaps.

### Updating

`scripts/loadout update` never upgrades quietly. For every installed entry it prints
the pin on disk, the pin the catalog measured and what that pin costs, warns you if
you are already off the measured pin, and states that an update moves to whatever
upstream publishes now — a pin this catalog has not measured — before it asks. caveman
is the entry on record for why that gate exists: the same skill priced at ~780 tokens
per session on the pin `84cc3c14fa1e` and at ~2,480 on `v2.6.0`, one version apart.
`--yes` accepts every gate up front.

Run `scripts/loadout doctor` at any time to see what is missing and how to fix it,
without changing anything.

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
| headroom | Compression proxy on the wire: shrinks tool output, logs, search results and history before they reach the API, leaving a hash to expand on demand | The only entry that costs no context at all — it is not in the window. Measured on this machine: 3.0% off a 66 M-token session, 4.42% off 6.86 B lifetime tokens ($1,339). Paid for in latency, ~2.2 s added per request | none in the proxy shape; ~525 tokens if you add its MCP server | [guide](integrations/headroom/README.md) |

### Own assets

Installed by the same script, as a plain copy of the directory — no plugin index in
between.

| Name | What it does | What you get back | Always-on cost | Docs |
|---|---|---|---|---|
| token-economy | Audits every component of a Claude Code setup for token cost — measured by script, never by eye — and states the design rules for writing new skills, agents and CLAUDE.md files lean from the start | An audit report priced in always-on tokens with a per-finding risk column; one applied finding typically pays back the skill's own cost hundreds of times over. Measured here: this repo's CLAUDE.md fell from a rule list to a ~430-token index using its dimensions | ~43 tokens (description); ~1,500-token body and two shell scripts load only on invocation | [guide](skills/token-economy/SKILL.md) |

## Layout

```text
skills/<name>/SKILL.md          loadout's own skills
agents/<name>.md                loadout's own sub-agent definitions
workflows/<name>.md             loadout's own workflow scripts and recipes
integrations/<name>/            third-party guides (plugins, binaries, MCP servers)
scripts/loadout                 single entrypoint: install, update, status, doctor, remove, list
scripts/install-all.sh          one-block install of the whole loadout
scripts/lib/                    manifest, probe, ui and actions libraries
scripts/loadout.manifest        catalog data: one row per installable entry
scripts/loadout.deps            dependency registry: what each entry needs, why, how to fix it
scripts/validate.sh             structural validation
scripts/selftest.sh             test runner
docs/                           longer-form guides
```

There is no application code and no build. Validation is structural — every path the
catalog names resolves, every asset is documented, and the language mirrors stay in
parity:

```bash
scripts/validate.sh
```

`scripts/selftest.sh` is the installer's own test runner: it exercises
`scripts/loadout` against a faked machine, with no network access and no real
installs.

## License

MIT. See [LICENSE](LICENSE).
