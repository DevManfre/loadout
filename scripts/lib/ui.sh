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

# ' @ <pin>' when the installed entry will say its version, nothing when not.
_menu_installed_ver() {
  local pin
  pin=$(entry_version "$1")
  [ "$pin" = "-" ] || printf ' @ %s' "$pin"
  return 0
}

# The upstream pin _menu_prepare already paid for, out of the caller's
# latest_map. Nothing here probes: the map is the menu's whole knowledge of
# upstream, and a name missing from it answers empty, which reads as unknown.
_menu_latest() {
  printf '%s\n' "${latest_map:-}" | awk -v n="$1" '$1 == n { print $2; exit }'
}

# What an update row is offering, in the three lines pin_report prints before
# an update actually runs.
_menu_why_update() {
  printf 'installed: %s\n' "$(entry_version "$1")"
  if entry_is_container "$1"; then
    printf 'container: %s\n' "$(container_field "$1" 2)"
    printf 'image:     %s — the update pulls this tag and recreates the container\n' \
      "$(container_field "$1" 3)"
    return 0
  fi
  if printf '%s\n' "${remote_behind[@]:-}" | grep -qx "$1"; then
    printf 'where:     not on this machine — a proxy answers for it, so the update runs there\n'
  fi
  printf 'upstream:  %s — where an update would move it\n' "$(_menu_latest "$1")"
  printf 'measured:  %s — the pin the catalog priced this entry on (%s)\n' \
    "$(manifest_field "$1" 8)" "$(manifest_field "$1" 7)"
}

# The status column for a selectable row.
_menu_status() {
  local soft
  soft=$(entry_soft_blocks "$1" | tr '\n' ' ' | sed 's/ *$//')
  if [ -n "$soft" ]; then printf 'needs %s (auto-install, asks first)' "$soft"
  else printf 'ready'
  fi
}

# Loadout's own assets never get a manifest row (they install by plain copy,
# with no upstream or pin to probe — see copy_own_assets), but an entry the
# menu never names reads as "not carried". One summary line covers them.
# Same globs as copy_own_assets; both run from LOADOUT_ROOT.
_menu_own_assets() {
  local src base names=""
  for src in skills/*/ agents/*.md workflows/*.md; do
    [ -e "$src" ] || continue
    case "$src" in */.gitkeep) continue ;; esac
    base=$(basename "${src%/}")
    names="${names:+$names, }${base%.md}"
  done
  [ -n "$names" ] || return 0
  printf "plus loadout's own, copied with any install: %s" "$names"
}

# Everything on a row that cannot change while the menu is open — install
# state, version, cost, dependency status — is priced once here, before the
# redraw loop. Probing per frame is what made the menu lag: entry_version
# shells out to the plugin CLI, and every keystroke paid that again for every
# installed row. Fills the caller's locals (dynamic scoping): installed,
# blocked, rows, row_mark, row_cost, row_status, own_line.
_menu_prepare() {
  local name idx
  # Warm the plugin CLI's answer here, in this shell, before anything asks for
  # it from inside a $( ): the first caller pays the second it costs, and
  # every later one — including the ones in subshells — reads the export.
  _plugin_list >/dev/null
  # Installed and blocked entries are shown but cannot be chosen; that is the
  # whole point of showing them — the menu is the installer's whole view of
  # the catalog, and an invisible entry reads as "not carried" rather than
  # "already done". Only unfixable blocks land in blocked — an entry whose
  # blocks the installer can fix itself is selectable and says so on its row.
  installed=() blocked=() updatable=() remote_behind=() image_behind=()
  for name in $(manifest_names); do
    if entry_installed "$name"; then installed+=("$name")
    elif [ -n "$(entry_hard_blocks "$name")" ]; then blocked+=("$name")
    fi
  done
  # What upstream publishes now, asked once, for installed entries only —
  # nothing else can be behind anything. The answer costs the network, so it is
  # paid here with the rest of the row pricing and never inside the redraw
  # loop; entry_latest_all asks about every entry at the same time, so the menu
  # waits for the slowest probe rather than for the sum of them.
  latest_map=$(entry_latest_all "${installed[@]:-}")
  local -a current=()
  for name in "${installed[@]:-}"; do
    [ -n "$name" ] || continue
    # An unknown pin on either side (offline, a timeout, a proxy that will not
    # name its version) leaves the entry on its plain installed row rather than
    # claiming it is either current or behind.
    # A container is judged by its image, not by a version string: what an
    # update can deliver is whatever the registry serves for that tag, and the
    # package index is free to publish a version no image exists for.
    if entry_is_container "$name"; then
      if container_image_moved "$name"; then image_behind+=("$name")
      else current+=("$name"); fi
      continue
    fi
    if ! pin_outdated "$(entry_version "$name")" "$(_menu_latest "$name")"; then
      current+=("$name")
    elif entry_installed_locally "$name"; then
      updatable+=("$name")
    else
      # Behind, but running somewhere this machine cannot reach — a container,
      # or the Windows host under WSL. Saying so is the point: the row cannot
      # be actioned from here, and silence would read as "current".
      remote_behind+=("$name")
    fi
  done
  installed=("${current[@]:-}")
  # One array, in display order: selectable rows first, installed then
  # blocked rows after. Built with explicit appends because "${arr[@]:-}"
  # on an empty array expands to a single empty argument, which would
  # shift every row number.
  rows=()
  for name in "${all[@]:-}";       do [ -n "$name" ] && rows+=("$name"); done
  for name in "${updatable[@]:-}"; do [ -n "$name" ] && rows+=("$name"); done
  for name in "${image_behind[@]:-}"; do [ -n "$name" ] && rows+=("$name"); done
  for name in "${remote_behind[@]:-}"; do [ -n "$name" ] && rows+=("$name"); done
  for name in "${installed[@]:-}"; do [ -n "$name" ] && rows+=("$name"); done
  for name in "${blocked[@]:-}";   do [ -n "$name" ] && rows+=("$name"); done
  row_mark=() row_cost=() row_status=()
  for idx in "${!rows[@]}"; do
    name=${rows[$idx]}
    row_cost[idx]=$(manifest_field "$name" 7)
    if printf '%s\n' "${image_behind[@]:-}" | grep -qx "$name"; then
      # Selectable: the container is on this machine, so the pull and the
      # recreate can both happen from here.
      row_mark[idx]="^"
      row_status[idx]="update: new build of $(container_field "$name" 3) (running $(entry_version "$name"))"
    elif printf '%s\n' "${remote_behind[@]:-}" | grep -qx "$name"; then
      # Same mark, no action: the pins are the news, and the machine that could
      # act on them is not this one.
      row_mark[idx]="^"
      row_status[idx]="update: $(entry_version "$name") → $(_menu_latest "$name") — runs remotely, update it there"
    elif printf '%s\n' "${updatable[@]:-}" | grep -qx "$name"; then
      # Selectable like a new entry, and toggled off like one: an update is a
      # mutation on something that already works, so it is offered, not
      # assumed. _menu_toggle lets it through because it is in neither the
      # installed nor the blocked list.
      row_mark[idx]="^"
      row_status[idx]="update: $(entry_version "$name") → $(_menu_latest "$name")"
    elif printf '%s\n' "${installed[@]:-}" | grep -qx "$name"; then
      row_mark[idx]="="
      if entry_installed_locally "$name"; then
        row_status[idx]="installed$(_menu_installed_ver "$name")"
      else
        row_status[idx]="running remotely (proxy reachable, nothing on PATH here)"
      fi
    elif printf '%s\n' "${blocked[@]:-}" | grep -qx "$name"; then
      row_mark[idx]="!"
      row_status[idx]="BLOCKED: needs $(entry_deps "$name" block | tr '\n' ' ' | sed 's/ *$//')"
    else
      row_mark[idx]=" "
      row_status[idx]=$(_menu_status "$name")
    fi
  done
  own_line=$(_menu_own_assets) || own_line=""
}

# Toggle rows[idx] in the caller's selection. Relies on bash dynamic scoping:
# rows, installed, blocked, chosen and feedback are the caller's locals.
_menu_toggle() {
  local idx=$1 name t
  name=${rows[$idx]:-}
  [ -n "$name" ] || { feedback="no row $((idx + 1))"; return 0; }
  if printf '%s\n' "${remote_behind[@]:-}" | grep -qx "$name"; then
    feedback="$name runs remotely — update it where it runs, not from here"
    return 0
  fi
  if printf '%s\n' "${installed[@]:-}" | grep -qx "$name"; then
    feedback="$name already installed (remove: scripts/loadout remove $name)"
    return 0
  fi
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
  local -a installed=() blocked=() updatable=() remote_behind=() image_behind=()
  local -a row_mark=() row_cost=() row_status=()
  local i name reply idx token mark feedback="" own_line="" latest_map=""
  for name in "${all[@]}"; do chosen+=("$name"); done

  _menu_prepare

  while :; do
    printf '\n  #  entry        cost/session           status\n' >&2
    # Installed and blocked rows are numbered too, continuing after the
    # selectable ones: the prompt offers `d <n>` for them, and an unnumbered
    # row is an instruction the user cannot follow.
    for idx in "${!rows[@]}"; do
      name=${rows[$idx]}
      i=$((idx + 1))
      mark=${row_mark[$idx]}
      # '^' is selectable too, so it takes the same 'x' when chosen; the status
      # column is what keeps saying which of the two actions the row is.
      if [ "$mark" = " " ] || [ "$mark" = "^" ]; then
        if printf '%s\n' "${chosen[@]:-}" | grep -qx "$name"; then mark="x"; fi
      fi
      printf '  %d [%s] %-12s %-22s %s\n' \
        "$i" "$mark" "$name" "${row_cost[$idx]}" "${row_status[$idx]}" >&2
    done
    [ -z "$own_line" ] || printf '\n  %s\n' "$own_line" >&2
    printf '\ntoggle 1-%d · a=all · n=none · d <n>=why · Enter=apply %d · q=quit\n> ' \
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
        if printf '%s\n' "${updatable[@]:-}" "${image_behind[@]:-}" "${remote_behind[@]:-}" \
           | grep -qx "$name"; then
          _menu_why_update "$name" | sed 's/^/   /' >&2
          continue
        fi
        if printf '%s\n' "${installed[@]:-}" | grep -qx "$name"; then
          printf '   %s already installed (remove: scripts/loadout remove %s)\n' \
            "$name" "$name" >&2
          continue
        fi
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
  # Update rows leave by the same door, marked: the caller has to tell an
  # install from an update, and a bare name cannot say which it is.
  for name in "${updatable[@]:-}"; do
    [ -n "$name" ] || continue
    printf '%s\n' "${chosen[@]:-}" | grep -qx "$name" && printf 'update:%s\n' "$name"
  done
  return 0
}

# One line of the interactive menu. In-place mode clears the old content of
# the line first; append mode (stderr not a terminal) just prints.
# One line of the interactive frame, appended to the caller's frame_buf and
# counted in its frame_lines (how far up the next redraw must go — frames
# change height when the feedback area holds a full explanation). Buffering
# the frame and writing it in one printf is what keeps the repaint free of
# flicker: each line overwrites the old one (\e[2K) instead of the whole
# area being cleared first and repainted line by line.
_menu_ln() {
  frame_lines=$((${frame_lines:-0} + 1))
  if [ "${inplace:-0}" -eq 1 ]; then
    frame_buf+=$'\e[2K'"$*"$'\n'
  else
    frame_buf+="$*"$'\n'
  fi
}

# Undo everything _menu_interactive did to the terminal: show the cursor
# again and give the tty its echo back. Runs on every exit path, Ctrl-C
# included.
_menu_restore() {
  [ "${inplace:-0}" -eq 1 ] && printf '\e[?25h' >&2
  [ -n "${stty_saved:-}" ] && stty "$stty_saved" 2>/dev/null
  return 0
}

# The arrow-key menu: ▸ marks the current row, ↑/↓ move it, Space toggles it,
# d explains it, digits toggle by number, Enter installs, q quits. Reached
# only on a real TTY; the screen is redrawn in place so the menu stands still
# instead of scrolling one copy of itself per keystroke.
_menu_interactive() {
  local -a all=("$@") chosen=() rows=()
  local -a installed=() blocked=() updatable=() remote_behind=() image_behind=()
  local -a row_mark=() row_cost=() row_status=()
  local i name cur=0 key seq idx token feedback="" drawn=0 inplace=0 latest_map=""
  local status line mark cursor frame_lines=0 last_frame=0 fline stty_saved=""
  local frame_buf="" own_line=""
  for name in "${all[@]}"; do [ -n "$name" ] && chosen+=("$name"); done

  _menu_prepare

  # In-place redraw and a hidden terminal cursor only when stderr really is a
  # terminal; through a pipe (the pty-driven tests capture stderr that way)
  # the same menu draws by appending, with no escape codes to choke on.
  [ -t 2 ] && [ "${TERM:-}" != dumb ] && inplace=1
  [ "$inplace" -eq 1 ] && printf '\e[?25l' >&2
  # read -s silences the terminal only while a read is pending; a key typed
  # during the redraw in between would be echoed by the tty driver and flash
  # its escape code on screen. Echo goes off for the menu's whole lifetime.
  if stty_saved=$(stty -g 2>/dev/null); then stty -echo 2>/dev/null; else stty_saved=""; fi
  trap '_menu_restore; trap - INT; kill -INT $$' INT

  while :; do
    frame_lines=0
    frame_buf=""

    _menu_ln ""
    _menu_ln "    #  entry        cost/session           status"
    for idx in "${!rows[@]}"; do
      name=${rows[$idx]}
      i=$((idx + 1))
      cursor=" "; [ "$idx" -eq "$cur" ] && cursor="${C_BOLD}▸${C_RESET}"
      mark=${row_mark[$idx]}
      case "$mark" in
        =) status="${C_DIM}${row_status[$idx]}${C_RESET}" ;;
        !) status="${C_RED}${row_status[$idx]}${C_RESET}" ;;
        *)
          case "${row_status[$idx]}" in
            ready) status="${C_GREEN}ready${C_RESET}" ;;
            *)     status="${C_YELLOW}${row_status[$idx]}${C_RESET}" ;;
          esac
          if printf '%s\n' "${chosen[@]:-}" | grep -qx "$name"; then mark="x"; fi ;;
      esac
      printf -v line '%d [%s] %-12s %-22s' "$i" "$mark" "$name" "${row_cost[$idx]}"
      line=${line/\[x\]/[${C_GREEN}x${C_RESET}]}
      line=${line/\[=\]/[${C_DIM}=${C_RESET}]}
      line=${line/\[!\]/[${C_RED}!${C_RESET}]}
      _menu_ln " $cursor $line$status"
    done
    [ -z "$own_line" ] || _menu_ln "   ${C_DIM}${own_line}${C_RESET}"
    _menu_ln ""
    _menu_ln "${C_BOLD}↑/↓${C_RESET} move · ${C_BOLD}Space${C_RESET} toggle · d=why · a=all · n=none · ${C_BOLD}Enter${C_RESET}=apply $(_menu_count) · q=quit"
    # The feedback area holds one line ("toggled graphify off") or a whole
    # explanation from d — the frame grows to fit and the next redraw's
    # height comes from frame_lines, so nothing scrolls either way.
    if [ -n "$feedback" ]; then
      while IFS= read -r fline; do
        _menu_ln "   ${C_DIM}${fline}${C_RESET}"
      done <<< "$feedback"
    else
      _menu_ln ""
    fi

    # One write per frame. The cursor first moves up over the previous frame
    # (measured height — frames grow and shrink with the feedback area), the
    # buffered lines overwrite it, and the trailing clear-to-end drops
    # whatever a taller previous frame left below. Never clear first and
    # repaint after: the blank gap in between is visible as flicker.
    if [ "$inplace" -eq 1 ]; then
      if [ "$drawn" -eq 1 ]; then
        printf '\e[%dA%s\e[0J' "$last_frame" "$frame_buf" >&2
      else
        printf '%s' "$frame_buf" >&2
      fi
    else
      printf '%s' "$frame_buf" >&2
    fi
    drawn=1
    last_frame=$frame_lines

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
        _menu_restore; trap - INT
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
        # The explanation renders inside the frame's feedback area, so it
        # replaces the previous frame like any other keystroke instead of
        # pushing a second copy of the menu down the screen.
        if printf '%s\n' "${updatable[@]:-}" "${image_behind[@]:-}" "${remote_behind[@]:-}" \
           | grep -qx "$name"; then
          feedback=$(_menu_why_update "$name")
          continue
        fi
        if printf '%s\n' "${installed[@]:-}" | grep -qx "$name"; then
          feedback="$name already installed (remove: scripts/loadout remove $name)"
          continue
        fi
        token=$(entry_deps "$name" block | head -1)
        if [ -n "$token" ]; then
          feedback=$(explain_dep "$token" "$name")
        else
          feedback="$name is ready — nothing is blocking it"
        fi ;;
      [0-9])
        if [ "$key" -ge 1 ] && [ "$key" -le "${#rows[@]}" ]; then
          _menu_toggle "$((key - 1))"
        else
          feedback="no row $key"
        fi ;;
      *) feedback="keys: ↑ ↓ Space d a n Enter q" ;;
    esac
  done

  _menu_restore; trap - INT
  # Print in manifest order, not toggle order, so the install sequence is stable.
  for name in "${all[@]}"; do
    printf '%s\n' "${chosen[@]:-}" | grep -qx "$name" && printf '%s\n' "$name"
  done
  # Update rows leave by the same door, marked: the caller has to tell an
  # install from an update, and a bare name cannot say which it is.
  for name in "${updatable[@]:-}"; do
    [ -n "$name" ] || continue
    printf '%s\n' "${chosen[@]:-}" | grep -qx "$name" && printf 'update:%s\n' "$name"
  done
  return 0
}
