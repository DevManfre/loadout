# ui-ux-pro-max

A design plugin that answers with data instead of prose. Where `frontend-design` argues
for taste in about 2,350 tokens of body, this one ships a local database — 79 styles, 192
palettes with reasoning profiles, 74 font pairings, 119 UX guidelines, 105 icons, 25 chart
types, 22 implementation stacks — and a Python script that queries it. The 3.1 MB of CSV
and JSON never enter the context window: the model runs `search.py`, reads the few hundred
characters that come back, and decides. That is the whole architecture, and it is the
reason an asset this large is affordable at all.

The trade is the seven skills. The plugin exposes every directory under
`.claude/skills/`, so installing the one you want also installs `brand`, `slides` and
`banner-design`, and their descriptions are loaded whether or not you make slides. That
is ~683 tokens standing, the most expensive always-on figure in this catalog, against
~70 for `frontend-design` and ~560 for `impeccable`. Nothing in the plugin lets you take
six of the seven back out.

| | |
|---|---|
| Upstream | https://github.com/nextlevelbuilder/ui-ux-pro-max-skill |
| Author | nextlevelbuilder |
| License | MIT (`LICENSE`, and `"license": "MIT"` in `.claude-plugin/plugin.json`) |
| Version inspected | v2.13.0, commit `7f69fed6a271`, inspected 2026-09-12 |
| Contents | 7 skills, 0 commands, 0 agents, 0 hooks |

## Install

It is not in Anthropic's official directory, so the marketplace has to be added first:

```bash
claude plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill
claude plugin install ui-ux-pro-max@ui-ux-pro-max-skill
```

`scripts/loadout install` runs exactly those two commands, alongside the rest of loadout.

To take it out of context without uninstalling:

```bash
claude plugin disable ui-ux-pro-max
```

The search script needs Python 3.x and nothing else — every import is standard library
(`argparse`, `csv`, `json`, `difflib`, `urllib.parse`, …), and there is no network call at
runtime. Without Python the skill bodies still load and the database is unreachable, which
is the whole value, so `python3` is carried as a `warn` dependency rather than a `block`.

## Token economy

Three budgets, measured here at the pin named above. Tokens are characters ÷ 4, rounded.

**Always on, per session.** Paid before you type anything. `plugin.json` points `skills`
at `./.claude/skills/`, so all seven land in the index.

| Skill | description | ≈ tokens |
|---|---|---|
| `design` | 639 ch | ~159 |
| `ui-ux-pro-max` | 497 ch | ~124 |
| `ui-styling` | 489 ch | ~122 |
| `banner-design` | 445 ch | ~111 |
| `design-system` | 276 ch | ~69 |
| `brand` | 183 ch | ~45 |
| `slides` | 140 ch | ~35 |
| **Total, with names** | **2,735 ch** | **~683** |

**Per tool call or per prompt.** Zero. The plugin ships no `hooks/` directory at all, so
nothing fires on `Edit`, on `Write`, on a prompt or on a compaction.

**On demand.** Bodies load only when a skill is invoked, and the two big reference files
only when the body tells the model to read them.

| File | size | ≈ tokens |
|---|---|---|
| `ui-ux-pro-max/SKILL.md` | 15.9 KB | ~3,980 |
| `design/SKILL.md` | 13.3 KB | ~3,337 |
| `ui-styling/SKILL.md` | 10.6 KB | ~2,656 |
| `design-system/SKILL.md` | 7.4 KB | ~1,853 |
| `banner-design/SKILL.md` | 7.0 KB | ~1,752 |
| `brand/SKILL.md` | 3.5 KB | ~878 |
| `slides/SKILL.md` | 1.7 KB | ~429 |
| `ui-ux-pro-max/references/quick-reference.md` | 24.5 KB | ~6,130 |
| `ui-ux-pro-max/references/pro-rules.md` | 10.9 KB | ~2,730 |

**Per search, which is the figure that actually recurs.** Measured on the query
`"developer tooling catalog site"`:

| Invocation | output | ≈ tokens |
|---|---|---|
| `--design-system -p "<name>"` (default format) | 8,015 ch of box drawing and ANSI colour | ~2,000 nominal, more in practice |
| `--design-system -p "<name>" -f markdown` | 2,981 ch | ~745 |
| `--domain style` | 419 ch | ~105 |
| `--stack react` | 367 ch | ~92 |

The default format draws a frame in Unicode box characters and colours the swatches with
ANSI escapes. Both tokenize badly — a run of `═` and a `\x1b[38;2;30;41;59m` cost far more
than their character count suggests — so the 2.7× gap above is a floor, not the real one.
Add `-f markdown` to every call.

**What you get back.** A palette, a font pairing and a layout pattern chosen from a
catalogue rather than improvised, in ~105 tokens for a targeted domain query. The saving
is a second generation pass avoided: when a page comes back with the wrong visual
direction the fix is a rebuild, several thousand tokens plus the review round that asked
for it. Break-even at the always-on price is roughly one avoided rebuild per seven
sessions; at the invoked price a single `--domain` query pays for itself immediately. The
shape where it does not pay is a machine that mostly ships backend work: ~683 tokens a
session buys nothing on a day with no UI in it.

## Verdict, per item

| Skill | Size | Verdict | Why |
|---|---|---|---|
| ui-ux-pro-max | 15.9 KB | Keep if you ship UI | The database and the query contract are the entry. Everything else here is a satellite. |
| design | 13.3 KB | Situational — full page or flow work | Overlaps `ui-ux-pro-max` on style and palette; worth invoking by name when a whole screen is being laid out, not for a component fix. |
| ui-styling | 10.6 KB | Situational — stack-specific work | Pays when the implementation stack is one of the 22 it knows. On an unlisted stack it degrades to generic advice. |
| design-system | 7.4 KB | Situational — token architecture | Invoke when tokens, scales and theming are the deliverable. Otherwise the main skill's output already carries the decisions. |
| banner-design | 7.0 KB | Skip | Ad and social banner sizes. Nothing in this repo's work touches it, and it costs ~111 tokens a session to carry. |
| brand | 3.5 KB | Skip | Logo rules, voice framework, brand guideline templates. The valuable half of brand identity is behind the upstream's premium tier. |
| slides | 1.7 KB | Skip | Slide decks. Cheapest of the three at ~35 tokens, and still unused. |

Three Skips that cannot be acted on: the plugin has no per-skill switch. The verdict is
recorded so the ~191 tokens they cost are a known charge, not a surprise.

## Interaction with the rest of loadout

It meets `frontend-design` and `impeccable`, and the three do not do the same job.
`frontend-design` writes the brief and argues about direction before the code exists.
`ui-ux-pro-max` answers the brief with specific values — this palette, this pairing, this
pattern. `impeccable`'s `PostToolUse` detector checks the result after every edit. Brief,
decision, gate.

| Entry | Always-on | Hooks |
|---|---|---|
| frontend-design | ~70 | none |
| impeccable | ~560 | `PostToolUse`, `Stop` |
| ui-ux-pro-max | ~683 | none |
| all three | ~1,313 | 2 |

Carrying all three is ~1,313 tokens a session and no extra hook. If that is too much, the
order to drop in is `ui-ux-pro-max` first on a backend machine, `impeccable` first when
advice matters more than enforcement, and `frontend-design` last — at ~70 tokens it is
below the noise floor either way.

`ui-ux-pro-max` adds nothing to the hook count. The plugins in this catalog that fire
hooks remain caveman (`SessionStart`, `UserPromptSubmit`), superpowers (`SessionStart`)
and impeccable (`PostToolUse`, `Stop`).

## Gotchas

- **The database misses on niche products.** `"developer tooling catalog site" --domain
  style` returns `Found: 0 results` and offers `analog, tool` as nearest terms. The
  catalogue is built around consumer product categories. The skill body handles this
  honestly — it requires one narrower retry and then an explicit statement that no match
  was found — but the wasted round trip is real, and on a sufficiently unusual product
  every query ends that way.
- **The default output format is the expensive one.** Box drawing plus ANSI colour, 2.7×
  the characters of `-f markdown` for the same content and worse under the tokenizer.
  Nothing warns you; add the flag.
- **Seven skills, one install.** `plugin.json` sets `"skills": "./.claude/skills/"`, so
  `brand`, `slides` and `banner-design` are loaded into the index on every session whether
  or not the machine ever makes a banner. ~191 of the ~683 tokens buy nothing on a
  developer machine.
- **The descriptions quote their own database counts.** The main skill's description names
  "79 searchable styles (50 active), 192 product palettes…". Those numbers do not help the
  model route to the skill, they lengthen the always-on string, and they change on every
  release — which means the figures in this guide have to be re-measured on each pin, not
  just the totals.
- **About 9.6 MiB on disk.** `.claude/skills/` weighs 10,046,170 bytes, of which 3.1 MB is
  the main skill's `data/` (`google-fonts.csv` 747 KB, `phosphor-icons-upstream.json` 824
  KB). None of it is context, all of it is clone and update time.
- **A premium tier exists.** Brand identity generation, logo design, custom iconography and
  the scalable token architecture are sold separately. What is measured above is the MIT
  half, which is the half this catalog carries.
- **Python is not optional in practice.** Without `python3` the bodies still load and every
  query fails, so you pay ~683 tokens a session for advice the skill itself tells the model
  not to trust unverified.
