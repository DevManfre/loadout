---
name: token-audit
description: Use when asked to audit, reduce, or optimize the token cost of a Claude Code setup — CLAUDE.md too long, unused skills or plugins, verbose skill descriptions, subagent model choice, converting skills to scripts, or /token-audit.
---

# token-audit

Audit every Claude Code component (project + global) for token economy: measure
real costs, find waste, propose fixes with projected savings. **Never apply a
fix without the user picking it from the report.**

## Workflow

1. Gather data (both scripts, no judgment involved):
   ```bash
   scripts/measure.sh <project_dir>    # always-on vs on-trigger cost per component
   scripts/usage.sh 30                 # real invocation counts, last 30 days
   scripts/usage.sh 30 <project_dir>   # same, this project only
   ```
2. Judge each component against the six dimensions below.
3. Emit the report (format below). Stop. Apply only the findings the user picks.

## Six dimensions

| # | Check | Flag when | Proposed action |
|---|-------|-----------|-----------------|
| 1 | CLAUDE.md as index | Root CLAUDE.md carries procedure prose, rule lists, or content derivable from code/git | Move procedure → skill; derivable content → delete; keep pointers |
| 2 | Per-folder CLAUDE.md | Root CLAUDE.md carries rules that only apply inside one directory | Split into `<dir>/CLAUDE.md` (loaded lazily on entry) |
| 3 | Unused skills/agents/plugins | 0 invocations in usage window AND not new (<2 weeks) | Archive skill or agent / disable plugin |
| 4 | Verbose descriptions | Skill/agent description > ~60 tokens | Shorten to trigger conditions only |
| 5 | Model fit | Subagent or routine with no model pin, doing mechanical work (locate, rename, format, extract) | Pin `model: haiku`; keep default only when task needs reasoning |
| 6 | Skill → code | SKILL.md body is deterministic steps with no judgment calls | Convert to script or hook; skill shrinks to a pointer or dies |
| 7 | Facts vs rules | CLAUDE.md carries facts (versions, module lists, endpoints, layout) | Facts → regenerable `.claude/overview.md` (own update skill) or README; CLAUDE.md keeps a "where is what" table + rules only |
| 8 | Rule → hook | CLAUDE.md rule is mechanically checkable (path guards, commit format, branch policy, test gate) | Enforce via hook in `.claude/settings.json`; CLAUDE.md keeps only "rules no hook can block" |
| 9 | Skill body bloat | SKILL.md body > ~1500 tok, or carries heavy reference (API tables, long examples, multi-language duplicates) inline | Move reference to `references/*.md` read on demand; one example, not many; body keeps workflow + judgment rules only |

## Judgment rules

- **Description cuts:** keep every trigger keyword ("Use when...", error strings,
  command names, symptoms). Cut only workflow summary and prose. A description
  that summarizes the workflow is doubly wrong: costs tokens AND agents follow
  it instead of reading the body.
- **Always-on beats on-trigger:** a 1000-token body used weekly is fine; a
  100-token description paid every session on an unused skill is not.
  Prioritize findings by `always_on_tokens × (is it loaded every session?)`.
- **Usage window ≥ 30 days** before calling anything unused; note the window in
  the report.
- **Model fit:** Haiku for mechanical subagents (search, locate, mechanical
  edit, format). Sonnet+ when output needs judgment (review, design, debugging).

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
