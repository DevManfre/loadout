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
| `probe` | How to detect an install: `plugin:<name>`, `bin:<command>`, or `proxy:<VAR>` — a live HTTP answer at the URL the variable names, for a process serving this machine from somewhere PATH cannot see (a container, the Windows host under WSL). When the variable is not in the environment — it usually lives in Claude Code's settings, not the shell profile — the probe reads it from `.claude/settings.local.json`, `.claude/settings.json`, then `~/.claude/settings.json`. Comma-separated alternatives; any one satisfied counts as installed. `update` and `remove` act only when a non-`proxy:` probe matches — a remote process is managed where it runs |
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

## What upstream publishes now

The menu's third row state — `[^]`, installed but behind — needs a pin the machine
cannot produce on its own, so `entry_latest` asks upstream. Where it asks depends on
the entry, and the difference is deliberate:

| kind | the pin an install or update would land on |
|---|---|
| `pypkg` | `https://pypi.org/pypi/<package>/json`, the `version` in its metadata (the source column's `[extras]` are stripped first) |
| `plugin` from a `name=owner/repo` marketplace | `git ls-remote https://github.com/<owner>/<repo> HEAD` — the marketplace *is* the plugin's repo, so its head is what installs next |
| `plugin` from a plain marketplace name | the entry's `source.sha` in `~/.claude/plugins/marketplaces/<market>/.claude-plugin/marketplace.json` — a marketplace that pins its entries hands out its pin, and an upstream that has moved past it is not an update anybody here can take |

An entry reachable only through a proxy has no local pin at all, so `entry_version`
asks the proxy: `<ANTHROPIC_BASE_URL>/health`, the `version` key of its body. That is
what lets a container running 0.27.0 against an upstream at 0.37.0 show up as behind
instead of as a bare "remote"; the row it produces is read-only, because the machine
that could act on it is not this one.

A sha is then turned into something readable by reading `.claude-plugin/plugin.json`
at that sha over `raw.githubusercontent.com`; a plugin that declares no `version`
keeps its 12-character sha, which is also the form `entry_version` reports for it.

Two rules hold this together. **Unknown is an answer**: any failure — offline, a
timeout, an unparseable manifest — answers `-`, and an entry with an unknown upstream
stays a plain `[=]` row. A false update row walks somebody off a measured pin, and a
false "current" hides the release they opened the menu to find. **Nothing is
remembered**: like install state, the pin is probed per run, never cached to disk.

The seams: `LOADOUT_NO_NET=1` (what `--offline` sets, and what `scripts/selftest.sh`
exports for the whole suite) turns every upstream probe off; `LOADOUT_NET_TIMEOUT`
(default 4) caps each call. All of them run at once, in `entry_latest_all`, so the
menu waits for the slowest probe rather than the sum of them.

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
