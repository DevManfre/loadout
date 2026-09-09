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

# --- probes --------------------------------------------------------------
. scripts/lib/probe.sh

# Make a command look missing without emptying PATH. Truncating PATH would take
# awk, cut and sed with it, and every library under test calls those — the test
# would then be measuring absent coreutils rather than an absent tool. Exported,
# so a subprocess like `scripts/loadout doctor` sees it too.
absent()  { LOADOUT_FAKE_ABSENT=$1; export LOADOUT_FAKE_ABSENT; }
present() { unset LOADOUT_FAKE_ABSENT; }

it "a present command satisfies its token"
( stub_dir; stub git; assert_status 0 dep_present git )

it "an absent command does not"
( stub_dir; absent git; assert_status 1 dep_present git )

it "a group token is satisfied by either member"
( stub_dir; absent uv; stub pipx; assert_status 0 dep_present uv/pipx )

it "docker does not apply off Intel macOS"
( uname() { case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac; }
  assert_status 1 dep_applies docker )

it "docker applies on Intel macOS"
( uname() { case "$1" in -s) echo Darwin ;; -m) echo x86_64 ;; esac; }
  assert_status 0 dep_applies docker )

it "headroom is blocked without a package manager"
( stub_dir; absent uv,pipx
  uname() { case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac; }
  assert_contains "uv/pipx" "$(entry_deps headroom block)" )

it "headroom is not blocked by docker on Linux"
( stub_dir; stub uv
  uname() { case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac; }
  assert_eq "" "$(entry_deps headroom block)" )

it "headroom is blocked by docker on Intel macOS"
( stub_dir; absent docker; stub uv
  uname() { case "$1" in -s) echo Darwin ;; -m) echo x86_64 ;; esac; }
  assert_eq "docker" "$(entry_deps headroom block)" )

it "an unset variable is a runtime gap, not a blocker"
( stub_dir; stub uv; unset ANTHROPIC_BASE_URL
  uname() { case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac; }
  assert_eq "anthropic_base_url" "$(entry_deps headroom runtime)" )

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
