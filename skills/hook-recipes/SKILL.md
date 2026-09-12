---
name: hook-recipes
description: Use when a repeated instruction should become an enforced hook in settings.json, when a hook does not fire, or on /hook-recipes.
---

# hook-recipes

A rule in `CLAUDE.md` costs tokens every session and is followed only when the
agent happens to read it. The same rule as a hook costs nothing in the context
window and is enforced by the harness. This skill decides which rules make that
move, writes the hook correctly, and proves it fires.

Companion to **token-economy** dimensions 8 (rule → hook) and 6 (skill → code):
those are the *when*, this is the *how*.

## Decide first: hook, or not a hook

A rule belongs in a hook when all three hold:

1. **Mechanically checkable.** A script decides pass/fail from the tool name,
   the tool input, or the files on disk — no judgment, no reading of intent.
2. **Worth interrupting for.** The failure it prevents costs more than a false
   positive does. A blocking hook fires on the user's work as well as the
   agent's.
3. **Cheap to run.** It executes on every matching tool call. Anything shelling
   out to a type checker or a test suite belongs on `PostToolUse`, or later, as
   a warning — never on `PreToolUse` as a gate.

If it needs judgment, it is a skill. If it is a fact, it is a file. If it only
matters once, say it in the prompt.

## The four corrections

Most hooks found in the wild are dead on arrival for one of these reasons. Check
each one before writing anything.

**1. `matcher` filters the tool name, nothing else.** There is no expression
language. A value of only letters, digits, `_`, `-`, spaces, `,` and `|` is
matched as an exact string or a list of them (`Edit|Write`); anything containing
another character becomes an **unanchored JavaScript regex against the tool
name**. So `"tool == \"Bash\" && tool_input.command matches \"npm run dev\""` is
not a condition — it is a regex matching no tool name, and the hook silently
never runs. Anchor with `^...$` for the whole name.

**2. Filter on arguments with `if`, per handler.** `if` takes permission-rule
syntax — `"Bash(git *)"`, `"Edit(*.ts)"`, `"Edit(**/src/**)"` — and holds exactly
one rule. No `&&`, no `||`, no lists: use several handlers. It is evaluated only
on tool events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`,
`PermissionRequest`, `PermissionDenied`); on any other event a handler carrying
`if` never runs at all. It is best-effort by design — for a hard boundary use
the permission system, not a hook.

**3. Exit 2 blocks. Exit 1 does not.** On `PreToolUse`, exit 2 blocks the call
and the reason shown is the blocking JSON's reason, or stderr if there is none.
Every other non-zero code is a non-blocking error: the tool runs anyway and the
transcript shows a hook error. A hook that ends `process.exit(1)` after printing
"BLOCKED" blocks nothing. The JSON form is clearer and preferred:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"why"}}
```

Exit 0 with no output means *no decision*, not approval. A hook can deny;
silence cannot allow.

**4. State keyed to the process dies with it.** Each handler is a separate
short-lived process, so `$$`, `$PPID` and any in-memory counter reset on every
invocation. Key persistent state to the **session id** from the stdin payload,
under `${CLAUDE_PLUGIN_DATA}` or a path from `${CLAUDE_PROJECT_DIR}` — never
`/tmp/thing-$$`.

## Writing one

1. Pick the narrowest event. `PreToolUse` only when the call must not happen;
   `PostToolUse` for anything advisory; `SessionStart`/`SessionEnd` for state.
2. Set `matcher` to the tool name (or `Edit|Write`), and put the argument
   condition in `if`.
3. Read the payload from stdin — `jq` if present, `python3` otherwise; never
   parse it out of `$@`. A handler that shells out to a tool the machine lacks
   fails open and is indistinguishable from one that chose not to fire.
4. Prefer exec form — `"command": "node", "args": ["${CLAUDE_PLUGIN_ROOT}/x.js"]`
   — whenever a path placeholder is involved; shell form needs quoting and
   breaks on Windows `.cmd` shims.
5. Fail open: an unexpected payload must exit 0, never take the session down.
   Reserve exit 2 for the condition you designed for.
6. Keep the emitted text short. Stdout enters the context window on every
   matching call, so a chatty `PostToolUse` hook on `Edit` is a per-edit token
   tax. Price it with `token-economy`.

Tested JSON and handlers: `references/recipes.md`. Read it when you need one.

## Prove it fires

Never ship a hook you have only read. `scripts/probe-hook.sh` feeds a synthetic
payload to a handler and reports what the harness would do with the result:

```bash
scripts/probe-hook.sh <handler> <event> <tool> [json_tool_input]
scripts/probe-hook.sh ./guard.sh PreToolUse Bash '{"command":"npm run dev"}'
```

It prints the exit code, its blocking meaning, the per-call token cost of the
stdout, and a warning when the handler calls a tool this machine lacks. Run it
twice: once with input that must trigger, once with input that must not. A hook
that triggers on both is worse than no hook.

Then check the wiring, which the probe cannot see:

```bash
grep -n '"matcher"' .claude/settings.json ~/.claude/settings.json
```

A matcher containing `==`, `&&` or `matches` is correction 1, and never fires.

## Judgment rules

- **One hook, one condition.** Two conditions means two handlers. Compound
  matchers are the single most common way a hook silently stops firing.
- **Advisory beats blocking** until the failure is evidenced. Start as a
  `PostToolUse` warning; promote to `PreToolUse` only once that warning proved
  right and was ignored anyway.
- **A blocking hook needs an escape** named in the message it prints, or the
  first false positive costs the user their session.
- **Delete the `CLAUDE.md` rule in the same commit.** A rule both enforced by a
  hook and written in prose pays twice for one thing. That deletion is the whole
  saving — the hook alone changes no token cost.

## Common mistakes

- Writing a compound `matcher` expression (correction 1) and never testing it.
- Using exit 1 to block (correction 3).
- Counters or locks keyed to `$$` (correction 4).
- Running `tsc` on every edit: correct, and slower than the edit it follows.
  Debounce it, or move it to `Stop`.
- Keeping the prose rule after the hook lands, so the context cost stays.
