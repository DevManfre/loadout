# impeccable

A design-fluency plugin. It does not make the agent write frontend code it could not
write before; it gives that code a vocabulary and a floor. One skill exposes 23 named
commands — `polish`, `audit`, `typeset`, `colorize`, `layout`, `critique` and the rest —
and a compiled detector runs after every edit, looking for the mechanical tells of
AI-generated UI: gradient text, zero-offset colored glows, contrast below WCAG AA,
design-system drift. The trade is unusual for this catalog. The always-on cost is low,
because the plugin ships a single skill description and four sub-agent descriptions and
declares no `SessionStart` hook at all. What you pay instead is metered per edit, and
only on files that look like UI. On a backend session it costs ~560 tokens and never
speaks again; on a session of heavy frontend work it can add several thousand.

| | |
|---|---|
| Upstream | https://github.com/pbakaus/impeccable |
| Author | Paul Bakaus |
| License | Apache-2.0 (`LICENSE`) |
| Version inspected | plugin `v4.3.1`, repo commit `cb56ed6` (2026-09-10), engine `0.1.5` |
| Contents | 1 skill (23 commands), 4 sub-agents, 2 hooks (`PostToolUse`, `Stop`), own marketplace manifest, 39 reference documents, one downloaded platform binary |

## Install

Not in Anthropic's official directory, so its own marketplace is added first.
`scripts/install-all.sh` runs both commands for you:

```bash
claude plugin marketplace add pbakaus/impeccable
claude plugin install impeccable@impeccable
```

The first time the hook fires it downloads the engine binary for your platform from the
project's release channel into `~/.impeccable/bin/<engine-version>/` — about 16 MB, and
it needs `curl` or `wget`. Point `IMPECCABLE_HOME` somewhere else to move that cache, or
`IMPECCABLE_BIN` at a preinstalled binary on a machine with no egress.

Turn the hooks off for a project without uninstalling anything, by writing
`.impeccable/config.json` in the project root:

```json
{ "hook": { "enabled": false } }
```

`{ "hook": { "quiet": true } }` keeps the detector but drops the acknowledgement it
prints on a clean UI file — that is the difference between paying ~70 tokens per UI edit
and paying zero. Or drop the whole plugin from context:

```bash
claude plugin disable impeccable
```

## Token economy

Three budgets. Every figure was produced here by running the plugin's own hook against a
fixture project and counting the bytes it emitted, at the pin named above. Tokens are
characters ÷ 4, rounded.

**Always on, per session.** Paid before you type anything.

| Source | chars | ≈ tokens |
|---|---|---|
| Skill description in the skill index (1 skill) | 1,191 | ~300 |
| Sub-agent descriptions in the agent index (4 agents) | 1,040 | ~260 |
| `SessionStart` injection | none | 0 |
| **Total** | **2,231** | **~560** |

The absence of a `SessionStart` hook is the single most important line in this table.
Every other hook-bearing entry in this catalog re-pays its startup cost on `/clear` and
on every compaction; this one does not.

**Per tool call.** The `PostToolUse` hook has matcher `Edit|Write`, so it runs on every
single edit. What it costs depends entirely on what was edited:

| Edited file | Emitted | ≈ tokens |
|---|---|---|
| Anything that is not a design-relevant extension | 0 bytes | 0 |
| `.ts` / `.js` with no finding | 0 bytes | 0 |
| UI file (`.tsx`, `.html`, `.css`, `.vue`, `.svelte`, …), clean | 286 bytes | ~70 |
| UI file, 3 findings (gradient-text, low-contrast, dark-glow) | 1,894 bytes | ~475 |

Roughly 1,000 bytes of the findings payload is fixed triage boilerplate; the rest scales
with the number of findings. The `Stop` hook declares no matcher, so it runs at the end
of every turn with a 30-second budget, but it deduplicates against what the per-edit pass
already reported: measured at **0 bytes** on a session where every finding had been
surfaced during editing. It only costs tokens when findings were deferred — which is the
normal case, since the per-edit pass runs a reduced rule set and defers taste-level
findings (copy cadence, palette, rhythm) to that deep pass.

**On demand.** The skill body loads when the skill is invoked; each command pulls exactly
one reference document.

| Source | chars | ≈ tokens |
|---|---|---|
| `SKILL.md` body | 10,729 | ~2,700 |
| 39 reference documents, all of them | 385,166 | ~96,000 |
| `new-work.md` | 53,325 | ~13,300 |
| `critique.md` | 42,682 | ~10,700 |
| `live.md` | 36,147 | ~9,000 |
| `document.md` | 27,428 | ~6,900 |
| `polish.md` | 6,632 | ~1,700 |
| `typeset.md` | 5,249 | ~1,300 |
| `colorize.md` | 4,537 | ~1,100 |
| `bolder.md` | 3,471 | ~870 |
| 4 sub-agent bodies | 32,512 | ~8,100, in the sub-agent's context, not yours |

The 96,000 figure is never paid in one go and is listed only to show the spread. What
matters is that the commands differ by an order of magnitude between them: `bolder` is a
rounding error and `new-work` costs more than this whole repo's CLAUDE.md.

**What you get back.** The detector's findings are mechanical and checkable — a 1.9:1
contrast ratio is a fact, not an opinion — and they arrive at the edit rather than at
review time. The thing being avoided is a redesign round trip: an agent regenerating a
component after a human says "this looks AI-made" costs 3–8k tokens of output plus the
reading that follows it. Upstream's own before/after gallery is not reproduced here and
no claim from it is quoted in this guide.

**Break-even.** A typical frontend session of 20 UI edits, half of them with findings,
costs `560 + 10×70 + 10×475` ≈ **6,000 tokens**. That pays for itself if it prevents a
single component from being rebuilt. A session that touches no UI file costs ~560 tokens
and returns nothing — the shape where this entry is pure overhead is backend or
infrastructure work, and there `hook.enabled: false` in the project config is the right
answer rather than uninstalling.

## Verdict, per item

| Item | Size | Verdict | Why |
|---|---|---|---|
| the `PostToolUse` detector | 0–1.9 KB per edit | Keep | Silent on non-UI files, ~70 tokens on a clean one. The cheapest part of the plugin and the one that changes outcomes without being asked |
| `audit` | 8.5 KB | Keep | Whole-surface pass over what the detector found, on demand |
| `polish` | 6.6 KB | Keep | The default verb. Cheap enough to run repeatedly |
| `typeset` / `colorize` / `layout` | 4.5–5.2 KB | Keep | One dimension each, small reference, concrete output |
| `bolder` / `quieter` | 3.5–4.9 KB | Keep | Intensity adjustment on an existing design. Smallest bodies in the set |
| `animate` / `delight` | 3.7–5.2 KB | Situational | Motion and flourish are the first thing to cut on an internal tool; worth it on brand surfaces |
| `init` | 11.4 KB | Situational | Runs a discovery interview and writes `PRODUCT.md` and `DESIGN.md` into your repo. Run once per project, by hand, or not at all |
| `critique` | 42.7 KB | Situational | ~10.7k tokens per invocation. Worth it for a deliberate review of one surface; never in a loop |
| `new-work` | 53.3 KB | Situational | The largest body in the set. It is the from-scratch path — do not let it load for an edit to an existing component |
| `live` / `live-setup` | 36.1 + 8.2 KB | Situational | Interactive in-browser variant picking. Needs a running dev server and the engine binary; ~9k tokens before you see anything |
| `document` + `impeccable-documenter` | 27.4 + 3.1 KB | Skip | Generates a `DESIGN.md` from the codebase. Overlaps what graphify already answers about structure, and loadout writes its own docs by hand |
| `adapt.native` / `android` / `ios` | 3.8–8.4 KB | Skip | Native mobile targets, outside the frontend-web scope this catalog covers |
| `craft` | 0.5 KB | Skip | Upstream marks it a deprecated alias for the ordinary new-work flow |
| `impeccable-finish-reviewer` | 15.2 KB | Situational | Largest sub-agent. Runs in its own context, so it does not spend yours, but it is a second full pass over work already reviewed |

## Interaction with the rest of loadout

This is the third hook-bearing plugin in the catalog, and the first that does not add to
the session preamble. superpowers and caveman both fire on `SessionStart` and together
cost ~2.1k tokens on every compaction; impeccable adds ~560 tokens once and nothing on
re-fire. What it adds instead is a `PostToolUse` hook on `Edit|Write` alongside
graphify's per-read and per-grep injection — so a session that edits UI files now pays
graphify on the reads and impeccable on the writes. Both are silent when they have
nothing to say, and neither triggers on the other's events.

Against superpowers: no conflict, different layer. superpowers gates *whether* work
starts and *whether* it is done; impeccable judges what the result looks like. Its `Stop`
deep pass and superpowers' verification gate both fire at the end of a turn, which is
the one place to watch if turn latency starts to matter.

Against caveman: none. Caveman governs the agent's prose, impeccable governs the
artifact's pixels.

Against graphify: no overlap on capability, but `document` duplicates ground graphify
already covers, which is why it is marked Skip above.

## Gotchas

- **The engine is not in the repository.** `claude plugin install` gives you a POSIX shell
  launcher; the first hook invocation downloads a ~16 MB platform binary from the release
  channel. No network, or no `curl`/`wget`, means the launcher exits 127 and both hooks
  are dead — while the skill and its reference documents keep working. That is why this
  entry's dependency is a `warn`, not a `block`.
- **Three version numbers that do not agree.** `package.json` says `4.1.0`, the plugin
  manifest says `4.3.1`, the engine reports `0.1.5`. The one that determines detector
  behaviour is the engine, and it is fetched at runtime against the `VERSION` file — so
  the behaviour can move without the plugin pin changing.
- **It writes into your project.** `.impeccable/hook.cache.json` appears in the working
  directory on the first scan, and `init` will offer to add `PRODUCT.md` and `DESIGN.md`
  at the repo root. Add `.impeccable/` to `.gitignore` before you install.
- **The `Stop` hook has no matcher.** It runs at the end of every turn with a 30-second
  timeout, even when it ends up emitting nothing.
- **The per-edit pass is deliberately incomplete.** It reports only the mechanical tier;
  taste-level findings wait for the `Stop` pass. Setting `hook.perEditRules: "all"`
  restores the full rule set on every edit and multiplies the per-edit token cost
  accordingly.
- **Disk.** 2.2 MB of skill files, plus the 16 MB engine outside the plugin directory,
  which uninstalling the plugin does not remove.
