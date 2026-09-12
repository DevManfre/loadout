# frontend-design

Anthropic's own taste file for generated interfaces. It is a single skill and nothing
else — no hooks, no sub-agents, no commands, no binary — so it is the cheapest
design-related entry this catalog carries. The body is an argument rather than a
checklist: design from the subject matter, spend boldness in one place, plan tokens
before writing CSS, and avoid the five visual clusters that AI-generated pages keep
landing on. It even names the tell that matters most here — the warm cream background
with a terracotta accent near `#D97757`, which is Claude's own interaction colour and so
reads as a signature on any brief that did not ask for it.

The trade is unusually clean. The always-on cost is one skill description, about 70
tokens, and the 9.4 KB body loads only when the model is actually doing UI work. What
you do not get is enforcement: nothing inspects the output afterwards. This is a
prompt, not a detector.

| | |
|---|---|
| Upstream | https://github.com/anthropics/claude-plugins-official/tree/main/plugins/frontend-design |
| Author | Anthropic (Prithvi Rajasekaran, Alexander Bricken) |
| License | Apache-2.0 (`LICENSE`, plus `skills/frontend-design/LICENSE.txt`) |
| Version inspected | plugin pin `3deb821cb71c` (no version field is published), inspected 2026-09-12 |
| Contents | 1 skill, 0 commands, 0 agents, 0 hooks |

## Install

It lives in Anthropic's official directory, which the CLI already knows about, so no
marketplace has to be added first:

```bash
claude plugin install frontend-design@claude-plugins-official
```

`scripts/install-all.sh` runs exactly that command, alongside the rest of loadout.

To take it out of context without uninstalling:

```bash
claude plugin disable frontend-design
```

There is no configuration file, no environment variable and no network fetch at runtime.

## Token economy

Three budgets, measured here at the pin named above. Tokens are characters ÷ 4, rounded.

**Always on, per session.** Paid before you type anything.

| Source | characters | ≈ tokens |
|---|---|---|
| Skill description in the skill index (1 skill) | 279 | ~70 |
| Sub-agent descriptions in the agent index | none | 0 |
| `SessionStart` injection | none | 0 |
| **Total** | **279** | **~70** |

**Per tool call or per prompt.** Zero. The plugin ships no `hooks/` directory at all, so
nothing fires on `Edit`, on `Write`, on a prompt or on a compaction.

**On demand.** The body enters context only when the skill is invoked.

| File | size | ≈ tokens |
|---|---|---|
| `skills/frontend-design/SKILL.md` | 9.4 KB | ~2,350 |

**What you get back.** One design plan that is not the default. The measurable saving is
a rebuild avoided: when a page comes back reading as templated, the fix is rarely a tweak,
it is a second pass over palette, type and layout — several thousand tokens of generation
plus the review round that asked for it. Break-even is roughly one avoided rebuild per
twenty sessions at the always-on price, or one per session at the invoked price. The
shape where it does not pay is a brief that already pins the visual direction: the skill
says the brief's own words win, so it has little left to decide.

Note that the calibration list is the part that ages. It describes what generated design
looked like at this pin; as the clusters shift, an unrevised list starts steering away
from things that are no longer tells.

## Verdict, per item

| Skill | Size | Verdict | Why |
|---|---|---|---|
| frontend-design | 9.4 KB | Keep if you generate any UI | ~70 tokens standing cost is below the noise floor, and the body only loads on UI work. The aesthetic-defaults section is the part no amount of prompting reproduces cheaply. |

## Interaction with the rest of loadout

It overlaps with **impeccable**, and the two do not compete: this one writes the brief,
that one checks the result. `frontend-design` runs before the code exists and argues about
palette, type and layout; impeccable's `PostToolUse` detector runs after every edit and
flags gradient text, zero-offset glows, contrast below WCAG AA and design-system drift.
If you carry only one, carry this one on a machine that mostly ships backend work — it is
~70 tokens against impeccable's ~560 — and carry impeccable when UI quality has to be
enforced rather than recommended. Carrying both costs ~630 tokens per session and no
extra hook.

It also overlaps with impeccable's own skill description at the index level only; both
descriptions are loaded, neither body is, so the cost of the overlap is the ~70 tokens.

`frontend-design` adds nothing to the hook count. The plugins in this catalog that fire
hooks remain caveman (`SessionStart`, `UserPromptSubmit`), superpowers (`SessionStart`)
and impeccable (`PostToolUse`, `Stop`).

## Gotchas

- **There is no version.** `plugin.json` publishes a name and an author and no version
  field, so the CLI pins by commit and `status` shows a hex string, not a tag. Compare
  pins by diffing the skill, not by reading a number.
- **The pin moves under you, and the body grows.** The previous pin cached on this
  machine, `3da105324a27`, carries an 8.3 KB body against the current 9.4 KB — about 14%
  more on-demand cost for the same 279-character description. The always-on figure is
  stable; the invoked figure is not.
- **Automatic invocation is the upstream's claim, not a guarantee.** The README says
  Claude uses the skill automatically for frontend work; what actually triggers it is the
  description matching the request. A prompt that says "fix this CSS" may never load it.
  Ask for it by name when the design matters.
- **Two licenses, same terms.** The plugin root and the skill directory each carry an
  Apache-2.0 text. They agree; the duplicate exists so the skill stays licensed if it is
  copied out of the plugin.
- **It will not stop you shipping a default.** Nothing verifies the output. If you want a
  gate rather than advice, that is impeccable's job, or a hook of your own — see
  `skills/hook-recipes/SKILL.md`.
