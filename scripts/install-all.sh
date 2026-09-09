#!/usr/bin/env bash
# One-block install of everything loadout carries.
#
# Loadout is a guide, not a plugin: it vendors nothing and each asset comes
# from its own upstream source. That means three different install paths —
# the Claude Code plugin CLI for plugin entries, a package manager for
# third-party binaries a plugin cannot ship (graphify), and a plain copy for
# loadout's own skills and agents. This script is the seam that chains all
# three, and it does not hide the cost: every step prints its always-on token
# price first and, unless --yes, asks before paying it.
#
# Idempotent: an already-configured marketplace, an already-installed plugin,
# binary or asset is reported and skipped, so re-running is safe.
#
# Usage: scripts/install-all.sh [--scope user|project|local] [--yes]
#                               [--dry-run] [--skip-graphify]
set -uo pipefail

ORIGIN_DIR=$PWD
cd "$(dirname "$0")/.."

OFFICIAL_NAME=claude-plugins-official
OFFICIAL_SOURCE=anthropics/claude-plugins-official

# caveman is not in the official directory; it publishes its own marketplace.
CAVEMAN_NAME=caveman
CAVEMAN_SOURCE=JuliusBrussee/caveman

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
    -h|--help)
      awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
      exit 0
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$scope" in
  user|project|local) ;;
  *) echo "--scope must be user, project or local (got '$scope')" >&2; exit 2 ;;
esac

# Where loadout's own assets land. Plugin entries use the CLI's own --scope;
# a plain copy needs the directory spelled out. project and local both mean
# "the repo you ran this from", which is not this repo.
if [ "$scope" = user ]; then
  ASSET_ROOT=$HOME/.claude
else
  ASSET_ROOT=$ORIGIN_DIR/.claude
fi

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
  case "$reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) skip "declined"; return 1 ;;
  esac
}

run() {
  if [ "$dry_run" -eq 1 ]; then
    printf '   run: %s\n' "$*"
    return 0
  fi
  "$@"
}

if ! command -v claude >/dev/null 2>&1; then
  echo "FAIL: the 'claude' CLI is not on PATH; there is nothing to install into" >&2
  exit 1
fi

# --- Plugin entries -------------------------------------------------------
# Loadout runs no marketplace of its own. Plugin entries come from Anthropic's
# official directory where the upstream publishes there, and from the upstream's
# own marketplace where it does not. Either way `claude plugin install` pins a
# commit — so what you get is a fixed revision, not a moving HEAD.

add_marketplace() {
  local name=$1 source=$2

  say "marketplace $name"
  cost "none — an index, not an install"
  if claude plugin marketplace list 2>/dev/null | grep -Eq "^[[:space:]]*[^[:alnum:]]*[[:space:]]*${name}$"; then
    skip "already configured"
    return 0
  fi
  run claude plugin marketplace add "$source" || fail "could not add $source"
}

add_marketplace "$OFFICIAL_NAME" "$OFFICIAL_SOURCE"
add_marketplace "$CAVEMAN_NAME" "$CAVEMAN_SOURCE"

# Keep in sync with the catalog in README.md.
install_plugin() {
  local name=$1 marketplace=$2 price=$3 installed_json

  say "$name@$marketplace"
  cost "$price"

  installed_json=$(claude plugin list --json 2>/dev/null)
  if printf '%s' "$installed_json" | grep -Fq "\"$name@$marketplace\""; then
    skip "already installed"
    return 0
  fi
  # Same asset from another marketplace: installing a second copy duplicates
  # the always-on cost, so leave the existing one alone.
  if printf '%s' "$installed_json" | grep -Eq "\"id\": \"$name@[^\"]+\""; then
    skip "'$name' is already installed from another marketplace"
    return 0
  fi

  confirm || return 0
  if run claude plugin install "$name@$marketplace" --scope "$scope" --yes; then
    installed=$((installed + 1))
  else
    fail "claude plugin install $name@$marketplace failed"
  fi
}

install_plugin superpowers "$OFFICIAL_NAME" \
  "~800 tokens at every session start, /clear and compaction (SessionStart hook)"

install_plugin caveman "$CAVEMAN_NAME" \
  "~2,480 tokens at every session start, /clear and compaction, plus ~60 on every user prompt (two hooks)"

# --- Third-party binaries -------------------------------------------------
# graphify is a Python package, not a plugin: a plugin cannot run a package
# manager, so this is the one entry that installs itself.

if [ "$skip_graphify" -eq 1 ]; then
  say "graphify"
  skip "--skip-graphify"
else
  say "graphify"
  cost "~340 tokens per session, plus ~48-105 per read or grep while a graph exists"
  if command -v graphify >/dev/null 2>&1; then
    skip "already on PATH ($(command -v graphify)) — update with 'uv tool upgrade graphifyy' or 'pipx upgrade graphifyy'"
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
      fail "neither uv nor pipx is on PATH; install one and re-run (avoid 'pip install' — see integrations/graphify/README.md)"
    fi

    if [ "$problems" -eq 0 ]; then
      if [ "$scope" = user ]; then
        run graphify install || fail "graphify install failed"
      else
        run graphify install --project || fail "graphify install --project failed"
      fi
      run graphify claude install || fail "graphify claude install failed"
      installed=$((installed + 1))
    fi
  fi
fi

# --- Loadout's own assets -------------------------------------------------
# A plain copy into $ASSET_ROOT. No plugin index sits in between, so what
# lands on disk is exactly what is in this repo.

copy_assets() {
  local kind=$1 src=$2 dest=$3 base found=0

  for base in $src; do
    [ -e "$base" ] || continue
    case "$base" in */.gitkeep) continue ;; esac
    found=1
    if [ -e "$dest/$(basename "$base")" ]; then
      skip "$kind $(basename "$base") already installed in $dest"
      continue
    fi
    confirm || continue
    run mkdir -p "$dest" || { fail "could not create $dest"; continue; }
    if run cp -R "$base" "$dest/"; then
      installed=$((installed + 1))
    else
      fail "could not copy $base into $dest"
    fi
  done

  [ "$found" -eq 1 ] || return 1
  return 0
}

say "loadout's own skills"
cost "one skill description each in the skill index; bodies load only when invoked"
copy_assets skill 'skills/*/' "$ASSET_ROOT/skills" || skip "none shipped yet"

say "loadout's own sub-agents"
cost "one description each in the agent index"
copy_assets agent 'agents/*.md' "$ASSET_ROOT/agents" || skip "none shipped yet"

say "loadout's own workflows"
cost "none until a workflow is run"
copy_assets workflow 'workflows/*.md' "$ASSET_ROOT/workflows" || skip "none shipped yet"

printf '\n== done: %d installed, %d skipped, %d failed\n' "$installed" "$skipped" "$problems"
if [ "$dry_run" -eq 1 ]; then
  echo "   (dry run — nothing was changed)"
fi
echo "   too heavy in practice? '/plugin disable <name>' drops it from context without uninstalling."

[ "$problems" -gt 0 ] && exit 1
exit 0
