# shellcheck shell=bash
# The mutations, one handler per kind. Everything that changes the machine
# goes through run(), so --dry-run is a property of this file's callers rather
# than of each command.

INSTALLED=0
UPDATED=0
SKIPPED=0
PROBLEMS=0

# Set by cmd_install right after a menu selection is accepted with Enter: the
# menu already priced this exact set and the user consented to it there, so
# install_entry must not ask again for each member of that set. Every other
# path into install_entry (--only, --except, --yes, no TTY) leaves this 0 and
# keeps its own per-entry confirmation.
SELECTION_CONFIRMED=0

_ok()   { INSTALLED=$((INSTALLED + 1)); }
# Updates are counted apart from installs: one menu run now does both, and a
# summary that adds them together cannot say which of the two actually ran.
_ok_up() { UPDATED=$((UPDATED + 1)); }
_skip() { printf '   %sskip: %s%s\n' "$C_DIM" "$*" "$C_RESET"; SKIPPED=$((SKIPPED + 1)); }
_fail() { printf '   %sFAIL: %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; PROBLEMS=$((PROBLEMS + 1)); }

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

# The auto-fixable dependencies a selection is missing, each once.
selection_fixables() {
  local name
  for name in "$@"; do
    [ -n "$name" ] || continue
    entry_soft_blocks "$name"
  done | sort -u
}

# Install one dependency the installer knows how to provide (dep_autofix_cmd).
# Consent is per mutation: the menu priced the entries' context cost, not a
# change to the machine, so SELECTION_CONFIRMED deliberately does not cover
# this prompt and only --yes waives it. A decline or a failure is not fatal —
# the entries needing the token simply stay on their normal blocked path.
fix_dep() {
  local token=$1 cmd
  cmd=$(dep_autofix_cmd "$token") || return 1
  dep_present "$token" && return 0
  say "dependency: $token"
  note "why:  $(dep_field "$token" 5)"
  note "runs: $cmd"
  confirm "install it now?" || { _skip "declined; entries needing $token stay blocked"; return 1; }
  run sh -c "$cmd" || { _fail "auto-install of $token failed"; return 1; }
  if [ "${OPT_DRY_RUN:-0}" -eq 1 ]; then
    note "(dry run: nothing was installed, so dependent entries below still print as blocked)"
    return 0
  fi
  # The Astral script lands in ~/.local/bin, which this process may not have
  # on PATH yet; dependent installs need it now — the user's next shell picks
  # it up from their rc file instead.
  PATH="$HOME/.local/bin:$PATH"; export PATH
  dep_present "$token" || { _fail "$token is still missing after the install"; return 1; }
  note "installed; open a new shell to have it on PATH outside this run"
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

  if entry_installed_locally "$name"; then _skip "already installed"; return 0; fi
  if entry_installed "$name"; then
    _skip "already running remotely (a live proxy answered) — nothing to install here"
    return 0
  fi
  if [ "${SELECTION_CONFIRMED:-0}" -eq 1 ]; then
    :   # the menu priced this set and the user accepted it there
  elif ! confirm "install?"; then
    _skip "declined"; return 0
  fi

  if container_wanted "$name"; then install_container "$name"; return 0; fi

  case "$kind" in
    plugin)
      install_marketplace "$name"
      if run claude plugin install "$name@$(plugin_marketplace "$name")" \
           --scope "$OPT_SCOPE" --yes; then plugin_list_reset; _ok
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
# Whether this run should carry an entry as a container rather than as a
# package. The row in loadout.containers is the offer; Docker being here is
# what makes it possible; --container answers for a run with no TTY, and an
# interactive run is asked, once, with both commands already on screen.
container_wanted() {
  local name=$1
  container_field "$name" 2 >/dev/null 2>&1 || return 1
  have_cmd docker || return 1
  _in_list "$name" "${OPT_CONTAINER:-}" && return 0
  [ "${OPT_YES:-0}" -eq 1 ] && return 1
  [ -t 0 ] || return 1
  note "$name can run either way on this machine:"
  note "  package:   $(_python_installer 2>/dev/null || printf 'uv/pipx') tool install $(manifest_field "$name" 3)"
  note "  container: docker run --name $(container_field "$name" 2) $(container_field "$name" 4) $(container_field "$name" 3)"
  confirm "run it as a container?"
}

install_container() {
  local name=$1 ctr image
  ctr=$(container_field "$name" 2); image=$(container_field "$name" 3)
  run docker pull "$image" || { _fail "docker pull $image failed"; return 0; }
  # Unquoted on purpose: the run column is a list of flags, and quoting it
  # would hand docker one long argument instead of the flags it spells out.
  # shellcheck disable=SC2046,SC2086
  if run docker run --name "$ctr" $(container_field "$name" 4) "$image"; then
    docker_ps_reset; _ok
    _post_install_container "$name"
  else
    _fail "docker run $ctr failed"
  fi
}

_post_install_container() {
  case "$1" in
    headroom)
      note "point the agent at the container:"
      note "  export ANTHROPIC_BASE_URL=http://127.0.0.1:8787"
      note "telemetry is on by default upstream; HEADROOM_BEACON=off turns it off." ;;
  esac
}

# A container the spec cannot reproduce must not be recreated from the spec:
# the recreate would silently drop whatever is not written down. Mounts and
# hand-set env are the two ways that happens — so they are named, and the
# update stops. Failing closed costs a skipped update; failing open costs data.
_container_unreproducible() {
  local ctr=$1 name=$2 mounts img_env ctr_env extra line
  mounts=$(docker inspect "$ctr" --format '{{range .Mounts}}{{.Destination}} {{end}}' 2>/dev/null)
  [ -z "$(printf '%s' "$mounts" | tr -d '[:space:]')" ] || {
    printf 'mounts this row does not declare: %s' "$mounts"; return 0; }

  # Env the image itself sets is not configuration; env only the container
  # carries is, and the spec has to be the place it is written down.
  ctr_env=$(docker inspect "$ctr" --format '{{range .Config.Env}}{{println .}}' 2>/dev/null | sort)
  img_env=$(docker image inspect "$(docker inspect "$ctr" --format '{{.Image}}' 2>/dev/null)" \
            --format '{{range .Config.Env}}{{println .}}' 2>/dev/null | sort)
  extra=$(comm -23 <(printf '%s\n' "$ctr_env") <(printf '%s\n' "$img_env") | sed '/^$/d')
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case " $(container_field "$name" 4) " in
      *" $line "*) continue ;;
      *" ${line%%=*}="*) continue ;;
    esac
    printf 'environment this row does not declare: %s' "${line%%=*}"
    return 0
  done <<< "$extra"
  return 1
}

update_container() {
  local name=$1 ctr image why
  ctr=$(container_field "$name" 2); image=$(container_field "$name" 3)
  printf '   container: %s\n' "$ctr"
  printf '   image:     %s\n' "$image"
  printf '   running:   %s\n' "$(_local_image_digest "$ctr")"
  printf '   registry:  %s\n' "$(_registry_digest "$image")"
  if container_image_moved "$name"; then
    printf '   ! the update pulls that tag, removes the container and runs it again from this row\n'
  else
    printf '   ! the registry serves that same digest — a pull changes nothing, the recreate still restarts it\n'
  fi

  if why=$(_container_unreproducible "$ctr" "$name"); then
    note "$why"
    note "recreating from the catalog row would drop it; update this one by hand."
    _skip "not reproducible from loadout.containers"
    return 0
  fi

  if [ "${SELECTION_CONFIRMED:-0}" -ne 1 ]; then
    confirm "pull and recreate $ctr?" || { _skip "declined"; return 0; }
  fi
  run docker pull "$image" || { _fail "docker pull $image failed"; return 0; }
  run docker rm -f "$ctr" || { _fail "docker rm -f $ctr failed"; return 0; }
  # shellcheck disable=SC2046,SC2086
  if run docker run --name "$ctr" $(container_field "$name" 4) "$image"; then
    docker_ps_reset; _ok_up
  else
    _fail "docker run $ctr failed — the old container is gone, run the command above by hand"
  fi
}

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
      # A fresh copy must say its name: skips already print theirs, and an
      # asset installed in silence reads as "not carried". Dry run stays
      # quiet — run() already printed the cp and nothing actually landed.
      [ "${OPT_DRY_RUN:-0}" -eq 1 ] || note "installed $base -> $dest/$base"
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

# The catalog prices an entry at a specific pin, and an update moves off it.
# Three pins decide whether that is a good idea — what is installed, what
# upstream publishes now (entry_latest, '-' when the network cannot say), and
# what the catalog actually measured its price on — so all three are printed
# before anything asks. Nothing is invented: an unknown upstream says so.
#
# Split from pin_gate so the install menu can show the same report for a whole
# batch of updates behind a single prompt, instead of the report existing only
# inside a per-entry confirmation.
pin_report() {
  local name=$1 measured installed latest
  measured=$(manifest_field "$name" 8)
  installed=$(entry_version "$name")
  latest=$(entry_latest "$name")

  printf '   installed: %s\n' "$installed"
  if [ "$latest" = "-" ]; then
    printf '   upstream:  unknown from here — an update moves to whatever upstream publishes now\n'
  else
    printf '   upstream:  %s — where this update moves it\n' "$latest"
  fi
  printf '   measured:  %s — the catalog prices this entry at %s on that pin\n' \
    "$measured" "$(manifest_field "$name" 7)"
  if [ "$installed" != "$measured" ]; then
    printf '   ! you are already off the measured pin, so the catalog price does not describe what you have\n'
  fi
  if [ "$latest" != "$measured" ]; then
    printf '   ! the catalog has not measured the pin this update lands on\n'
  fi
}

pin_gate() {
  pin_report "$1"
  confirm "update anyway?"
}

update_entry() {
  local name=$1 kind source
  kind=$(manifest_field "$name" 2)
  source=$(manifest_field "$name" 3)

  say "$name"
  if ! entry_installed "$name"; then _skip "not installed"; return 0; fi
  if ! entry_installed_locally "$name"; then
    _skip "runs remotely (container or another host) — update it where it runs"
    return 0
  fi

  # A container is updated as a container: its own report, its own commands.
  if entry_is_container "$name"; then update_container "$name"; return 0; fi

  # The install menu prints the same pin report for the whole update set and
  # takes one answer for it; asking again here would be asking twice for the
  # consent already given, row by row, on screen.
  if [ "${SELECTION_CONFIRMED:-0}" -ne 1 ]; then
    pin_gate "$name" || { _skip "declined"; return 0; }
  fi

  case "$kind" in
    plugin)
      run claude plugin marketplace update "$(plugin_marketplace "$name")" \
        || _fail "marketplace update failed"
      if run claude plugin update "$name"; then plugin_list_reset; _ok_up
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
      _ok_up ;;
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
    if run cp -R "${src%/}" "$dest/"; then _record_asset "$base" "$src"; _ok_up
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
  if ! entry_installed_locally "$name"; then
    _skip "runs remotely (container or another host) — remove it where it runs"
    return 0
  fi
  confirm "uninstall $name?" || { _skip "declined"; return 0; }

  # A container entry removes as a container, whatever its manifest kind says:
  # the package was never installed here, the container was. The image is left
  # on disk — pulling it again is the expensive half, and `docker image rm` is
  # the user's call, not a side effect of removing one entry.
  if entry_is_container "$name"; then
    if run docker rm -f "$(container_field "$name" 2)"; then docker_ps_reset; _ok
    else _fail "docker rm -f $(container_field "$name" 2) failed"; fi
    return 0
  fi

  case "$kind" in
    plugin)
      if run claude plugin uninstall "$name"; then plugin_list_reset; _ok
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
