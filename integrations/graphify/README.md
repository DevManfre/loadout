# graphify

A local code-graph indexer for Claude Code. It parses a repository with tree-sitter,
writes a knowledge graph to `graphify-out/`, and then answers structural questions
(`explain`, `path`, `query`) against that graph instead of against the files. It adds a
capability rather than changing how the agent works: the agent can ask "who calls this"
and get an answer that costs a few hundred tokens instead of a grep sweep plus three
file reads.

It is not a Claude Code plugin. It is a Python package with a CLI that writes a skill,
a `CLAUDE.md` section and two `PreToolUse` hooks into your setup.

| | |
|---|---|
| Upstream | https://github.com/Graphify-Labs/graphify |
| Author | Safi Shamsi |
| License | Apache-2.0 (`LICENSE-MIT` and `NOTICE` ship alongside) |
| Version inspected | 0.9.56 (PyPI package `graphifyy`, CLI `graphify`) |
| Contents (Claude Code) | 1 skill (41 KB `SKILL.md` + 8 reference files, 44 KB), 1 `CLAUDE.md` section, 2 `PreToolUse` hooks, 0 plugin manifest |

## Install

A plugin cannot run a package manager, so this one installs itself. `scripts/install-all.sh`
runs the commands below for you; loadout carries the cost accounting and the verdicts, nothing else.

```bash
uv tool install graphifyy        # or: pipx install graphifyy
graphify install                 # writes the skill + a CLAUDE.md pointer
```

`graphify install` alone gives you the `/graphify` skill. The always-on layer — the
graph-first `CLAUDE.md` rules and the two hooks that nudge every read and every grep —
is a second, separate command:

```bash
graphify claude install
```

Keep it to one repository instead of your user profile with `--project`, which writes
`.claude/skills/graphify/SKILL.md` under the current directory:

```bash
graphify install --project
```

Avoid `pip install`: the skill resolves its Python runtime through
`graphify-out/.graphify_python`, and a `pip`-installed package outside an isolated
environment surfaces as `ModuleNotFoundError: No module named 'graphify'`.

## Token economy

Three separate budgets, and they behave differently. Every figure below was measured on
version 0.9.56, not estimated from the upstream README.

**Always on, per session.** Paid whether or not a graph exists.

| Source | Size | ≈ tokens |
|---|---|---|
| Skill description in the skill index | 353 chars | ~90 |
| `CLAUDE.md` pointer written by `graphify install` | 211 chars | ~55 |
| `CLAUDE.md` rules written by `graphify claude install` | 772 chars | ~195 |

Roughly 340 tokens per session with the always-on layer installed, ~145 without it. The
`CLAUDE.md` share is re-injected on every compaction, like any other project memory.

**Per tool call, while `graphify-out/graph.json` exists.** This is the cost people miss.
The hooks match `Bash|Grep` and `Read|Glob`, so they fire on the agent's two most
frequent actions, and the injected text is a mandate, not a hint.

| Hook | Fires on | Injected | ≈ tokens |
|---|---|---|---|
| `hook-guard search` | every Bash search command and every Grep call | 190 chars | ~48 |
| `hook-guard read` | every Read and Glob of indexed, fresh, in-project code | 400 chars | ~100 |
| `hook-guard read` (stale) | same, when the file changed after the last build | 239 chars | ~60 |
| `hook-guard read --strict` | first such read per session — a hard `deny` | 421 chars | ~105 |

A 30-read, 10-grep session pays ~3.5k tokens in nudges alone. That is the price of the
behavioural change, and it is only worth paying if the agent then actually queries the
graph instead of reading anyway.

**On demand.** The skill body enters context only when `/graphify` is invoked.

| File | Size | ≈ tokens |
|---|---|---|
| `SKILL.md` | 41.2 KB | ~10.3k |
| `references/query.md` | 13.5 KB | ~3.4k |
| `references/update.md` | 10.4 KB | ~2.6k |
| `references/extraction-spec.md` | 8.0 KB | ~2.0k |
| `references/exports.md` | 3.4 KB | ~0.8k |
| `references/transcribe.md` | 3.2 KB | ~0.8k |
| `references/add-watch.md` | 2.5 KB | ~0.6k |
| `references/github-and-merge.md` | 2.2 KB | ~0.5k |
| `references/hooks.md` | 1.3 KB | ~0.3k |

The 41 KB `SKILL.md` is the single most expensive skill body loadout documents. Invoking
`/graphify` costs about as much as three compactions' worth of always-on overhead, so
build the graph deliberately and then stay on the CLI: `graphify explain` and
`graphify path` are plain shell commands and do not load the skill at all.

## What a build actually costs

Measured on graphify's own repository — 483 code files, `--code-only`, 4 extraction
workers, no API key:

| | |
|---|---|
| Wall clock, cold build | 4m 10s |
| Wall clock, `graphify update .` after touching one file | 41s |
| Graph | 12,504 nodes, 26,145 edges, 639 communities |
| `graph.json` | 15.4 MB |
| `GRAPH_REPORT.md` | 236 KB — **~59k tokens, never read it whole** |
| `graphify-out/` on disk | 34 MB (17 MB of it cache) |
| LLM credits for code | 0 — tree-sitter AST, fully local |

Code is free. Everything else is not: the same repository has 368 docs, 1 paper and 5
images, and extraction refuses to start without `GEMINI_API_KEY`, `ANTHROPIC_API_KEY`,
`OPENAI_API_KEY` or an equivalent unless you pass `--code-only`. The "0 LLM credits"
headline is true for code and only for code.

## Command-by-command verdict

Measured output sizes, same repository and same graph.

| Command | Output | Verdict | Why |
|---|---|---|---|
| `graphify explain "<symbol>"` | 1.2 KB, ~290 tokens | Keep — this is the whole value | 14 edges with direction, `EXTRACTED`/`INFERRED` confidence and `file:line` for each. Cheaper and more complete than grep plus two file reads. |
| `graphify path "<A>" "<B>" --undirected` | ~130 bytes | Keep | Answers "how are these two connected" in one line. Pass `--undirected` or it will tell you there is no path when there plainly is one. |
| `graphify update .` | — | Keep, but run it yourself | 41s and it shifts the graph (12.5k → 15.5k nodes, 639 → 1008 communities on a one-file touch). Cheap in tokens, not in wall clock. |
| `graphify query "<question>"` | 6.7 KB, ~1.7k tokens | Situational, and often a loss | Self-truncates at a ~2000-token budget. On "how does the hook guard nudge the agent?" it returned 61 of 190 matched nodes, mostly test docstrings; `grep -rn hook_guard --include=*.py` cost 844 bytes (~210 tokens) and answered better. Use it for orientation in an unfamiliar repo, not for questions you can already name a symbol for. |
| `GRAPH_REPORT.md` | 236 KB | Skip unless you slice it | At ~59k tokens it is a context-window event. The skill says "broad architecture review only" and means it. |
| `graph.html` | — | Keep, for humans | Zero token cost: it is a browser artifact, not agent context. Above 5,000 nodes it aggregates to community level. |
| The `PreToolUse` hooks | ~48–105 tokens per tool call | Situational, measure before you keep | They are the difference between a graph you own and a graph the agent uses. They also tax every read for the rest of the session. Install them per project, not globally. |
| `--strict` mode | 421 chars, once per session | Situational | Denies the first raw read per session and redirects to `graphify query`. It can never strand the agent, but it does spend a turn. |

## Interaction with loadout

graphify is a capability, superpowers is a process. They do not overlap and they compose
in one direction: a process skill decides what gets built, graphify answers the
structural questions raised along the way. In practice the graph is at its most useful
during `brainstorming` and `systematic-debugging`, where the question is "what does this
touch" rather than "what does this line do".

Precedence is unchanged: direct instructions, then `CLAUDE.md` / `AGENTS.md`, then skill
workflows, then default behaviour. Note that graphify installs *into* `CLAUDE.md`, which
puts it one rung above any skill's own preferences — including its own.

This repository is a poor fit for it, and that is worth stating plainly: loadout is
prose and JSON, no application code. `--code-only` would index almost nothing, and a
full extraction would bill the whole catalog through a model API.

## Gotchas

- **The PyPI package is `graphifyy`, with two y's.** The CLI is still `graphify`. Other
  `graphify*` packages on PyPI are unaffiliated.
- **`uvx graphify …` fails.** `uv tool run` reads the *package* name:
  `uvx --from graphifyy graphify install`.
- **`graphify install` and `graphify claude install` are different installs.** The first
  gives you a skill you invoke. The second is the always-on layer — `CLAUDE.md` rules
  plus the two hooks. Installing only the first means you pay ~145 tokens per session
  and nothing changes until you type `/graphify`.
- **A stale graph is worse than no graph.** The read hook softens its wording when the
  target file changed after the last build, but the graph itself keeps serving old edges
  until you run `graphify update .`. Its git hook (`graphify hook install`) rebuilds on
  commit and on branch checkout, which covers commits and not the hour of editing before
  them.
- **`path` is directed by default** and will report no path between a function and its
  own caller. `--undirected` is almost always what you want.
- **Extraction refuses to start on a mixed repository without an API key.** It exits with
  a list of the keys it accepts. `--code-only` is the free path; it skips docs, papers
  and images entirely.
- **Missing grammars fail quietly per language.** On its own repository, `.sql`, `.dm`,
  `.lisp`, `.robot` and `.resource` files contributed nothing to the graph — each needs
  its own extra (`graphifyy[sql]`, `[dm]`, `[commonlisp]`, `[robot]`). The build prints a
  warning and carries on, so a language can be silently absent from a graph you trust.
- **`graphify-out/` is 34 MB of build artefact.** Add it to `.gitignore` before the
  first build, not after.
