---
name: token-economy
description: Use when asked to audit or cut the token cost of a Claude Code setup, when writing a new skill, agent or CLAUDE.md, or on /token-economy.
---

# token-economy

Two modes, same rules:

- **Audit** — measure real costs of every Claude Code component (project +
  global), find waste, propose fixes with projected savings. **Never apply a
  fix without the user picking it from the report.**
- **Author** — when writing a new component, apply the dimensions as design
  rules up front (see Authoring rules) instead of fixing waste later.

## Audit workflow

1. Gather data (both scripts, no judgment involved):
   ```bash
   scripts/measure.sh <project_dir>    # always-on vs on-trigger cost per component
   scripts/usage.sh 30                 # real invocation counts, last 30 days
   scripts/usage.sh 30 <project_dir>   # same, this project only
   ```
   `measure.sh` cannot see MCP tool definitions — the harness sends them, no
   file holds them. Read that figure off `/context` in a live session of the
   project and record it with the rest. Limits and the compaction rule behind
   dimensions 10 and 11: `references/budgets.md`, read on demand.
2. Judge each component against the eleven dimensions below.
3. Emit the report (format below). Stop. Apply only the findings the user picks.

## Eleven dimensions

| # | Check | Flag when | Proposed action |
|---|-------|-----------|-----------------|
| 1 | CLAUDE.md as index | Root CLAUDE.md carries procedure prose, rule lists, or content derivable from code/git | Move procedure → skill; derivable content → delete; keep pointers |
| 2 | Per-folder CLAUDE.md | Root CLAUDE.md carries rules that only apply inside one directory | Split into `<dir>/CLAUDE.md` (loaded lazily on entry) |
| 3 | Unused skills/agents/plugins | 0 invocations in usage window AND not new (<2 weeks) | Archive skill or agent / disable plugin |
| 4 | Verbose descriptions | Skill/agent description > ~40 tokens | Shorten to trigger conditions only |
| 5 | Model fit | Subagent or routine with no model pin, doing mechanical work (locate, rename, format, extract) | Pin `model: haiku`; keep default only when task needs reasoning |
| 6 | Skill → code | SKILL.md body is deterministic steps with no judgment calls | Convert to script or hook; skill shrinks to a pointer or dies |
| 7 | Facts vs rules | CLAUDE.md carries facts (versions, module lists, endpoints, layout) | Facts → regenerable `.claude/overview.md` (own update skill) or README; CLAUDE.md keeps a "where is what" table + rules only |
| 8 | Rule → hook | CLAUDE.md rule is mechanically checkable (path guards, commit format, branch policy, test gate) | Enforce via hook in `.claude/settings.json`; CLAUDE.md keeps only "rules no hook can block" |
| 9 | Skill body bloat | SKILL.md body > ~1500 tok, or carries heavy reference (API tables, long examples, multi-language duplicates) inline | Move reference to `references/*.md` read on demand; one example, not many; body keeps workflow + judgment rules only |
| 10 | MCP tool budget | `/context` shows MCP tool definitions above ~10% of the window, or servers are enabled globally rather than per project | Disable the servers this project never calls; keep servers the agent uses, not servers that might be useful |
| 11 | Compaction discipline | Sessions routinely hit auto-compaction mid-task, losing the plan and keeping the exploration | Compact at a phase boundary instead; if the pattern repeats, enforce the reminder with a hook (see `hook-recipes`) |

## Authoring rules

The dimensions above, inverted — apply while writing, don't wait for the audit:

- **Pick the cheapest form first:** deterministic steps → script or hook, not a
  skill (dim 6, 8). Facts → regenerable file or README, not CLAUDE.md (dim 7).
  Rules scoped to one directory → `<dir>/CLAUDE.md` (dim 2). A skill only when
  the work needs judgment.
- **Description = trigger conditions only,** ~30-45 tokens: "Use when..." plus
  the keywords, error strings or commands that must fire it. No workflow
  summary — it costs always-on tokens and agents follow it instead of the body.
- **Body = workflow + judgment rules only.** Heavy reference (API tables, long
  examples, language mirrors) → `references/*.md` read on demand. One example,
  not many (dim 9).
- **Pin the model** on mechanical subagents: `model: haiku` for locate, rename,
  format, extract. Default model only when output needs reasoning (dim 5).
- **Pre-ship checklist:** run `scripts/measure.sh` on the new component; check
  the description contains every situation it must fire in and nothing else;
  confirm nothing in the body is derivable from code or git.

## Judgment rules

- **Description cuts:** keep every trigger keyword ("Use when...", error strings,
  command names, symptoms). Cut everything else: workflow summary, prose,
  qualifiers ("in this repo", "that must appear in"), enumerated examples when
  one generic term covers them. Target: one trigger sentence plus at most one
  key-fact clause, ~30-45 tokens. A description that summarizes the workflow is
  doubly wrong: costs tokens AND agents follow it instead of reading the body.
- **Always-on beats on-trigger:** a 1000-token body used weekly is fine; a
  100-token description paid every session on an unused skill is not.
  Prioritize findings by `always_on_tokens × (is it loaded every session?)`.
- **Usage window ≥ 30 days** before calling anything unused; note the window in
  the report.
- **Model fit:** Haiku for mechanical subagents (search, locate, mechanical
  edit, format). Sonnet+ when output needs judgment (review, design, debugging).
- **A hook saves nothing on its own.** Dimensions 8 and 11 pay only once the
  prose rule leaves `CLAUDE.md` in the same commit — count the saving from the
  deleted text. `hook-recipes` carries the mechanics and the four ways a hook
  silently fails to fire.

## Report format

One table, sorted by projected always-on savings, then details per finding:

```
| # | Component | Dim | Cost now (always-on) | Projected | Action | Risk |
```

Risk column is mandatory — name the failure mode (e.g. "trigger keyword removed
→ skill stops firing", "archived skill needed next month").

## Guardrails

- Archive = move, never delete: global skills → `~/.claude/skills-archive/<name>/`,
  project skills/agents → `.claude/skills-archive/`, `.claude/agents-archive/`.
- Global config (`~/.claude/`) edits: show full diff, apply only on explicit yes.
- Plugin-owned files (`~/.claude/plugins/cache/`): never edit — updates
  overwrite them. Propose disabling the plugin or reporting upstream instead.
- After description cuts, verify: does the description still contain every
  situation in which the skill must fire?

## Common mistakes

- Estimating costs by eye instead of running `measure.sh` — numbers must come
  from the scripts.
- Cutting a description below the point where it still triggers (dimension 4
  fights dimension 3 — a skill nobody triggers becomes an unused skill).
- Counting on-trigger cost as always-on and inflating savings.
