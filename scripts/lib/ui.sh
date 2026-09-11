# shellcheck shell=bash
# Everything the user sees, and the one wrapper that performs mutations.

# Colors are cosmetic, never load-bearing: every message must read the same
# with them stripped, because that is what a pipe, NO_COLOR or TERM=dumb gets.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != dumb ]; then
  C_BOLD=$'\e[1m' C_DIM=$'\e[2m' C_RED=$'\e[31m'
  C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_RESET=$'\e[0m'
else
  C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_RESET=''
fi

say()  { printf '\n%s== %s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
note() { printf '   %s\n' "$*"; }
cost() { printf '   %scost:%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }

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

# The menu comes in two shapes behind one name. A real TTY gets the arrow-key
# menu; a pipe (the line-driven tests), LOADOUT_PLAIN_MENU=1 or TERM=dumb gets
# the numbered line-based one, which is also the fallback for terminals whose
# arrow keys never arrive as ESC [ sequences.
menu_select() {
  if [ -t 0 ] && [ "${LOADOUT_PLAIN_MENU:-0}" != 1 ] && [ "${TERM:-}" != dumb ]; then
    _menu_interactive "$@"
  else
    _menu_plain "$@"
  fi
}

# Selected entries, ignoring the empty element bash leaves behind when an
# array is emptied through ("${keep[@]:-}").
_menu_count() {
  local c=0 t
  for t in "${chosen[@]:-}"; do [ -n "$t" ] && c=$((c + 1)); done
  printf '%s' "$c"
}

# The status column for a selectable row.
_menu_status() {
  local soft
  soft=$(entry_soft_blocks "$1" | tr '\n' ' ' | sed 's/ *$//')
  if [ -n "$soft" ]; then printf 'needs %s (auto-install, asks first)' "$soft"
  else printf 'ready'
  fi
}

# Toggle rows[idx] in the caller's selection. Relies on bash dynamic scoping:
# rows, blocked, chosen and feedback are the caller's locals.
_menu_toggle() {
  local idx=$1 name t
  name=${rows[$idx]:-}
  [ -n "$name" ] || { feedback="no row $((idx + 1))"; return 0; }
  if printf '%s\n' "${blocked[@]:-}" | grep -qx "$name"; then
    feedback="$name is blocked (missing: $(entry_deps "$name" block | tr '\n' ' ' | sed 's/ *$//'))"
    return 0
  fi
  if printf '%s\n' "${chosen[@]:-}" | grep -qx "$name"; then
    local -a keep=()
    for t in "${chosen[@]:-}"; do [ -n "$t" ] && [ "$t" != "$name" ] && keep+=("$t"); done
    chosen=("${keep[@]:-}")
    feedback="toggled $name off"
  else
    chosen+=("$name")
    feedback="toggled $name on"
  fi
}

# A numbered toggle list, redrawn after every keystroke line. No raw mode, no
# cursor movement: this has to work under a pipe and on any terminal.
_menu_plain() {
  local -a all=("$@") chosen=() rows=()
  local i name reply idx token soft status feedback=""
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
      status=$(_menu_status "$name")
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
      "${#rows[@]}" "$(_menu_count)" >&2

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
      *)
        # One reply may name several rows: "1 3" or "1,3" toggles each. A row
        # that does not exist — a junk word included — reads as "no row X".
        for idx in $(printf '%s' "$reply" | tr ',' ' '); do
          if ! _menu_row "$idx" >/dev/null; then
            printf '   no row %s\n' "$idx" >&2
            continue
          fi
          feedback=""
          _menu_toggle "$((idx - 1))"
          printf '   %s\n' "$feedback" >&2
        done ;;
    esac
  done

  # Print in manifest order, not toggle order, so the install sequence is stable.
  for name in "${all[@]}"; do
    printf '%s\n' "${chosen[@]:-}" | grep -qx "$name" && printf '%s\n' "$name"
  done
  return 0
}

# One line of the interactive menu. In-place mode clears the old content of
# the line first; append mode (stderr not a terminal) just prints.
_menu_ln() {
  if [ "${inplace:-0}" -eq 1 ]; then printf '\e[2K%s\n' "$*" >&2
  else printf '%s\n' "$*" >&2
  fi
}

_menu_cursor_restore() { [ "${inplace:-0}" -eq 1 ] && printf '\e[?25h' >&2; }

# The arrow-key menu: ▸ marks the current row, ↑/↓ move it, Space toggles it,
# d explains it, digits toggle by number, Enter installs, q quits. Reached
# only on a real TTY; the screen is redrawn in place so the menu stands still
# instead of scrolling one copy of itself per keystroke.
_menu_interactive() {
  local -a all=("$@") chosen=() rows=()
  local i name cur=0 key seq idx token feedback="" drawn=0 inplace=0
  local status line mark cursor
  for name in "${all[@]}"; do [ -n "$name" ] && chosen+=("$name"); done

  local -a blocked=()
  for name in $(manifest_names); do
    [ -z "$(entry_hard_blocks "$name")" ] || blocked+=("$name")
  done
  rows=()
  for name in "${all[@]:-}";     do [ -n "$name" ] && rows+=("$name"); done
  for name in "${blocked[@]:-}"; do [ -n "$name" ] && rows+=("$name"); done

  # In-place redraw and a hidden terminal cursor only when stderr really is a
  # terminal; through a pipe (the pty-driven tests capture stderr that way)
  # the same menu draws by appending, with no escape codes to choke on.
  [ -t 2 ] && [ "${TERM:-}" != dumb ] && inplace=1
  [ "$inplace" -eq 1 ] && printf '\e[?25l' >&2
  trap '_menu_cursor_restore; trap - INT; kill -INT $$' INT

  while :; do
    if [ "$drawn" -eq 1 ] && [ "$inplace" -eq 1 ]; then
      printf '\e[%dA' "$(( ${#rows[@]} + 5 ))" >&2
    fi
    drawn=1

    _menu_ln ""
    _menu_ln "    #  entry        cost/session           status"
    i=0
    for name in "${rows[@]:-}"; do
      [ -n "$name" ] || continue
      i=$((i + 1))
      cursor=" "; [ $((i - 1)) -eq "$cur" ] && cursor="${C_BOLD}▸${C_RESET}"
      if printf '%s\n' "${blocked[@]:-}" | grep -qx "$name"; then
        status="${C_RED}BLOCKED: needs $(entry_deps "$name" block | tr '\n' ' ' | sed 's/ *$//')${C_RESET}"
        mark="!"
      else
        status=$(_menu_status "$name")
        case "$status" in
          ready) status="${C_GREEN}ready${C_RESET}" ;;
          *)     status="${C_YELLOW}${status}${C_RESET}" ;;
        esac
        if printf '%s\n' "${chosen[@]:-}" | grep -qx "$name"; then mark="x"; else mark=" "; fi
      fi
      printf -v line '%d [%s] %-12s %-22s' "$i" "$mark" "$name" "$(manifest_field "$name" 7)"
      line=${line/\[x\]/[${C_GREEN}x${C_RESET}]}
      line=${line/\[!\]/[${C_RED}!${C_RESET}]}
      _menu_ln " $cursor $line$status"
    done
    _menu_ln ""
    _menu_ln "${C_BOLD}↑/↓${C_RESET} move · ${C_BOLD}Space${C_RESET} toggle · d=why · a=all · n=none · ${C_BOLD}Enter${C_RESET}=install $(_menu_count) · q=quit"
    _menu_ln "   ${C_DIM}${feedback}${C_RESET}"

    IFS= read -rsn1 key || key=q
    feedback=""
    case "$key" in
      $'\e')
        IFS= read -rsn2 -t 0.2 seq || seq=""
        case "$seq" in
          '[A') [ "$cur" -gt 0 ] && cur=$((cur - 1)) ;;
          '[B') [ "$cur" -lt $(( ${#rows[@]} - 1 )) ] && cur=$((cur + 1)) ;;
        esac ;;
      ''|$'\r'|$'\n') break ;;
      q|Q)
        _menu_cursor_restore; trap - INT
        return 1 ;;
      a|A)
        chosen=()
        for name in "${all[@]}"; do [ -n "$name" ] && chosen+=("$name"); done
        feedback="all selected" ;;
      n|N) chosen=(); feedback="none selected" ;;
      ' ') _menu_toggle "$cur" ;;
      d|D)
        name=${rows[$cur]:-}
        [ -n "$name" ] || continue
        # The explanation is multi-line, so it stays put as a log above the
        # menu: print it, then draw the next frame fresh below it.
        printf '\n' >&2
        token=$(entry_deps "$name" block | head -1)
        if [ -n "$token" ]; then
          explain_dep "$token" "$name" >&2
        else
          printf '   %s is ready — nothing is blocking it\n' "$name" >&2
        fi
        drawn=0 ;;
      [0-9])
        if [ "$key" -ge 1 ] && [ "$key" -le "${#rows[@]}" ]; then
          _menu_toggle "$((key - 1))"
        else
          feedback="no row $key"
        fi ;;
      *) feedback="keys: ↑ ↓ Space d a n Enter q" ;;
    esac
  done

  _menu_cursor_restore; trap - INT
  # Print in manifest order, not toggle order, so the install sequence is stable.
  for name in "${all[@]}"; do
    printf '%s\n' "${chosen[@]:-}" | grep -qx "$name" && printf '%s\n' "$name"
  done
  return 0
}
