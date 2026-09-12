# Hook recipes

Working configurations for the cases that come up most. Each one states the
event, what it costs per call, and how to turn it off. Paste into
`.claude/settings.json` (project) or `~/.claude/settings.json` (global) and then
prove it fires with `scripts/probe-hook.sh` before trusting it.

All of them read the hook payload from stdin and fail open. Each one is
self-contained: the four-line `field` helper reads JSON with `jq` or `python3`,
whichever the machine has, so no recipe carries a hard dependency on either. A
handler that shells out to a tool the machine lacks does not announce itself — it
exits quietly and reads exactly like a hook that decided not to fire.

The ideas behind recipes 1, 2, 4 and 5 come from
[everything-claude-code](https://github.com/affaan-m/everything-claude-code)
(MIT). The configurations there use a compound `matcher` expression, which the
harness treats as an unanchored regex on the tool name — so none of them fire.
These are rewritten against the real matcher/`if`/exit-code contract and tested
here.

---

## 1. Keep long-running commands in tmux

A dev server started as a plain `Bash` call has no reachable logs: the agent sees
the first chunk of output and nothing after. Started in tmux, the session
survives and the log is one `tmux capture-pane` away.

Advisory, `PostToolUse` — a block here is not worth the false positives.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(*run dev*)",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/tmux-hint.sh"
          }
        ]
      }
    ]
  }
}
```

```bash
#!/usr/bin/env bash
# .claude/hooks/tmux-hint.sh — advisory only, never blocks.
[ -n "${TMUX:-}" ] && exit 0
[ "${LOADOUT_TMUX_HINT:-on}" = "off" ] && exit 0
echo "Dev server outside tmux: logs will not be reachable after this call. tmux new -d -s dev '<cmd>' then tmux capture-pane -p -t dev."
exit 0
```

Cost: ~30 tokens, only on a matching command. Off: `LOADOUT_TMUX_HINT=off`.

`if` holds one rule, so one handler per pattern. `Bash(*run dev*)` covers
`npm run dev`, `pnpm run dev` and `bun run dev`; `yarn dev` and `make dev` need
their own handler.

---

## 2. Stop stray documentation files

Agents produce `NOTES.md`, `SUMMARY.md`, `IMPLEMENTATION_PLAN.md` nobody asked
for. Each one is a file a human must later read and delete.

Blocking, `PreToolUse` — the failure is concrete and the escape is obvious.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "if": "Write(**/*.md)",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/no-stray-docs.sh"
          }
        ]
      }
    ]
  }
}
```

```bash
#!/usr/bin/env bash
# .claude/hooks/no-stray-docs.sh — deny new top-level .md outside an allowlist.
set -u
[ "${LOADOUT_DOC_GUARD:-on}" = "off" ] && exit 0
payload=$(cat)
# field <json.path> — read one value from $payload, jq or python3, whichever exists.
field() {
  if command -v jq >/dev/null 2>&1; then printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null
  else printf '%s' "$payload" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for k in sys.argv[1].lstrip(".").split("."): d=(d or {}).get(k)
print(d or "")' "$1" 2>/dev/null; fi
}
path=$(field .tool_input.file_path)
[ -n "$path" ] || exit 0
[ -e "$path" ] && exit 0                      # edits to existing docs are fine
case $(basename "$path") in
  README*.md|CLAUDE.md|AGENTS.md|CONTRIBUTING.md|CHANGELOG.md|SKILL.md) exit 0 ;;
esac
case $path in */docs/*|*/references/*) exit 0 ;; esac
esc=$(printf '%s' "$path" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"New doc file %s - put it in docs/ or fold it into a README. LOADOUT_DOC_GUARD=off to override."}}\n' "$esc"
exit 0
```

Cost: 0 on every call that passes; ~45 tokens on a denial. Off:
`LOADOUT_DOC_GUARD=off`.

The `-e "$path"` test matters: without it the guard blocks ordinary rewrites of
files it would have allowed you to create.

---

## 3. Format after edit

Deterministic, silent, and the one case where running a tool on every edit pays
for itself: the diff stays clean and the agent never spends a turn on
whitespace.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "if": "Edit(**/*.{ts,tsx,js,jsx,css,json})",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/format.sh"
          }
        ]
      }
    ]
  }
}
```

```bash
#!/usr/bin/env bash
# .claude/hooks/format.sh — format silently; print nothing on success.
set -u
payload=$(cat)
# field <json.path> — read one value from $payload, jq or python3, whichever exists.
field() {
  if command -v jq >/dev/null 2>&1; then printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null
  else printf '%s' "$payload" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for k in sys.argv[1].lstrip(".").split("."): d=(d or {}).get(k)
print(d or "")' "$1" 2>/dev/null; fi
}
path=$(field .tool_input.file_path)
[ -f "$path" ] || exit 0
command -v prettier >/dev/null 2>&1 || exit 0
prettier --write "$path" >/dev/null 2>&1
exit 0
```

Cost: 0 tokens — it prints nothing. Paid in latency, not context.

Print nothing on success. A formatter that announces itself on every edit is a
per-edit token tax for information the agent cannot act on.

---

## 4. Type check without paying for it on every edit

`tsc --noEmit` on each edit is correct and slower than the edit. Run it once at
the end of the turn instead, on `Stop`, and only when something actually changed.

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/typecheck-once.sh"
          }
        ]
      }
    ]
  }
}
```

```bash
#!/usr/bin/env bash
# .claude/hooks/typecheck-once.sh — one check per turn, first 20 errors only.
set -u
[ "${LOADOUT_TYPECHECK:-on}" = "off" ] && exit 0
[ -f tsconfig.json ] || exit 0
git diff --quiet -- '*.ts' '*.tsx' 2>/dev/null && exit 0
out=$(npx --no-install tsc --noEmit 2>&1 | head -20) || true
[ -n "$out" ] && printf 'tsc:\n%s\n' "$out"
exit 0
```

`Stop` takes no matcher — it always fires. Cost: 0 when clean, up to ~400 tokens
when the file is broken, which is exactly when you want it. Off:
`LOADOUT_TYPECHECK=off`.

---

## 5. Suggest compaction at a logical boundary

Auto-compaction fires when the window fills, which is usually mid-task. A count
of edits since the last compaction is a decent proxy for "a phase just ended".

The version of this idea in the wild keys its counter to `/tmp/...-$$`. Each hook
invocation is a new process, so the counter is recreated at 1 every time and the
threshold never trips. Key it to the **session id** instead.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/compact-hint.sh"
          }
        ]
      }
    ],
    "PostCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/compact-hint.sh --reset"
          }
        ]
      }
    ]
  }
}
```

```bash
#!/usr/bin/env bash
# .claude/hooks/compact-hint.sh — suggest /compact every N edits; reset on compaction.
set -u
threshold=${LOADOUT_COMPACT_THRESHOLD:-60}
[ "$threshold" = "0" ] && exit 0
[ "${1:-}" = "--reset" ] && { rm -f "${TMPDIR:-/tmp}"/loadout-compact-*; exit 0; }
payload=$(cat)
# field <json.path> — read one value from $payload, jq or python3, whichever exists.
field() {
  if command -v jq >/dev/null 2>&1; then printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null
  else printf '%s' "$payload" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for k in sys.argv[1].lstrip(".").split("."): d=(d or {}).get(k)
print(d or "")' "$1" 2>/dev/null; fi
}
sid=$(field .session_id); sid=${sid:-nosession}
state="${TMPDIR:-/tmp}/loadout-compact-$sid"
n=$(( $(cat "$state" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$state"
[ $((n % threshold)) -eq 0 ] &&
  echo "$n edits since the last compaction. If a phase just ended, /compact now keeps the plan and drops the exploration."
exit 0
```

Cost: ~25 tokens every `threshold` edits. Off: `LOADOUT_COMPACT_THRESHOLD=0`.

The `--reset` handler on `PostCompact` is what makes the count mean "since the
last compaction" rather than "since the session began".

---

## 6. Refuse to answer LLM questions from memory

A project rule enforced instead of written down: any prompt naming a model or a
price must consult the reference, not the model's memory.

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/pricing-guard.sh"
          }
        ]
      }
    ]
  }
}
```

```bash
#!/usr/bin/env bash
# .claude/hooks/pricing-guard.sh — inject a reminder, never block.
set -u
payload=$(cat)
# field <json.path> — read one value from $payload, jq or python3, whichever exists.
field() {
  if command -v jq >/dev/null 2>&1; then printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null
  else printf '%s' "$payload" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for k in sys.argv[1].lstrip(".").split("."): d=(d or {}).get(k)
print(d or "")' "$1" 2>/dev/null; fi
}
prompt=$(field .prompt)
[ -n "$prompt" ] || exit 0
printf '%s' "$prompt" | grep -qiE 'price|pricing|cost per token|context window|model id' || exit 0
echo "Pricing and model-id questions: read the claude-api skill, do not answer from memory."
exit 0
```

`UserPromptSubmit` takes no matcher and its stdout is injected as context, so
keep the text to one line. Cost: ~20 tokens, only on a matching prompt.

This shape — grep the prompt, inject one line — is how a standing instruction
moves out of `CLAUDE.md` without becoming an always-on cost. Delete the rule from
`CLAUDE.md` in the same commit.
