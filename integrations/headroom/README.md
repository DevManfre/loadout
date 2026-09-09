# headroom

A compression proxy that sits between the agent and the API. Every other entry in this
catalog spends context to save work; headroom is the only one that spends no context at
all — it never appears in the window, because it works on the wire. Requests pass through
a local HTTP proxy which shrinks tool outputs, logs, search results, file contents and
conversation history before they reach the model, replacing the removed bulk with a short
marker and a hash the model can spend tokens to expand again.

The trade is therefore not context against capability, as it is everywhere else here. It
is *tokens against wall clock and fidelity*: the reduction measured on this machine is
real but modest, the latency it costs is large, and the compression is lossy on prose —
including the prose in files the agent reads back. This guide is unusually well evidenced
because the proxy was already running while it was written, so every figure below comes
from the running instance's own `/stats`, not from the upstream README.

| | |
|---|---|
| Upstream | https://github.com/headroomlabs-ai/headroom |
| Author | Headroom Contributors (headroomlabs-ai) |
| License | Apache-2.0, with a `NOTICE` listing MIT third-party components (tiktoken, Pydantic) |
| Version inspected | `v0.37.0` (commit `e67b3c8a2944`, 2026-09-06); the instance measured here reports `0.27.0` |
| Contents | Rust workspace plus Python package and TypeScript SDK: `headroom` CLI, HTTP proxy, MCP server (4 tools), 5 plugin directories of which `headroom-agent-hooks` is the Claude Code one — hooks only, no skills, no sub-agents |

## Install

Four shapes ship in one package, and only the first is worth carrying. The proxy needs
no code changes and no plugin:

```bash
uv tool install --python 3.13 "headroom-ai[proxy]"
headroom proxy --port 8787
export ANTHROPIC_BASE_URL=http://127.0.0.1:8787
```

Python 3.13 is the recommended interpreter: the dashboard's dollar tile depends on
LiteLLM, which does not install on 3.14+. `[all]` pulls the ML compressor, memory,
vector and image extras as well — a much larger install for a strategy that, measured
below, contributes almost nothing.

Under WSL the proxy usually runs on the Windows host, so the variable points at the host
address rather than loopback, and the URL carries a project namespace that keeps lifetime
savings separated per project:

```bash
export ANTHROPIC_BASE_URL=http://172.27.176.1:8787/p/<project>
```

Turn it off for a session by unsetting the variable — no uninstall, no restart of
anything but the agent:

```bash
unset ANTHROPIC_BASE_URL
```

The Claude Code plugin is a separate, optional shape. It carries no skills and no
sub-agents; its whole content is two hooks that run `headroom init hook ensure` to start
the runtime:

```bash
claude plugin marketplace add headroomlabs-ai/headroom
claude plugin install headroom@headroom-marketplace
```

## Token economy

Three budgets, as always. What makes this entry different is that the first one is empty.

**Always on, per session.** The proxy shape costs nothing at all: no skill index entry,
no sub-agent description, no `SessionStart` injection. It is not in the context window,
so there is nothing to pay before you type.

| Shape | Always-on context cost |
|---|---|
| Proxy (`ANTHROPIC_BASE_URL`) | **none** — the process is outside the window |
| Claude Code plugin (`headroom-agent-hooks`) | no skills, no agents; two hooks whose stdout was not measurable here (the CLI is not on PATH in this WSL guest, since the proxy runs host-side) |
| MCP server (`headroom mcp serve`) | 4 tool definitions, 2,099 chars whitespace-collapsed · **~525 tokens**, paid every session whether or not the model calls them |

The plugin's `SessionStart` hook declares the matcher `startup|resume`, so unlike
superpowers and caveman it does **not** re-fire on `/clear` or on compaction. Its
`PreToolUse` hook matches `Bash|PowerShell`, so it runs once per shell call — a latency
cost, not a token cost.

**Per request.** Each compressed block is replaced by a marker of the form
`[175 items compressed to 138. Retrieve more: hash=26420830ad95b10f417448c3]` — 75 chars,
~19 tokens, against a saving far larger than that. If the model then retrieves the
original, the saving is returned and a round trip is added. Lifetime counters on this
machine show that happening constantly: 15,783 compressions against 16,148 retrievals, a
retrieval rate of **1.02 per compression**.

The measurable per-request price is time, not tokens:

| Timing (this instance, 631 requests) | Value |
|---|---|
| Added overhead, average | 2,186 ms |
| Added overhead, min / max | 1.39 ms / 30,189 ms |
| `compressor:mixed`, average | 5,590 ms |
| `compressor:kompress` (ML), average | 2,264 ms |
| `compressor:smart_crusher` / `search` / `diff`, average | 31–65 ms |

Upstream advertises "0.21 ms p50". That figure is one SmartCrusher call on a 10K-token
JSON payload, not the proxy pipeline with the text and ML strategies enabled, and the gap
between the two is four orders of magnitude.

**What you get back.** Measured, on real Claude Code traffic through this proxy:

| Window | Requests | Input tokens before | Saved | Ratio | Dollars |
|---|---|---|---|---|---|
| This session | 631 | 65.79 M | 1.99 M | **3.02 %** | $9.93 of $173.65 |
| Lifetime, this project | 69,523 | 6.86 B | 317.5 M | **4.42 %** | $1,339 of $10,088 |
| Per compressed request | 485 | — | — | 4.8 % average, 19.7 % best (33,226 → 26,692) | — |

Most requests are left alone, and the reasons are worth reading: 4,551 blocks were too
small to bother with, 2,420 had a ratio too poor to be worth it, 604 were protected
because they sat behind a cache breakpoint, 459 came from excluded tools, 273 were already
compressed. That router is the reason the aggregate lands near 4 % rather than the 21–57 %
the upstream README quotes for hand-picked scenarios.

Where the savings actually come from is also not where you would guess:

| Strategy | Calls | Tokens saved |
|---|---|---|
| text | 465 | 34,761 |
| tabular | 22 | 22,360 |
| kompress (ML) | 63 | 3,499 |
| code_aware | 226 | 2,527 |
| smart_crusher | 73 | 432 |
| search / diff / log | 33 | 459 |

Twenty-two tabular blocks saved nine times what 226 code-aware compressions did.

**Break-even.** With zero always-on context cost, any positive ratio pays for itself in
tokens — the arithmetic that decides other entries in this catalog does not apply. The
question is whether ~4 % off the input bill is worth ~2.2 s added to every request. On
long autonomous runs where the context window itself is the binding constraint, yes: 317 M
tokens is real headroom against the limit, which is the product's actual name and its
actual argument. On interactive work it is a tax on every turn for a few percent.

One more number keeps the dollar claim honest: on the same instance, prompt caching saved
$313.81 while compression saved $9.93. The dashboard reports both, and 97 % of the money
came from a mechanism Claude Code already uses on its own. Headroom's contribution there
is defensive — its CacheAligner protected 604 blocks behind breakpoints and recorded only
11 cache busts.

## Verdict, per component

| Component | Verdict | Why |
|---|---|---|
| HTTP proxy | Keep — it is the product | Zero context cost, measured 3–4.4 % input reduction, one env var to enable and one to disable. Everything else here is optional around it. |
| CacheAligner | Keep | Flags cache-busting content instead of rewriting it. 604 protected blocks, 11 busts. Compressing across a breakpoint would cost more than it saves, and this is what stops it. |
| SmartCrusher (JSON) + tabular | Keep | The best ratio per call in the whole set, and the strategies fast enough not to be felt: 22 tabular calls, 22,360 tokens. |
| CCR retrieval + hashes | Situational | Makes the compression reversible, which is what makes it safe. But lifetime retrievals exceed compressions 1.02:1 — on that traffic the model pays most of the saving back plus a round trip. Worth watching in `/stats`, not assuming. |
| code_aware (AST) | Situational | 226 calls for 2,527 tokens: 36 % of the compressions, 0.8 % of the savings. Harmless, but it is not why you would install this. |
| Kompress ML model | Skip | 2,264 ms average for 3,499 tokens. The `[ml]` extra is the bulk of the install and the bulk of the latency. Leave it out of `[proxy]`. |
| MCP server (4 tools) | Skip | ~525 tokens always on, and it inverts the design: the model must remember to call `headroom_compress` instead of compression simply happening. The proxy already does this for free. |
| Claude Code plugin | Skip | Contributes no skills and no capability — two hooks that start a runtime you can start yourself. The `PreToolUse` matcher means it fires on every Bash call to do so. |
| `headroom wrap <agent>` | Situational | Sets the environment for you. Useful once, then you know the variable. |
| Dashboard (`/stats`, `/dashboard`) | Keep, situational | The reason this guide has numbers. Read it before believing any compression claim, including this one. |
| `headroom learn` / memory / vector / image extras | Skip | Adjacent products bundled into the same package. Not what the proxy is carried for. |
| Anonymous beacon | Skip — turn it off | On by default upstream. See gotchas. |

## Interaction with the rest of loadout

Nothing in the catalog overlaps with this, because nothing else in the catalog works at
this layer. The three compression stories in loadout are complementary and it is worth
being precise about which is which: caveman shrinks the **output** the model writes,
graphify avoids **reads** ever happening by answering from a graph, and headroom shrinks
the **input** already on its way to the API. Only headroom pays no context for the
privilege.

It also changes the accounting for the others. Superpowers' and caveman's `SessionStart`
injections re-fire on every compaction, and those repeated injections travel through the
proxy like anything else — but they sit behind a cache breakpoint, so they land in the
604 protected blocks and are not compressed. The hook cost measured in those two guides is
paid in full, with or without this entry.

The hook count is unchanged if you take the recommended shape: the proxy adds no hook.
Install the optional plugin and you have a third hook-bearing plugin, and a `PreToolUse`
hook on every shell call, for no context benefit.

## Gotchas

- **Compression is lossy on prose, including files you read.** While this guide was being
  written, `cat scripts/install-all.sh` came back through the proxy with articles and
  filler stripped from its comments and blocks replaced by `[175 items compressed to 138.
  Retrieve more: hash=…]`. Shell output, file contents and search results are all fair
  game. Never edit a file from a compressed read: retrieve by hash, or read in small
  chunks, which the router leaves alone as "too small".
- **The proxy is a single point of failure in front of the API.** The same instance logged
  one 502, two 503s and one failed request across 1,218 inbound calls. When it is down,
  the agent is down until `ANTHROPIC_BASE_URL` is unset.
- **Its own rate limiter can throttle you.** Defaults are 60 requests and 100k tokens per
  minute; 11 requests were rate-limited with `429` on this instance. That is headroom
  refusing traffic, not Anthropic.
- **Telemetry is on by default.** An anonymous beacon reports ratios, counters,
  provider and model IDs, OS and architecture — not prompts or code. Disable with
  `HEADROOM_BEACON=off`, `DO_NOT_TRACK=1` or `--offline`. It was off on the instance
  measured here; that was a choice, not the default.
- **Retrieval can erase the saving.** `headroom_read` and CCR hashes let the model pull
  originals back, and lifetime counters here show it doing so slightly more than once per
  compression. A compression ratio in the dashboard is not a saving until you look at the
  retrieval rate next to it.
- **The advertised latency is not the pipeline's latency.** "0.21 ms p50" is one JSON
  strategy in isolation. Average added overhead measured here is 2,186 ms, with a maximum
  of 30 s.
- **Originals are cached on disk, unencrypted.** On this instance under
  `/root/.headroom/`, which also means the proxy was running as root in a container.
  Compression is local and nothing is sent away to be compressed, but the plaintext
  originals do land in a file.
- **The pin drifts silently and the repository is large.** HEAD is `v0.37.0`; the running
  proxy is `0.27.0`, ten minor versions behind, and `headroom update --check` is the only
  thing that will tell you. A shallow clone of the source is 104 MB.
- **Intel macOS has no native wheel.** Apple Silicon and Linux are covered; Intel needs
  Docker or a system ONNX Runtime.
