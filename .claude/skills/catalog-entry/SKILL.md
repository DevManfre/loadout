---
name: catalog-entry
description: Use when asked to add, replace, re-measure or remove anything loadout carries — a third-party integration, one of loadout's own skills, sub-agents or workflows.
---

# Catalog entry

Loadout admits an asset the way a good editor admits an article: it is not enough that
it exists and looks useful upstream. It has to be pinned to a revision, measured on this
machine, judged item by item, and wired into the install path and the catalog in the same
commit — or it does not go in.

This skill is that procedure. Follow it in order. Do not skip measurement because the
upstream README already quotes numbers; those numbers are the thing this repo exists to
replace.

## 0. Classify before anything else

| The thing is… | Home | Install path | Catalog row |
|---|---|---|---|
| A third-party plugin, binary or MCP server | `integrations/<name>/README.md` (+ mirrors) | `claude plugin install`, or a package manager | Integrations table |
| A skill loadout itself writes | `skills/<name>/SKILL.md` | plain copy by `install-all.sh` | Own assets |
| A sub-agent loadout itself writes | `agents/<name>.md` | plain copy | Own assets |
| A workflow loadout itself writes | `workflows/<name>.md` | plain copy | Own assets |
| Tooling for maintaining **this repo** | `.claude/skills/<name>/SKILL.md` | **not installed, not catalogued** | none |
| Application code, a runtime, a plugin manifest, a vendored copy of someone else's asset | nowhere | — | — |

The last two rows are the ones that get violated. `.claude/` is a hard boundary: it never
appears in the README catalog and `install-all.sh` never touches it. And loadout vendors
nothing — if the asset already has an upstream, the entry points at that upstream and
installs from it.

## 1. Gate — ask before spending the work

Answer these first, in writing, before cloning or measuring anything. If the answer to
either of the first two is no, say so and stop; a rejected entry is a normal, cheap
outcome and the whole point of the exercise.

1. **Does it pay for its context?** Name the concrete thing it saves — a wasted
   implementation run, a grep sweep plus three file reads, a class of bug. "It's useful"
   is not an answer.
2. **Does it duplicate something already carried?** Check the existing catalog before
   measuring. Overlap is not automatically fatal, but the entry must say which one wins
   and why.
3. **Is the source trustworthy and licensed?** No license, or a license that forbids the
   use, means it is documented as such or not carried at all.
4. **What is the smallest useful unit?** Often only part of a plugin is worth keeping.
   The per-item verdict table exists so the reader can carry three skills out of twenty.

## 2. Pin the revision

Everything downstream is a claim about a specific revision, so establish it before
measuring and state it in the entry.

```bash
# Plugins installed through the CLI land here, one directory per pin:
ls ~/.claude/plugins/cache/<marketplace>/<plugin>/
# Record the tag if the upstream publishes one, otherwise the commit:
git -C ~/.claude/plugins/cache/<marketplace>/<plugin>/<pin> log -1 --format='%H %cs'
```

Record: upstream URL, author, license (read the actual `LICENSE`/`LICENSING.md`, and note
when GitHub disagrees with it), version or commit inspected with its date, and a one-line
inventory — how many skills, commands, agents, hooks.

If the asset has more than one live pin worth comparing (an old install versus current
HEAD), measure both. A pin that triples the always-on cost is exactly the kind of fact
this catalog is for.

## 3. Measure on this machine

Token estimate: **characters ÷ 4**. Say "~" and round; precision beyond two significant
figures is false confidence. Every figure in an entry must come from a command run here.

Three budgets, always reported separately — conflating them is how upstream READMEs
mislead:

**Always on, per session.** Paid before the user types anything.

```bash
P=~/.claude/plugins/cache/<marketplace>/<plugin>/<pin>

# Skill index: only the frontmatter name + description of each skill is always loaded.
awk '/^---$/{n++; next} n==1' "$P"/skills/*/SKILL.md | wc -c

# Agent index: same shape, one description per sub-agent.
awk '/^---$/{n++; next} n==1' "$P"/agents/*.md | wc -c

# Hooks: read hooks.json, then run each SessionStart command and count what it emits.
cat "$P"/hooks/hooks.json
bash "$P"/hooks/<the-session-start-script> | wc -c
```

Then check the hook's **matcher**. A `SessionStart` hook with no matcher fires on startup,
resume, `/clear` *and every compaction* — on a long session the always-on cost is paid
many times, and the entry must say so.

**Per tool call or per prompt.** The cost people miss. A `UserPromptSubmit` hook is
unconditional; a skill that injects on read or grep is priced per operation.

```bash
bash "$P"/hooks/<the-user-prompt-script> | wc -c
```

**On demand.** Skill bodies load only when invoked. List the big ones by name and size:

```bash
find "$P"/skills -name SKILL.md -printf '%s\t%p\n' | sort -rn | head
```

**What you get back.** State the benefit in the same currency where possible. If the
number is upstream's and was not reproduced here, say that in the sentence that quotes it.
Then write the break-even arithmetic explicitly: how much has to be saved per session for
the entry to pay for itself, and the session shape where it does not.

## 4. Judge, item by item

One row per skill, command or sub-agent, with a verdict from exactly this vocabulary:

- **Keep** — carries its own weight for most sessions.
- **Situational** — worth it under a stated condition. Name the condition.
- **Skip** — do not carry. Name what to use instead, or why nothing is needed.

The "why" column is a claim about this repo's work, not a paraphrase of the item's own
description. Overlap with an asset already carried is decided here, by name.

## 5. Write the guide

`integrations/<name>/README.md`, sections in this fixed order — every entry answers the
same questions in the same sequence, because that is what makes the catalog comparable:

1. **Lede** — what kind of thing it is and what the trade actually is, in prose.
2. **Fact table** — upstream, author, license, version inspected, contents.
3. **Install** — the exact commands, including any marketplace that must be added first,
   plus how to disable it without uninstalling.
4. **Token economy** — the three budgets from step 3, as tables, plus what you get back
   and the break-even.
5. **Verdict, per item** — the table from step 4.
6. **Interaction with the rest of loadout** — what composes, what overlaps, and the
   running total of hook-bearing plugins now firing together.
7. **Gotchas** — what the upstream docs do not tell you. Behaviour that never stops on
   its own, matchers, upgrade cliffs, mixed licensing, disk weight.

For one of loadout's own assets there is no upstream to inspect, so steps 2–3 collapse:
write the `SKILL.md`/agent/workflow with valid frontmatter (`name`, `description`),
explicit trigger conditions and no assumptions about the user's machine, then measure its
own description cost and body size the same way.

Write guides and skills in normal English prose. The caveman register is for chat, never
for a file that ships.

## 6. Wire it in — same commit, no exceptions

An entry that is not reachable and not installable is a broken entry, and `validate.sh`
will say so.

1. **A third-party integration gets one row in `scripts/loadout.manifest`** — the data
   file `scripts/loadout` reads to build the menu and run `install`/`update`/`status`/
   `remove`. Columns, `|`-delimited, no field may contain a `|`:
   - `name` — the entry's id; must match `integrations/<name>/` exactly.
   - `kind` — `plugin` or `pypkg`; `install_entry` understands nothing else.
   - `source` — for a plugin, `marketplace=owner/repo` if a new marketplace must be
     added, or the bare marketplace name if one is already configured; for a pypkg, the
     package name, extras included (e.g. `headroom-ai[proxy]`).
   - `presets` — comma-separated subset of `core,full` this entry belongs to.
   - `needs` — comma-separated dependency tokens (next step); a `/` inside one token
     groups alternatives that each satisfy it, e.g. `uv/pipx`.
   - `probe` — how `status`/`doctor` detect it: `plugin:<name>`, `bin:<name>`; see
     `scripts/lib/probe.sh` for the forms it understands.
   - `cost_session` — the always-on figure from steps 3–4, written exactly as the README
     catalog cell will read; `validate.sh` cross-checks the two and fails on drift.
   - `measured` — the pinned version from step 2.
2. **A dependency token in `needs` that is not already in `scripts/loadout.deps` gets its
   own row there**: the token, its severity (`block` keeps the entry out of the menu
   entirely, `warn` installs anyway and says what is degraded, `runtime` never blocks and
   only shows up later as "installed, not in the path"), how it is probed, which platform
   it applies to (`always`, or `platform:<uname -s>/<uname -m>`), why the entry needs it,
   how to fix it, and which doc explains it.
3. **Loadout's own assets need neither.** `copy_own_assets` copies every `skills/*/`,
   `agents/*.md` and `workflows/*.md` unconditionally, so dropping the file in the right
   directory (step 0) is the entire wiring step. Do not give one a manifest row: it has no
   `integrations/<name>/` guide, and `validate.sh` requires every manifest row's name to
   resolve to one.
4. **README catalog** — a row in the right table: name, what it does, what you get back,
   always-on cost, link to the guide. Use the **readme-sync** skill; `README.md` is
   canonical, `README-it.md` and every other mirror change in the same commit.
5. **Integration guides have mirrors too** — `integrations/<name>/README-it.md` is
   required by the parity check, not optional.
6. **Removing an entry** is the same list in reverse, plus `🔥`. Renaming a shipped
   `skills/` name breaks existing installs: `💥`, and spell out the migration in the body.

## 7. Verify before claiming done

```bash
scripts/validate.sh
scripts/selftest.sh
scripts/loadout install --dry-run
```

`validate.sh` must print `ok` — for a third-party integration this includes checking that
the new manifest row resolves to `integrations/<name>/README.md` (+ mirror) and that its
`cost_session` matches the README cell. `scripts/selftest.sh` must still report every
test passing; add a case for the new entry if it exercises something no existing test
does (a new dependency token, a new probe form). The dry run must show the new entry
priced in the menu and change nothing. If the parity check complains about heading,
fence, link or table counts, a hunk was dropped from a mirror — fix it, do not adjust the
count.

## 8. Commit

One commit covering the guide, its mirrors, the `scripts/loadout.manifest` row (and any
new `scripts/loadout.deps` row) and the README catalog. Use the **commit-convention**
skill: `✨ INTEGRATION - …` for a new third-party entry, `✨ SKILL - …` / `✨ AGENT - …`
for loadout's own, `📝` when only the write-up changes, `🔥` for a removal. English, no
attribution trailer.

## Red flags

- "Upstream says it saves 65%" with no local measurement → the entry is not written yet.
- A cost quoted as a single number → the three budgets were not separated.
- Every item in the verdict table marked Keep → the judging step was skipped.
- A guide exists but the manifest has no row → `validate.sh` fails.
- A guide exists but the README does not mention it → half a commit.
- An `integrations/<name>/README.md` with no `README-it.md` → parity check fails.
- Something added under `.claude/` also added to the catalog → boundary violated.
- A copy of the upstream's files committed into this repo → loadout vendors nothing.
