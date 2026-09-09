# shellcheck shell=bash
# The mutations, one handler per kind. Everything that changes the machine
# goes through run(), so --dry-run is a property of this file's callers rather
# than of each command.

INSTALLED=0
SKIPPED=0
PROBLEMS=0

_ok()   { INSTALLED=$((INSTALLED + 1)); }
_skip() { note "skip: $*"; SKIPPED=$((SKIPPED + 1)); }
_fail() { printf '   FAIL: %s\n' "$*" >&2; PROBLEMS=$((PROBLEMS + 1)); }

# A marketplace is an index, not an install: it costs no context, so it is
# added without asking.
install_marketplace() {
  local name=$1 source market repo
  source=$(manifest_field "$name" 3)
  case "$source" in *=*) ;; *) return 0 ;; esac
  market=${source%%=*}; repo=${source#*=}
  if claude plugin marketplace list 2>/dev/null | grep -q "$market"; then
    return 0
  fi
  run claude plugin marketplace add "$repo" || _fail "could not add marketplace $repo"
}

_python_installer() {
  if have_cmd uv; then printf 'uv'
  elif have_cmd pipx; then printf 'pipx'
  else printf ''
  fi
}

install_entry() {
  local name=$1 kind source token
  kind=$(manifest_field "$name" 2)
  source=$(manifest_field "$name" 3)

  say "$name"
  cost "$(manifest_field "$name" 7)"

  for token in $(entry_deps "$name" block); do
    printf '   [!] %s — cannot install here (missing: %s)\n' "$name" "$token"
    explain_dep "$token" "$name"
    SKIPPED=$((SKIPPED + 1))
    return 0
  done
  for token in $(entry_deps "$name" warn); do
    printf '   [~] installable, degraded (missing: %s)\n' "$token"
    explain_dep "$token" "$name"
  done

  if entry_installed "$name"; then _skip "already installed"; return 0; fi
  confirm "install?" || { _skip "declined"; return 0; }

  case "$kind" in
    plugin)
      install_marketplace "$name"
      if run claude plugin install "$name@$(plugin_marketplace "$name")" \
           --scope "$OPT_SCOPE" --yes; then _ok
      else _fail "claude plugin install $name failed"; fi ;;
    pypkg)
      # A failed package install must not fall through: _post_install_pypkg
      # would run graphify's own setup against a package that never landed,
      # and _ok would count the failure as an install.
      case "$(_python_installer)" in
        uv)   run uv tool install "$source" \
                || { _fail "uv tool install $source failed"; return 0; } ;;
        pipx) run pipx install "$source" \
                || { _fail "pipx install $source failed"; return 0; } ;;
        *)    _fail "no python installer on PATH"; return 0 ;;
      esac
      _post_install_pypkg "$name"
      _ok ;;
    *) _fail "unknown kind: $kind" ;;
  esac
}

# The two python entries each need one more thing after the package lands, and
# neither is a package-manager step.
_post_install_pypkg() {
  case "$1" in
    graphify)
      if [ "$OPT_SCOPE" = user ]; then run graphify install || _fail "graphify install failed"
      else run graphify install --project || _fail "graphify install --project failed"; fi
      run graphify claude install || _fail "graphify claude install failed" ;;
    headroom)
      note "start it, then point the agent at it:"
      note "  headroom proxy --port 8787"
      note "  export ANTHROPIC_BASE_URL=http://127.0.0.1:8787"
      note "telemetry is on by default upstream; HEADROOM_BEACON=off turns it off." ;;
  esac
}

# Loadout's own assets: a plain copy, no plugin index in between, and a
# recorded checksum so `update` can tell an upstream change from a local edit.
copy_own_assets() {
  local dest_root=$1 src base dest
  run mkdir -p "$(dirname "${LOADOUT_STATE:-$HOME/.claude/loadout/state}")"
  for src in skills/*/ agents/*.md workflows/*.md; do
    [ -e "$src" ] || continue
    case "$src" in */.gitkeep) continue ;; esac
    case "$src" in
      skills/*)    dest=$dest_root/skills ;;
      agents/*)    dest=$dest_root/agents ;;
      workflows/*) dest=$dest_root/workflows ;;
    esac
    base=$(basename "${src%/}")
    if [ -e "$dest/$base" ]; then _skip "$base already installed in $dest"; continue; fi
    run mkdir -p "$dest" || { _fail "could not create $dest"; continue; }
    if run cp -R "${src%/}" "$dest/"; then
      _record_asset "$base" "$src"
      _ok
    else
      _fail "could not copy $src into $dest"
    fi
  done
}

_record_asset() {
  local name=$1 src=$2 state=${LOADOUT_STATE:-$HOME/.claude/loadout/state}
  [ "${OPT_DRY_RUN:-0}" -eq 1 ] && return 0
  mkdir -p "$(dirname "$state")"
  grep -v "^$name·" "$state" 2>/dev/null > "$state.tmp" || :
  printf '%s·%s\n' "$name" "$(_asset_sum "$src")" >> "$state.tmp"
  mv "$state.tmp" "$state"
}

_asset_sum() { find "${1%/}" -type f -exec cat {} + 2>/dev/null | sha256sum | cut -d' ' -f1; }

# What the upstream would give us if we updated now. LOADOUT_FAKE_AVAILABLE is
# a test seam; nothing else sets it.
available_version() {
  local name=$1 kind
  [ -z "${LOADOUT_FAKE_AVAILABLE:-}" ] || { printf '%s' "$LOADOUT_FAKE_AVAILABLE"; return 0; }
  kind=$(manifest_field "$name" 2)
  case "$kind" in
    plugin)
      claude plugin marketplace list --json 2>/dev/null |
        grep -o "\"$name[^\"]*\"" | head -1 | tr -d '"' ;;
    pypkg) printf '%s' "unknown" ;;
  esac
}

# The catalog measures a cost against a pin. Moving to a pin it never measured
# means the price the user agreed to no longer describes what they are getting,
# and caveman is the documented case: ~780 tokens on one pin, ~2,480 on the
# next. So say it, and ask.
pin_gate() {
  local name=$1 available=$2 measured
  measured=$(manifest_field "$name" 8)
  [ -n "$available" ] || return 0
  [ "$available" != "unknown" ] || return 0
  [ "$available" != "$measured" ] || return 0

  printf '   installed: %s (measured: %s)\n' "$(entry_version "$name")" "$(manifest_field "$name" 7)"
  printf '   available: %s  (NOT measured in this catalog)\n' "$available"
  printf '   ! the catalog price does not describe the version you are about to get\n'
  confirm "update anyway?"
}

update_entry() {
  local name=$1 kind source available
  kind=$(manifest_field "$name" 2)
  source=$(manifest_field "$name" 3)

  say "$name"
  if ! entry_installed "$name"; then _skip "not installed"; return 0; fi

  available=$(available_version "$name")
  pin_gate "$name" "$available" || { _skip "declined"; return 0; }

  case "$kind" in
    plugin)
      run claude plugin marketplace update "$(plugin_marketplace "$name")" \
        || _fail "marketplace update failed"
      if run claude plugin update "$name"; then _ok
      else _fail "claude plugin update $name failed"; fi
      note "a plugin update needs a restart of the agent to take effect" ;;
    pypkg)
      case "$(_python_installer)" in
        uv)   run uv tool upgrade "${source%%\[*}" || _fail "uv tool upgrade failed" ;;
        pipx) run pipx upgrade "${source%%\[*}" || _fail "pipx upgrade failed" ;;
        *)    _fail "no python installer on PATH"; return 0 ;;
      esac
      _ok ;;
  esac
}

# A copied asset has no pin. What matters instead is whether the copy on disk
# is still the one this repo wrote, because clobbering somebody's edit is the
# one unrecoverable thing an updater can do.
update_own_assets() {
  local dest_root=$1 state=${LOADOUT_STATE:-$HOME/.claude/loadout/state}
  local src base dest recorded current
  for src in skills/*/ agents/*.md workflows/*.md; do
    [ -e "$src" ] || continue
    case "$src" in */.gitkeep) continue ;; esac
    case "$src" in
      skills/*)    dest=$dest_root/skills ;;
      agents/*)    dest=$dest_root/agents ;;
      workflows/*) dest=$dest_root/workflows ;;
    esac
    base=$(basename "${src%/}")
    [ -e "$dest/$base" ] || { _skip "$base not installed"; continue; }

    recorded=$(grep "^$base·" "$state" 2>/dev/null | awk -F'·' '{print $2}')
    current=$(_asset_sum "$dest/$base")
    if [ -n "$recorded" ] && [ "$recorded" != "$current" ]; then
      say "$base"
      note "modified locally: $dest/$base"
      note "leaving it alone. To take the repo's version: cp -R '$src' '$dest/' after saving yours."
      _skip "locally modified"
      continue
    fi
    [ "$(_asset_sum "$src")" != "$current" ] || { _skip "$base already current"; continue; }
    say "$base"
    if run cp -R "${src%/}" "$dest/"; then _record_asset "$base" "$src"; _ok
    else _fail "could not update $base"; fi
  done
}
