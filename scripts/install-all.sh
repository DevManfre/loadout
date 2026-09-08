#!/usr/bin/env bash
# One-block install of everything loadout carries.
#
# There is deliberately no single command for this: the plugin CLI installs one
# asset at a time, and third-party binaries (graphify) install themselves
# because a plugin cannot run a package manager. This script is the seam that
# chains both paths — it does not hide the cost. Every step prints its
# always-on token price first and, unless --yes, asks before paying it.
#
# Idempotent: an already-added marketplace, an already-installed plugin and an
# already-installed graphify are reported and skipped, so re-running is safe.
#
# Usage: scripts/install-all.sh [--scope user|project|local] [--yes]
#                              [--dry-run] [--skip-graphify]
set -uo pipefail
cd "$(dirname "$0")/.."

MARKETPLACE_NAME=loadout
MARKETPLACE_SOURCE=DevManfre/loadout

scope=user
assume_yes=0
dry_run=0
skip_graphify=0

while [ $# -gt 0 ]; do
  case "$1" in
    --scope)
      [ $# -ge 2 ] || { echo "--scope needs a value (user, project or local)" >&2; exit 2; }
      scope=$2
      shift 2
      ;;
    --scope=*) scope=${1#*=}; shift ;;
    -y|--yes) assume_yes=1; shift ;;
    -n|--dry-run) dry_run=1; shift ;;
    --skip-graphify) skip_graphify=1; shift ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$scope" in
  user|project|local) ;;
  *) echo "--scope must be user, project or local (got '$scope')" >&2; exit 2 ;;
esac

skipped=0
installed=0
problems=0

say()  { printf '\n== %s\n' "$*"; }
cost() { printf '   cost: %s\n' "$*"; }
skip() { printf '   skip: %s\n' "$*"; skipped=$((skipped + 1)); }
fail() { printf '   FAIL: %s\n' "$*" >&2; problems=$((problems + 1)); }

# Ask before each paid step. Non-interactive without --yes is a hard stop:
# silently installing an always-on context cost is exactly what this repo is
# against.
confirm() {
  [ "$assume_yes" -eq 1 ] && return 0
  if [ ! -t 0 ]; then
    fail "no TTY to confirm on; re-run with --yes to accept the printed costs"
    return 1
  fi
  printf '   install? [y/N] '
  read -r reply
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) skip "declined"; return 1 ;; esac
}

run() {
  if [ "$dry_run" -eq 1 ]; then
    printf '   would run: %s\n' "$*"
    return 0
  fi
  "$@"
}

if ! command -v claude >/dev/null 2>&1; then
  echo "FAIL: the 'claude' CLI is not on PATH; nothing to install into" >&2
  exit 1
fi

say "marketplace $MARKETPLACE_NAME"
cost "none — an index, not an install"
if claude plugin marketplace list 2>/dev/null | grep -Eq "^[[:space:]]*[^[:alnum:]]*[[:space:]]*${MARKETPLACE_NAME}$"; then
  skip "already configured"
else
  run claude plugin marketplace add "$MARKETPLACE_SOURCE" || fail "could not add $MARKETPLACE_SOURCE"
fi

# Plugin entries, in catalog order. Keep in sync with .claude-plugin/marketplace.json.
install_plugin() {
  local name=$1 price=$2 installed_json
  say "$name@$MARKETPLACE_NAME"
  cost "$price"

  installed_json=$(claude plugin list --json 2>/dev/null)
  if printf '%s' "$installed_json" | grep -Fq "\"$name@$MARKETPLACE_NAME\""; then
    skip "already installed"
    return 0
  fi
  # Same asset from another marketplace: installing a second copy duplicates
  # its always-on cost, so leave the existing one alone.
  if printf '%s' "$installed_json" | grep -Eq "\"id\": \"$name@[^\"]+\""; then
    skip "'$name' is already installed from another marketplace"
    return 0
  fi

  confirm || return 0
  if run claude plugin install "$name@$MARKETPLACE_NAME" --scope "$scope" --yes; then
    installed=$((installed + 1))
  else
    fail "claude plugin install $name@$MARKETPLACE_NAME failed"
  fi
}

install_plugin loadout     "~0 tokens — loadout's own skills and sub-agents; the entry is empty for now"
install_plugin superpowers "~800 tokens per session start, /clear and compaction"

# graphify: a binary plus its own installers, so it cannot come through the
# plugin index. Two installs, on purpose: 'graphify install' gives the
# /graphify skill, 'graphify claude install' adds the always-on CLAUDE.md rules.
if [ "$skip_graphify" -eq 1 ]; then
  say "graphify"
  skip "--skip-graphify"
else
  say "graphify (package manager, not a plugin)"
  cost "~340 tokens per session with the always-on layer, ~145 without it, plus ~48-105 per read or grep while a graph exists"
  if command -v graphify >/dev/null 2>&1; then
    skip "already on PATH ($(command -v graphify)) — update it with 'uv tool upgrade graphifyy' or 'pipx upgrade graphifyy'"
  elif ! confirm; then
    :
  else
    # uv first: the skill resolves its Python runtime through an isolated
    # environment, which is why 'pip install' is the wrong tool here.
    if command -v uv >/dev/null 2>&1; then
      run uv tool install graphifyy || fail "uv tool install graphifyy failed"
    elif command -v pipx >/dev/null 2>&1; then
      run pipx install graphifyy || fail "pipx install graphifyy failed"
    else
      fail "neither uv nor pipx is on PATH; install one, then re-run (avoid 'pip install' — see integrations/graphify/README.md)"
    fi
    if [ "$problems" -eq 0 ]; then
      if [ "$scope" = project ]; then
        run graphify install --project || fail "graphify install --project failed"
      else
        run graphify install || fail "graphify install failed"
      fi
      run graphify claude install || fail "graphify claude install failed"
      installed=$((installed + 1))
    fi
  fi
fi

printf '\n== done: %d installed, %d skipped, %d failed\n' "$installed" "$skipped" "$problems"
if [ "$dry_run" -eq 1 ]; then
  echo "   (dry run — nothing was changed)"
fi
echo "   too heavy in practice? '/plugin disable <name>' drops it from context without uninstalling."
[ "$problems" -gt 0 ] && exit 1
exit 0
