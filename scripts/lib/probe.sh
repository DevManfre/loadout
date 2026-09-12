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

# `claude plugin list` costs around a second per call (a node CLI), and one
# menu open asks about every plugin more than once. The answer changes only
# when this process itself installs or removes a plugin, so those code paths
# call plugin_list_reset; nothing is ever written to disk.
_PLUGIN_LIST_LOADED=0
_PLUGIN_LIST=""
_plugin_list() {
  if [ "$_PLUGIN_LIST_LOADED" -eq 0 ]; then
    _PLUGIN_LIST=$(claude plugin list --json 2>/dev/null)
    _PLUGIN_LIST_LOADED=1
  fi
  printf '%s' "$_PLUGIN_LIST"
}
plugin_list_reset() { _PLUGIN_LIST_LOADED=0; _PLUGIN_LIST=""; }

# Install state is probed, never remembered: a state file would rot the first
# time somebody uninstalled something by hand. The probe column holds one or
# more alternatives, comma-separated; any one satisfied counts as installed.
entry_installed() {
  local token
  for token in $(_entry_probe_tokens "$1"); do
    _install_probe_ok "$token" && return 0
  done
  return 1
}

# Same question, blind to proxy: tokens — "is the thing on THIS machine",
# which is what update and remove need. A proxy answering from a container or
# the WSL host is nothing uv or the plugin CLI here can touch.
entry_installed_locally() {
  local token
  for token in $(_entry_probe_tokens "$1"); do
    case "$token" in proxy:*) continue ;; esac
    _install_probe_ok "$token" && return 0
  done
  return 1
}

_entry_probe_tokens() {
  local probe
  probe=$(manifest_field "$1" 6) || return 1
  printf '%s' "$probe" | tr ',' ' '
}

_install_probe_ok() {
  case "$1" in
    plugin:*) _plugin_list | grep -Fq "\"${1#plugin:}@" ;;
    bin:*)    have_cmd "${1#bin:}" ;;
    proxy:*)  _proxy_alive "${1#proxy:}" ;;
    *) return 1 ;;
  esac
}

# A live HTTP answer at the URL the named variable points at counts as
# installed: the process serves this machine from somewhere PATH cannot see —
# a container, or the Windows host under WSL. Any HTTP status counts as alive
# (an API-shaped proxy 404s a bare GET /); only a dead connection means
# absent. Cached per URL for this process: the menu asks about the same entry
# more than once per open, and a network probe costs up to 2 s each time.
_PROXY_ALIVE_URL=""
_PROXY_ALIVE_RC=1
_proxy_alive() {
  local var=$1 url
  url=${!var:-}
  [ -n "$url" ] || url=$(_proxy_url_from_settings "$var")
  [ -n "$url" ] || return 1
  have_cmd curl || return 1
  if [ "$_PROXY_ALIVE_URL" != "$url" ]; then
    curl -s -o /dev/null --max-time 2 "$url"
    _PROXY_ALIVE_RC=$?
    _PROXY_ALIVE_URL=$url
  fi
  [ "$_PROXY_ALIVE_RC" -eq 0 ]
}

# The variable usually lives in Claude Code's settings env, not in the shell
# profile — the proxy serves the agent, so the agent's config is where the URL
# is written down, and the interactive shell that launches the installer has
# no reason to have it exported. Project settings win over global; the live
# variable, checked above, wins over both. The extraction is a sed over one
# quoted key, not a JSON parse: enough for a flat "env" block, and jq is not a
# dependency this script is allowed to grow.
_proxy_url_from_settings() {
  local var=$1 f url files
  files=${LOADOUT_SETTINGS_FILES:-.claude/settings.local.json:.claude/settings.json:$HOME/.claude/settings.json}
  local IFS=:
  for f in $files; do
    [ -f "$f" ] || continue
    url=$(sed -n 's/.*"'"$var"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)
    [ -n "$url" ] && { printf '%s' "$url"; return 0; }
  done
  return 1
}

# The pin on disk for a plugin, the reported version for a binary, '-' when
# the entry is not installed, will not say, or is reachable only remotely —
# a remote process leaves no local pin to read.
entry_version() {
  local name=$1 token pin dir
  for token in $(_entry_probe_tokens "$name"); do
    _install_probe_ok "$token" || continue
    case "$token" in
      plugin:*)
        dir="$HOME/.claude/plugins/cache/$(plugin_marketplace "$name")/${token#plugin:}"
        pin=$(ls -1 "$dir" 2>/dev/null | head -1)
        printf '%s' "${pin:--}"; return 0 ;;
      bin:*)
        pin=$("${token#bin:}" --version 2>/dev/null | head -1 | tr -dc '0-9.v' )
        printf '%s' "${pin:--}"; return 0 ;;
    esac
  done
  printf '%s' '-'
}
