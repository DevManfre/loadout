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

# t_ prefix, not _pass/_fail: this file sources the installer's own libraries,
# and scripts/lib/actions.sh defines _ok/_skip/_fail for its own tallies. A
# collision here does not error — it silently replaces the harness's counter,
# and the suite then prints "0 failed" while swallowing real failures.
t_pass() { printf 'x' >> "$RESULTS/pass"; }

it() { current=$1; }

t_fail() {
  printf 'FAIL: %s\n      %s\n' "$current" "$1" >&2
  printf 'x' >> "$RESULTS/fail"
}

assert_eq() {
  if [ "$1" = "$2" ]; then t_pass; else
    t_fail "expected [$1], got [$2]"
  fi
}

assert_contains() {
  case "$2" in
    *"$1"*) t_pass ;;
    *) t_fail "expected to find [$1] in [$2]" ;;
  esac
}

assert_status() {
  local want=$1; shift
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then t_pass; else
    t_fail "expected exit $want, got $got from: $*"
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
( stub_dir; absent graphify,headroom; stub claude
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

# --- selection -------------------------------------------------------------
. scripts/lib/ui.sh

it "the default preset is everything installable"
( stub_dir; stub claude; stub git; stub uv; absent graphify
  OPT_PRESET=full OPT_ONLY="" OPT_EXCEPT="" LOADOUT_FAKE_PLATFORM=Linux/x86_64
  export OPT_PRESET OPT_ONLY OPT_EXCEPT LOADOUT_FAKE_PLATFORM
  assert_eq "superpowers caveman graphify headroom" "$(resolve_selection | tr '\n' ' ' | sed 's/ $//')" )

it "core drops the style plugin and the proxy"
( stub_dir; stub claude; stub git; stub uv; absent graphify
  OPT_PRESET=core OPT_ONLY="" OPT_EXCEPT=""
  assert_eq "superpowers graphify" "$(resolve_selection | tr '\n' ' ' | sed 's/ $//')" )

it "--except removes an entry"
( stub_dir; stub claude; stub git; stub uv
  OPT_PRESET=full OPT_ONLY="" OPT_EXCEPT=caveman
  assert_eq "" "$(resolve_selection | grep -x caveman)" )

it "--only is the same set a menu toggled to those entries would give"
( stub_dir; stub claude; stub git; stub uv; absent graphify
  OPT_PRESET=full OPT_EXCEPT="" OPT_ONLY="graphify,headroom"
  assert_eq "graphify headroom" "$(resolve_selection | tr '\n' ' ' | sed 's/ $//')" )

it "a blocked entry is never selected"
( stub_dir; absent uv,pipx; stub claude; stub git
  OPT_PRESET=full OPT_ONLY="" OPT_EXCEPT=""
  assert_eq "superpowers caveman" "$(resolve_selection | tr '\n' ' ' | sed 's/ $//')" )

it "an already-installed entry is not selected again"
( stub_dir; stub claude; stub git; stub uv; stub graphify
  OPT_PRESET=full OPT_ONLY="" OPT_EXCEPT=""
  assert_eq "" "$(resolve_selection | grep -x graphify)" )

it "the menu obeys a toggle then Enter"
( stub_dir; stub claude; stub git; stub uv; absent graphify
  OPT_PRESET=full OPT_ONLY="" OPT_EXCEPT=""
  assert_eq "superpowers graphify headroom" \
    "$(printf '2\n\n' | menu_select $(resolve_selection) | tr '\n' ' ' | sed 's/ $//')" )

it "the menu can clear and rebuild a selection"
( stub_dir; stub claude; stub git; stub uv
  assert_eq "caveman" "$(printf 'n\n2\n\n' | menu_select $(resolve_selection) | tr '\n' ' ' | sed 's/ $//')" )

it "the total names both budgets"
( stub_dir
  assert_contains "per tool call" "$(selection_total superpowers graphify)" )

it "the menu prints in manifest order, not toggle order"
( stub_dir; absent graphify,headroom; stub claude
  assert_eq "superpowers caveman" \
    "$(printf 'n\n2\n1\n\n' | menu_select $(resolve_selection) 2>/dev/null | tr '\n' ' ' | sed 's/ $//')" )

it "d explains a blocked row instead of aborting"
( stub_dir; absent uv,pipx; stub claude; stub git
  out=$(printf 'd 3\n\n' | menu_select $(resolve_selection) 2>&1 >/dev/null)
  assert_contains "why:" "$out" )

it "d with a bad argument does not abort the menu"
( stub_dir; absent graphify,headroom; stub claude
  out=$(printf 'd 99\nd x\nd\n\n' | menu_select $(resolve_selection) 2>&1 >/dev/null)
  assert_eq "" "$(printf '%s' "$out" | grep 'unbound variable')" )

it "a blocked row cannot be toggled on"
( stub_dir; absent uv,pipx; stub claude; stub git
  out=$(printf '3\n\n' | menu_select $(resolve_selection) 2>/dev/null)
  assert_eq "" "$(printf '%s' "$out" | grep -x graphify)" )

it "row numbers stay correct when nothing is selectable"
( stub_dir; absent uv,pipx; stub claude; stub git
  out=$(printf 'd 2\n\n' | menu_select 2>&1 >/dev/null)
  assert_contains "headroom" "$out"
  assert_eq "" "$(printf '%s' "$out" | grep 'skip graphify')" )

it "the prompt counts every visible row"
( stub_dir; absent uv,pipx; stub claude; stub git
  out=$(printf '\n' | menu_select 2>&1 >/dev/null)
  assert_contains "toggle 1-2" "$out" )

# --- install ---------------------------------------------------------------
it "install runs the plugin CLI for a plugin entry"
( stub_dir; stub claude; stub git
  HOME=$(mktemp -d) scripts/loadout install --only superpowers --yes >/dev/null 2>&1
  assert_contains "plugin install superpowers@claude-plugins-official" "$(stub_calls)" )

it "install adds a marketplace when the source names one"
( stub_dir; stub claude; stub git
  HOME=$(mktemp -d) scripts/loadout install --only caveman --yes >/dev/null 2>&1
  assert_contains "marketplace add JuliusBrussee/caveman" "$(stub_calls)" )

# graphify is a real binary on this machine, so its dependency probe must be
# faked absent too or resolve_selection sees it as already installed and the
# python-installer branch below never runs; it is also stubbed so that, once
# the fake-absent probe lets install proceed, `_post_install_pypkg` runs a
# harmless logger instead of the real `graphify install`.
it "install prefers uv over pipx for a python entry"
( stub_dir; absent graphify; stub claude; stub uv; stub pipx; stub graphify
  HOME=$(mktemp -d) scripts/loadout install --only graphify --yes >/dev/null 2>&1
  assert_contains "uv tool install graphifyy" "$(stub_calls)"
  assert_eq "" "$(grep pipx "$STUB_CALLS")" )

it "install falls back to pipx when uv is absent"
( stub_dir; absent uv,graphify; stub claude; stub pipx; stub graphify
  HOME=$(mktemp -d) scripts/loadout install --only graphify --yes >/dev/null 2>&1
  assert_contains "pipx install graphifyy" "$(stub_calls)" )

it "install prints the cost before the command"
out=$( stub_dir; stub claude; stub git
       HOME=$(mktemp -d) scripts/loadout install --only superpowers --yes 2>&1 )
assert_contains "cost: ~800" "$out"

it "dry run mutates nothing at all"
( stub_dir; stub claude; stub git; stub uv
  HOME=$(mktemp -d) scripts/loadout install --yes --dry-run >/dev/null 2>&1
  assert_eq "" "$(grep -E '(plugin install|tool install|marketplace add)' "$STUB_CALLS")" )

# graphify must also be faked absent here: otherwise entry_installed reports
# it as already installed on this machine and the blocked-entry diagnostic in
# cmd_install is skipped (it only fires for a named entry that is neither
# selected nor already installed), so the explanation this test looks for
# would never be printed.
it "a blocked entry named with --only refuses and explains"
out=$( stub_dir; absent uv,pipx,graphify; stub claude; stub git
       HOME=$(mktemp -d) scripts/loadout install --only graphify --yes 2>&1 )
assert_contains "cannot install here" "$out"
assert_contains "docs.astral.sh" "$out"

it "no TTY and no --yes is a hard stop"
( stub_dir; stub claude; stub git
  assert_status 1 env HOME=$(mktemp -d) scripts/loadout install --only superpowers < /dev/null )

it "install-all.sh still works as a shim"
( stub_dir; stub claude; stub git
  HOME=$(mktemp -d) scripts/install-all.sh --only superpowers --yes >/dev/null 2>&1
  assert_contains "plugin install superpowers" "$(stub_calls)" )

# The example asset is created inside the real repo tree (copy_own_assets
# reads from relative skills/*/ paths), so a trap guarantees it is removed
# even if an assertion above aborts the subshell under set -u.
it "loadout's own assets are copied, and never twice"
( stub_dir; stub claude
  fake_home=$(mktemp -d)
  mkdir -p "$LOADOUT_ROOT/skills/example-asset"
  printf -- '---\nname: example-asset\ndescription: x\n---\n' > "$LOADOUT_ROOT/skills/example-asset/SKILL.md"
  trap 'rm -rf "$LOADOUT_ROOT/skills/example-asset"' EXIT
  HOME=$fake_home scripts/loadout install --only nothing --yes >/dev/null 2>&1
  assert_eq "0" "$([ -f "$fake_home/.claude/skills/example-asset/SKILL.md" ]; echo $?)" )

# Ordering, not just presence: the earlier test only checked the cost line
# existed, so it stayed green even with cost printed after the mutation. A
# stub's own call log has no timestamps, so ordering is only observable in
# dry-run output, where run() prints "run: ..." to stdout instead of calling
# the stub.
it "install prints the cost before it runs the command"
( stub_dir; stub claude; stub git
  out=$(HOME=$(mktemp -d) scripts/loadout install --only superpowers --yes --dry-run 2>&1)
  cost_at=$(printf '%s\n' "$out" | grep -n 'cost: ~800' | head -1 | cut -d: -f1)
  run_at=$(printf '%s\n' "$out" | grep -n 'run: claude plugin install' | head -1 | cut -d: -f1)
  assert_status 0 test "${cost_at:-0}" -gt 0
  assert_status 0 test "${cost_at:-0}" -lt "${run_at:-0}" )

# Stronger than checking one path: a dry run must leave the fake HOME
# completely empty, which catches any future unwrapped mutation, not just
# the one already found.
it "a dry run writes nothing at all under HOME"
( stub_dir; absent graphify; stub claude; stub git; stub uv; stub graphify
  fake=$(mktemp -d)
  HOME=$fake scripts/loadout install --yes --dry-run >/dev/null 2>&1
  assert_eq "" "$(find "$fake" -mindepth 1 -print -quit)" )

it "no marketplace is added for an entry whose source names none"
( stub_dir; stub claude; stub git
  HOME=$(mktemp -d) scripts/loadout install --only superpowers --yes >/dev/null 2>&1
  assert_eq "" "$(grep 'marketplace add' "$STUB_CALLS")" )

it "a failed package install is not counted as installed"
( stub_dir; absent uv,graphify; stub claude; stub graphify; stub pipx 1
  out=$(HOME=$(mktemp -d) scripts/loadout install --only graphify --yes 2>&1)
  assert_contains "FAIL" "$out"
  assert_contains "0 installed" "$out"
  assert_eq "" "$(grep 'graphify claude install' "$STUB_CALLS")" )

# --- update --------------------------------------------------------------
. scripts/lib/actions.sh
it "update skips what is not installed"
( stub_dir; absent graphify,headroom; stub claude
  out=$(HOME=$(mktemp -d) scripts/loadout update --yes 2>&1)
  assert_contains "not installed" "$out" )

it "update refreshes the marketplace before updating a plugin"
( stub_dir
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$STUB_CALLS"
[ "$1 $2" = "plugin list" ] && echo '[{"id": "caveman@caveman"}]'
exit 0
EOF
  chmod +x "$STUB/claude"
  HOME=$(mktemp -d) scripts/loadout update --only caveman --yes >/dev/null 2>&1
  assert_contains "marketplace update caveman" "$(stub_calls)"
  assert_contains "plugin update caveman" "$(stub_calls)" )

it "the pin gate warns that an update goes to an unmeasured version"
out=$( stub_dir
       cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "plugin list" ] && echo '[{"id": "caveman@caveman"}]'
exit 0
EOF
       chmod +x "$STUB/claude"
       HOME=$(mktemp -d) \
       scripts/loadout update --only caveman --yes 2>&1 )
assert_contains "has not measured" "$out"
assert_contains "installed:" "$out"

it "an entry already on the measured pin gets no drift line"
out=$( fake_home=$(mktemp -d)
       mkdir -p "$fake_home/.claude/plugins/cache/caveman/caveman/v2.6.0"
       stub_dir
       cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "plugin list" ] && echo '[{"id": "caveman@caveman"}]'
exit 0
EOF
       chmod +x "$STUB/claude"
       HOME=$fake_home scripts/loadout update --only caveman --yes 2>&1 )
assert_eq "" "$(printf '%s' "$out" | grep 'already off the measured pin')"
assert_contains "an update moves to whatever upstream publishes now" "$out"

it "the pin gate refuses without --yes and no TTY"
( stub_dir; stub claude
  assert_status 1 env HOME=$(mktemp -d) \
    scripts/loadout update --only caveman < /dev/null )

it "no entry escapes the gate for want of a version"
( stub_dir
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$STUB_CALLS"
[ "$1 $2" = "plugin list" ] && echo '[{"id": "superpowers@claude-plugins-official"}]'
exit 0
EOF
  chmod +x "$STUB/claude"
  out=$(HOME=$(mktemp -d) scripts/loadout update --only superpowers --yes 2>&1)
  assert_contains "has not measured" "$out" )

it "every installed entry is gated, not just the drifted ones"
( stub_dir; absent uv,graphify,headroom
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$STUB_CALLS"
[ "$1 $2" = "plugin list" ] && echo '[{"id": "superpowers@claude-plugins-official"}, {"id": "caveman@caveman"}]'
exit 0
EOF
  chmod +x "$STUB/claude"
  out=$(HOME=$(mktemp -d) scripts/loadout update --yes 2>&1)
  assert_eq "2" "$(printf '%s\n' "$out" | grep -c 'an update moves to whatever upstream')" )

it "no gate is shown for an entry that is not installed"
( stub_dir; absent graphify,headroom; stub claude
  out=$(HOME=$(mktemp -d) scripts/loadout update --yes 2>&1)
  assert_eq "" "$(printf '%s' "$out" | grep 'an update moves to whatever upstream')" )

it "update upgrades a python entry with the manager that is present"
( stub_dir; absent uv; stub claude; stub pipx; stub graphify
  HOME=$(mktemp -d) scripts/loadout update --only graphify --yes >/dev/null 2>&1
  assert_contains "pipx upgrade graphifyy" "$(stub_calls)" )

it "a package update still faces the pin gate"
( stub_dir; absent uv; stub claude; stub pipx; stub graphify
  out=$(HOME=$(mktemp -d) scripts/loadout update --only graphify --yes 2>&1)
  assert_contains "the catalog prices this entry at ~340" "$out" )

it "a failed package upgrade is not counted as updated"
( stub_dir; absent uv; stub claude; stub graphify; stub pipx 1
  out=$(HOME=$(mktemp -d) scripts/loadout update --only graphify --yes 2>&1)
  assert_contains "FAIL" "$out"
  assert_contains "0 updated" "$out" )

it "a locally edited own asset is never overwritten"
( fake_home=$(mktemp -d); state=$fake_home/state
  trap 'rm -rf "$LOADOUT_ROOT/skills/example-asset"' EXIT
  stub_dir; absent graphify,headroom; stub claude
  mkdir -p "$LOADOUT_ROOT/skills/example-asset" "$fake_home/.claude/skills/example-asset"
  printf 'upstream\n' > "$LOADOUT_ROOT/skills/example-asset/SKILL.md"
  printf 'edited by hand\n' > "$fake_home/.claude/skills/example-asset/SKILL.md"
  printf 'example-asset·deadbeef\n' > "$state"
  out=$(HOME=$fake_home LOADOUT_STATE=$state scripts/loadout update --yes 2>&1)
  assert_contains "modified locally" "$out"
  assert_eq "edited by hand" "$(cat "$fake_home/.claude/skills/example-asset/SKILL.md")" )

it "an asset with no state record is never overwritten"
( stub_dir; absent graphify,headroom; stub claude
  fake=$(mktemp -d); state=$fake/state
  : > "$state"
  mkdir -p "$LOADOUT_ROOT/skills/example-asset" "$fake/.claude/skills/example-asset"
  trap 'rm -rf "$LOADOUT_ROOT/skills/example-asset"' EXIT
  printf 'upstream\n' > "$LOADOUT_ROOT/skills/example-asset/SKILL.md"
  printf 'edited by hand\n' > "$fake/.claude/skills/example-asset/SKILL.md"
  out=$(HOME=$fake LOADOUT_STATE=$state scripts/loadout update --yes 2>&1)
  assert_contains "not recorded" "$out"
  assert_eq "edited by hand" "$(cat "$fake/.claude/skills/example-asset/SKILL.md")" )

it "a recorded, untouched asset is still updated"
( stub_dir; absent graphify,headroom; stub claude
  fake=$(mktemp -d); state=$fake/state
  mkdir -p "$LOADOUT_ROOT/skills/example-asset" "$fake/.claude/skills"
  trap 'rm -rf "$LOADOUT_ROOT/skills/example-asset"' EXIT
  printf 'v1\n' > "$LOADOUT_ROOT/skills/example-asset/SKILL.md"
  cp -R "$LOADOUT_ROOT/skills/example-asset" "$fake/.claude/skills/"
  printf 'example-asset·%s\n' "$(_asset_sum "$fake/.claude/skills/example-asset")" > "$state"
  printf 'v2\n' > "$LOADOUT_ROOT/skills/example-asset/SKILL.md"
  HOME=$fake LOADOUT_STATE=$state scripts/loadout update --yes >/dev/null 2>&1
  assert_eq "v2" "$(cat "$fake/.claude/skills/example-asset/SKILL.md")" )

# --- remove --------------------------------------------------------------
it "remove needs an entry name"
assert_status 2 scripts/loadout remove

it "remove rejects an unknown entry"
assert_status 2 scripts/loadout remove nosuchentry

it "remove uninstalls a plugin"
( stub_dir
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$STUB_CALLS"
[ "$1 $2" = "plugin list" ] && echo '[{"id": "caveman@caveman"}]'
exit 0
EOF
  chmod +x "$STUB/claude"
  HOME=$(mktemp -d) scripts/loadout remove caveman --yes >/dev/null 2>&1
  assert_contains "plugin uninstall caveman" "$(stub_calls)" )

it "remove uninstalls a python entry"
( stub_dir; stub claude; stub uv; stub graphify
  HOME=$(mktemp -d) scripts/loadout remove graphify --yes >/dev/null 2>&1
  assert_contains "uv tool uninstall graphifyy" "$(stub_calls)" )

it "remove says so when nothing is installed"
out=$( stub_dir; stub claude
       HOME=$(mktemp -d) scripts/loadout remove caveman --yes 2>&1 )
assert_contains "not installed" "$out"

it "remove mentions the cheaper alternative"
out=$( stub_dir; stub claude
       HOME=$(mktemp -d) scripts/loadout remove caveman --yes 2>&1 )
assert_contains "plugin disable" "$out"

# Unlike every other test here, this one calls remove_entry in-process rather
# than through the loadout CLI subprocess: cmd_remove prints no summary line
# to assert on, and INSTALLED is mutated inside remove_entry itself, a
# mutation that cannot survive a $(...) subshell. So the counter is asserted
# directly instead of scraping it from output.
it "a failed uninstall is not counted as removed"
( stub_dir; absent uv; stub claude; stub graphify; stub pipx 1
  export HOME=$(mktemp -d)
  OPT_YES=1
  INSTALLED=0; PROBLEMS=0
  remove_entry graphify >"$STUB/out" 2>&1
  assert_contains "FAIL" "$(cat "$STUB/out")"
  assert_eq 0 "$INSTALLED" )

it "a plugin uninstall failure is reported, not counted"
( stub_dir
  cat > "$STUB/claude" <<'INNEREOF'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$STUB_CALLS"
[ "$1 $2" = "plugin list" ] && { echo '[{"id": "caveman@caveman"}]'; exit 0; }
exit 1
INNEREOF
  chmod +x "$STUB/claude"
  out=$(HOME=$(mktemp -d) scripts/loadout remove caveman --yes 2>&1)
  assert_contains "FAIL" "$out"
  assert_contains "claude plugin uninstall caveman failed" "$out" )

# --- validation ----------------------------------------------------------
it "validate passes on the repo as it stands"
assert_status 0 scripts/validate.sh

it "validate catches a cost that drifted from the README"
( work=$(mktemp -d); cp -R "$LOADOUT_ROOT"/. "$work/"
  sed -i 's/| ~800  *|/| ~999 |/' "$work/scripts/loadout.manifest"
  cd "$work" && assert_status 1 scripts/validate.sh
  rm -rf "$work" )

it "validate catches a needs token with no registry row"
( work=$(mktemp -d); cp -R "$LOADOUT_ROOT"/. "$work/"
  sed -i 's/| claude,git  *|/| claude,git,unicorn |/' "$work/scripts/loadout.manifest"
  cd "$work" && assert_status 1 scripts/validate.sh
  rm -rf "$work" )

it "validate catches an entry with no guide"
( work=$(mktemp -d); cp -R "$LOADOUT_ROOT"/. "$work/"
  rm -rf "$work/integrations/headroom"
  cd "$work" && assert_status 1 scripts/validate.sh
  rm -rf "$work" )

it "validate catches a pipe inside a data field"
( work=$(mktemp -d); cp -R "$LOADOUT_ROOT"/. "$work/"
  printf 'bogus | plugin | x | full | claude | plugin:x | a|b | 1\n' >> "$work/scripts/loadout.manifest"
  cd "$work" && assert_status 1 scripts/validate.sh
  rm -rf "$work" )

# --- harness integrity ---------------------------------------------------
# Runs last, after every production library has been sourced, and proves the
# counters still work rather than assuming it.
#
# Deliberately does NOT verify via assert_eq/t_fail: the failure mode under
# test is exactly "t_fail got shadowed and no longer records anything", and
# an assertion that reports through t_fail cannot report that t_fail is
# broken — it would just as silently be dropped, same as any other. So this
# writes straight to $RESULTS/fail on a bad result, the same file t_fail
# writes to, bypassing the function entirely.
it "a deliberately failed assertion is recorded"
count=$(
  probe=$(mktemp -d)
  RESULTS=$probe; export RESULTS
  : > "$probe/pass"; : > "$probe/fail"
  assert_eq one two 2>/dev/null
  wc -c < "$probe/fail" | tr -d ' '
)
if [ "$count" = "1" ]; then
  t_pass
else
  printf 'FAIL: %s\n      t_fail did not record a failure (count=%s)\n' "$current" "$count" >&2
  printf 'x' >> "$RESULTS/fail"
fi

pass=$(wc -c < "$RESULTS/pass")
fail=$(wc -c < "$RESULTS/fail")
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
