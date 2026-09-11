---
name: readme-sync
description: Use when editing any README or adding/renaming/removing a catalog asset. Edits cascade to README.md (canonical) and all README-<lang>.md mirrors.
---

# README sync

## Language set

| File | Language | Role |
|---|---|---|
| `README.md` | English | **canonical** — edit here first, always |
| `README-it.md` | Italian | mirror |

Active set is English + Italian only. Other locales (`README-es.md`, `README-fr.md`, …)
follow the exact same rules the day they are added: add the row above, add the file,
add it to the language switcher in every existing README.

## The rule

A commit may never touch one README without touching all of them. A mirror that lags
behind the canonical file is a bug, not a TODO.

## Procedure

1. **Edit `README.md` first.** If the request arrives as an Italian edit, translate the
   intent into English, apply it to `README.md`, then regenerate the Italian.
2. **Diff the canonical file** (`git diff README.md`) and treat each changed hunk as a
   unit of work. Do not retranslate untouched sections — preserve existing wording in
   the mirrors so the diff stays reviewable.
3. **Propagate hunk by hunk** to every mirror, in the same position and at the same
   heading depth.
4. **Translate prose only.** Verbatim across all languages:
   - code fences and everything inside them
   - commands, flags, env vars, file paths, directory trees
   - asset names (skill / agent / workflow / integration identifiers)
   - URLs, badge markup, table structure, license text
   - the language-switcher line
5. **Headings are translated**, so anchors differ per file. Every intra-document link
   must point at anchors *of its own file*. Cross-language links only ever target the
   other README's top.
6. **Verify** (below), then commit all READMEs together — one commit, `📝 README` scope
   (or the scope of the change that caused it, with the READMEs riding along).

## Language switcher

First line of body in every README, identical structure, each file linking to the others:

```markdown
[English](README.md) · [Italiano](README-it.md)
```

## Verification

Parity is structural; run it before claiming done:

```bash
for f in README.md README-it.md; do
  printf '%s  headings=%s fences=%s links=%s tables=%s\n' "$f" \
    "$(grep -c '^#\+ ' "$f")" \
    "$(grep -c '^```' "$f")" \
    "$(grep -oc '](\S\+)' "$f")" \
    "$(grep -c '^|' "$f")"
done
```

All four counts must match across files. A mismatch means a hunk was dropped or a code
fence was translated. Also confirm every path mentioned in the catalog resolves:

```bash
grep -oE '(skills|agents|workflows|integrations)/[A-Za-z0-9._/-]+' README.md | sort -u | while read -r p; do
  [ -e "$p" ] || echo "MISSING: $p"
done
```

## Terminology (EN → IT)

Keep translations stable; do not re-word case by case.

| English | Italian |
|---|---|
| skill | skill *(invariato)* |
| sub-agent | sub-agent *(invariato)* |
| workflow | workflow *(invariato)* |
| harness | harness *(invariato)* |
| install / installation | installazione |
| token usage | consumo di token |
| catalog | catalogo |
| getting started | primi passi |
| contributing | come contribuire |
| requirements | requisiti |
| usage | utilizzo |

Product and ecosystem names stay in English: Claude Code, Claude, MCP, plugin,
marketplace, hook, prompt.

## Red flags

- "I will update the Italian one later" → no. Same commit or the edit is incomplete.
- Editing `README-it.md` as the primary source → wrong direction, restart from `README.md`.
- Translated command or path inside a code fence → breaks copy-paste, revert it.
- Heading counts diverge → a section is missing somewhere.
