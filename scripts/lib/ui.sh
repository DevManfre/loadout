# shellcheck shell=bash
# Everything the user sees, and the one wrapper that performs mutations.

say()  { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }
cost() { printf '   cost: %s\n' "$*"; }

# The single choke point for anything that changes the machine. --dry-run
# prints instead of running, which is what makes "dry run mutates nothing"
# a property of one function rather than of every call site.
run() {
  if [ "${OPT_DRY_RUN:-0}" -eq 1 ]; then
    printf '   run: %s\n' "$*"
    return 0
  fi
  "$@"
}

# What is missing, why this entry needs it, how to fix it, what skipping costs.
# No entry in this catalog depends on another entry, so walking away from one
# never breaks a second — that is why the 'or:' line can promise it.
explain_dep() {
  local token=$1 entry=$2
  printf '    why:  %s\n' "$(dep_field "$token" 5)"
  printf '    fix:  %s\n' "$(dep_field "$token" 6)"
  printf '    or:   skip %s — no other entry in the loadout depends on it\n' "$entry"
  printf '    docs: %s\n' "$(dep_field "$token" 7)"
}

confirm() {
  [ "${OPT_YES:-0}" -eq 1 ] && return 0
  if [ ! -t 0 ]; then
    printf '   FAIL: no TTY to confirm on; re-run with --yes to accept the printed costs\n' >&2
    return 1
  fi
  printf '   %s [y/N] ' "${1:-proceed?}"
  local reply
  read -r reply
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}
