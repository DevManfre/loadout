#!/usr/bin/env bash
# usage.sh — real invocation counts for skills and subagents, from Claude Code
# session transcripts (~/.claude/projects/*/*.jsonl).
#
# Usage: usage.sh [days]            count across ALL projects (default 30 days)
#        usage.sh [days] [project]  restrict to one project dir (path, not slug)

set -euo pipefail

DAYS="${1:-30}"
LOGS="$HOME/.claude/projects"

if [ -n "${2:-}" ]; then
  slug=$(realpath "$2" | sed 's#/#-#g')
  LOGS="$LOGS/$slug"
  [ -d "$LOGS" ] || { echo "no transcripts for $2 ($LOGS)"; exit 1; }
fi

mapfile -t files < <(find "$LOGS" -name '*.jsonl' -mtime "-$DAYS" 2>/dev/null)
echo "sessions scanned: ${#files[@]} (last $DAYS days)"
[ ${#files[@]} -eq 0 ] && exit 0

echo
echo "== skill invocations =="
grep -hoE '"skill"[[:space:]]*:[[:space:]]*"[^"]+"' "${files[@]}" 2>/dev/null |
  sed -E 's/.*"skill"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' |
  sort | uniq -c | sort -rn || echo "(none)"

echo
echo "== slash-command invocations =="
grep -hoE '<command-name>[^<]+</command-name>' "${files[@]}" 2>/dev/null |
  sed -E 's#</?command-name>##g' |
  sort | uniq -c | sort -rn || echo "(none)"

echo
echo "== subagent invocations =="
grep -hoE '"subagent_type"[[:space:]]*:[[:space:]]*"[^"]+"' "${files[@]}" 2>/dev/null |
  sed -E 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' |
  sort | uniq -c | sort -rn || echo "(none)"
