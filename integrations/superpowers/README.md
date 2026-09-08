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

Both pull the same upstream repository, but not the same revision: loadout's entry has
no `sha` and tracks upstream HEAD, while `claude-plugins-official` pins a specific
commit — so the byte figures in the table below can drift on loadout's path. Loadout
vendors nothing and adds no code — what it adds is the cost accounting and the
per-skill verdicts below. Install it wherever you prefer; read this page either way.

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
- **It writes one file, and it's not what you'd guess.** The `SessionStart` hook only
  prints JSON; it touches nothing. What does write is the subagent-driven-development
  workspace script, which creates `.superpowers/sdd/.gitignore` containing `*`.
  `docs/superpowers/` — where `writing-plans` and `brainstorming` save output by
  default — is left untracked, not ignored.
- **No commands, no agents.** Everything is skills plus that one hook. There is no
  slash command to discover.
