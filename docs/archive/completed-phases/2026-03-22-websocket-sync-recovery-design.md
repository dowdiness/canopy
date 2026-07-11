# WebSocket Sync Recovery — Design Spec

**Date:** 2026-03-22
**Status:** Draft (revised after Codex review)
**Scope:** Recover from failed `apply_sync` via `SyncRequest`/`SyncResponse` peer-addressed recovery protocol

## Problem

When `apply_sync` fails with a retryable error (e.g., `MissingDependency` — the incoming ops reference causal history the local peer doesn't have), the error is silently caught and the editor diverges from the peer. There is no recovery mechanism.

```moonbit
// Current behavior in sync_editor_ws.mbt:
try {
  let crdt_msg = @text.SyncMessage::from_json_string(json_str)
  self.apply_sync(crdt_msg)
} catch {
  _ => ()  // Silent divergence
}
```

The `SyncRequest` and `SyncResponse` wire protocol variants exist but are no-ops (`=> ()`).

## Goals

- Automatically recover from retryable sync failures without user intervention
- Identify which peer caused the failure and request missing state from them specifically
- Limit retry attempts with exponential backoff to prevent infinite loops
- Surface unrecoverable failures in the UI via `SyncStatus::Error`
- Work over the relay server (primary) and be compatible with future P2P connections

## Non-Goals

- Full state resync (too risky — can silently discard local work)
- Automatic conflict resolution beyond what eg-walker already provides
- Relay server persistence (recovery is peer-to-peer, relay is stateless forwarder)

## Design

### Wire Protocol v2

**Protocol version bump:** The protocol version byte changes from `0x01` to `0x02`. All participants (relay + clients) must upgrade together. This is acceptable because:
- The relay and all clients are deployed from the same repo
- There is no third-party client compatibility to maintain
- Capability negotiation adds complexity for zero benefit in this deployment model

Old clients receiving v2 messages will return `None` from `decode_message` (existing behavior for unknown versions). This is the same silent drop as today — no worse than current behavior.

**New message type `0x06` = `RelayedCrdtOps`:**

The sender sends plain `CrdtOps` (`0x01`) as before. The relay upgrades it to `RelayedCrdtOps` with the sender's peer ID:

```
[version=0x02][type=0x06][flags=0x00][sender_id (write_string: uvarint len + utf8)][original_payload_bytes]
```

Recipients decode the sender ID and payload separately. The sender's code is unchanged.

**Peer-addressed `SyncRequest`/`SyncResponse`:**

These are targeted (not broadcast). The wire format uses existing `write_string`/`read_string` (uvarint-length-prefixed) for all string fields:

```
SyncRequest:
  [version=0x02][type=0x03][flags=0x00]
  [target_id (write_string)]     -- who to send this to
  [request_id (write_string)]    -- correlator for response matching
  [version_json (write_string)]  -- requester's version

SyncResponse:
  [version=0x02][type=0x04][flags=0x00]
  [target_id (write_string)]         -- who to send this to
  [request_id (write_string)]        -- copied from the request
  [sync_message_json (write_string)] -- delta ops (empty string if export_since failed)
```

The relay reads `target_id`, wraps the message with the sender's peer ID (prepended via `write_string`), and calls `send_to(target_id, wrapped_data)`.

After relay wrapping, the recipient sees:

```
SyncRequest (received):
  [header][sender_id (write_string)][request_id (write_string)][version_json (write_string)]

SyncResponse (received):
  [header][sender_id (write_string)][request_id (write_string)][sync_message_json (write_string)]
```

The `request_id` is a monotonically increasing counter (`recovery_epoch`) on the requester. Stale responses (where `request_id` doesn't match the current pending recovery) are ignored.

### Recovery State Machine

```
                       ┌─────────────────────────────────────────┐
                       │                                         │
Normal ──(apply_sync fails, retryable)──> Recovering(peer_id)   │
  ▲                                            │                 │
  │                                   Send SyncRequest           │
  │                                   Start timeout (3s)         │
  │                                   Buffer peer's messages     │
  │                                            │                 │
  │                                  Waiting for SyncResponse    │
  │                                    │        │        │       │
  │                              response   timeout   PeerLeft   │
  │                              arrives    fires     arrives    │
  │                                 │        │          │        │
  │                            Apply delta   │     Abort recovery│
  │                            Retry pending │     Drain buffer  │
  │                            Drain buffer  │          │        │
  │                                 │        └──────────┼────────┘
  │                          ┌──────┴───────┐           │
  │                        Success     Still fails      │
  │                          │        (retries < 3)     │
  │                          │             │            │
  │                          │       Backoff × 2        │
  │                          │       Send SyncRequest   │
  │                          │             │            │
  └──────────────────────────┘        (retries = 3)     │
                                           │            │
                                    SyncStatus::Error ◄─┘
                                    Drain buffer (drop)
```

**Recovery context (per-peer):**

```moonbit
struct RecoveryContext {
  peer_id : String               // peer we're recovering from
  retries : Int                  // current retry count (0-3)
  pending_msg : @text.SyncMessage // the failed message to retry
  deferred : Array[(@text.SyncMessage, String)]  // buffered messages from this peer: (msg, request_id)
  backoff_ms : Int               // current delay (500 → 1000 → 2000)
  request_id : String            // current request correlator
}
```

**State on `SyncEditor`:**

```moonbit
recovery : RecoveryContext?      // None = not recovering
recovery_epoch : Int             // monotonic counter for request_id generation
```

**Key rules:**

1. **One recovery at a time.** If recovery is active for peer X and peer Y's message also fails, Y's message is dropped (same as current behavior). This keeps the state machine simple. The Y failure is likely caused by the same missing history — once X's recovery fills the gap, Y's future messages should succeed.

2. **Buffer same-peer messages.** While recovering from peer X, new messages from X are buffered in `deferred` (up to 32 entries, drop oldest if full). After successful recovery, buffered messages are applied in order.

3. **Other peers are unaffected.** Messages from peers other than `recovery.peer_id` are applied normally. If they fail, they are dropped (not a second recovery — rule 1).

4. **Timeout.** If no `SyncResponse` arrives within 3 seconds, count it as a failed retry. Increment retries, double backoff, send another `SyncRequest`. The 3s timeout is implemented via `js_set_timeout` calling a trigger button.

5. **PeerLeft during recovery.** If `PeerLeft(recovery.peer_id)` arrives, abort recovery immediately. Drain and drop buffered messages. Set `SyncStatus::Error` (the peer left, so we can't recover from them). If the peer rejoins (`PeerJoined`), the normal full-state exchange will fill the gap.

6. **Socket close during recovery.** Abort recovery, clear all state. Reconnection triggers `PeerJoined` exchange which naturally resyncs.

7. **Stale responses.** `SyncResponse` with a `request_id` that doesn't match `recovery.request_id` is ignored (late response from a previous retry).

8. **Empty response.** If `SyncResponse` contains an empty `sync_message_json`, the responder couldn't satisfy the version (e.g., `VersionNotFound`). Count as failed retry — the responder lacks the history too, retrying won't help. After 3 attempts, escalate to `SyncStatus::Error`.

**Backoff schedule:** 500ms → 1000ms → 2000ms → give up.

### Message Flow

**Happy path (no failure):**

```
Peer A edits → CrdtOps → Relay → RelayedCrdtOps(sender="A") → Peer B
Peer B: apply_sync succeeds → done
```

**Recovery path:**

```
Peer A edits → CrdtOps → Relay → RelayedCrdtOps(sender="A") → Peer B
Peer B: apply_sync fails (MissingDependency) → enter recovery(peer="A")
Peer B: SyncRequest(target="A", request_id="1", my_version) → Relay → forward to Peer A
Peer A: receives SyncRequest → export_since(requester_version) → SyncResponse(target="B", request_id="1", ops) → Relay → forward to Peer B
Peer B: apply SyncResponse(request_id="1" matches) → retry pending → success
Peer B: drain deferred messages from A → apply each → exit recovery
```

**Responder (Peer A) handling:**

When a peer receives `SyncRequest`:
1. **Rate limit:** If this peer already responded to a `SyncRequest` from the same requester within the last 1 second, ignore (prevents amplification).
2. Parse the requester's version from `version_json`.
3. Call `export_since(requester_version)` to get the delta.
4. If `export_since` fails, send `SyncResponse` with empty `sync_message_json`.
5. Otherwise send `SyncResponse` with the delta.
6. Cap response size: if the serialized delta exceeds 1MB, send empty response instead (the requester will need a full resync via page reload).

### Relay Changes

`RelayRoom` needs two additions:

1. **`send_to(peer_id, data)`** — find peer by ID, call their `send_fn`. Returns silently if peer not found.

2. **Message type detection in `on_message`:**

   The relay inspects the message to determine routing. **Safety guard:** if `data.length() < 3`, fall back to current broadcast behavior (no parsing).

   For valid frames (`length >= 3` and `version == 0x02`):
   - `0x01` (CrdtOps): wrap as `RelayedCrdtOps` (`0x06`) with sender ID, then `broadcast(exclude=sender)`
   - `0x03` (SyncRequest) / `0x04` (SyncResponse): read `target_id` from payload, wrap with sender ID, `send_to(target)`. If target not found, drop silently.
   - `0x02` (EphemeralUpdate), `0x05` (PeerJoined/PeerLeft): `broadcast(exclude=sender)` as before
   - Unknown type or `version != 0x02`: `broadcast(exclude=sender)` (forward-compatible)

   For short/malformed frames: `broadcast(exclude=sender)` (current behavior preserved).

### Editor Changes

**`sync_editor_ws.mbt` — `ws_on_message` updates:**

- `RelayedCrdtOps(sender, payload)`:
  - If currently recovering from `sender`: buffer the message in `deferred`
  - Otherwise: attempt `apply_sync`. On retryable failure, enter recovery targeting `sender`. On non-retryable failure, drop.
- `SyncRequest(sender, request_id, version_json)`:
  - Rate-limit check (1 per sender per second)
  - `export_since(version)` → `SyncResponse(target=sender, request_id, delta)`
- `SyncResponse(sender, request_id, delta)`:
  - If `request_id` doesn't match `recovery.request_id`, ignore (stale)
  - If empty delta, count as failed retry
  - Otherwise: apply delta, retry `recovery.pending_msg`, drain `deferred`, exit recovery or increment retries

**`sync_editor.mbt` — new fields:**

```moonbit
recovery : RecoveryContext?
recovery_epoch : Int
```

**FFI (`crdt_websocket.mbt`):** No changes — `ws_on_message` already passes raw bytes.

**TypeScript:** No changes to client code. The relay wrapping is transparent. Timer for recovery timeout uses existing `js_set_timeout` pattern.

### Error Classification

Uses the existing `TextError::is_retryable()`:

| Error | Retryable | Recovery action |
|-------|-----------|-----------------|
| `MissingDependency` | Yes | Enter recovery |
| `VersionNotFound` | Yes | Enter recovery |
| `Timeout` | Yes | Enter recovery |
| `MalformedMessage` | No | Drop silently |
| `Internal` | No | Drop silently |

Non-retryable errors are dropped (same as current behavior). They indicate a bug in the sender, not a recoverable state.

### Security: Rate Limiting

**Responder side:** Track `last_sync_request_time` per sender. Ignore `SyncRequest` if the previous response to the same sender was less than 1 second ago.

**Response size cap:** If `export_since` produces a delta larger than 1MB serialized, send empty response. This prevents a malicious peer from requesting ancient history to force expensive exports.

**Buffer cap:** Deferred message buffer is limited to 32 entries per recovery context. If full, drop the oldest entry. This prevents memory exhaustion from a flooding peer.

### UI Impact

When recovery is exhausted (3 retries) or peer disconnects during recovery, set `SyncStatus::Error`. The existing sync status panel shows a red dot with "Connection error." No new UI components needed.

When recovery succeeds, `SyncStatus` stays `Connected` — recovery is invisible to the user.

## Files Changed

| File | Change |
|------|--------|
| `relay/relay_room.mbt` | Add `send_to`, message type detection with safety guards in `on_message` |
| `editor/sync_protocol.mbt` | Protocol v2, add `RelayedCrdtOps` variant, peer-addressed `SyncRequest`/`SyncResponse` with `request_id`, use `write_string`/`read_string` |
| `editor/sync_editor_ws.mbt` | Handle `RelayedCrdtOps`, `SyncRequest`, `SyncResponse`; recovery state machine with buffering, timeout, rate limiting |
| `editor/sync_editor.mbt` | Add `RecoveryContext`, `recovery`, `recovery_epoch` fields |

## Test Plan

**Unit tests — wire protocol:**
- Encode/decode `RelayedCrdtOps` roundtrip (v2)
- Encode/decode peer-addressed `SyncRequest`/`SyncResponse` with `request_id` roundtrip
- Old v1 messages return `None` from v2 decoder (backward compat)
- Short/malformed frames return `None`

**Unit tests — relay:**
- `RelayRoom::send_to` delivers to correct peer
- `RelayRoom::send_to` for unknown peer is silent no-op
- `RelayRoom::on_message` wraps `CrdtOps` as `RelayedCrdtOps` with sender ID
- `RelayRoom::on_message` routes `SyncRequest`/`SyncResponse` to target peer
- `RelayRoom::on_message` broadcasts short/malformed frames unchanged
- `RelayRoom::on_message` broadcasts unknown message types

**Unit tests — recovery state machine:**
- Enter recovery on retryable error
- Don't enter recovery on non-retryable error
- Stale `SyncResponse` (wrong `request_id`) ignored
- Empty `SyncResponse` counts as failed retry
- Retry with backoff (500 → 1000 → 2000)
- Recovery exhaustion → `SyncStatus::Error`
- `PeerLeft` during recovery → abort, `SyncStatus::Error`
- Buffer overflow (>32 messages) drops oldest
- Same-peer messages buffered during recovery
- Other-peer messages applied normally during recovery

**Integration tests:**
- 2-peer relay sync with simulated `MissingDependency` → recovery → convergence
- 3-peer where only one pair needs recovery, third peer unaffected
- Recovery exhaustion → `SyncStatus::Error`
- Peer disconnect during recovery → abort → rejoin → full sync via `PeerJoined`

## References

- `editor/sync_protocol.mbt` — existing wire protocol (v1)
- `editor/sync_editor_ws.mbt` — current `ws_on_message` handler
- `editor/ephemeral_encoding.mbt` — `write_string`/`read_string` codec helpers
- `event-graph-walker/text/errors.mbt` — `TextError::is_retryable()`
- `event-graph-walker/text/text_test.mbt` — existing sync recovery tests at CRDT layer
- `relay/relay_room.mbt` — relay room implementation
