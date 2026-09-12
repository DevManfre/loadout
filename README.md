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
    #  entry           cost/session           status
 ▸  1 [x] superpowers     ~800                   ready
    2 [x] graphify        ~340 +48-105/toolcall  ready
    3 [x] headroom        none                   ready
    4 [x] frontend-design ~70                    ready
    5 [x] ui-ux-pro-max   ~683                   ready
    6 [^] caveman         ~2,480 +60/prompt      update: 84cc3c14fa1e → v2.6.0
    7 [=] impeccable      ~560 +0-475/edit       installed @ v4.3.1

↑/↓ move · Space toggle · d=why · a=all · n=none · Enter=apply 5 · q=quit
```

`▸` marks the current row: arrows move it, Space toggles it, `d` explains it, and the
digits still toggle by number. The menu redraws in place — no scrolling copies of
itself — and colors the status column (green ready, yellow auto-install, red blocked).
Colors respect `NO_COLOR`; on a pipe, with `TERM=dumb` or with `LOADOUT_PLAIN_MENU=1`
the same menu falls back to a line-based numbered prompt where one reply may toggle
several rows (`1 3`).

A blocked entry stays numbered but cannot be toggled; `d` on its row prints what it is
missing, why the entry needs it, how to fix it, and what skipping it costs.

One menu answers all three questions about an entry: `[ ]`/`[x]` is not installed,
`[=]` is installed and current, `[^]` is installed and behind what upstream publishes
now, with both pins on its row. An update row is selectable but never preselected —
an update moves something that already works off the pin this catalog measured — and
Enter applies the installs and the updates in the same pass, printing every pin it is
about to move and asking once for the set. `d` on an update row prints the three pins
that decide it: installed, upstream, and the one the catalog priced the entry on.

An entry that runs somewhere this machine cannot reach — headroom behind a proxy, in a
container or on the Windows host — is priced from the pin its `/health` endpoint
admits to, so it gets an `[^]` row too. That row is read-only: it names both pins and
says to update it where it runs, because nothing here can. `scripts/loadout status`
prints the same pin as `remote 0.27.0`.

The upstream check runs when the menu opens: one `git ls-remote` per plugin, the
package index per package, every call bounded and all of them at once — about a second
in total, remembered nowhere. `--offline` (or `LOADOUT_NO_NET=1`) skips it, and so
does an unreachable upstream: the entry stays a plain `[=]` row rather than claiming to
be either current or behind.

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
| `--offline` | Never ask upstream what it publishes — no update rows |

Every command is idempotent. An already-installed plugin, binary or asset is reported
and skipped, so re-running only fills the gaps.

### Updating

`scripts/loadout update` never upgrades quietly. For every installed entry it prints
the pin on disk, the pin upstream publishes now, the pin the catalog measured and what
that pin costs, warns you if you are already off the measured pin, and says when the
pin the update lands on is one this catalog has not measured — before it asks. caveman
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
| impeccable | Design-fluency plugin: 23 named design commands, plus a compiled detector that flags gradient text, zero-offset glows, contrast failures and design-system drift after every edit | Mechanical, checkable findings at the moment of the edit instead of at review time, so a component is not rebuilt after a human calls it AI-made. The only hook-bearing entry here with no `SessionStart` cost | ~560 tokens per session, plus 0 on non-UI edits, ~70 on a clean UI file and ~475 on one with three findings | [guide](integrations/impeccable/README.md) |
| frontend-design | Anthropic's own frontend taste file: one skill that argues for a design plan grounded in the subject matter, and names the five visual clusters generated pages keep landing on — including the terracotta-on-cream palette that is Claude's own accent | A first pass that does not read as templated, so the page is not rebuilt from palette up after review calls it AI-made. No hooks, no agents, no binary: the body loads only on UI work | ~70 tokens per session; ~2,350-token body loads only on invocation | [guide](integrations/frontend-design/README.md) |
| ui-ux-pro-max | Local design database queried by a script: 79 styles, 192 palettes with reasoning profiles, 74 font pairings, 119 UX guidelines, 25 chart types, 22 stacks — 3.1 MB of CSV and JSON that never enter the context | Specific values instead of improvised ones — this palette, this pairing, this pattern — for ~105 tokens a targeted query, so a page is not rebuilt after the direction turns out wrong. No hooks, and the database stays out of the window | ~683 tokens per session, the highest here: the plugin exposes seven skills and there is no per-skill switch | [guide](integrations/ui-ux-pro-max/README.md) |

### Own assets

Installed by the same script, as a plain copy of the directory — no plugin index in
between.

| Name | What it does | What you get back | Always-on cost | Docs |
|---|---|---|---|---|
| hook-recipes | Turns a repeated instruction into an enforced hook: which rules qualify, the four contract details that make most hooks in the wild fire never, six tested recipes, and a probe that runs a handler against a synthetic payload | A rule moved out of `CLAUDE.md` and into a hook stops being paid for in every session — the deletion is the saving, and the probe is what makes it safe to delete. Measured here: the six recipes cost 0 tokens when they pass and ~22–55 when they fire | ~41 tokens (description); ~1,610-token body, a recipe page and one shell script load only on invocation | [guide](skills/hook-recipes/SKILL.md) |
| token-economy | Audits every component of a Claude Code setup for token cost — measured by script, never by eye — and states the design rules for writing new skills, agents and CLAUDE.md files lean from the start | An audit report priced in always-on tokens with a per-finding risk column; one applied finding typically pays back the skill's own cost hundreds of times over. Measured here: this repo's CLAUDE.md fell from a rule list to a ~430-token index using its dimensions | ~43 tokens (description); ~1,790-token body, a reference page and two shell scripts load only on invocation | [guide](skills/token-economy/SKILL.md) |

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
