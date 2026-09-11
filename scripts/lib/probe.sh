# shellcheck shell=bash
# Answering "is this present on this machine". Read-only: nothing here
# installs, starts or configures anything.

platform_id() {
  if [ -n "${LOADOUT_FAKE_PLATFORM:-}" ]; then
    printf '%s' "$LOADOUT_FAKE_PLATFORM"
    return 0
  fi
  printf '%s/%s' "$(uname -s)" "$(uname -m)"
}

# 0 when the token is relevant on this platform.
dep_applies() {
  local when
  when=$(dep_field "$1" 4) || return 0
  case "$when" in
    platform:*) [ "${when#platform:}" = "$(platform_id)" ] ;;
    *) return 0 ;;
  esac
}

# One place asks whether a command exists, so one seam can lie about it.
have_cmd() {
  case ",${LOADOUT_FAKE_ABSENT:-}," in *",$1,"*) return 1 ;; esac
  command -v "$1" >/dev/null 2>&1
}

# 0 when the token is satisfied.
dep_present() {
  local probe var candidate
  probe=$(dep_field "$1" 3) || return 0
  case "$probe" in
    cmd:*) have_cmd "${probe#cmd:}" ;;
    anycmd:*)
      for candidate in $(printf '%s' "${probe#anycmd:}" | tr ',' ' '); do
        have_cmd "$candidate" && return 0
      done
      return 1
      ;;
    env:*) var=${probe#env:}; [ -n "${!var:-}" ] ;;
    *) return 0 ;;
  esac
}

# The dependencies the installer can install for itself, and the exact
# command it would run. The arm is the authority: a token is auto-fixable
# exactly when it has one. Kept as code rather than as a loadout.deps column
# because that file is '|'-delimited and this command contains a pipe.
dep_autofix_cmd() {
  case "$1" in
    uv/pipx) printf 'curl -LsSf https://astral.sh/uv/install.sh | sh' ;;
    *) return 1 ;;
  esac
}

# Blocking tokens the installer cannot fix; these keep an entry out of the
# selection entirely.
entry_hard_blocks() {
  local token
  for token in $(entry_deps "$1" block); do
    dep_autofix_cmd "$token" >/dev/null || printf '%s\n' "$token"
  done
}

# Blocking tokens the installer can fix itself, with consent, at install time.
entry_soft_blocks() {
  local token
  for token in $(entry_deps "$1" block); do
    dep_autofix_cmd "$token" >/dev/null && printf '%s\n' "$token"
  done
}

# Applicable, missing tokens of one severity, one per line.
entry_deps() {
  local name=$1 severity=$2 token needs
  needs=$(manifest_field "$name" 5) || return 1
  for token in $(printf '%s' "$needs" | tr ',' ' '); do
    [ "$(dep_field "$token" 2)" = "$severity" ] || continue
    dep_applies "$token" || continue
    dep_present "$token" || printf '%s\n' "$token"
  done
}

# The marketplace an entry's plugin comes from. Column 3 is either a plain
# marketplace name or `name=owner/repo` when the marketplace must be added.
plugin_marketplace() {
  local source
  source=$(manifest_field "$1" 3) || return 1
  printf '%s' "${source%%=*}"
}

# Install state is probed, never remembered: a state file would rot the first
# time somebody uninstalled something by hand.
entry_installed() {
  local probe
  probe=$(manifest_field "$1" 6) || return 1
  case "$probe" in
    plugin:*)
      claude plugin list --json 2>/dev/null | grep -Fq "\"${probe#plugin:}@" ;;
    bin:*)
      have_cmd "${probe#bin:}" ;;
    *) return 1 ;;
  esac
}

# The pin on disk for a plugin, the reported version for a binary, '-' when
# the entry is not installed or will not say.
entry_version() {
  local name=$1 probe pin dir
  probe=$(manifest_field "$name" 6) || return 1
  entry_installed "$name" || { printf '%s' '-'; return 0; }
  case "$probe" in
    plugin:*)
      dir="$HOME/.claude/plugins/cache/$(plugin_marketplace "$name")/${probe#plugin:}"
      pin=$(ls -1 "$dir" 2>/dev/null | head -1)
      printf '%s' "${pin:--}" ;;
    bin:*)
      pin=$("${probe#bin:}" --version 2>/dev/null | head -1 | tr -dc '0-9.v' )
      printf '%s' "${pin:--}" ;;
  esac
}
