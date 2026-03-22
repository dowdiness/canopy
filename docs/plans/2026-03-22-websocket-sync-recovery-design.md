# WebSocket Sync Recovery — Design Spec

**Date:** 2026-03-22
**Status:** Draft
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

### Wire Protocol: Sender-Tagged Messages

Currently the relay broadcasts `CrdtOps` without identifying the sender. Recovery requires knowing which peer's message failed.

**New message type `0x06` = `RelayedCrdtOps`:**

The sender sends plain `CrdtOps` (`0x01`) as before. The relay upgrades it to `RelayedCrdtOps` with the sender's peer ID prepended:

```
[version=0x01][type=0x06][flags=0x00][sender_id_len:u16][sender_id:utf8][original_payload]
```

Recipients decode the sender ID and payload separately. The sender's code is unchanged.

**Peer-addressed `SyncRequest`/`SyncResponse`:**

These are targeted (not broadcast). The wire format includes a target peer ID so the relay can forward to a specific peer:

```
SyncRequest:  [header][target_id_len:u16][target_id:utf8][version_json]
SyncResponse: [header][target_id_len:u16][target_id:utf8][sync_message_json]
```

The relay reads the target peer ID and calls `send_to(target_id, data)` instead of `broadcast`. Before forwarding, the relay wraps the message with the sender's peer ID (same pattern as `RelayedCrdtOps`) so the recipient knows who is requesting/responding.

### Recovery State Machine

```
Normal ──(apply_sync fails, retryable)──> Recovering
                                              │
                                     Send SyncRequest to peer
                                     Start backoff timer (500ms)
                                              │
                                    Waiting for SyncResponse
                                              │
                                     (response arrives)
                                     Apply response, retry original
                                              │
                                       ┌──────┴───────┐
                                     Success        Still fails
                                       │           (retries < 3)
                                       │                │
                                       │          Backoff × 2
                                       │          Send SyncRequest again
                                       │                │
                                    Normal         (retries = 3)
                                                        │
                                                 SyncStatus::Error
                                                 "Sync failed" in UI
```

**State fields on `SyncEditor`:**

```moonbit
recovery_peer : String?              // peer we're recovering from (None = not recovering)
recovery_retries : Int               // current retry count (0-3)
recovery_pending_msg : @text.SyncMessage?  // the failed message to retry
recovery_backoff_ms : Int            // current delay (500 → 1000 → 2000)
```

**Backoff schedule:** 500ms, 1000ms, 2000ms, then give up.

**Key invariant:** While recovering from peer X, incoming messages from other peers are applied normally. Only peer X's failed message is retried. One bad peer does not block all collaboration.

### Message Flow

**Happy path (no failure):**

```
Peer A edits → CrdtOps → Relay → RelayedCrdtOps(sender="A") → Peer B
Peer B: apply_sync succeeds → done
```

**Recovery path:**

```
Peer A edits → CrdtOps → Relay → RelayedCrdtOps(sender="A") → Peer B
Peer B: apply_sync fails (MissingDependency) → enter recovery
Peer B: SyncRequest(target="A", my_version) → Relay → forward to Peer A
Peer A: receives SyncRequest → export_since(requester_version) → SyncResponse(target="B", ops) → Relay → forward to Peer B
Peer B: apply SyncResponse → retry original message → success → exit recovery
```

**Responder (Peer A) is stateless:** When a peer receives `SyncRequest`, it:

1. Parses the requester's version from the payload
2. Calls `export_since(requester_version)` to get the delta
3. Sends `SyncResponse` back via the relay

If `export_since` fails (`VersionNotFound`), the responder sends an empty `SyncResponse`. The requester counts this as a failed retry attempt.

### Relay Changes

`RelayRoom` needs two additions:

1. **`send_to(peer_id, data)`** — find peer by ID, call their `send_fn`. Used for `SyncRequest`/`SyncResponse` targeted delivery.

2. **Message type detection in `on_message`:**
   - `CrdtOps` (`0x01`): wrap as `RelayedCrdtOps` (`0x06`) with sender ID, then `broadcast(exclude=sender)`
   - `SyncRequest`/`SyncResponse` (`0x03`/`0x04`): read target peer ID from payload, wrap with sender ID, `send_to(target)`
   - All other types: `broadcast(exclude=sender)` as before

### Editor Changes

**`sync_editor_ws.mbt` — `ws_on_message` updates:**

- `RelayedCrdtOps(sender, payload)`: same as `CrdtOps` but on retryable failure, enter recovery targeting `sender`
- `SyncRequest(requester_version)`: respond with `export_since(version)` → `SyncResponse`
- `SyncResponse(delta)`: apply delta, retry `recovery_pending_msg`, exit recovery on success or increment retries

**`sync_editor.mbt` — new recovery fields** added to `SyncEditor` struct.

**No TypeScript changes** — the relay wrapping is transparent to the JS WebSocket layer.

### Error Classification

Uses the existing `TextError::is_retryable()`:

| Error | Retryable | Recovery action |
|-------|-----------|-----------------|
| `MissingDependency` | Yes | Send `SyncRequest` |
| `VersionNotFound` | Yes | Send `SyncRequest` |
| `Timeout` | Yes | Send `SyncRequest` |
| `MalformedMessage` | No | Log and drop |
| `Internal` | No | Log and drop |

Non-retryable errors are still silently dropped (same as current behavior). They indicate a bug in the sender, not a recoverable state.

### UI Impact

When recovery is exhausted (3 retries), set `SyncStatus::Error`. The existing sync status panel shows a red dot with "Connection error." No new UI components needed.

When recovery succeeds, `SyncStatus` stays `Connected` — recovery is invisible to the user.

## Files Changed

| File | Change |
|------|--------|
| `relay/relay_room.mbt` | Add `send_to`, message type detection in `on_message` |
| `editor/sync_protocol.mbt` | Add `RelayedCrdtOps` variant, peer-addressed `SyncRequest`/`SyncResponse` encoding |
| `editor/sync_editor_ws.mbt` | Handle `RelayedCrdtOps`, `SyncRequest`, `SyncResponse`; recovery state machine |
| `editor/sync_editor.mbt` | Add recovery fields to `SyncEditor` struct |

## Test Plan

**Unit tests:**
- Encode/decode `RelayedCrdtOps` roundtrip
- Encode/decode peer-addressed `SyncRequest`/`SyncResponse` roundtrip
- `RelayRoom::send_to` delivers to correct peer
- `RelayRoom::on_message` wraps `CrdtOps` as `RelayedCrdtOps`
- `RelayRoom::on_message` routes `SyncRequest`/`SyncResponse` to target peer
- Recovery state transitions: enter → retry → exhaust → Error status

**Integration tests:**
- 2-peer relay sync with simulated `MissingDependency` → recovery → convergence
- 3-peer where only one pair needs recovery, third peer unaffected
- Recovery exhaustion → `SyncStatus::Error`
- Non-retryable error (MalformedMessage) does not trigger recovery

## Open Questions

None — all design decisions resolved during brainstorming.

## References

- `editor/sync_protocol.mbt` — existing wire protocol
- `editor/sync_editor_ws.mbt` — current `ws_on_message` handler
- `event-graph-walker/text/errors.mbt` — `TextError::is_retryable()`
- `event-graph-walker/text/text_test.mbt` — existing sync recovery tests at CRDT layer
- `relay/relay_room.mbt` — relay room implementation
