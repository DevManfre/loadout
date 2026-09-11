# CLAUDE.md — loadout

A guide, **not a plugin**: documents which Claude Code skills, sub-agents, workflows and
integrations are worth carrying and what each costs in context. No application code.
Token economy is a feature: an asset that costs more context than it saves doesn't
belong here.

## Where is what

| Need | Read |
|---|---|
| Catalog, philosophy, install flow | `README.md` (canonical, English) |
| Layout facts (dirs, scripts, manifest) | `ls` + `README.md` — small repo, no overview file |
| Installer internals | `scripts/lib/`, entrypoint `scripts/loadout` |
| Validation / installer tests | `scripts/validate.sh` / `scripts/selftest.sh` (stubbed machine, no network) |
| Codebase questions | `graphify query "<q>"` (hook enforces); after edits `graphify update .` |

Skills present themselves via their descriptions (catalog-entry, readme-sync,
commit-convention; token-economy now ships from `skills/`).

## Rules no hook can block

1. **Hard boundary:** `.claude/` = workspace tooling, never shipped, never in the
   catalog. `skills/`, `agents/`, `workflows/`, `integrations/` = shipped, must be
   reachable from the README catalog.
2. No plugin manifest or marketplace index — point at upstream, never re-publish.
3. Every catalog entry states upstream, license, version inspected, token cost
   **measured on a real repository**, per-item verdict, gotchas.
4. Catalog add/rename/remove = one commit covering entry, `install-all.sh`, and the
   README catalog in **all** languages (readme-sync cascades; never hand-edit one).
5. `skills/` names are public API — renaming is a breaking change (`💥` in commit body).
6. Commits English, `<gitmoji> <SCOPE> - <subject>` (commit-convention).
