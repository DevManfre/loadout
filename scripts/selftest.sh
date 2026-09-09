#!/usr/bin/env bash
# Smoke tests for scripts/loadout. No test runner is added to this repo: this
# file is the runner. Every test builds a directory of stub executables, puts
# it first on PATH, and runs the real code against it, so nothing here touches
# the machine it runs on.
set -uo pipefail

cd "$(dirname "$0")/.."
LOADOUT_ROOT=$PWD
export LOADOUT_ROOT

pass=0
fail=0
current=""

it() { current=$1; }

_fail() {
  printf 'FAIL: %s\n      %s\n' "$current" "$1" >&2
  fail=$((fail + 1))
}

assert_eq() {
  if [ "$1" = "$2" ]; then pass=$((pass + 1)); else
    _fail "expected [$1], got [$2]"
  fi
}

assert_contains() {
  case "$2" in
    *"$1"*) pass=$((pass + 1)) ;;
    *) _fail "expected to find [$1] in [$2]" ;;
  esac
}

assert_status() {
  local want=$1; shift
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass + 1)); else
    _fail "expected exit $want, got $got from: $*"
  fi
}

# A throwaway directory of fake executables, first on PATH. Each stub appends
# its argv to $STUB_CALLS, so a test can assert that nothing was invoked.
stub_dir() {
  STUB=$(mktemp -d)
  STUB_CALLS=$STUB/.calls
  : > "$STUB_CALLS"
  PATH=$STUB:$PATH
  export PATH STUB STUB_CALLS
}

stub() {
  local name=$1 code=${2:-0}
  cat > "$STUB/$name" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$name" "\$*" >> "$STUB_CALLS"
exit $code
EOF
  chmod +x "$STUB/$name"
}

stub_calls() { cat "$STUB_CALLS"; }

# --- manifest ------------------------------------------------------------
. scripts/lib/manifest.sh

it "manifest lists every entry"
assert_eq "superpowers caveman graphify headroom" "$(manifest_names | tr '\n' ' ' | sed 's/ $//')"

it "manifest keeps spaces inside a field"
assert_contains "+60/prompt" "$(manifest_field caveman 7)"

it "manifest reports an unknown entry"
assert_status 1 manifest_field nosuchentry 1

it "a group token stays one token"
assert_contains "uv/pipx" "$(manifest_field headroom 5)"

it "preset membership"
assert_status 0 manifest_in_preset graphify core
assert_status 1 manifest_in_preset caveman core

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
