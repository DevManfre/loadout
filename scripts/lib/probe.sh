# shellcheck shell=bash
# Answering "is this present on this machine". Read-only: nothing here
# installs, starts or configures anything.

platform_id() {
  if [ -n "${LOADOUT_FAKE_PLATFORM:-}" ]; then
    printf '%s' "$LOADOUT_FAKE_PLATFORM"
    return 0
  fi
  printf '%s/%s' "$(uname -s)" "$(uname -m)"
}

# 0 when the token is relevant on this platform.
dep_applies() {
  local when
  when=$(dep_field "$1" 4) || return 0
  case "$when" in
    platform:*) [ "${when#platform:}" = "$(platform_id)" ] ;;
    *) return 0 ;;
  esac
}

# One place asks whether a command exists, so one seam can lie about it.
have_cmd() {
  case ",${LOADOUT_FAKE_ABSENT:-}," in *",$1,"*) return 1 ;; esac
  command -v "$1" >/dev/null 2>&1
}

# 0 when the token is satisfied.
dep_present() {
  local probe var candidate
  probe=$(dep_field "$1" 3) || return 0
  case "$probe" in
    cmd:*) have_cmd "${probe#cmd:}" ;;
    anycmd:*)
      for candidate in $(printf '%s' "${probe#anycmd:}" | tr ',' ' '); do
        have_cmd "$candidate" && return 0
      done
      return 1
      ;;
    env:*) var=${probe#env:}; [ -n "${!var:-}" ] ;;
    *) return 0 ;;
  esac
}

# The dependencies the installer can install for itself, and the exact
# command it would run. The arm is the authority: a token is auto-fixable
# exactly when it has one. Kept as code rather than as a loadout.deps column
# because that file is '|'-delimited and this command contains a pipe.
dep_autofix_cmd() {
  case "$1" in
    uv/pipx) printf 'curl -LsSf https://astral.sh/uv/install.sh | sh' ;;
    *) return 1 ;;
  esac
}

# Blocking tokens the installer cannot fix; these keep an entry out of the
# selection entirely.
entry_hard_blocks() {
  local token
  for token in $(entry_deps "$1" block); do
    dep_autofix_cmd "$token" >/dev/null || printf '%s\n' "$token"
  done
}

# Blocking tokens the installer can fix itself, with consent, at install time.
entry_soft_blocks() {
  local token
  for token in $(entry_deps "$1" block); do
    dep_autofix_cmd "$token" >/dev/null && printf '%s\n' "$token"
  done
}

# Applicable, missing tokens of one severity, one per line.
entry_deps() {
  local name=$1 severity=$2 token needs
  needs=$(manifest_field "$name" 5) || return 1
  for token in $(printf '%s' "$needs" | tr ',' ' '); do
    [ "$(dep_field "$token" 2)" = "$severity" ] || continue
    dep_applies "$token" || continue
    dep_present "$token" || printf '%s\n' "$token"
  done
}

# The marketplace an entry's plugin comes from. Column 3 is either a plain
# marketplace name or `name=owner/repo` when the marketplace must be added.
plugin_marketplace() {
  local source
  source=$(manifest_field "$1" 3) || return 1
  printf '%s' "${source%%=*}"
}

# `claude plugin list` costs around a second per call (a node CLI), and one
# menu open asks about every plugin more than once. The answer changes only
# when this process itself installs or removes a plugin, so those code paths
# call plugin_list_reset; nothing is ever written to disk.
_PLUGIN_LIST_LOADED=0
_PLUGIN_LIST=""
_plugin_list() {
  if [ "$_PLUGIN_LIST_LOADED" -eq 0 ]; then
    # The cache is exported, not just held in a variable, because most callers
    # of this ask through $( ), and a command substitution is a subshell: a
    # shell-local cache dies with it and the next row pays the CLI's second
    # all over again. One menu open asks about every entry several times, so
    # that is the difference between one second and ten.
    if [ -n "${LOADOUT_PLUGIN_LIST:-}" ]; then
      _PLUGIN_LIST=$LOADOUT_PLUGIN_LIST
    else
      _PLUGIN_LIST=$(claude plugin list --json 2>/dev/null)
      LOADOUT_PLUGIN_LIST=$_PLUGIN_LIST
      export LOADOUT_PLUGIN_LIST
    fi
    _PLUGIN_LIST_LOADED=1
  fi
  printf '%s' "$_PLUGIN_LIST"
}
plugin_list_reset() { _PLUGIN_LIST_LOADED=0; _PLUGIN_LIST=""; unset LOADOUT_PLUGIN_LIST; }

# Install state is probed, never remembered: a state file would rot the first
# time somebody uninstalled something by hand. The probe column holds one or
# more alternatives, comma-separated; any one satisfied counts as installed.
entry_installed() {
  local token
  for token in $(_entry_probe_tokens "$1"); do
    _install_probe_ok "$token" && return 0
  done
  return 1
}

# Same question, blind to proxy: tokens — "is the thing on THIS machine",
# which is what update and remove need. A proxy answering from a container or
# the WSL host is nothing uv or the plugin CLI here can touch.
entry_installed_locally() {
  local token
  for token in $(_entry_probe_tokens "$1"); do
    case "$token" in proxy:*) continue ;; esac
    _install_probe_ok "$token" && return 0
  done
  return 1
}

_entry_probe_tokens() {
  local probe
  probe=$(manifest_field "$1" 6) || return 1
  printf '%s' "$probe" | tr ',' ' '
}

_install_probe_ok() {
  case "$1" in
    plugin:*)    _plugin_list | grep -Fq "\"${1#plugin:}@" ;;
    bin:*)       have_cmd "${1#bin:}" ;;
    proxy:*)     _proxy_alive "${1#proxy:}" ;;
    container:*) _container_exists "${1#container:}" ;;
    *) return 1 ;;
  esac
}

# A container, unlike a proxy, is something this machine can act on: it counts
# as a local install, so update and remove are allowed to touch it. Stopped
# counts as present — `docker ps -a` — because a stopped container is installed
# and broken, not absent, and installing a second one over it would be worse.
# The listing is cached in an exported variable for the same reason the plugin
# list is: most callers ask from inside a $( ), and the CLI is not free.
_DOCKER_PS_LOADED=0
_DOCKER_PS=""
_docker_ps() {
  if [ "$_DOCKER_PS_LOADED" -eq 0 ]; then
    # Set-but-empty is a real answer ("no containers here"), which is how the
    # test suite keeps the developer's own Docker out of the picture — so this
    # asks whether the variable exists, not whether it has content.
    if [ -n "${LOADOUT_DOCKER_PS+x}" ]; then
      _DOCKER_PS=$LOADOUT_DOCKER_PS
    elif have_cmd docker; then
      _DOCKER_PS=$(docker ps -a --format '{{.Names}}' 2>/dev/null)
      LOADOUT_DOCKER_PS=$_DOCKER_PS
      export LOADOUT_DOCKER_PS
    fi
    _DOCKER_PS_LOADED=1
  fi
  printf '%s' "$_DOCKER_PS"
}
docker_ps_reset() { _DOCKER_PS_LOADED=0; _DOCKER_PS=""; unset LOADOUT_DOCKER_PS; }

_container_exists() {
  have_cmd docker || return 1
  _docker_ps | grep -qx "$1"
}

# The entry can run as a container (it has a row) and does, here.
entry_is_container() {
  local ctr
  ctr=$(container_field "$1" 2) || return 1
  _container_exists "$ctr"
}

# The digest the registry serves for the entry's image tag, and the digest the
# running container's image was pulled at. "Behind" for a container is exactly
# this pair disagreeing: it is what `docker pull` would change, and nothing
# else — the package index can publish a version the registry has no image for,
# and offering that would offer something no pull can deliver.
_local_image_digest() {
  local ctr=$1 image
  have_cmd docker || return 1
  image=$(docker inspect "$ctr" --format '{{.Image}}' 2>/dev/null) || return 1
  [ -n "$image" ] || return 1
  docker image inspect "$image" --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' 2>/dev/null \
    | sed -n 's/.*@//p'
}

# The version an image says it is, out of the label every OCI build stamps on
# it. A build without that label leaves the short digest, which is a pin too —
# and is what the update compares anyway.
_container_version() {
  local ctr=$1 image digest
  have_cmd docker || return 1
  image=$(docker inspect "$ctr" --format '{{.Image}}' 2>/dev/null) || return 1
  [ -n "$image" ] || return 1
  docker image inspect "$image" \
    --format '{{index .Config.Labels "org.opencontainers.image.version"}}' 2>/dev/null \
    | sed '/^<no value>$/d;/^$/d' | head -1 | grep . && return 0
  digest=$(_local_image_digest "$ctr") || return 1
  printf '%s' "${digest#sha256:}" | cut -c1-12
}

# Anonymous pull tokens: ghcr.io and Docker Hub both hand one out for the
# asking. A registry that needs real credentials answers nothing here, which
# reads as unknown — never as "current".
_registry_token() {
  local host=$1 repo=$2 url
  case "$host" in
    ghcr.io)    url="https://ghcr.io/token?scope=repository:$repo:pull&service=ghcr.io" ;;
    docker.io)  url="https://auth.docker.io/token?scope=repository:$repo:pull&service=registry.docker.io" ;;
    *) return 1 ;;
  esac
  _net_get "$url" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

_registry_digest() {
  local ref=$1 host repo tag token api rest
  # The tag is a colon in the LAST path segment; a colon earlier is a host
  # port (`registry.local:5000/x`), not a tag.
  case "${ref##*/}" in
    *:*) tag=${ref##*:}; ref=${ref%:*} ;;
    *)   tag=latest ;;
  esac
  host=${ref%%/*}; rest=${ref#*/}
  # A first segment with no dot, no colon and no slash after it is not a host
  # but a Docker Hub namespace — `owner/image`, or a bare `image`.
  case "$ref" in
    */*) case "$host" in
           *.*|*:*|localhost) repo=$rest ;;
           *) host=docker.io; repo=$ref ;;
         esac ;;
    *) host=docker.io; repo="library/$ref" ;;
  esac
  case "$host" in
    docker.io) api=https://registry-1.docker.io ;;
    *)         api="https://$host" ;;
  esac
  net_probe_ok || return 1
  token=$(_registry_token "$host" "$repo") || return 1
  [ -n "$token" ] || return 1
  curl -sI --max-time "${LOADOUT_NET_TIMEOUT:-4}" \
    -H "Authorization: Bearer $token" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
    "$api/v2/$repo/manifests/$tag" 2>/dev/null \
    | sed -n 's/[Dd]ocker-[Cc]ontent-[Dd]igest:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1
}

# 0 when the tag has a build the running container is not on. Unknown on
# either side is not an update: the same rule pin_outdated follows.
container_image_moved() {
  local name=$1 ctr image have want
  ctr=$(container_field "$name" 2) || return 1
  image=$(container_field "$name" 3) || return 1
  have=$(_local_image_digest "$ctr") || return 1
  want=$(_registry_digest "$image") || return 1
  [ -n "$have" ] && [ -n "$want" ] || return 1
  [ "$have" != "$want" ]
}

# A live HTTP answer at the URL the named variable points at counts as
# installed: the process serves this machine from somewhere PATH cannot see —
# a container, or the Windows host under WSL. Any HTTP status counts as alive
# (an API-shaped proxy 404s a bare GET /); only a dead connection means
# absent. Cached per URL for this process: the menu asks about the same entry
# more than once per open, and a network probe costs up to 2 s each time.
_PROXY_ALIVE_URL=""
_PROXY_ALIVE_RC=1
# The URL the named variable points at, live value first, then the settings
# files. One place resolves it, because two probes now ask about the same proxy
# and a second copy of this would be a second chance to disagree.
_proxy_url() {
  local url
  url=${!1:-}
  [ -n "$url" ] || url=$(_proxy_url_from_settings "$1")
  [ -n "$url" ] || return 1
  printf '%s' "$url"
}

_proxy_alive() {
  local var=$1 url
  url=$(_proxy_url "$var") || return 1
  have_cmd curl || return 1
  if [ "$_PROXY_ALIVE_URL" != "$url" ]; then
    curl -s -o /dev/null --max-time 2 "$url"
    _PROXY_ALIVE_RC=$?
    _PROXY_ALIVE_URL=$url
  fi
  [ "$_PROXY_ALIVE_RC" -eq 0 ]
}

# The variable usually lives in Claude Code's settings env, not in the shell
# profile — the proxy serves the agent, so the agent's config is where the URL
# is written down, and the interactive shell that launches the installer has
# no reason to have it exported. Project settings win over global; the live
# variable, checked above, wins over both. The extraction is a sed over one
# quoted key, not a JSON parse: enough for a flat "env" block, and jq is not a
# dependency this script is allowed to grow.
_proxy_url_from_settings() {
  local var=$1 f url files
  files=${LOADOUT_SETTINGS_FILES:-.claude/settings.local.json:.claude/settings.json:$HOME/.claude/settings.json}
  local IFS=:
  for f in $files; do
    [ -f "$f" ] || continue
    url=$(sed -n 's/.*"'"$var"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)
    [ -n "$url" ] && { printf '%s' "$url"; return 0; }
  done
  return 1
}

# A proxy that answers /health names the version it is running, and that is the
# only pin a remote install will ever hand over: there is no cache directory to
# list and no binary on PATH to ask. Without it a container six releases behind
# looks exactly like one that is current — which is the whole reason the menu
# asks. Cached per URL for this process, like _proxy_alive above.
_PROXY_VERSION_URL=""
_PROXY_VERSION=""
_proxy_version() {
  local var=$1 url
  url=$(_proxy_url "$var") || return 1
  have_cmd curl || return 1
  if [ "$_PROXY_VERSION_URL" != "$url" ]; then
    _PROXY_VERSION=$(curl -s --max-time "${LOADOUT_NET_TIMEOUT:-4}" "${url%/}/health" 2>/dev/null \
                     | tr ',' '\n' \
                     | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    _PROXY_VERSION_URL=$url
  fi
  [ -n "$_PROXY_VERSION" ] || return 1
  printf '%s' "$_PROXY_VERSION"
}

# The pin on disk for a plugin, the reported version for a binary, the pin a
# reachable proxy admits to for a remote one, '-' when nothing will say.
entry_version() {
  local name=$1 token pin dir
  for token in $(_entry_probe_tokens "$name"); do
    _install_probe_ok "$token" || continue
    case "$token" in
      plugin:*)
        # The CLI's own answer first: the cache directory keeps every pin it
        # ever fetched, so listing it returns the alphabetically first of them
        # — 6.2.0 for an installed 6.3.0 — which reads as a pin behind
        # upstream and would put a phantom update row in the menu. The
        # directory stays as the fallback for a CLI that will not answer.
        # One key per line first (the CLI prints compact JSON through a pipe
        # and pretty JSON to a terminal, and this has to read both), then the
        # first "version" after the entry's own id.
        pin=$(_plugin_list | tr ',' '\n' | awk -v p="\"${token#plugin:}@" '
          index($0, p) { inb = 1; next }
          inb && /"version"[[:space:]]*:/ {
            sub(/^[^:]*:[[:space:]]*"/, ""); sub(/".*$/, ""); print; exit
          }')
        if [ -z "$pin" ]; then
          dir="$HOME/.claude/plugins/cache/$(plugin_marketplace "$name")/${token#plugin:}"
          pin=$(ls -1 "$dir" 2>/dev/null | head -1)
        fi
        printf '%s' "${pin:--}"; return 0 ;;
      bin:*)
        pin=$("${token#bin:}" --version 2>/dev/null | head -1 | tr -dc '0-9.v' )
        printf '%s' "${pin:--}"; return 0 ;;
      proxy:*)
        pin=$(_proxy_version "${token#proxy:}") || pin=""
        printf '%s' "${pin:--}"; return 0 ;;
      container:*)
        pin=$(_container_version "${token#container:}") || pin=""
        printf '%s' "${pin:--}"; return 0 ;;
    esac
  done
  printf '%s' '-'
}

# The one question in this file that disk cannot answer: what upstream
# publishes now. Every call is bounded (LOADOUT_NET_TIMEOUT, 4 s by default)
# and every failure answers '-' — unknown, never "current" and never
# "outdated". Guessing either way is worse than saying nothing: a false update
# row walks somebody off the pin the catalog measured, and a false "current"
# hides the release they opened the menu to find. LOADOUT_NO_NET=1 turns the
# whole thing off, which is also what keeps the test suite hermetic.
net_probe_ok() {
  [ "${LOADOUT_NO_NET:-0}" != 1 ] || return 1
  have_cmd curl
}

_net_get() {
  net_probe_ok || return 1
  curl -fsSL --max-time "${LOADOUT_NET_TIMEOUT:-4}" "$1" 2>/dev/null
}

# PyPI's own metadata, read for one key. The value is checked against the shape
# of a version before it is believed: "version" also occurs inside the rendered
# README a package ships as its description, and a sentence is not a pin.
_latest_pypi() {
  _net_get "https://pypi.org/pypi/$1/json" \
    | tr ',' '\n' \
    | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | grep -E -m1 '^[0-9][0-9A-Za-z.+!-]*$'
}

# One key out of one entry of a marketplace manifest. An awk walk over that
# entry's own lines, not a JSON parse: jq is not a dependency this script is
# allowed to grow, and the alternative — `claude plugin marketplace list
# --json` — is the same node CLI that already costs a second per call.
_marketplace_field() {
  local file=$1 name=$2 key=$3
  awk -v name="$name" -v key="$key" '
    !inb && $0 ~ "\"name\"[[:space:]]*:[[:space:]]*\"" name "\"" { inb = 1; next }
    inb && /^    \},?$/ { exit }
    inb && $0 ~ "\"" key "\"[[:space:]]*:" {
      line = $0
      sub(/^[^:]*:[[:space:]]*"/, "", line)
      sub(/".*$/, "", line)
      print line
      exit
    }
  ' "$file" 2>/dev/null
}

# `owner/repo sha` for the version of a plugin that would be installed next.
# Which sha that is depends on where the marketplace comes from, and the
# difference matters: a marketplace that pins its entries hands out its pin,
# not whatever upstream pushed an hour ago, so reporting the upstream head for
# those would offer an update `claude plugin update` cannot take.
_plugin_upstream() {
  local name=$1 source repo sha file
  source=$(manifest_field "$name" 3) || return 1
  case "$source" in
    *=*)
      repo=${source#*=}
      net_probe_ok || return 1
      have_cmd git || return 1
      sha=$(GIT_TERMINAL_PROMPT=0 git ls-remote "https://github.com/$repo" HEAD 2>/dev/null \
            | head -1 | cut -f1)
      ;;
    *)
      file="$HOME/.claude/plugins/marketplaces/$source/.claude-plugin/marketplace.json"
      [ -f "$file" ] || return 1
      repo=$(_marketplace_field "$file" "$name" url)
      sha=$(_marketplace_field "$file" "$name" sha)
      repo=${repo#https://github.com/}; repo=${repo%.git}
      ;;
  esac
  [ -n "$repo" ] && [ -n "$sha" ] || return 1
  printf '%s %s' "$repo" "$sha"
}

_plugin_version_at() {
  _net_get "https://raw.githubusercontent.com/$1/$2/.claude-plugin/plugin.json" \
    | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# The pin an install or update would land on, in the same form entry_version
# reports the installed one, or '-' when nothing here can say.
entry_latest() {
  local name=$1 kind source repo sha ver="" pair
  net_probe_ok || { printf '%s' '-'; return 0; }
  kind=$(manifest_field "$name" 2) || { printf '%s' '-'; return 0; }
  case "$kind" in
    pypkg)
      source=$(manifest_field "$name" 3)
      ver=$(_latest_pypi "${source%%\[*}")
      ;;
    plugin)
      pair=$(_plugin_upstream "$name") || { printf '%s' '-'; return 0; }
      repo=${pair%% *}; sha=${pair#* }
      # The sha is the identity; a version string is only how a human reads it,
      # and not every plugin declares one — then the short sha is the pin,
      # which is also the form entry_version reports for that plugin.
      ver=$(_plugin_version_at "$repo" "$sha")
      [ -n "$ver" ] || ver=${sha:0:12}
      ;;
  esac
  printf '%s' "${ver:--}"
}

# Pins compare past the noise: a leading 'v' (the catalog writes v0.37.0 where
# PyPI writes 0.37.0) and a 40-character sha against the 12 the plugin cache
# names its directory with.
_pin_eq() {
  local a=${1#v} b=${2#v}
  [ "$a" = "$b" ] && return 0
  case "$a$b" in *[!0-9a-f]*) return 1 ;; esac
  [ "${a:0:12}" = "${b:0:12}" ]
}

# Both pins known and different. Takes values, not a name, so a caller that has
# already paid for the probe does not pay again.
pin_outdated() {
  [ -n "$1" ] && [ "$1" != '-' ] || return 1
  [ -n "$2" ] && [ "$2" != '-' ] || return 1
  ! _pin_eq "$1" "$2"
}

entry_outdated() {
  entry_installed_locally "$1" || return 1
  pin_outdated "$(entry_version "$1")" "$(entry_latest "$1")"
}

# Every named entry's latest pin, one `name pin` line each, probed in parallel:
# the menu needs all of them before it can draw a single row, and asking one at
# a time turns four bounded calls into four bounded waits.
entry_latest_all() {
  local dir name
  dir=$(mktemp -d) || return 1
  for name in "$@"; do
    [ -n "$name" ] || continue
    ( entry_latest "$name" > "$dir/$name" ) &
  done
  wait
  for name in "$@"; do
    [ -n "$name" ] || continue
    printf '%s %s\n' "$name" "$(cat "$dir/$name" 2>/dev/null)"
  done
  rm -rf "$dir"
}
