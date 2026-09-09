# caveman

A style plugin. It does not give the agent a new capability — it changes how the agent
*writes*: articles, filler, pleasantries and hedging are dropped, fragments are allowed,
technical terms, code and error strings stay exact. The saving is on the **output** side
of the bill, and it is bought with a permanent input-side cost: a `SessionStart` hook
that injects the ruleset, a `UserPromptSubmit` hook that re-injects a reminder on every
turn, and a skill index that grew fourfold between the two revisions measured here.

Whether it is worth carrying is entirely a question of that trade, and the numbers below
are the only honest way to answer it.

| | |
|---|---|
| Upstream | https://github.com/JuliusBrussee/caveman |
| Author | Julius Brussee |
| License | MIT for `skills/`, BSL 1.1 for the proxy/wrap components (`LICENSING.md`); GitHub reports the repo as `NOASSERTION` |
| Version inspected | `v2.6.0` (2026-09-04), and the older pin `84cc3c14fa1e` (2026-04-18) for comparison |
| Contents (`v2.6.0`) | 20 skills, 6 commands, 3 sub-agents, 2 hooks (`SessionStart`, `UserPromptSubmit`), own marketplace manifest |

## Install

This one is not in Anthropic's official directory, so its own marketplace has to be
added first. `scripts/install-all.sh` runs both commands for you:

```bash
claude plugin marketplace add JuliusBrussee/caveman
claude plugin install caveman@caveman
```

`claude plugin install` pins whatever the marketplace HEAD is on the day you run it.
That pin matters more here than in any other entry in this catalog — see the token
table below, where two pins of the same plugin differ by a factor of three.

Turn it off for a session without uninstalling:

```text
stop caveman
```

Or drop it from context entirely:

```bash
claude plugin disable caveman
```

## Token economy

Three budgets. Every figure was measured by running the plugin's own hooks and counting
the bytes they emit, on the two revisions named above — none of it is copied from the
upstream README.

**Always on, per session.** Paid before you type anything.

| Source | `84cc3c14fa1e` | `v2.6.0` |
|---|---|---|
| Skill descriptions in the skill index | 1,281 chars · ~320 tokens (5 skills) | 3,213 chars · ~800 tokens (20 skills) |
| Sub-agent descriptions in the agent index | none | ~1,000 chars · ~250 tokens (3 `cavecrew` agents) |
| `SessionStart` ruleset injection | 1,847 chars · ~460 tokens | 5,290 chars · ~1,320 tokens |
| `SessionStart` statusline nudge, until configured | not present | ~450 chars · ~110 tokens |
| **Total** | **~780 tokens** | **~2,480 tokens** |

The `SessionStart` hook declares no matcher, so it fires on every source: startup,
resume, `/clear` **and every compaction**. On a long session you pay it repeatedly.

**Per user prompt.** This is the cost people miss, and it is unconditional while the
mode flag exists.

| Revision | Injected on every prompt | ≈ tokens |
|---|---|---|
| `84cc3c14fa1e` | 122 chars | ~30 |
| `v2.6.0` | 245 chars | ~60 |

A 40-turn session on `v2.6.0` spends ~2.4k tokens on reinforcement alone, on top of the
~2.5k it already paid at startup and again at each compaction.

**On demand.** Skill bodies load only when invoked, and on `v2.6.0` they are not small:
`caveman-setup` 10.5 KB, `caveman-learn` 9.2 KB, `caveman` itself 7.0 KB, `caveman-discover`
5.3 KB. The six one-page process skills (`investigate-first`, `lean-build`, `migration`,
`safe-refactor`, `surgical-patch`, `verify-and-stop`) are ~700–1,100 bytes each.

**What you get back.** Upstream benchmarks 10 tasks and reports output falling from an
average of 1,214 tokens to 294 — a 65% cut, best case 87%, worst case 22% — and, to its
credit, documents the cases where it loses in `docs/HONEST-NUMBERS.md`. Loadout did not
reproduce that benchmark; the output claim is upstream's, the input costs above are ours.

The arithmetic that decides it: output has to shrink by more than ~2.5k tokens per
session plus ~60 per turn for the plugin to break even on tokens alone. On a session of
long explanatory answers that is easy. On a session of tool calls, diffs and short
confirmations — the shape most agent work actually has — output is already terse and
there is nothing to cut, so you pay the input cost and get nothing back. The reliable
win is readability and speed, not the invoice.

## Verdict, per skill

Measured on `v2.6.0`.

| Skill | Size | Verdict | Why |
|---|---|---|---|
| caveman | 7.0 KB | Keep — it is the plugin | The mode itself. Everything else is optional around it. |
| caveman-help | 2.2 KB | Keep | One-shot reference card, no persistent state. Cheap. |
| caveman-review | 2.6 KB | Keep | One line per finding, location/problem/fix. Review comments are exactly the verbose-output case the compression is good at. |
| caveman-compress | 4.7 KB | Situational | Compresses `CLAUDE.md` and other memory files in place. Real, permanent input saving — but it rewrites your source of truth and keeps only a `.original.md` backup. Read the diff. |
| verify-and-stop | 0.7 KB | Situational | Overlaps `superpowers:verification-before-completion`, which is stricter. Redundant if you carry superpowers. |
| investigate-first | 0.7 KB | Situational | Same relationship to `superpowers:systematic-debugging`. |
| surgical-patch / safe-refactor / lean-build / migration | ~0.7–1.1 KB each | Situational | Thin process nudges. Harmless at this size, but they duplicate ground superpowers already covers more thoroughly. |
| caveman-explore | 2.0 KB | Situational | Overlaps the built-in `Explore` agent and, if you carry it, graphify's graph queries. |
| cavecrew + 3 `cavecrew-*` agents | 3.6 KB + ~4.5 KB | Situational, expensive | A whole sub-agent delegation layer bolted onto a style plugin. Pays the agent-index cost every session whether or not you delegate. |
| caveman-commit | 2.4 KB | Skip in this repo | Writes Conventional Commits. This repo's format is `<gitmoji> <SCOPE> - <subject>`; use the **commit-convention** skill instead. |
| caveman-setup | 10.5 KB | Skip | Largest body in the set, and it exists to configure the plugin. Run it once by hand if at all. |
| caveman-learn | 9.2 KB | Skip | Second-largest body, teaching material rather than working capability. |
| caveman-stats / caveman-manage / caveman-optimize / caveman-discover / caveman-evidence-review | 1.0–5.3 KB | Skip | Plugin self-management and ecosystem discovery. Context spent on the tool rather than on your work. |

## Interaction with the rest of loadout

Two `SessionStart` hooks now fire together: superpowers injects ~800 tokens of
`using-superpowers`, caveman injects ~1.3k of ruleset. Both re-fire on `/clear` and on
every compaction, so a compaction-heavy session pays ~2.1k tokens in style and process
preamble each time. That is the single biggest reason to think before adding a third
hook-bearing plugin.

The two do not fight over behaviour: superpowers governs *what happens next*, caveman
governs *how the result is worded*. Caveman's own Auto-Clarity rule already drops the
compressed register for security warnings, irreversible-action confirmations and
multi-step sequences, which is exactly where superpowers' gates live.

Against loadout's own assets: `commit-convention` wins over `caveman-commit` — the house
format is not Conventional Commits, and caveman writes commits, PRs and issue bodies in
normal English by its own rules anyway. Against graphify: no overlap, different layer.

## Gotchas

- **The per-prompt hook never stops on its own.** While `~/.claude/.caveman-active`
  exists, every single user message carries the reminder. Saying "stop caveman" removes
  the flag; uninstalling the plugin is not required, and disabling it is not the same as
  deleting the flag.
- **`SessionStart` has no matcher.** It fires on startup, resume, `/clear` and every
  compaction — the same repeated-injection behaviour superpowers has, doubled.
- **Upgrading the pin triples the always-on cost.** Between April's `84cc3c14fa1e` and
  `v2.6.0` the skill count went 5 → 20, three sub-agents appeared, and per-session cost
  went ~780 → ~2,480 tokens. Nothing warns you: `claude plugin update` just takes it.
- **It nudges you to configure a statusline.** Until `statusLine` is set in
  `settings.json`, the hook appends ~450 chars asking the agent to proactively offer to
  set it up. Configure it or accept the recurring ask.
- **Mixed licensing.** `skills/` is MIT per `LICENSING.md`, but the repository also ships
  BSL 1.1 components and GitHub resolves the whole repo to `NOASSERTION`. Irrelevant to
  using the plugin, relevant the moment anyone copies code out of it.
- **The repository is no longer small.** `v2.6.0` carries a Go module, a proxy, an MCP
  server and a browser layer. `claude plugin install` clones all of it; only the skills,
  agents and hooks ever reach your context, but the disk cost is real.
- **The 65% figure is an output-only measurement.** Upstream says so plainly. Input and
  reasoning tokens are unchanged, and on this plugin they go up.
