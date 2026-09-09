#!/usr/bin/env bash
# Structural validation for the loadout repo.
# There is no build and no test runner here: the guide and its assets are the
# product, so "valid" means every shipped asset has parsable frontmatter,
# every integration documents itself, every doc link resolves, README language
# mirrors stay in parity, and every integration is reachable from the README
# catalog.
set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 is required for the index and doc checks; everything else was skipped" >&2
  exit 1
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

# Relative links in every root README and every markdown file under
# integrations/ (any depth) must resolve, relative to the directory of the
# file that contains them — not the repo root. A leading-slash link is
# always a failure: there is no filesystem root inside these docs.
link_failures=$(python3 <<'PY'
import glob, os, re

files = sorted(set(glob.glob('README.md') + glob.glob('README-*.md')
                    + glob.glob('integrations/**/*.md', recursive=True)))

link_re = re.compile(r'\]\(([^)#][^)]*)\)')

for f in files:
    if not os.path.isfile(f):
        continue
    with open(f, encoding='utf-8') as fh:
        text = fh.read()
    for m in link_re.finditer(text):
        link = m.group(1).split('#', 1)[0]
        if not link:
            continue
        if link.startswith(('http://', 'https://', 'mailto:')):
            continue
        if link.startswith('/'):
            print(f"FAIL: {f}: link '{link}' is an absolute path (leading slash), never valid in this repo's docs")
            continue
        target = os.path.normpath(os.path.join(os.path.dirname(f), link))
        if not os.path.exists(target):
            print(f"FAIL: {f}: link '{link}' does not resolve")
PY
)

if [ -n "$link_failures" ]; then
  printf '%s\n' "$link_failures" >&2
  link_fails=$(printf '%s\n' "$link_failures" | grep -c '^FAIL:')
  fails=$((fails + link_fails))
fi

# README language parity: every README.md (root, and each integrations/<name>/)
# must have a mirror for every language suffix seen anywhere in the repo, and
# the mirror's heading/fence/link/table-row counts must match the canonical.
parity_failures=$(python3 <<'PY'
import glob, os, re

def counts(path):
    with open(path, encoding='utf-8') as fh:
        lines = fh.readlines()
    return {
        'headings': sum(1 for l in lines if re.match(r'^#+ ', l)),
        'fences': sum(1 for l in lines if re.match(r'^```', l)),
        'links': sum(1 for l in lines if re.search(r'\]\(\S+\)', l)),
        'tables': sum(1 for l in lines if l.startswith('|')),
    }

canon_dirs = ['.'] + [d.rstrip('/') for d in sorted(glob.glob('integrations/*/'))]

langs = set()
for f in glob.glob('README-*.md') + glob.glob('integrations/*/README-*.md'):
    m = re.match(r'README-([A-Za-z0-9]+)\.md$', os.path.basename(f))
    if m:
        langs.add(m.group(1))

for d in canon_dirs:
    canon = os.path.join(d, 'README.md')
    if not os.path.isfile(canon):
        continue
    c_counts = counts(canon)
    for lang in sorted(langs):
        mirror = os.path.join(d, f'README-{lang}.md')
        if not os.path.isfile(mirror):
            print(f"FAIL: {canon} vs {mirror}: mirror is missing")
            continue
        m_counts = counts(mirror)
        for key in ('headings', 'fences', 'links', 'tables'):
            if c_counts[key] != m_counts[key]:
                print(f"FAIL: {canon} vs {mirror}: {key} count diverges ({c_counts[key]} vs {m_counts[key]})")
PY
)

if [ -n "$parity_failures" ]; then
  printf '%s\n' "$parity_failures" >&2
  parity_fails=$(printf '%s\n' "$parity_failures" | grep -c '^FAIL:')
  fails=$((fails + parity_fails))
fi

# Every integrations/<name> directory must be reachable from the root README
# catalog, and every skills/agents/workflows/integrations path mentioned in a
# root README must resolve on disk.
index_failures=$(python3 <<'PY'
import glob, os, re

readme = ''
if os.path.isfile('README.md'):
    with open('README.md', encoding='utf-8') as fh:
        readme = fh.read()

for d in sorted(glob.glob('integrations/*/')):
    name = d.rstrip('/').split('/')[-1]
    if f'integrations/{name}' not in readme:
        print(f"FAIL: integrations/{name} is not reachable from the README.md catalog")

for m in re.finditer(r'(?:skills|agents|workflows|integrations)/[A-Za-z0-9._/-]+', readme):
    path = m.group(0).rstrip('.,)')
    if not os.path.exists(path):
        print(f"FAIL: README.md references '{path}' which does not resolve on disk")
PY
)

if [ -n "$index_failures" ]; then
  printf '%s\n' "$index_failures" >&2
  index_fails=$(printf '%s\n' "$index_failures" | grep -c '^FAIL:')
  fails=$((fails + index_fails))
fi

# The manifest is the single source of truth for what the catalog carries and
# what it costs. These checks are what make that true rather than aspirational.
#
# The cost check compares only the first whitespace-delimited token of
# cost_session (e.g. '~2,480' out of '~2,480 +60/prompt') against each
# README's catalog row, not the whole field: the manifest also carries a
# compact per-call display suffix ('+60/prompt', '+48-105/toolcall') that no
# README row quotes verbatim, while the always-on number is what every row
# states. The comparison itself is digit-only, so a mirror's localised
# thousands separator ('~2.480' in Italian vs '~2,480' in English) is not
# mistaken for drift, while a real change to the number still fails in every
# language. A cost token with no digits at all ('none') is a word, not a
# figure, so it is checked against the canonical README.md only -- a mirror
# is free to translate it, and the existing reachability and parity checks
# already require the mirror to carry a catalog row for the entry at all.
manifest_failures=$(LOADOUT_ROOT=$PWD python3 <<'PY'
import os, re, sys

def table(path, want):
    rows = []
    for n, line in enumerate(open(path, encoding='utf-8'), 1):
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        cells = [c.strip() for c in s.split('|')]
        if len(cells) != want:
            print(f"FAIL: {path}:{n}: expected {want} columns, found {len(cells)}")
            continue
        rows.append(cells)
    return rows

def digits(s):
    return re.sub(r'\D', '', s)

entries = table('scripts/loadout.manifest', 8)
deps = {r[0]: r for r in table('scripts/loadout.deps', 7)}
readmes = ['README.md'] + [p for p in os.listdir('.') if re.fullmatch(r'README-\w+\.md', p)]
texts = {p: open(p, encoding='utf-8').read() for p in readmes}

known_presets = {'core', 'full'}
for name, kind, source, presets, needs, probe, cost, measured in entries:
    for suffix in ('README.md', 'README-it.md'):
        guide = f'integrations/{name}/{suffix}'
        if not os.path.isfile(guide):
            print(f"FAIL: {name}: no {guide}")
    for token in needs.split(','):
        if token and token not in deps:
            print(f"FAIL: {name}: needs '{token}', which has no row in scripts/loadout.deps")
    if not presets or any(p not in known_presets for p in presets.split(',')):
        print(f"FAIL: {name}: presets '{presets}' names something outside {sorted(known_presets)}")
    if kind not in ('plugin', 'pypkg'):
        print(f"FAIL: {name}: unknown kind '{kind}'")
    head = cost.split()[0] if cost.split() else ''
    want = digits(head)
    for path, text in texts.items():
        row = [l for l in text.splitlines() if l.strip().startswith('|') and f'| {name} ' in l]
        if not row:
            print(f"FAIL: {name}: no catalog row in {path}")
            continue
        if want:
            if want not in digits(row[0]):
                print(f"FAIL: {name}: cost '{head}' does not appear in the {path} catalog row")
        elif path == 'README.md':
            if head not in row[0]:
                print(f"FAIL: {name}: cost '{head}' does not appear in the {path} catalog row")

for token, row in deps.items():
    if row[1] not in ('block', 'warn', 'runtime'):
        print(f"FAIL: dep {token}: unknown severity '{row[1]}'")
    if not os.path.exists(row[6]):
        print(f"FAIL: dep {token}: docs path '{row[6]}' does not resolve")

if not os.access('scripts/install-all.sh', os.X_OK):
    print("FAIL: scripts/install-all.sh is not executable")
if not os.access('scripts/loadout', os.X_OK):
    print("FAIL: scripts/loadout is not executable")
PY
)
if [ -n "$manifest_failures" ]; then
  printf '%s\n' "$manifest_failures" >&2
  manifest_fails=$(printf '%s\n' "$manifest_failures" | grep -c '^FAIL:')
  fails=$((fails + manifest_fails))
fi

if [ "$fails" -gt 0 ]; then
  echo "$fails structural problem(s)" >&2
  exit 1
fi
echo "ok"
