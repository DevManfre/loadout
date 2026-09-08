#!/usr/bin/env bash
# Structural validation for the loadout repo.
# There is no build and no test runner here: the assets and their index are
# the product, so "valid" means the index parses, every path it names exists,
# nothing is listed twice, and every doc link resolves.
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }

MARKETPLACE=.claude-plugin/marketplace.json

if [ ! -f "$MARKETPLACE" ]; then
  fail "$MARKETPLACE is missing"
else
  python3 - "$MARKETPLACE" <<'PY'
import json, os, sys

path = sys.argv[1]
fails = []

try:
    with open(path) as fh:
        data = json.load(fh)
except json.JSONDecodeError as exc:
    print(f"FAIL: {path} does not parse: {exc}", file=sys.stderr)
    raise SystemExit(1)

plugins = data.get("plugins")
if not isinstance(plugins, list) or not plugins:
    fails.append(f"{path} has no plugins array")
    plugins = []

ALLOWED_KINDS = {"url", "git-subdir"}
seen = {}

for i, plugin in enumerate(plugins):
    label = plugin.get("name") or f"entry {i}"
    for key in ("name", "description"):
        if not plugin.get(key):
            fails.append(f"{label}: missing or empty '{key}'")

    name = plugin.get("name")
    if name:
        if name in seen:
            fails.append(f"{name}: listed twice (entries {seen[name]} and {i})")
        else:
            seen[name] = i

    source = plugin.get("source")
    if source is None:
        fails.append(f"{label}: missing 'source'")
    elif isinstance(source, str):
        if not os.path.isdir(source):
            fails.append(f"{label}: local source '{source}' does not resolve")
    elif isinstance(source, dict):
        kind = source.get("source")
        if kind in ALLOWED_KINDS:
            if not source.get("url"):
                fails.append(f"{label}: source kind '{kind}' without a url")
        elif isinstance(kind, str) and kind.startswith("."):
            if not os.path.isdir(kind):
                fails.append(f"{label}: local source '{kind}' does not resolve")
        else:
            fails.append(f"{label}: source kind '{kind}' is not allowed")
    else:
        fails.append(f"{label}: 'source' is neither a string nor an object")

for line in fails:
    print(f"FAIL: {line}", file=sys.stderr)
raise SystemExit(1 if fails else 0)
PY
  [ $? -ne 0 ] && fails=$((fails + 1))
fi

# Frontmatter on shipped skills and agents.
for skill in skills/*/SKILL.md; do
  [ -e "$skill" ] || continue
  [ "$(head -n 1 "$skill")" = "---" ] || fail "$skill: no frontmatter on line 1"
  grep -q '^name:' "$skill" || fail "$skill: frontmatter has no 'name'"
  grep -q '^description:' "$skill" || fail "$skill: frontmatter has no 'description'"
done

for agent in agents/*.md; do
  [ -e "$agent" ] || continue
  [ "$(head -n 1 "$agent")" = "---" ] || fail "$agent: no frontmatter on line 1"
  grep -q '^name:' "$agent" || fail "$agent: frontmatter has no 'name'"
  grep -q '^description:' "$agent" || fail "$agent: frontmatter has no 'description'"
done

# Every integration directory must document itself.
for dir in integrations/*/; do
  [ -e "$dir" ] || continue
  [ -f "$dir/README.md" ] || fail "$dir: no README.md"
done

# Relative links in every root README must resolve.
# (R1: single pass — capture the loop's failures instead of running it twice.)
link_failures=$(for readme in README.md README-*.md; do
  [ -e "$readme" ] || continue
  grep -oE '\]\([^)#][^)]*\)' "$readme" \
    | sed -E 's/^\]\(//; s/\)$//; s/#.*$//' \
    | while read -r link; do
        case "$link" in
          http*|mailto:*|"") continue ;;
        esac
        [ -e "$link" ] || echo "FAIL: $readme: link '$link' does not resolve"
      done
done)

if [ -n "$link_failures" ]; then
  printf '%s\n' "$link_failures" >&2
  link_fails=$(printf '%s\n' "$link_failures" | grep -c '^FAIL:')
  fails=$((fails + link_fails))
fi

if [ "$fails" -gt 0 ]; then
  echo "$fails structural problem(s)" >&2
  exit 1
fi
echo "ok"
