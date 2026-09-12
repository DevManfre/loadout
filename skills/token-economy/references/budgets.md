# MCP tool budget and compaction discipline

Read on demand — dimensions 10 and 11 of the audit.

## MCP tool budget

Every enabled MCP server sends its full tool definitions on every request, before
the user types anything — usually the largest always-on cost in a setup, and the
one `measure.sh` cannot reach. Read it off `/context`, per project.

Starting limits, upstream practice rather than measured here
([everything-claude-code](https://github.com/affaan-m/everything-claude-code),
MIT): servers **configured** in the tens, **enabled** below ten per project, live
tools under ~80; upstream reports a 200k window falling to roughly 70k of usable
room when that is ignored. Replace the numbers with the project's own `/context`
reading. The durable rule is the shape: a server enabled because it might be
useful is paid for in every session in which it is not.

## Compaction discipline

Auto-compaction fires when the window fills — statistically mid-task, discarding
the exploration *and* the plan built from it. Compacting at a phase boundary
(research done, plan agreed, milestone finished) keeps the plan and drops only the
exploration.

A habit, not a finding: raise it only when the transcript shows the pattern
repeating. The fix is then mechanical — a `PostToolUse` counter suggesting
`/compact` every N edits, reset on `PostCompact`. Recipe 5 in `hook-recipes`.
