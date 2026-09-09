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

if [ "$fails" -gt 0 ]; then
  echo "$fails structural problem(s)" >&2
  exit 1
fi
echo "ok"
