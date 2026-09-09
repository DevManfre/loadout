# shellcheck shell=bash
# The mutations, one handler per kind. Everything that changes the machine
# goes through run(), so --dry-run is a property of this file's callers rather
# than of each command.

INSTALLED=0
SKIPPED=0
PROBLEMS=0

# Set by cmd_install right after a menu selection is accepted with Enter: the
# menu already priced this exact set and the user consented to it there, so
# install_entry must not ask again for each member of that set. Every other
# path into install_entry (--only, --except, --yes, no TTY) leaves this 0 and
# keeps its own per-entry confirmation.
SELECTION_CONFIRMED=0

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
  # An unanchored, unescaped substring match here would treat $market as a
  # regex and match any line that merely mentions it (e.g. another
  # marketplace's repo path containing the same word), skipping the add and
  # leaving the plugin install with nothing to install from. --json plus an
  # exact, literal key match is the same technique entry_installed already
  # uses for plugins.
  if claude plugin marketplace list --json 2>/dev/null | grep -Fq "\"name\": \"$market\""; then
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
  if [ "${SELECTION_CONFIRMED:-0}" -eq 1 ]; then
    :   # the menu priced this set and the user accepted it there
  elif ! confirm "install?"; then
    _skip "declined"; return 0
  fi

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

# The catalog prices an entry at a specific pin. An update moves to whatever
# upstream publishes now, and nothing available locally says what that will be:
# `claude plugin marketplace list --json` carries no version field, and a
# package index is not consulted until the upgrade runs. So the gate reports
# what IS known — the pin on disk, and the pin the catalog measured, with its
# price — and asks. Inventing a target version, or waiving the gate when we
# cannot find one, both defeat the promise this gate exists to keep.
pin_gate() {
  local name=$1 measured installed
  measured=$(manifest_field "$name" 8)
  installed=$(entry_version "$name")

  printf '   installed: %s\n' "$installed"
  printf '   measured:  %s — the catalog prices this entry at %s on that pin\n' \
    "$measured" "$(manifest_field "$name" 7)"
  if [ "$installed" != "$measured" ]; then
    printf '   ! you are already off the measured pin, so the catalog price does not describe what you have\n'
  fi
  printf '   ! an update moves to whatever upstream publishes now, which this catalog has not measured\n'
  confirm "update anyway?"
}

update_entry() {
  local name=$1 kind source
  kind=$(manifest_field "$name" 2)
  source=$(manifest_field "$name" 3)

  say "$name"
  if ! entry_installed "$name"; then _skip "not installed"; return 0; fi

  pin_gate "$name" || { _skip "declined"; return 0; }

  case "$kind" in
    plugin)
      run claude plugin marketplace update "$(plugin_marketplace "$name")" \
        || _fail "marketplace update failed"
      if run claude plugin update "$name"; then _ok
      else _fail "claude plugin update $name failed"; fi
      note "a plugin update needs a restart of the agent to take effect" ;;
    pypkg)
      case "$(_python_installer)" in
        uv)   run uv tool upgrade "${source%%\[*}" \
                || { _fail "uv tool upgrade failed"; return 0; } ;;
        pipx) run pipx upgrade "${source%%\[*}" \
                || { _fail "pipx upgrade failed"; return 0; } ;;
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
  local src base dest recorded current upstream
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

    recorded=$(awk -F'·' -v n="$base" '$1 == n { print $2 }' "$state" 2>/dev/null)
    current=$(_asset_sum "$dest/$base")
    upstream=$(_asset_sum "${src%/}")

    [ "$current" != "$upstream" ] || { _skip "$base already current"; continue; }

    # Update only what we can prove we wrote. A checksum that does not match —
    # or no record at all, because the state file was lost or the asset predates
    # it — means the copy on disk is not provably ours, and it is not ours to
    # overwrite. Failing closed costs a skipped update; failing open costs the
    # user's edits.
    if [ -z "$recorded" ] || [ "$recorded" != "$current" ]; then
      say "$base"
      if [ -z "$recorded" ]; then
        note "not recorded as installed by loadout: $dest/$base"
      else
        note "modified locally: $dest/$base"
      fi
      note "leaving it alone. To take the repo's version: cp -R '$src' '$dest/' after saving yours."
      _skip "not provably ours"
      continue
    fi

    say "$base"
    if run cp -R "${src%/}" "$dest/"; then _record_asset "$base" "$src"; _ok
    else _fail "could not update $base"; fi
  done
}

remove_entry() {
  local name=$1 kind source
  kind=$(manifest_field "$name" 2)
  source=$(manifest_field "$name" 3)

  say "$name"
  note "uninstalling drops it from disk; '/plugin disable $name' only drops it from context"
  if ! entry_installed "$name"; then _skip "not installed"; return 0; fi
  confirm "uninstall $name?" || { _skip "declined"; return 0; }

  case "$kind" in
    plugin)
      if run claude plugin uninstall "$name"; then _ok
      else _fail "claude plugin uninstall $name failed"; fi ;;
    pypkg)
      # Same shape as install_entry and update_entry: a failed command must not
      # fall through to _ok, or the summary counts one action as both failed
      # and done.
      case "$(_python_installer)" in
        uv)   run uv tool uninstall "${source%%\[*}" \
                || { _fail "uv tool uninstall failed"; return 0; } ;;
        pipx) run pipx uninstall "${source%%\[*}" \
                || { _fail "pipx uninstall failed"; return 0; } ;;
        *)    _fail "no python installer on PATH"; return 0 ;;
      esac
      _ok ;;
  esac
}
