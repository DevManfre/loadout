#!/usr/bin/env bash
# measure.sh — token cost of every Claude Code component visible from a project.
#
# Distinguishes:
#   always-on  = loaded into EVERY session (CLAUDE.md files at root/global,
#                skill name+description lines, agent descriptions)
#   on-trigger = loaded only when invoked (full SKILL.md body, agent body,
#                per-directory CLAUDE.md)
#
# Estimate: tokens ~= chars / 4.
# Usage: measure.sh [project_dir]   (default: cwd)

set -euo pipefail

PROJECT="${1:-$PWD}"
GLOBAL="$HOME/.claude"

tok_file() { # whole-file token estimate
  local c
  c=$(wc -c <"$1")
  echo $(((c + 3) / 4))
}

tok_desc() { # frontmatter name+description token estimate
  awk '
    /^---[[:space:]]*$/ { n++; next }
    n == 1 {
      if ($0 ~ /^(name|description):/) { grab = 1; buf = buf $0 " "; next }
      if (grab && $0 ~ /^[A-Za-z_-]+:/) { grab = 0 }
      else if (grab) { buf = buf $0 " " }
    }
    n >= 2 { exit }
    END { print int((length(buf) + 3) / 4) }
  ' "$1"
}

rows=""
add_row() { # scope component always_on on_trigger path
  rows+="$1|$2|$3|$4|$5"$'\n'
}

# --- project ---
[ -f "$PROJECT/CLAUDE.md" ] &&
  add_row project CLAUDE.md "$(tok_file "$PROJECT/CLAUDE.md")" 0 "$PROJECT/CLAUDE.md"

while IFS= read -r f; do
  add_row project "CLAUDE.md (per-dir)" 0 "$(tok_file "$f")" "$f"
done < <(find "$PROJECT" -mindepth 2 -name CLAUDE.md \
  -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)

for f in "$PROJECT"/.claude/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  add_row project "skill:$(basename "$(dirname "$f")")" "$(tok_desc "$f")" "$(tok_file "$f")" "$f"
done

for f in "$PROJECT"/.claude/agents/*.md; do
  [ -f "$f" ] || continue
  add_row project "agent:$(basename "$f" .md)" "$(tok_desc "$f")" "$(tok_file "$f")" "$f"
done

# --- global ---
[ -f "$GLOBAL/CLAUDE.md" ] &&
  add_row global CLAUDE.md "$(tok_file "$GLOBAL/CLAUDE.md")" 0 "$GLOBAL/CLAUDE.md"

for f in "$GLOBAL"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  add_row global "skill:$(basename "$(dirname "$f")")" "$(tok_desc "$f")" "$(tok_file "$f")" "$f"
done

for f in "$GLOBAL"/agents/*.md; do
  [ -f "$f" ] || continue
  add_row global "agent:$(basename "$f" .md)" "$(tok_desc "$f")" "$(tok_file "$f")" "$f"
done

# --- plugins (enabled only; newest version dir of each) ---
enabled=$(python3 -c "
import json,sys
try: s=json.load(open('$GLOBAL/settings.json'))
except Exception: sys.exit()
print('\n'.join(k for k,v in s.get('enabledPlugins',{}).items() if v))" 2>/dev/null || true)

for pdir in "$GLOBAL"/plugins/cache/*/*/; do
  [ -d "$pdir" ] || continue
  plugin=$(echo "$pdir" | sed -E 's#.*/plugins/cache/([^/]+/[^/]+)/?$#\1#')
  # cache path is <marketplace>/<plugin>; enabledPlugins key is <plugin>@<marketplace>
  key="${plugin##*/}@${plugin%%/*}"
  grep -qxF "$key" <<<"$enabled" || continue
  latest=$(ls -td "$pdir"*/ 2>/dev/null | head -1)
  [ -n "$latest" ] || continue
  for f in "$latest"skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    add_row "plugin:$plugin" "skill:$(basename "$(dirname "$f")")" "$(tok_desc "$f")" "$(tok_file "$f")" "$f"
  done
  for f in "$latest"agents/*.md; do
    [ -f "$f" ] || continue
    add_row "plugin:$plugin" "agent:$(basename "$f" .md)" "$(tok_desc "$f")" "$(tok_file "$f")" "$f"
  done
done

# --- report ---
printf '%s' "$rows" | sort -t'|' -k3,3nr | awk -F'|' '
  BEGIN {
    printf "%-28s %-38s %10s %11s\n", "SCOPE", "COMPONENT", "ALWAYS-ON", "ON-TRIGGER"
    printf "%-28s %-38s %10s %11s\n", "-----", "---------", "---------", "----------"
  }
  NF >= 4 {
    printf "%-28s %-38s %10d %11d\n", $1, $2, $3, $4
    ao += $3; ot += $4
  }
  END {
    printf "%-28s %-38s %10s %11s\n", "", "", "---------", "----------"
    printf "%-28s %-38s %10d %11d\n", "TOTAL", "", ao, ot
    printf "\nalways-on = paid every session; on-trigger = paid per invocation\n"
  }'
