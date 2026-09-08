# Superpowers Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `superpowers` as loadout's first catalog asset, and lock the plugin index shape so every later asset kind installs through one command.

**Architecture:** Two commits. First a structural validator under `scripts/` — this repo has no test runner, and the spec's acceptance criteria are mechanical (JSON parses, paths resolve, no duplicate entries), so the validator is the test cycle. Then one atomic commit carrying the asset docs, the index, and both root READMEs together, because CLAUDE.md requires those three to land in the same commit.

**Tech Stack:** bash, `python3` (JSON parsing — present on this machine), markdown. No package manifest, no dependencies added.

**Spec:** `docs/specs/2026-09-08-superpowers-integration-design.md`

## Global Constraints

- All shipped docs and all commit messages are English. `README-it.md` is the only Italian file, and it is a mirror, never an independent edit.
- Commit format: `<gitmoji> <SCOPE> - <subject>`, ` - ` separator, subject lowercase, no trailing period, whole line ≤ 72 chars. One gitmoji as a Unicode glyph. No co-author or attribution trailer of any kind.
- Adding a shipped asset is one commit covering the asset, `.claude-plugin/marketplace.json`, and the README catalog in every language.
- Nothing under `.claude/` is ever listed in `marketplace.json` or in the README catalog.
- Nothing is vendored from upstream: no copy of any superpowers skill lands under `skills/`.
- Marketplace `source` kind for an external repo is `url`. Not `github`.
- No `sha` pin on the superpowers entry.
- Upstream facts, to be reproduced verbatim wherever quoted: repo `https://github.com/obra/superpowers`, author Jesse Vincent, license MIT, version inspected 6.3.0, contents 14 skills / 0 commands / 0 agents / 1 SessionStart hook.
- Token figures come from spec §2.1 and must match it exactly. Token estimates use bytes ÷ 4.

---

### Task 1: Structural validator

**Files:**
- Create: `scripts/validate.sh`
- Test: the script is its own test — it is run against the repo and must fail before Task 2 and pass after.

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/validate.sh`, executable, exit 0 when the repo is structurally valid and exit 1 with one `FAIL: <reason>` line per problem on stderr. Task 2 relies on this exact contract: it runs `bash scripts/validate.sh` and expects exit 0.

Checks it performs, one per spec §7 bullet:
1. `.claude-plugin/marketplace.json` exists and parses as JSON.
2. Every entry in `.plugins[]` has non-empty `name` and `description`.
3. No `name` appears twice in `.plugins[]`.
4. Every local `source` (a string starting with `.`, or an object whose `source` is a local path) resolves to an existing directory on disk.
5. Every object `source` uses a kind from the allowed set `url`, `git-subdir`.
6. Every `skills/*/SKILL.md`, `agents/*.md` and `integrations/*/README.md` that exists has YAML frontmatter opening on line 1 with `---` — SKILL.md and agent files additionally must carry `name:` and `description:` keys. (`integrations/*/README.md` is plain markdown and is exempt from the key check; it is checked for existence only.)
7. Every relative markdown link in `README.md` and in each `README-<lang>.md` resolves to an existing path.

- [ ] **Step 1: Write the validator**

```bash
mkdir -p scripts
cat > scripts/validate.sh <<'EOF'
#!/usr/bin/env bash
# Structural validation for the loadout repo.
# There is no build and no test runner here: the assets and their index are
# the product, so "valid" means the index parses, every path it names exists,
# nothing is listed twice, and every doc link resolves.
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }

MARKETPLACE=.claude-plugin/marketplace.json

if [ ! -f "$MARKETPLACE" ]; then
  fail "$MARKETPLACE is missing"
else
  python3 - "$MARKETPLACE" <<'PY'
import json, os, sys

path = sys.argv[1]
fails = []

try:
    with open(path) as fh:
        data = json.load(fh)
except json.JSONDecodeError as exc:
    print(f"FAIL: {path} does not parse: {exc}", file=sys.stderr)
    raise SystemExit(1)

plugins = data.get("plugins")
if not isinstance(plugins, list) or not plugins:
    fails.append(f"{path} has no plugins array")
    plugins = []

ALLOWED_KINDS = {"url", "git-subdir"}
seen = {}

for i, plugin in enumerate(plugins):
    label = plugin.get("name") or f"entry {i}"
    for key in ("name", "description"):
        if not plugin.get(key):
            fails.append(f"{label}: missing or empty '{key}'")

    name = plugin.get("name")
    if name:
        if name in seen:
            fails.append(f"{name}: listed twice (entries {seen[name]} and {i})")
        else:
            seen[name] = i

    source = plugin.get("source")
    if source is None:
        fails.append(f"{label}: missing 'source'")
    elif isinstance(source, str):
        if not os.path.isdir(source):
            fails.append(f"{label}: local source '{source}' does not resolve")
    elif isinstance(source, dict):
        kind = source.get("source")
        if kind in ALLOWED_KINDS:
            if not source.get("url"):
                fails.append(f"{label}: source kind '{kind}' without a url")
        elif isinstance(kind, str) and kind.startswith("."):
            if not os.path.isdir(kind):
                fails.append(f"{label}: local source '{kind}' does not resolve")
        else:
            fails.append(f"{label}: source kind '{kind}' is not allowed")
    else:
        fails.append(f"{label}: 'source' is neither a string nor an object")

for line in fails:
    print(f"FAIL: {line}", file=sys.stderr)
raise SystemExit(1 if fails else 0)
PY
  [ $? -ne 0 ] && fails=$((fails + 1))
fi

# Frontmatter on shipped skills and agents.
for skill in skills/*/SKILL.md; do
  [ -e "$skill" ] || continue
  [ "$(head -n 1 "$skill")" = "---" ] || fail "$skill: no frontmatter on line 1"
  grep -q '^name:' "$skill" || fail "$skill: frontmatter has no 'name'"
  grep -q '^description:' "$skill" || fail "$skill: frontmatter has no 'description'"
done

for agent in agents/*.md; do
  [ -e "$agent" ] || continue
  [ "$(head -n 1 "$agent")" = "---" ] || fail "$agent: no frontmatter on line 1"
  grep -q '^name:' "$agent" || fail "$agent: frontmatter has no 'name'"
  grep -q '^description:' "$agent" || fail "$agent: frontmatter has no 'description'"
done

# Every integration directory must document itself.
for dir in integrations/*/; do
  [ -e "$dir" ] || continue
  [ -f "$dir/README.md" ] || fail "$dir: no README.md"
done

# Relative links in every root README must resolve.
for readme in README.md README-*.md; do
  [ -e "$readme" ] || continue
  grep -oE '\]\([^)#][^)]*\)' "$readme" \
    | sed -E 's/^\]\(//; s/\)$//; s/#.*$//' \
    | while read -r link; do
        case "$link" in
          http*|mailto:*|"") continue ;;
        esac
        [ -e "$link" ] || echo "FAIL: $readme: link '$link' does not resolve" >&2
      done
done

# The link loop above runs in a subshell, so re-count its output.
link_fails=$(for readme in README.md README-*.md; do
  [ -e "$readme" ] || continue
  grep -oE '\]\([^)#][^)]*\)' "$readme" \
    | sed -E 's/^\]\(//; s/\)$//; s/#.*$//' \
    | while read -r link; do
        case "$link" in
          http*|mailto:*|"") continue ;;
        esac
        [ -e "$link" ] || echo x
      done
done | wc -l)
fails=$((fails + link_fails))

if [ "$fails" -gt 0 ]; then
  echo "$fails structural problem(s)" >&2
  exit 1
fi
echo "ok"
EOF
chmod +x scripts/validate.sh
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/validate.sh; echo "exit=$?"`

Expected: FAIL, because `marketplace.json` does not exist yet.

```
FAIL: .claude-plugin/marketplace.json is missing
1 structural problem(s)
exit=1
```

If it prints `ok`, the validator is not checking anything — stop and fix it before continuing.

- [ ] **Step 3: Verify it catches a bad index too**

Run:

```bash
mkdir -p .claude-plugin
printf '{ "plugins": [ {"name":"a","description":"d","source":"./nope"} ] }' > .claude-plugin/marketplace.json
bash scripts/validate.sh; echo "exit=$?"
```

Expected: FAIL naming the unresolvable local source.

```
FAIL: a: local source './nope' does not resolve
```

Then remove the probe so Task 2 starts from a clean slate:

```bash
rm .claude-plugin/marketplace.json
```

- [ ] **Step 4: Commit**

```bash
git add scripts/validate.sh
git commit -m "🔨 SCRIPTS - check the index parses, resolves and lists nothing twice"
```

---

### Task 2: The superpowers catalog entry

One commit. CLAUDE.md requires the asset, the index, and every README language to land together, so every step below stages files and only the last step commits.

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Create: `.claude-plugin/plugin.json`
- Create: `integrations/superpowers/README.md`
- Create: `integrations/superpowers/README-it.md`
- Modify: `README.md` — append a `## Catalog` section
- Modify: `README-it.md` — mirror of the same section
- Test: `bash scripts/validate.sh` must print `ok` and exit 0

**Interfaces:**
- Consumes: `scripts/validate.sh` from Task 1, exit 0 on a valid repo.
- Produces: the index shape every later asset extends — an external plugin as `{"source":{"source":"url","url":"…"}}`, loadout's own assets as `{"source":"./"}`, and a future MCP server as `{"source":"./integrations/<name>"}`.

- [ ] **Step 1: Write the index**

```bash
mkdir -p .claude-plugin
cat > .claude-plugin/marketplace.json <<'EOF'
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "loadout",
  "description": "Curated toolkit for AI coding agents: skills, sub-agents, workflows, integrations.",
  "owner": {
    "name": "Alessio Manfredini",
    "url": "https://github.com/DevManfre"
  },
  "plugins": [
    {
      "name": "loadout",
      "description": "Loadout's own skills and sub-agents. Empty for now: the entry exists so the install path is stable from the first release.",
      "author": {
        "name": "Alessio Manfredini"
      },
      "category": "development",
      "source": "./",
      "homepage": "https://github.com/DevManfre/loadout"
    },
    {
      "name": "superpowers",
      "description": "Process skills: brainstorming, TDD, systematic debugging, subagent-driven dev, skill authoring.",
      "author": {
        "name": "Jesse Vincent"
      },
      "category": "development",
      "source": {
        "source": "url",
        "url": "https://github.com/obra/superpowers.git"
      },
      "homepage": "https://github.com/obra/superpowers"
    }
  ]
}
EOF
```

- [ ] **Step 2: Write the root plugin manifest**

This is what makes `source: "./"` installable. It sits beside the index, in the same `.claude-plugin/` directory.

```bash
cat > .claude-plugin/plugin.json <<'EOF'
{
  "name": "loadout",
  "description": "Curated skills, sub-agents and workflows for AI coding agents, with token cost measured rather than assumed.",
  "version": "0.1.0",
  "author": {
    "name": "Alessio Manfredini"
  },
  "homepage": "https://github.com/DevManfre/loadout",
  "repository": "https://github.com/DevManfre/loadout",
  "license": "MIT",
  "keywords": [
    "skills",
    "agents",
    "workflows",
    "token-economy",
    "catalog"
  ]
}
EOF
```

- [ ] **Step 3: Run the validator to see the index accepted**

Run: `bash scripts/validate.sh; echo "exit=$?"`

Expected: `ok` and `exit=0`. The index now parses, `./` resolves, and no name is
listed twice. The `integrations/*/` and README-link loops find nothing to reject yet,
so they stay silent. If anything is reported against `marketplace.json`, fix it before
moving on — later steps only add files and will not repair a malformed index.

- [ ] **Step 4: Write the integration guide**

Six sections, in this order, per spec §5.2.

```bash
mkdir -p integrations/superpowers
cat > integrations/superpowers/README.md <<'EOF'
# superpowers

Process skills for Claude Code: it front-loads brainstorming before creative work,
enforces red/green TDD, drives debugging systematically instead of by guesswork, runs
implementation through subagents with review gates, and teaches the model to author and
test new skills. It changes *how* the agent works rather than adding a capability.

| | |
|---|---|
| Upstream | https://github.com/obra/superpowers |
| Author | Jesse Vincent |
| License | MIT |
| Version inspected | 6.3.0 |
| Contents | 14 skills, 0 commands, 0 agents, 1 `SessionStart` hook |

## Install

Through loadout:

```
/plugin marketplace add DevManfre/loadout
/plugin install superpowers@loadout
```

Straight from Anthropic's own directory, which also carries it:

```
/plugin install superpowers@claude-plugins-official
```

Both pull the same upstream repository. Loadout vendors nothing and adds no code — what
it adds is the cost accounting and the per-skill verdicts below. Install it wherever you
prefer; read this page either way.

## Token economy

One cost is unconditional. The plugin's `SessionStart` hook matches
`startup|clear|compact` and injects the full text of `using-superpowers` — 3.1 KB, about
800 tokens — at every session start, at every `/clear`, and after **every compaction**.
On a long session with several compactions you pay it several times.

Everything else is on demand: a skill's body enters context only when it is invoked.
Sizes below are `SKILL.md` alone, and the full directory where a skill carries reference
files that it may pull in as well.

| Skill | SKILL.md | ≈ tokens | Full tree |
|---|---|---|---|
| brainstorming | 15.5 KB | ~3.9k | 80 KB |
| dispatching-parallel-agents | 6.1 KB | ~1.5k | 6 KB |
| executing-plans | 2.3 KB | ~0.6k | 2 KB |
| finishing-a-development-branch | 7.8 KB | ~1.9k | 8 KB |
| receiving-code-review | 6.2 KB | ~1.6k | 6 KB |
| requesting-code-review | 3.0 KB | ~0.7k | 9 KB |
| subagent-driven-development | 32.3 KB | ~8.1k | 57 KB |
| systematic-debugging | 9.5 KB | ~2.4k | 41 KB |
| test-driven-development | 9.0 KB | ~2.3k | 17 KB |
| using-git-worktrees | 6.8 KB | ~1.7k | 7 KB |
| using-superpowers | 3.1 KB | ~0.8k | 17 KB |
| verification-before-completion | 3.6 KB | ~0.9k | 4 KB |
| writing-plans | 7.1 KB | ~1.8k | 9 KB |
| writing-skills | 26.4 KB | ~6.6k | 107 KB |

Read that as a budget, not a warning. `verification-before-completion` costs under a
thousand tokens and can save an entire wrong-direction session. `writing-skills` costs
seven thousand and is worth it exactly once per skill you author.

## Skill-by-skill verdict

| Skill | Size | Verdict | Why |
|---|---|---|---|
| using-superpowers | 3.1 KB | Keep — you have no choice | The hook injects it every session. It is the index that makes the others fire. |
| brainstorming | 15.5 KB | Keep | The highest-leverage skill in the set: it stops implementation until you approve a design. Most wasted agent work comes from skipping this. |
| verification-before-completion | 3.6 KB | Keep | Cheapest real win here. Forces evidence before any "it works" claim. |
| systematic-debugging | 9.5 KB | Keep | Turns "try a fix and see" into a hypothesis loop. Pays for itself on the first non-obvious bug. |
| test-driven-development | 9.0 KB | Keep, if you have a test runner | Strict red/green. In a repo with no tests to run it is friction with no payoff. |
| requesting-code-review | 3.0 KB | Keep | Small, and it hands the reviewer a crafted context instead of your whole transcript. |
| receiving-code-review | 6.2 KB | Situational | Useful when review feedback is wrong and you would otherwise agree with it anyway. Skip if you review your own work. |
| writing-plans | 7.1 KB | Situational | Earns its keep on multi-session work. Overhead on a one-file change. |
| executing-plans | 2.3 KB | Situational | Only after `writing-plans` produced a plan. Cheap enough to be free. |
| subagent-driven-development | 32.3 KB | Situational, and expensive | Strong for long plans with independent tasks. The single biggest context cost in the set — do not invoke it to do one thing. |
| dispatching-parallel-agents | 6.1 KB | Situational | Only pays off with genuinely independent, state-free tasks. |
| using-git-worktrees | 6.8 KB | Situational | Worth it for feature work that must not disturb your workspace. Ignore it for edits you would commit straight away. |
| finishing-a-development-branch | 7.8 KB | Situational | Codifies the merge/rebase/PR decision at the end of a branch. Skip if that decision is already habit. |
| writing-skills | 26.4 KB | Skip until you author a skill | Excellent and very large. Invoke it deliberately, never in passing. |

## Interaction with loadout

Superpowers sets the *process*; loadout's own assets do the domain work inside it. When
both apply, the process skill goes first — brainstorm, then implement.

Precedence, from strongest to weakest: your direct instructions, then `CLAUDE.md` /
`AGENTS.md`, then skill workflows, then default behaviour. A repo convention in
`CLAUDE.md` beats anything a skill prescribes; that is by design and superpowers says so
itself.

In this repository, `brainstorming` and `commit-convention` compose exactly that way:
brainstorming decides what gets built, `commit-convention` decides how the commit is
worded, and neither overrides the other.

## Gotchas

- **The hook fires on compaction.** Not only at startup. Long sessions pay the
  `using-superpowers` injection repeatedly.
- **`brainstorming` is a hard gate.** It will refuse to write code until you have
  approved a stated intent, including for changes you consider trivial. That is the
  point, and it is occasionally infuriating.
- **The skills self-invoke aggressively.** `using-superpowers` instructs the model to
  invoke a skill whenever there is even a slim chance one applies. Expect more skill
  invocations than you would choose by hand.
- **It writes to your repo.** The `SessionStart` hook adds a `.gitignore` entry for
  `docs/superpowers`, its scratch directory for specs and plans. Harmless, but it shows
  up as an untracked change on a clean tree.
- **No commands, no agents.** Everything is skills plus that one hook. There is no
  slash command to discover.
EOF
```

- [ ] **Step 5: Add the catalog section to the canonical README**

```bash
cat >> README.md <<'EOF'

## Install

Add the marketplace once:

```
/plugin marketplace add DevManfre/loadout
```

Then install any catalog entry by name:

```
/plugin install <name>@loadout
```

The same command covers every kind of asset — loadout's own skills and sub-agents,
a curated third-party plugin, or an MCP server. Third-party binaries are the one
exception: a plugin cannot run a package manager, so those ship with an install script.

## Catalog

### Integrations

| Name | What it does | Always-on cost | Docs |
|---|---|---|---|
| superpowers | Process skills: brainstorming gate, red/green TDD, systematic debugging, subagent-driven development, skill authoring | ~800 tokens per session start, `/clear` and compaction | [guide](integrations/superpowers/README.md) |
EOF
```

- [ ] **Step 6: Mirror both READMEs into Italian**

Invoke the repo's own **readme-sync** skill and have it propagate the new `## Install`
and `## Catalog` sections from `README.md` into `README-it.md`, and create
`integrations/superpowers/README-it.md` as a full mirror of
`integrations/superpowers/README.md`.

Rules the mirror must respect:
- Section-for-section correspondence. Same headings in the same order, translated.
- Code blocks, commands, URLs, file paths, table numbers and skill names stay verbatim.
- The verdict column translates its wording (`Keep`, `Situational`, `Skip`) but keeps
  the same verdict for the same skill.
- The Italian catalog table links to `integrations/superpowers/README-it.md`, not to the
  English guide.

- [ ] **Step 7: Run the validator**

Run: `bash scripts/validate.sh; echo "exit=$?"`

Expected:

```
ok
exit=0
```

If a link fails to resolve, the usual cause is the Italian catalog row still pointing at
the English guide, or `README-it.md` linking a path that was never created.

- [ ] **Step 8: Verify the index by hand as well**

Run:

```bash
python3 -c "
import json
d = json.load(open('.claude-plugin/marketplace.json'))
print([p['name'] for p in d['plugins']])
"
ls .claude-plugin integrations/superpowers
```

Expected: `['loadout', 'superpowers']`, and both README languages present in the
integration directory.

- [ ] **Step 9: Commit — everything together**

```bash
git add .claude-plugin integrations README.md README-it.md
git commit -F - <<'MSG'
✨ INTEGRATION - carry superpowers with its cost measured, not assumed

Superpowers already ships in claude-plugins-official, so this entry is
curation rather than distribution: nothing is vendored, and the guide
earns its place by stating the always-on hook cost and giving a verdict
per skill.

The index takes its final shape here. An external plugin arrives as a
url source, loadout's own assets as "./", and a future MCP server as
"./integrations/<name>" — one install command for all three.
MSG
```

- [ ] **Step 10: Confirm the tree is clean**

Run: `git status --short && bash scripts/validate.sh`

Expected: no output from `git status`, `ok` from the validator.

---

## Notes for the executor

- **`docs/superpowers/` is git-ignored here.** The superpowers hook put it in
  `.gitignore`. This repo's specs live in `docs/specs/` and plans in `docs/plans/`.
- **No test framework exists and none should be added.** `scripts/validate.sh` is the
  whole verification story, per CLAUDE.md: "validation is structural".
- **Do not create `skills/`, `agents/` or `workflows/` directories.** They stay absent
  until a real asset needs them. The validator tolerates their absence by design.
- **`scripts/install.sh` is out of scope.** Spec §6 defers it to the first
  binary-shaped asset.
