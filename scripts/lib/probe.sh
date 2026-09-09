# shellcheck shell=bash
# Answering "is this present on this machine". Read-only: nothing here
# installs, starts or configures anything.

platform_id() { printf '%s/%s' "$(uname -s)" "$(uname -m)"; }

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
