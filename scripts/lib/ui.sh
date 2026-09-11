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
  local token=$1 entry=$2 auto
  printf '    why:  %s\n' "$(dep_field "$token" 5)"
  printf '    fix:  %s\n' "$(dep_field "$token" 6)"
  if auto=$(dep_autofix_cmd "$token"); then
    printf '    auto: the installer can run this for you, asking first: %s\n' "$auto"
  fi
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

_in_list() {
  case ",$2," in *",$1,"*) return 0 ;; esac
  return 1
}

# The set the menu opens with, and the set the flags produce on their own.
# Both paths run through here, so a --only run and a menu session that toggled
# the same entries cannot disagree.
resolve_selection() {
  local name
  for name in $(manifest_names); do
    [ -z "${OPT_ONLY:-}" ] || { _in_list "$name" "$OPT_ONLY" || continue; }
    [ -z "${OPT_EXCEPT:-}" ] || { _in_list "$name" "$OPT_EXCEPT" && continue; }
    [ -n "${OPT_ONLY:-}" ] || manifest_in_preset "$name" "${OPT_PRESET:-full}" || continue
    # A block the installer can fix itself (dep_autofix_cmd) does not exclude
    # the entry: cmd_install offers the fix, behind its own prompt, before
    # installing. Only unfixable blocks take an entry out of the selection.
    [ -z "$(entry_hard_blocks "$name")" ] || continue
    entry_installed "$name" && continue
    printf '%s\n' "$name"
  done
}

selection_total() {
  local name per_session="" per_call=""
  for name in "$@"; do
    per_session="$per_session $(manifest_field "$name" 7)"
    case "$(manifest_field "$name" 7)" in *toolcall*) per_call=" plus a per tool call charge" ;; esac
  done
  printf 'selected %d · always-on:%s%s\n' "$#" "$per_session" "$per_call"
}

# Row number to entry name, using menu_select's `rows` array. Validation happens
# before any arithmetic: $(( x - 1 )) on a non-numeric string aborts under set -u.
_menu_row() {
  local n=$1
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  [ "$n" -ge 1 ] || return 1
  [ "$n" -le "${#rows[@]}" ] || return 1
  printf '%s' "${rows[$((n - 1))]}"
}

# A numbered toggle list, redrawn after every keystroke line. No raw mode, no
# cursor movement: this has to work over ssh, in WSL and under a pipe.
menu_select() {
  local -a all=("$@") chosen=() rows=()
  local i name reply idx token soft status
  for name in "${all[@]}"; do chosen+=("$name"); done

  # Blocked entries are shown but cannot be chosen; that is the whole point of
  # showing them. Only unfixable blocks land here — an entry whose blocks the
  # installer can fix itself is selectable and says so on its row.
  local -a blocked=()
  for name in $(manifest_names); do
    [ -z "$(entry_hard_blocks "$name")" ] || blocked+=("$name")
  done

  while :; do
    # One array, in display order: selectable rows first, blocked rows after.
    # Built with explicit appends because "${arr[@]:-}" on an empty array
    # expands to a single empty argument, which would shift every row number.
    rows=()
    for name in "${all[@]:-}"; do [ -n "$name" ] && rows+=("$name"); done
    for name in "${blocked[@]:-}"; do [ -n "$name" ] && rows+=("$name"); done

    printf '\n  #  entry        cost/session           status\n' >&2
    i=0
    for name in "${all[@]}"; do
      i=$((i + 1))
      soft=$(entry_soft_blocks "$name" | tr '\n' ' ' | sed 's/ *$//')
      if [ -n "$soft" ]; then status="needs $soft (auto-install, asks first)"; else status=ready; fi
      if printf '%s\n' "${chosen[@]}" | grep -qx "$name"; then
        printf '  %d [x] %-12s %-22s %s\n' "$i" "$name" "$(manifest_field "$name" 7)" "$status" >&2
      else
        printf '  %d [ ] %-12s %-22s %s\n' "$i" "$name" "$(manifest_field "$name" 7)" "$status" >&2
      fi
    done
    # Blocked rows are numbered too, continuing after the selectable ones: the
    # prompt offers `d <n>` for them, and an unnumbered row is an instruction
    # the user cannot follow.
    for name in "${blocked[@]:-}"; do
      [ -n "$name" ] || continue
      i=$((i + 1))
      printf '  %d [!] %-12s %-22s BLOCKED: needs %s\n' \
        "$i" "$name" "$(manifest_field "$name" 7)" \
        "$(entry_deps "$name" block | tr '\n' ' ' | sed 's/ *$//')" >&2
    done
    printf '\ntoggle 1-%d · a=all · n=none · d <n>=why · Enter=install %d · q=quit\n> ' \
      "${#rows[@]}" "${#chosen[@]}" >&2

    read -r reply || reply=""
    case "$reply" in
      "") break ;;
      q|Q) return 1 ;;
      a|A) chosen=("${all[@]}") ;;
      n|N) chosen=() ;;
      d|d\ *)
        idx=${reply#d}; idx=${idx# }
        name=$(_menu_row "$idx") || {
          printf '   d needs a row number, e.g. d 2\n' >&2; continue; }
        token=$(entry_deps "$name" block | head -1)
        if [ -n "$token" ]; then
          explain_dep "$token" "$name" >&2
        else
          printf '   %s is ready — nothing is blocking it\n' "$name" >&2
        fi ;;
      *[!0-9]*) printf '   not a number: %s\n' "$reply" >&2 ;;
      *)
        name=$(_menu_row "$reply") || {
          printf '   no row %s\n' "$reply" >&2; continue; }
        if printf '%s\n' "${blocked[@]:-}" | grep -qx "$name"; then
          printf '   %s is blocked and cannot be selected\n' "$name" >&2
          explain_dep "$(entry_deps "$name" block | head -1)" "$name" >&2
          continue
        fi
        if printf '%s\n' "${chosen[@]:-}" | grep -qx "$name"; then
          local -a keep=()
          for i in "${chosen[@]}"; do [ "$i" = "$name" ] || keep+=("$i"); done
          chosen=("${keep[@]:-}")
        else
          chosen+=("$name")
        fi ;;
    esac
  done

  # Print in manifest order, not toggle order, so the install sequence is stable.
  for name in "${all[@]}"; do
    printf '%s\n' "${chosen[@]:-}" | grep -qx "$name" && printf '%s\n' "$name"
  done
  return 0
}
