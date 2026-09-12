#!/usr/bin/env bash
# probe-hook.sh — feed a synthetic payload to a hook handler and report what the
# harness would do with the result.
#
# A hook is only trustworthy once you have seen it fire on the input that must
# trigger it AND stay silent on the input that must not. This runs one of those
# two halves; run it twice.
#
# Usage: probe-hook.sh <handler> <event> [tool] [tool_input_json] [prompt]
#   probe-hook.sh ./guard.sh PreToolUse Bash '{"command":"npm run dev"}'
#   probe-hook.sh ./hint.sh  UserPromptSubmit '' '{}' 'what does opus cost'

set -u

handler=${1:-}
event=${2:-PreToolUse}
tool=${3:-Bash}
tool_input=${4:-'{}'}
prompt=${5:-}

if [ -z "$handler" ]; then
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
fi
[ -x "$handler" ] || { echo "not executable: $handler" >&2; exit 64; }

if command -v python3 >/dev/null 2>&1; then json=python3
elif command -v jq >/dev/null 2>&1; then json=jq
else echo "probe-hook.sh needs python3 or jq" >&2; exit 69
fi

# A handler that shells out to a tool this machine lacks fails open and looks
# like a hook that simply decided not to fire. Say so before the probe runs.
for dep in jq node python3 prettier tsc; do
  grep -q "\\b$dep\\b" "$handler" 2>/dev/null || continue
  command -v "$dep" >/dev/null 2>&1 && continue
  # A handler that guards the call with `command -v` already has a fallback.
  grep -q "command -v $dep" "$handler" 2>/dev/null && continue
  echo "note    : handler calls '$dep', which is not installed here."
  echo "          It will fail open and never fire. Install it or rewrite the handler."
done

_py() { python3 -c "$1" "$@"; }

if [ "$json" = python3 ]; then
  payload=$(EV="$event" TL="$tool" TI="$tool_input" PR="$prompt" CWD="$PWD" python3 - <<'PY'
import json, os, time
d = {"session_id": "probe-%d" % time.time(), "cwd": os.environ["CWD"],
     "hook_event_name": os.environ["EV"], "tool_name": os.environ["TL"],
     "tool_input": json.loads(os.environ["TI"] or "{}")}
if os.environ["PR"]:
    d["prompt"] = os.environ["PR"]
print(json.dumps(d))
PY
)
else
  payload=$(jq -n --arg e "$event" --arg t "$tool" --arg p "$prompt" \
    --arg sid "probe-$(date +%s)" --arg cwd "$PWD" --argjson ti "$tool_input" \
    '{session_id:$sid, cwd:$cwd, hook_event_name:$e, tool_name:$t, tool_input:$ti}
     + (if $p == "" then {} else {prompt:$p} end)')
fi

errf=$(mktemp)
out=$(printf '%s' "$payload" | "$handler" 2>"$errf")
code=$?
err=$(cat "$errf"); rm -f "$errf"

echo "exit    : $code"
case "$code:$event" in
  2:PreToolUse)       echo "meaning : BLOCKS the tool call" ;;
  2:UserPromptSubmit) echo "meaning : BLOCKS the prompt and erases it" ;;
  2:Stop)             echo "meaning : prevents Claude from stopping" ;;
  2:*)                echo "meaning : blocking error for $event" ;;
  0:*)                echo "meaning : no block; stdout below reaches the model" ;;
  *:*)                echo "meaning : NON-BLOCKING error — the tool runs anyway."
                      echo "          Exit 1 does not block; use exit 2 or a deny JSON." ;;
esac

decision=""
if [ -n "$out" ] && [ "${out#\{}" != "$out" ]; then
  if [ "$json" = python3 ]; then
    decision=$(printf '%s' "$out" | python3 -c '
import json,sys
try: d = json.load(sys.stdin)
except Exception: print("INVALID"); sys.exit()
h = d.get("hookSpecificOutput") or {}
if "permissionDecision" in h:
    print(h["permissionDecision"] + "\t" + str(h.get("permissionDecisionReason", "-")))
else: print("INVALID")')
  else
    decision=$(printf '%s' "$out" | jq -r 'if .hookSpecificOutput.permissionDecision
      then .hookSpecificOutput.permissionDecision + "\t" + (.hookSpecificOutput.permissionDecisionReason // "-")
      else "INVALID" end' 2>/dev/null || echo INVALID)
  fi
fi
case "$decision" in
  ""|INVALID)
    [ -n "$decision" ] && {
      echo "warning : stdout starts with '{' but is not a valid hook decision —"
      echo "          the harness treats it as a non-blocking error."; } ;;
  *) echo "decision: ${decision%%	*}"
     echo "reason  : ${decision#*	}" ;;
esac

bytes=$(printf '%s' "$out" | wc -c)
echo "stdout  : $bytes bytes, ~$(( (bytes + 3) / 4 )) tokens per matching call"
[ -n "$out" ] && printf -- '--- stdout ---\n%s\n' "$out"
[ -n "$err" ] && printf -- '--- stderr (debug log only, unless exit 2) ---\n%s\n' "$err"
exit 0
