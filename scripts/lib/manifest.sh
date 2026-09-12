# shellcheck shell=bash
# Reading the two data files. Sourced, never executed.
#
# One awk pass per read. The files are a few lines long, so re-reading them is
# cheaper than any cache would be to keep correct.

: "${LOADOUT_ROOT:?LOADOUT_ROOT must be set before sourcing manifest.sh}"
LOADOUT_MANIFEST=${LOADOUT_MANIFEST:-$LOADOUT_ROOT/scripts/loadout.manifest}
LOADOUT_DEPS=${LOADOUT_DEPS:-$LOADOUT_ROOT/scripts/loadout.deps}
LOADOUT_CONTAINERS=${LOADOUT_CONTAINERS:-$LOADOUT_ROOT/scripts/loadout.containers}

MANIFEST_COLUMNS=8
DEPS_COLUMNS=7
CONTAINERS_COLUMNS=4

# Comments and blank lines out, every field trimmed, wrong column counts
# reported by line so a typo in the data file names itself.
_table_rows() {
  local file=$1 want=$2
  [ -f "$file" ] || { printf 'missing data file: %s\n' "$file" >&2; return 1; }
  awk -F'|' -v want="$want" -v file="$file" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      if (NF != want) {
        printf("%s:%d: expected %d columns, found %d\n", file, NR, want, NF) > "/dev/stderr"
        bad = 1
        next
      }
      line = ""
      for (i = 1; i <= NF; i++) {
        f = $i
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
        line = (i == 1 ? f : line "|" f)
      }
      print line
    }
    END { exit bad ? 1 : 0 }
  ' "$file"
}

manifest_rows() { _table_rows "$LOADOUT_MANIFEST" "$MANIFEST_COLUMNS"; }
deps_rows()     { _table_rows "$LOADOUT_DEPS" "$DEPS_COLUMNS"; }
containers_rows() { _table_rows "$LOADOUT_CONTAINERS" "$CONTAINERS_COLUMNS"; }

manifest_names() { manifest_rows | cut -d'|' -f1; }

_row_field() {
  local rows=$1 key=$2 idx=$3
  printf '%s\n' "$rows" |
    awk -F'|' -v k="$key" -v i="$idx" '$1 == k { print $i; found = 1 } END { exit found ? 0 : 1 }'
}

manifest_field() { _row_field "$(manifest_rows)" "$1" "$2"; }
dep_field()      { _row_field "$(deps_rows)" "$1" "$2"; }
# Fails when the entry has no row at all, which is how every caller asks
# "can this entry run as a container" without a second predicate.
container_field() { _row_field "$(containers_rows)" "$1" "$2"; }

manifest_in_preset() {
  local presets
  presets=$(manifest_field "$1" 4) || return 1
  case ",$presets," in *",$2,"*) return 0 ;; esac
  return 1
}
