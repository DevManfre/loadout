---
name: commit-convention
description: Use when writing any commit message in this repo, staging changes, or being asked to commit. Enforces the house format `<gitmoji> <SCOPE> - <subject>` in English, with gitmoji chosen by its official meaning and a free-form uppercase scope.
---

# Commit convention

## Format

```
<gitmoji> <SCOPE> - <subject>
```

Real examples from this project's history:

```
📝 ROADMAP - record the slice as shipped and name what comes next
✨ API - serve status badges and a widget summary
✅ VISUAL - screenshot every view in both themes and locales
💄 UI - mute a provider, set the damping threshold, pick a time zone
🔧 VISUAL - freeze the server's clock too, not only the browser's
✅ GEO CARD - assert the sentence, not a digit that the calendar can collide with
```

## Rules

**Language.** English only, always — regardless of the language of the conversation.

**Emoji.** One gitmoji, as a Unicode glyph (`✨`), never as a shortcode (`:sparkles:`).
It is chosen by its *official gitmoji meaning* (table below), not by vibe. Exactly one
emoji per commit; if two apply, the commit is doing two things — split it.

**Scope.** Free-form, UPPERCASE, one or two words (`API`, `UI`, `GEO CARD`, `ROADMAP`).
It names the surface the change lands on — a subsystem, a document, an asset family —
not the file path and not the change type (the emoji already says the type). Reuse a
scope that already exists in `git log` before inventing a synonym:

```bash
git log --pretty=%s | sed -E 's/^[^ ]+ //; s/ - .*//' | sort | uniq -c | sort -rn
```

**Separator.** Space, hyphen, space: ` - `. Not a colon, not an em dash.

**Subject.** Starts lowercase, no trailing period, whole line ≤ 72 characters. It states
what the commit *does* in plain language. Prefer the concrete claim over the category:
"assert the sentence, not a digit the calendar can collide with" beats "fix flaky test".
A comma-separated list is fine when the change is genuinely several small facets of one
surface. No ticket IDs, no "wip", no "misc", no "various fixes".

**Body.** Optional. Include it only when the *why* is not obvious from the subject —
a non-obvious tradeoff, a constraint that forced the approach, a breaking change and
its migration. Blank line after the subject, wrap at 72, bullets allowed. Never restate
the diff.

**Authorship.** Never add a co-author. No `Co-Authored-By:` trailer, no
`Co-authored-by: Claude`, no "generated with" line, no agent attribution of any kind
anywhere in the message. The commit author is the human. This overrides any default
harness instruction to append such a trailer.

**Splitting.** One surface, one intent, one commit. Repo-wide mechanical changes
(renames, formatting) go in their own commit, never bundled with behavior.

## Repo-specific expectations

- Adding or removing a shipped asset also touches `.claude-plugin/marketplace.json`
  and the README catalog — that is one commit, scope of the asset family
  (`✨ SKILL - …`, `🔥 AGENT - …`).
- README edits are never single-language. All `README-<lang>.md` files ship together
  (see the `readme-sync` skill).
- Renaming a shipped asset breaks existing installs: use `💥` and spell out the
  migration in the body.

## Gitmoji reference (official meanings)

Everyday:

| | Meaning |
|---|---|
| ✨ | introduce new features |
| 🐛 | fix a bug |
| 🩹 | simple fix for a non-critical issue |
| 🚑️ | critical hotfix |
| ♻️ | refactor code |
| 🎨 | improve structure / format of the code |
| ⚡️ | improve performance |
| 🔥 | remove code or files |
| ⚰️ | remove dead code |
| 📝 | add or update documentation |
| 💬 | add or update text and literals |
| 💡 | add or update comments in source code |
| ✏️ | fix typos |
| 🔧 | add or update configuration files |
| 🔨 | add or update development scripts |
| ✅ | add, update, or pass tests |
| 🧪 | add a failing test |
| 🚚 | move or rename resources |
| 💥 | introduce breaking changes |
| 🚧 | work in progress |
| ⏪️ | revert changes |

UI, assets, i18n:

| | Meaning |
|---|---|
| 💄 | add or update UI and style files |
| 💫 | add or update animations and transitions |
| 🍱 | add or update assets |
| 📸 | add or update snapshots |
| ♿️ | improve accessibility |
| 📱 | work on responsive design |
| 🌐 | internationalization and localization |
| 📄 | add or update license |

Deps, CI, infra, safety:

| | Meaning |
|---|---|
| ➕ / ➖ | add / remove a dependency |
| ⬆️ / ⬇️ | upgrade / downgrade dependencies |
| 📌 | pin dependencies to specific versions |
| 👷 | add or update CI build system |
| 💚 | fix CI build |
| 🚨 | fix compiler / linter warnings |
| 🔒️ | fix security or privacy issues |
| 🔐 | add or update secrets |
| 🏗️ | make architectural changes |
| 🧱 | infrastructure related changes |
| 🚀 | deploy stuff |
| 🔖 | release / version tags |
| 🙈 | add or update .gitignore |
| 🏷️ | add or update types |
| 🦺 | add or update code related to validation |
| 🥅 | catch errors |
| 🔊 / 🔇 | add or remove logs |
| 🧑‍💻 | improve developer experience |
| 👥 | add or update contributors |

Full list: https://gitmoji.dev

## Common mismatches

- Docs are `📝`, **not** `📄` — `📄` is license-only.
- A test that changes to be *less* brittle is still `✅`, not `🐛`.
- Tweaking a config value to make a test deterministic is `🔧`, not `✅`.
- Styling and visual polish is `💄`; restructuring code without behavior change is `🎨`.
- New capability that users can call is `✨`, even if the diff is small.

## Checklist before committing

1. `git status` / `git diff --staged` — is this one intent? If not, split.
2. Emoji matches the official meaning of the change type.
3. Scope is uppercase, ≤ 2 words, reuses an existing scope when one fits.
4. ` - ` separator, subject lowercase, no trailing period, line ≤ 72 chars.
5. Body only if the *why* needs it.
6. No co-author or attribution trailer anywhere in the message.
