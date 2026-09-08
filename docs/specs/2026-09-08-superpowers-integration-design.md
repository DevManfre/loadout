# Design — superpowers integration (first catalog asset)

Date: 2026-09-08
Status: approved
Scope: first shipped asset for `loadout`, plus the install architecture every later asset inherits.

## 1. Problem

`loadout` has no assets yet. The first one must do two jobs at once:

1. Carry **superpowers** (third-party plugin) into the catalog with real curation value.
2. Establish the install architecture so that a skill, a plugin, an MCP server, or a
   third-party binary added later all reach the user through one uniform command,
   with no reshaping of the index.

## 2. Upstream facts (verified 2026-09-08)

| Fact | Value |
|---|---|
| Repo | `https://github.com/obra/superpowers` |
| Author | Jesse Vincent |
| License | MIT |
| Version inspected | 6.3.0 |
| Contents | 14 skills, 0 commands, 0 agents, 1 `SessionStart` hook |
| Already distributed | Yes — present in `claude-plugins-official` (291 plugins) as `source: {source:"url", url:"https://github.com/obra/superpowers.git"}` |

Consequence: loadout is **not** the distribution channel for superpowers. Users can
install it from Anthropic's own marketplace. Loadout's contribution is curation —
measured token cost, per-skill verdicts, interaction notes. The docs must say this
plainly rather than implying loadout is required.

### 2.1 Measured token cost

Only one cost is unconditional: the `SessionStart` hook (matcher
`startup|clear|compact`) injects the full text of `using-superpowers` (3.1 KB, ~800
tokens) on every session start, `/clear`, and every compaction. Everything else is
on-demand skill loading.

SKILL.md sizes (bytes) and full-tree sizes where references exist:

| Skill | SKILL.md | tree |
|---|---|---|
| brainstorming | 15456 | 80159 |
| dispatching-parallel-agents | 6078 | 6078 |
| executing-plans | 2305 | 2305 |
| finishing-a-development-branch | 7781 | 7781 |
| receiving-code-review | 6203 | 6203 |
| requesting-code-review | 2956 | 8625 |
| subagent-driven-development | 32339 | 56664 |
| systematic-debugging | 9465 | 40772 |
| test-driven-development | 9015 | 17283 |
| using-git-worktrees | 6813 | 6813 |
| using-superpowers | 3108 | 17169 |
| verification-before-completion | 3646 | 3646 |
| writing-plans | 7053 | 8766 |
| writing-skills | 26360 | 107377 |

## 3. Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Superpowers is carried as a **doc-only entry** under `integrations/superpowers/`. Nothing is vendored into `skills/`. | No fork, no upstream drift, no license/attribution burden, no skill-name collision with the real plugin. |
| D2 | It is reachable through loadout's marketplace via an **external source** entry. | Satisfies the CLAUDE.md invariant that every shipped asset is reachable via the plugin index, at zero maintenance cost. |
| D3 | Source kind is `url`, not `github`. | Only `url`, `git-subdir`, and local paths were observed as valid `source` kinds in the official marketplace; `url` is what official uses for this exact repo. |
| D4 | No `sha` pin. | Users track upstream. Revisit only if drift causes breakage. |
| D5 | Loadout's own assets ship as **one plugin**: the repo root, `source: "./"`. | The root layout (`skills/`, `agents/`) is already what a plugin root looks like. Zero per-asset boilerplate. Users disable individual skills via `/plugin`. |
| D6 | MCP servers added later become tiny plugin dirs: `integrations/<name>/` with `.claude-plugin/plugin.json` + `.mcp.json`, indexed as `source: "./integrations/<name>"`. | Verified pattern — the official `context7` external plugin is exactly this. Keeps MCP on the same one-command install path. |
| D7 | Third-party binaries/CLIs are the one kind a plugin cannot install; they go through `scripts/install.sh <name>`. | Plugins cannot run package managers. Documented as a deliberate exception, not an oversight. |
| D8 | `workflows/` install path is deferred. | Not a native plugin directory (Claude Code reads `.claude/workflows/`). Decided when the first workflow lands; `scripts/install.sh` is the fallback. |

## 4. Install architecture

Bootstrap, once ever:

```
/plugin marketplace add DevManfre/loadout
```

Then, per asset kind:

| Kind | Index mechanism | User command |
|---|---|---|
| loadout's own skills / agents | repo root as plugin, `source: "./"` | `/plugin install loadout@loadout` |
| third-party plugin | `source: {source:"url", url:"…git"}` | `/plugin install <name>@loadout` |
| MCP server | `integrations/<name>/` plugin dir with `.mcp.json` | `/plugin install <name>@loadout` |
| third-party binary / CLI | per-asset manifest read by the installer | `scripts/install.sh <name>` |

## 5. Files in this change (single commit)

```
.claude-plugin/marketplace.json          new — index, superpowers is first entry
.claude-plugin/plugin.json               new — makes the repo root installable as the "loadout" plugin
integrations/superpowers/README.md       new — curated guide (English, canonical)
integrations/superpowers/README-it.md    new — Italian mirror
README.md                                new "Catalog" section with an Integrations table
README-it.md                             mirror, via the readme-sync skill
```

### 5.1 `marketplace.json`

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "loadout",
  "description": "Curated toolkit for AI coding agents: skills, sub-agents, workflows, integrations.",
  "owner": { "name": "Alessio Manfredini", "url": "https://github.com/DevManfre" },
  "plugins": [
    {
      "name": "superpowers",
      "description": "Process skills: brainstorming, TDD, systematic debugging, subagent-driven dev, skill authoring.",
      "author": { "name": "Jesse Vincent" },
      "category": "development",
      "source": { "source": "url", "url": "https://github.com/obra/superpowers.git" },
      "homepage": "https://github.com/obra/superpowers"
    }
  ]
}
```

The `loadout` self-entry (`source: "./"`, D5) is added by this change as the second
entry, so the pattern exists from day one even though the repo ships no own assets yet.

### 5.2 `integrations/superpowers/README.md` — required sections

This file is the template every later integration follows.

1. **What it is** — one paragraph, plus upstream URL, author, license, version inspected.
2. **Install** — loadout path and the upstream/official path, both stated.
3. **Token economy** — the measured table from §2.1, with the `SessionStart` hook called
   out as the only always-on cost.
4. **Skill-by-skill verdict** — 14 rows: skill, size, verdict (keep / situational / skip),
   one-line reason.
5. **Interaction with loadout** — how it composes with loadout's own assets; note that
   CLAUDE.md and direct user instructions take precedence over skill workflows.
6. **Gotchas** — the hook fires on compaction too; `brainstorming` enforces a hard approval
   gate before any implementation; these skills self-invoke aggressively by design.

Target length ~130 lines.

## 6. Non-goals

- No vendored copy of any upstream skill.
- No `sha` pinning.
- No `scripts/install.sh` implementation in this change — D7 defines its contract; it is
  written when the first binary-shaped asset arrives.
- No workflow install path (D8).

## 7. Acceptance criteria

- `marketplace.json` parses and contains exactly two entries: `superpowers` and `loadout`.
- Every local `source` path in the index resolves on disk.
- `integrations/superpowers/README.md` contains all six sections of §5.2, and its token
  figures match §2.1.
- `README.md` has a Catalog → Integrations table whose link to the integration doc resolves.
- `README-it.md` mirrors `README.md` section for section.
- No asset is listed twice in the index.
- The commit follows `<gitmoji> <SCOPE> - <subject>` and covers asset + index + all README
  languages together.
