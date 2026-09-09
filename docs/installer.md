# The installer

`scripts/loadout` is the one entrypoint for installing, updating, inspecting and
removing everything in the catalog. `scripts/install-all.sh` is a three-line shim
that execs `scripts/loadout install "$@"`, kept because that is the path both
READMEs and a lot of muscle memory already name.

Everything the installer knows about the catalog lives in two plain, `|`-delimited
data files. This page documents those files, how to add an entry to them, how the
dependency registry's severities and platform gate work, and how to add a test to
`scripts/selftest.sh`.

## `scripts/loadout.manifest`

One row per installable entry.

| Column | Meaning |
|---|---|
| `name` | The entry's id — what `--only`, `--except` and `remove <entry>` take |
| `kind` | `plugin` (Claude Code CLI) or `pypkg` (installed with `uv` or `pipx`) |
| `source` | Marketplace name, or `name=owner/repo` when the marketplace needs adding; the package name for a `pypkg` |
| `presets` | Comma-separated presets this entry belongs to (`core`, `full`) |
| `needs` | Comma-separated dependency tokens, matched against `scripts/loadout.deps` |
| `probe` | How to detect an install: `plugin:<name>` or `bin:<command>` |
| `cost_session` | The always-on token figure — must match, digit for digit, what the README catalog row leads with, in every language. `scripts/validate.sh` enforces this |
| `measured` | The pin (plugin version, package version) the `cost_session` figure was measured on |

`needs` can name a group token such as `uv/pipx` — one token standing in for "either
satisfies this" — rather than forcing two separate rows for the same requirement.

## `scripts/loadout.deps`

One row per dependency token, shared across every entry that names it.

| Column | Meaning |
|---|---|
| `token` | The id a manifest row's `needs` column references |
| `severity` | `block`, `warn` or `runtime` — see below |
| `probe` | How to detect the dependency: `cmd:<name>`, `anycmd:<a>,<b>` (either satisfies it), or `env:<VAR>` |
| `when` | `always`, or `platform:<uname -s>/<uname -m>` to scope the token to one platform |
| `why` | Why the entry needs it, printed by `doctor` and by a blocked menu row |
| `fix` | What to run or install to satisfy it |
| `docs` | A path in this repo with more detail; `scripts/validate.sh` checks that it resolves |

### The three severities

- **`block`** — missing, the entry is taken out of the install menu entirely. It is
  still listed, numbered, with `d <n>` available to explain why.
- **`warn`** — missing, the entry installs anyway but is reported as degraded.
- **`runtime`** — never blocks or warns at install time; it shows up later, in
  `scripts/loadout status`, as an entry that is installed but not in the path (for
  example headroom installed with nothing pointing `ANTHROPIC_BASE_URL` at it).

### The `when` field

Most tokens apply on every machine (`when` is `always`). A token can instead be
scoped to one platform with `platform:<uname -s>/<uname -m>` — for example
`platform:Darwin/x86_64` for the dependency that only matters on Intel macOS, because
no native ONNX wheel exists for that combination. `dep_applies()` in
`scripts/lib/probe.sh` is the one place that reads this field; a token whose `when`
does not match the current platform is treated as satisfied, whatever `probe` says.

## Adding an entry

The measurement procedure — pinning a revision, measuring it on a real machine,
judging it item by item — is the **catalog-entry** skill's job
(`.claude/skills/catalog-entry/SKILL.md`); read that first. Once a figure is
measured, wiring it into the installer is mechanical:

1. Add a row to `scripts/loadout.manifest` with the measured `cost_session` and
   `measured` pin.
2. Add any new dependency tokens the entry needs to `scripts/loadout.deps` — reuse an
   existing token (`uv/pipx`, `claude`, `git`, …) rather than adding a near-duplicate.
3. Add the matching catalog row to `README.md`, whose `Always-on cost` cell must lead
   with the same figure as the manifest's `cost_session` — then propagate to
   `README-it.md` with the **readme-sync** skill.
4. Run `scripts/validate.sh` and `scripts/selftest.sh`. The former checks that the
   manifest and every README agree and that every `docs` path resolves; the latter
   exercises the entry through `scripts/loadout` against a faked environment.

## Adding a test to `scripts/selftest.sh`

`scripts/selftest.sh` is a small, dependency-free test file, not a framework. A test
is three pieces:

```bash
it "manifest keeps spaces inside a field"
assert_contains "+60/prompt" "$(manifest_field caveman 7)"
```

`it "<name>"` names the test that follows; `assert_eq`, `assert_contains` and
`assert_status` each record one pass or one failure under that name. To fake the
machine a test runs against, call `stub_dir` once to put an empty directory at the
front of `PATH`, then `stub <name> [exit-code]` to drop a fake executable there, and
`absent a,b` (sets `LOADOUT_FAKE_ABSENT`) to make specific commands look missing to
`have_cmd`. `LOADOUT_FAKE_PLATFORM=Darwin/x86_64` fakes `uname` for a `when` test. No
test in this file touches the real machine or the network.

Run the file directly — `scripts/selftest.sh` — and check the last line reads
`N passed, 0 failed`.

## Two facts worth knowing

**~688 tokens or ~800 — neither is a typo.** `claude plugin details superpowers`
projects superpowers' always-on cost at ~688 tokens, a static per-component estimate
computed from the plugin's manifest. The catalog's own README figure — ~800 tokens
per session start, `/clear` and compaction — is measured end to end on a real
session. They are two different, both defensible, methods of pricing the same
plugin, and `scripts/loadout status` prints a pointer to the former rather than
trying to reproduce it, so a reader who sees both numbers should know which is which
rather than assume one is wrong.

**Why the counters are named `t_pass` / `t_fail`.** `scripts/selftest.sh` sources the
installer's own libraries to test them for real, and `scripts/lib/actions.sh` already
defines `_ok`, `_skip` and `_fail` for its own install/update tallies. An earlier
version of the harness used those same names for its pass/fail counters; sourcing
`actions.sh` silently replaced them, so the suite kept printing "0 failed" while a
real failure went uncounted. The `t_` prefix exists so that collision cannot recur
unnoticed.
