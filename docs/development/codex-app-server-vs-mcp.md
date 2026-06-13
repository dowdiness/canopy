# Codex: app-server vs MCP

Two ways to drive OpenAI Codex from this project's tooling: the **MCP interface**
(`mcp__codex__codex`) and the **app-server** (stdio or the daemon's WebSocket
control socket). This doc compares them and says when to use which.

Verified end-to-end 2026-06-13 against `codex-cli 0.131.0-alpha.4` (the npm
`@openai/codex` distribution). Protocol/setup details: see the agent-memory
reference `reference_codex_app_server_driving`. Working client:
[`scripts/codex-app-server-turn.py`](../../scripts/codex-app-server-turn.py).

## TL;DR

For Codex's roles in this repo — **design validation, code review, second
opinions** — use the **MCP interface**. It does exactly that with zero setup.

Reach for the **app-server** only when building *on* Codex: live token
streaming, interactive per-event approvals, `thread/fork` / `turn/steer` /
`turn/interrupt`, or serving multiple clients. Its advantages don't pay off when
you're merely *consulting* Codex.

## Side-by-side

| Dimension | MCP (`mcp__codex__codex`) | app-server (stdio / WS control socket) |
|---|---|---|
| Setup in this env | None — already wired into the harness | Heavy: standalone-install symlink hack + `daemon bootstrap`/`start`; `/tmp` bind EPERM; sandbox/namespace traps |
| Interaction model | Request/response; returns final assembled text | Hand-managed protocol: handshake + streaming events + approval replies |
| Statefulness | `threadId` + `codex-reply`, no bookkeeping | `thread/*` lifecycle you manage yourself |
| Streaming visibility | None — black-box turn | Full: `agentMessage`/reasoning/command-output deltas, item lifecycle, token usage, rate limits |
| API surface | Only what the MCP tool exposes | Full ~75-method API: `thread/fork`, `thread/resume`, `turn/interrupt`, `turn/steer`, listeners |
| Approvals | Delegated to MCP server policy | Interactive: server→client `requestApproval` answered per event |
| Per-call config | `model`, `sandbox`, `approval-policy`, `cwd` | Same, per thread/turn |
| Multi-client | No | Daemon designed to serve several clients (e.g. IDE over SSH) |
| Harness integration | Native: permissioned, logged, counts as a delegation decision | Driven via Bash + script; no native permissioning/logging; awkward across one-shot calls |
| Stability | Stable wrapper | `[experimental]` subcommands; protocol can shift between versions |
| Lifecycle risk | Tied to MCP host | Persistent daemon to manage; `autoUpdateEnabled` pointed at a symlinked binary is a footgun |

## MCP — pros / cons

**Pros**
- Zero setup; worked on the first call.
- Simple request/response — returns the final text; no WS framing or streaming parse.
- Clean statefulness via `threadId` / `codex-reply`.
- Native to the tool layer: permissioned, logged, delegation-tracked.
- Exposes `model` / `sandbox` / `approval-policy` / `cwd` per call.

**Cons**
- Coarse-grained black box — no live deltas, reasoning, command output, or token usage.
- Limited surface — no `thread/fork`, `turn/steer`, `turn/interrupt`, listeners.
- Approval policy is delegated; no interactive mid-turn control.
- Tied to the MCP host lifecycle.

## app-server — pros / cons

**Pros**
- Full protocol surface — everything the IDE extensions use.
- Real-time streaming events (deltas, item lifecycle, token usage, rate limits) — needed for a UI or fine-grained monitor.
- Interactive approvals — answer command/file-change requests per event.
- Persistent daemon can serve multiple clients.
- Closest to source of truth; schema-introspectable via `generate-json-schema` / `generate-ts`.

**Cons**
- Heavy setup in this environment (see table).
- You hand-manage the protocol: WebSocket client (the `proxy` subcommand is a dumb byte relay, not an adapter), `initialize`/`initialized` handshake, streaming parse, approval replies, lifecycle.
- Not native to the harness — driven via Bash + a script.
- Experimental; protocol may change between versions.

## Transport / framing note

The app-server has **two transports with different framings**:

- **stdio** (`codex app-server`) → newline-delimited JSON-RPC, one object per line.
- **unix / daemon control socket** → **WebSocket** (RFC 6455), one JSON-RPC object
  per text frame. Raw JSON fails the HTTP/1.1 upgrade and the server drops the
  connection (the "accept-then-EOF" symptom). `codex app-server proxy` is a dumb
  byte relay (`tokio::io::copy`), **not** a protocol adapter — you must speak
  WebSocket yourself.

Per-connection protocol:
`initialize` → `initialized` (required notification) → `thread/start` →
`turn/start` → stream events until `turn/completed`. Streaming notifications of
interest: `item/agentMessage/delta` (incremental text) and `item/completed`
(`.item.text` = full answer for `agentMessage` items).

## When to use which

| Goal | Use |
|---|---|
| Design validation, code review, second opinions (the Codex roles in CLAUDE.md) | **MCP** |
| Building/testing an integration; need streaming, interactive approvals, fork/steer/interrupt, or multi-client serving | **app-server** |
