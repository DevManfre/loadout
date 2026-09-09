#!/usr/bin/env bash
# Smoke tests for scripts/loadout. No test runner is added to this repo: this
# file is the runner. Every test builds a directory of stub executables, puts
# it first on PATH, and runs the real code against it, so nothing here touches
# the machine it runs on.
set -uo pipefail

cd "$(dirname "$0")/.."
LOADOUT_ROOT=$PWD
export LOADOUT_ROOT

# Counters live in files, not variables: most tests run inside ( ... ) to scope
# a uname override or the absent seam, and a variable incremented in a subshell
# dies with it — the suite would report success while swallowing a real failure.
RESULTS=$(mktemp -d)
export RESULTS
trap 'rm -rf "$RESULTS"' EXIT
: > "$RESULTS/pass"
: > "$RESULTS/fail"
current=""

_pass() { printf 'x' >> "$RESULTS/pass"; }

it() { current=$1; }

_fail() {
  printf 'FAIL: %s\n      %s\n' "$current" "$1" >&2
  printf 'x' >> "$RESULTS/fail"
}

assert_eq() {
  if [ "$1" = "$2" ]; then _pass; else
    _fail "expected [$1], got [$2]"
  fi
}

assert_contains() {
  case "$2" in
    *"$1"*) _pass ;;
    *) _fail "expected to find [$1] in [$2]" ;;
  esac
}

assert_status() {
  local want=$1; shift
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then _pass; else
    _fail "expected exit $want, got $got from: $*"
  fi
}

# A throwaway directory of fake executables, first on PATH. Each stub appends
# its argv to $STUB_CALLS, so a test can assert that nothing was invoked.
stub_dir() {
  # Neutralise the developer's own environment: a variable the real proxy sets
  # would otherwise satisfy a runtime token and hide a broken filter.
  unset ANTHROPIC_BASE_URL
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
( stub_dir; absent docker; stub uv
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

# --- entrypoint and doctor ----------------------------------------------
it "help names every subcommand"
help_text=$(scripts/loadout --help)
for sub in install update status doctor remove list; do
  assert_contains "$sub" "$help_text"
done

it "an unknown subcommand exits 2"
assert_status 2 scripts/loadout frobnicate

it "doctor reports a blocker with why, fix and docs"
out=$( stub_dir; absent uv,pipx; stub claude; stub git
       LOADOUT_FAKE_PLATFORM=Linux/x86_64 scripts/loadout doctor 2>&1 )
assert_contains "cannot install here" "$out"
assert_contains "why:" "$out"
assert_contains "fix:" "$out"
assert_contains "integrations/graphify/README.md" "$out"

it "doctor exits 1 when something is blocked"
( stub_dir; absent uv,pipx; stub claude; stub git
  assert_status 1 env LOADOUT_FAKE_PLATFORM=Linux/x86_64 scripts/loadout doctor )

it "doctor exits 0 when everything is satisfied"
( stub_dir; stub claude; stub git; stub uv; stub docker
  assert_status 0 env LOADOUT_FAKE_PLATFORM=Linux/x86_64 scripts/loadout doctor )

it "doctor mutates nothing"
( stub_dir; stub claude; stub git; stub uv
  LOADOUT_FAKE_PLATFORM=Linux/x86_64 scripts/loadout doctor >/dev/null 2>&1
  assert_eq "" "$(grep -E '(install|upgrade|update)' "$STUB_CALLS")" )

# --- state, list, status -------------------------------------------------
it "an installed plugin is detected from the CLI's json"
( stub_dir
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$STUB_CALLS"
[ "$1 $2" = "plugin list" ] && echo '[{"id": "caveman@caveman"}]'
exit 0
EOF
  chmod +x "$STUB/claude"
  assert_status 0 entry_installed caveman
  assert_status 1 entry_installed superpowers )

it "an installed binary is detected on PATH"
( stub_dir; stub graphify; assert_status 0 entry_installed graphify )

it "list prints every entry with its cost"
out=$(scripts/loadout list)
assert_contains "headroom" "$out"
assert_contains "~2,480" "$out"

it "status shows the measured pin next to the installed one"
out=$( stub_dir; stub claude; scripts/loadout status 2>&1 )
assert_contains "measured" "$out"
assert_contains "v0.37.0" "$out"

it "status reports a runtime gap on an installed entry"
( stub_dir; stub claude; stub headroom; unset ANTHROPIC_BASE_URL
  out=$(scripts/loadout status 2>&1)
  assert_contains "not in the path" "$out" )

it "status mutates nothing"
( stub_dir; stub claude; stub graphify
  scripts/loadout status >/dev/null 2>&1
  assert_eq "" "$(grep -E '(plugin install|tool install|upgrade)' "$STUB_CALLS")" )

it "status reports DRIFT when the installed pin is not the measured one"
( stub_dir
  fake=$(mktemp -d)
  mkdir -p "$fake/.claude/plugins/cache/caveman/caveman/84cc3c14fa1e"
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$STUB_CALLS"
[ "$1 $2" = "plugin list" ] && echo '[{"id": "caveman@caveman"}]'
exit 0
EOF
  chmod +x "$STUB/claude"
  out=$(HOME=$fake scripts/loadout status 2>&1)
  assert_contains "DRIFT" "$out" )

it "status never reports DRIFT for an entry that is not installed"
( stub_dir; stub claude
  out=$(HOME=$(mktemp -d) scripts/loadout status 2>&1)
  assert_eq "" "$(printf '%s' "$out" | grep DRIFT)" )

it "the absent seam reaches entry_installed's binary probe"
( stub_dir; stub graphify; absent graphify
  assert_status 1 entry_installed graphify )

it "status names every runtime gap, not just the last"
( stub_dir; stub demo
  fx=$(mktemp -d)
  printf 'demo | pypkg | demo-pkg | full | r1,r2 | bin:demo | none | 1.0\n' > "$fx/manifest"
  printf 'r1 | runtime | env:LOADOUT_TEST_R1 | always | first gap | set it | README.md\n' > "$fx/deps"
  printf 'r2 | runtime | env:LOADOUT_TEST_R2 | always | second gap | set it | README.md\n' >> "$fx/deps"
  out=$(LOADOUT_MANIFEST=$fx/manifest LOADOUT_DEPS=$fx/deps HOME=$(mktemp -d) scripts/loadout status 2>&1)
  assert_contains "r1" "$out"
  assert_contains "r2" "$out" )

pass=$(wc -c < "$RESULTS/pass")
fail=$(wc -c < "$RESULTS/fail")
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
