# Ephemeral Store v2 — Hub, Namespaces & Sync Protocol

**Date:** March 19, 2026
**Status:** Draft
**Scope:** `editor/` (parent crdt repo)
**Builds on:** [Phase 04 — Ephemeral Store](../design/04-ephemeral-store.md)
**Inspired by:** [mizchi/converge](https://github.com/mizchi/converge) two-tier architecture

## Goal

Extend the existing Ephemeral Store with namespace-based organization, richer projectional editor presence state, and a multiplexed sync protocol — enabling multi-peer collaboration over WebSocket.

## Problem

The existing Ephemeral Store (Phase 04) is fully implemented and tested. It provides LWW registers, binary encoding, timeout cleanup, cursor awareness, and subscriptions. But it lacks:

1. **Organization:** Flat key-value store mixes cursor positions, edit mode, drag state, and presence in one namespace. No way to query "all cursors" or "all presence" without filtering.
2. **Presence coverage:** Only cursor positions are modeled. The text delta design's no-op operations (`Select`, `StartEdit`, `StartDrag`, `DragOver`) need an ephemeral sync path for collaborative visibility.
3. **Transport:** `encode()`/`apply()` exist for binary sync, but there's no protocol layer for multiplexing CRDT ops and ephemeral state over a shared connection, no peer join/leave handling, no relay architecture.

## Design

### Architecture Overview

```
SyncEditor
├── CrdtDoc (eg-walker)          — document state (existing)
├── EphemeralHub                  — NEW: manages per-namespace stores
│   ├── cursor_store      (timeout: 30s)  — position + selection
│   ├── edit_mode_store   (timeout: 60s)  — which node a peer is editing
│   ├── drag_store        (timeout: 5s)   — drag source + drop target
│   ├── presence_store    (timeout: 120s) — name, color, online status
│   └── Typed views (PeerCursorView, EditModeView, DragStateView, PresenceView)
├── SyncTransport (trait)         — NEW: transport abstraction
│   ├── WebSocketTransport        — production
│   └── InMemoryTransport         — testing
└── Message demuxer               — routes incoming messages by type
```

### One Trait, Everything Else Concrete

Following MoonBit trait design principles: only introduce a trait when multiple implementations are needed. The entire design has one trait.

**`SyncTransport` — the only trait (Capability pattern, 3 methods):**

```moonbit
trait SyncTransport {
  send(Self, Bytes) -> Unit
  on_receive(Self, (Bytes) -> Unit) -> Unit
  close(Self) -> Unit
}
```

Two implementations: `WebSocketTransport` (production) and `InMemoryTransport` (testing). WebRTC slots in as a third implementation later. The transport is point-to-point to a relay server; the relay handles fan-out to other peers.

**Everything else is concrete types.** Rationale per type:

- `SyncMessage` — closed enum. Adding a message type means a protocol version bump.
- `EphemeralNamespace` — closed enum. Coupled to editor features.
- `EphemeralHub` — one implementation. No reason for a trait.
- View types (`EditModeState`, `DragState`, `PeerPresence`) — concrete structs with plain `to_ephemeral()`/`from_ephemeral()` methods. No `ToEphemeral` trait — the hub always knows the concrete type per namespace. A trait here would be phantom generality.

### Wire Format & Message Protocol

Single multiplexed WebSocket connection. WebSocket framing handles message boundaries.

```
WebSocket message:
  [version: u8][message_type: u8][flags: u8][payload: bytes]

flags (bit field, reserved for BFT — see bft-adapter-design.md):
  0x00 = no BFT (default for v1)
  bit 0 = has_bft (all BFT fields follow payload: digest, signature, author_key, dep_digests)
  bits 1-7 = reserved

version:
  0x01 = v1 (this design)

message_type:
  0x01 = CRDT ops (eg-walker events)
  0x02 = Ephemeral update
  0x03 = CRDT sync request (pull missing events)
  0x04 = CRDT sync response
  0x05 = Room control

Ephemeral update payload (0x02):
  [namespace: u8][existing EphemeralStore binary encoding]

namespace:
  0x01 = cursor (position + selection range)
  0x02 = edit_mode (node being edited)
  0x03 = drag (source node + drop target + position)
  0x04 = presence (display name, color, status)

Room control payload (0x05):
  [sub_type: u8][payload]
  sub_type:
    0x01 = Join(peer_id as uvarint-prefixed string)
    0x02 = Leave(peer_id as uvarint-prefixed string)
    0x03 = PeerList(uvarint count + peer_id strings)  // future
```

**`SyncMessage` enum:**

```moonbit
pub enum SyncMessage {
  CrdtOps(Bytes)
  EphemeralUpdate(EphemeralNamespace, Bytes)
  SyncRequest(Bytes)
  SyncResponse(Bytes)
  PeerJoined(String)
  PeerLeft(String)
}
```

With `encode_message(SyncMessage) -> Bytes` and `decode_message(Bytes) -> SyncMessage?` for wire conversion.

**Delivery semantics differ by message type:**

| Type | Delivery | Persistence | Rationale |
|------|----------|-------------|-----------|
| CRDT ops (0x01) | Reliable, ordered | Relay stores for late joiners | Document integrity requires lossless delivery |
| Ephemeral (0x02) | Best-effort broadcast | None — memory only | Stale state replaced by next heartbeat; loss is harmless |
| Sync req/resp (0x03-04) | Reliable | N/A | One-shot request-response for catch-up |
| Room control (0x05) | Reliable | N/A | Peer join triggers full ephemeral state sync |

**Peer join sequence:**

1. New peer sends `0x05 Join` with peer ID
2. Relay broadcasts `0x05 PeerJoined` to existing peers
3. Each existing peer sends `hub.encode_all()` (full ephemeral state across all namespaces) to new peer
4. New peer sends CRDT sync request (`0x03`) with its version vector
5. Relay (or peers) respond with missing CRDT events (`0x04`)

The existing `encode()`/`apply()` binary format is untouched — it's wrapped in the namespace envelope at the hub level.

### EphemeralHub & Namespace Management

```moonbit
pub enum EphemeralNamespace {
  Cursor      // 0x01
  EditMode    // 0x02
  Drag        // 0x03
  Presence    // 0x04
}

pub struct EphemeralHub {
  local_peer_id : String
  wire_peer_id : String          // to_wire_peer_id(local_peer_id) — used as key in all stores
  stores : Map[EphemeralNamespace, EphemeralStore]
}
```

**Per-namespace timeout:**

```moonbit
fn default_timeout(ns : EphemeralNamespace) -> UInt64 {
  match ns {
    Cursor => 30_000UL      // 30s — stale cursors disappear quickly
    EditMode => 60_000UL    // 60s — editing sessions last longer
    Drag => 5_000UL         // 5s — drags are very transient
    Presence => 120_000UL   // 120s — with 30s heartbeat interval
  }
}
```

**Typed API (hides EphemeralValue serialization):**

```moonbit
// Write (always local peer)
hub.set_cursor(position, selection?)
hub.set_edit_mode(node_id)
hub.clear_edit_mode()
hub.set_drag(source_id, target_id?, position?)
hub.clear_drag()
hub.set_presence(display_name, color, status)

// Read
hub.get_cursor(peer_id) -> PeerCursor?
hub.get_edit_mode(peer_id) -> EditModeState?
hub.get_all_editing() -> Map[String, EditModeState]
hub.get_presence(peer_id) -> PeerPresence?
hub.get_online_peers() -> Array[PeerPresence]

// Sync
hub.encode(namespace, peer_id) -> Bytes
hub.encode_all() -> Bytes
hub.apply(namespace, bytes) -> Unit

// Lifecycle
hub.remove_outdated() -> Unit
hub.on_peer_leave(peer_id) -> Unit
```

**Key mapping:** The hub converts `local_peer_id` to a wire peer ID via `to_wire_peer_id()` at construction time. All store operations use this wire ID as the key, matching the existing `EphemeralStore.set()` validation that requires numeric peer IDs. Read operations accept either the wire ID or the original peer ID (the hub resolves the mapping).

**`encode_all()` wire format:** `[namespace_count: u8]` then for each namespace: `[namespace: u8][existing encode_entries() output]`. The existing `encode_entries()` uses uvarint for entry count, so this embeds directly with no format mismatch.

**`on_peer_leave(peer_id)` calls `store.delete(wire_peer_id)` on each namespace store.** This fires `removed` subscription events per store, so `PeerCursorView` and other listeners are notified automatically. One call removes cursor, edit mode, drag, and presence for the departing peer.

### View Types

**Existing (unchanged):**

```moonbit
pub(all) struct PeerCursor {
  mut raw_cursor : Int
  mut adjusted_cursor : Int
  mut display_name : String
  mut color : String
  mut selection : (Int, Int)?
}
```

`PeerCursorView` continues to handle `adjust_for_edit()`. Its role narrows: it derives from `hub.cursor_store` subscriptions rather than being standalone.

**Cursor/presence field ownership:** The cursor namespace stores position and selection only. Display name and color live in the presence namespace. `PeerCursorView` joins data from both namespaces: it subscribes to cursor store for position updates and to presence store for name/color. The `apply_raw_update()` method is split into `apply_cursor_update()` and `apply_presence_update()`. This avoids redundant data across namespaces at the cost of slightly more complex subscription wiring.

**Cursor timeout note:** The 30s cursor timeout is safe because cursor updates are event-driven — every cursor movement resets the timer. The 30s timeout only triggers for truly idle cursors (peer has not moved their cursor in 30s), which is the correct behavior for removing stale indicators.

**New view types:**

```moonbit
pub(all) struct EditModeState {
  node_id : String
}

pub(all) enum DragPosition {
  Before
  After
  Inside
}

pub(all) struct DragState {
  source_id : String
  target : (String, DragPosition)?  // (target_id, position) — both present or both absent
}

pub(all) enum PresenceStatus {
  Active
  Idle
}

pub(all) struct PeerPresence {
  peer_id : String
  display_name : String
  color : String
  status : PresenceStatus
}
```

Each has `to_ephemeral() -> EphemeralValue` and `from_ephemeral(EphemeralValue) -> Self?` as plain methods (not traits).

### Integration with SyncEditor

**Data flow — local edit:**

```
User action
  │
  ├─ Text edit → CrdtDoc.apply() → transport.send(encode(CrdtOps(bytes)))
  │                               → hub.set_cursor(new_pos)
  │                                 → transport.send(encode(EphemeralUpdate(Cursor, bytes)))
  │
  ├─ Start editing node → hub.set_edit_mode(node_id)
  │                        → transport.send(encode(EphemeralUpdate(EditMode, bytes)))
  │
  ├─ Drag node → hub.set_drag(source, target, pos)
  │               → transport.send(encode(EphemeralUpdate(Drag, bytes)))
  │
  └─ Heartbeat (timer, every 30s) → hub.set_presence(name, color, Active)
                                     → transport.send(encode(EphemeralUpdate(Presence, bytes)))
```

**Data flow — incoming message:**

```
transport.on_receive → decode_message(bytes) match {
  │
  ├─ CrdtOps(bytes) → crdt_doc.apply_remote(bytes)
  │                  → cursor_view.adjust_for_edit(edit)
  │
  ├─ EphemeralUpdate(ns, bytes) → hub.apply(ns, bytes)
  │                               → subscription fires → UI updates
  │
  ├─ SyncRequest(versions) → compute missing events
  │                         → transport.send(encode(SyncResponse(events)))
  │
  ├─ SyncResponse(bytes) → crdt_doc.apply_remote(bytes)
  │
  ├─ PeerJoined(peer_id) → for each namespace ns:
  │                          transport.send(encode(EphemeralUpdate(ns, hub.encode_ns(ns))))
  │
  └─ PeerLeft(peer_id) → hub.on_peer_leave(peer_id)
}
```

**SyncEditor gains three fields:**

```moonbit
hub : EphemeralHub
transport : &SyncTransport
peer_id : String
```

**Ordering guarantee:** CRDT ops must be applied before cursor adjustment. The message handler processes `CrdtOps` synchronously — `apply_remote` → reparse → `adjust_for_edit` — before processing any queued ephemeral updates. This ensures cursors are adjusted against the correct document state.

**Timeout cleanup — single timer:**

```moonbit
fn tick(self : SyncEditor) -> Unit {
  self.hub.remove_outdated()
}
```

Called every 10s. Each store applies its own timeout threshold.

## What Changes

**New files:**
- `editor/ephemeral_hub.mbt` — `EphemeralHub`, `EphemeralNamespace`
- `editor/ephemeral_hub_test.mbt` — hub tests
- `editor/sync_protocol.mbt` — `SyncMessage`, `SyncTransport` trait, encode/decode
- `editor/sync_protocol_test.mbt` — protocol tests
- `editor/presence_types.mbt` — `EditModeState`, `DragState`, `PeerPresence`, `PresenceStatus`, `DragPosition`
- `editor/in_memory_transport.mbt` — `InMemoryTransport`, `InMemoryRoom`

**Modified files:**
- `editor/sync_editor.mbt` — replaces `ephemeral: EphemeralStore` + `cursor_view: PeerCursorView` with `hub: EphemeralHub` + `transport: &SyncTransport` + `peer_id: String`
- `editor/sync_editor_sync.mbt` — adds message demuxer (`decode_message` → route to CRDT or hub)
- `editor/cursor_view.mbt` — `PeerCursorView` joins cursor + presence namespaces; `apply_raw_update()` split into `apply_cursor_update()` + `apply_presence_update()`
- `editor/moon.pkg.json` — no new external dependencies

**Unchanged:**
- `editor/ephemeral.mbt` — core EphemeralStore (untouched, used as-is by hub)
- `editor/ephemeral_encoding.mbt` — binary codec (untouched, reused)
- `editor/ephemeral_test.mbt` — existing tests remain valid
- `editor/ephemeral_wbtest.mbt` — existing whitebox tests remain valid

## Testing Strategy

Using `InMemoryTransport` to simulate a relay server in-process:

```moonbit
struct InMemoryTransport {
  peer_id : String
  room : InMemoryRoom
}

struct InMemoryRoom {
  peers : Map[String, Array[(Bytes) -> Unit]]
}
```

When `peer_a.send(bytes)`, the room calls `on_receive` handlers on all other peers. Identical semantics to a real relay.

**Test scenarios:**

1. **Two-peer cursor sync** — Peer A edits, peer B sees cursor update. Verify `adjust_for_edit` shifts B's view of A's cursor correctly.
2. **Edit mode conflict visibility** — Peer A starts editing node X, peer B sees the indicator. Peer B can check `hub.get_all_editing()` before starting their own edit.
3. **Drag state lifecycle** — Peer A starts drag, B sees indicator. A drops or cancels, B sees cleanup. Verify 5s timeout clears stale drag if A disconnects mid-drag.
4. **Peer join catch-up** — A and B are connected. C joins. C receives full ephemeral state from A and B via `encode_all()`. Verify C sees both cursors and presence.
5. **Peer leave cleanup** — A disconnects. B receives `PeerLeft("A")`. Verify all of A's entries (cursor, edit mode, drag, presence) are removed from B's hub.
6. **CRDT-then-ephemeral ordering** — A sends a text edit + cursor update. B processes CRDT ops first, then cursor. Verify cursor position is correct relative to new document state.
7. **Timeout expiry** — Peer A sets presence, then goes silent. After 120s (simulated via backdating), verify A's presence is removed and timeout event fires.
8. **Convergence** — Three peers each set `edit_mode` on the same node concurrently with different clocks. After all messages propagate, verify all three hubs resolve to the highest-clock value. Then each peer sets cursor to a different position. After propagation, verify each hub has all three cursors with correct positions.

**Not tested in v2 (future work):**
- Network partitions
- Message reordering (WebSocket guarantees ordering)
- Star/mesh/gossip topologies

## What This Does NOT Change

- The incremental parser / loom framework
- The CST, SyntaxNode, Term types
- The CRDT (eg-walker) integration internals
- `reconcile_flat_proj` / `reconcile_ast` reconciliation
- The reactive memo pipeline in `projection_memo.mbt`
- The existing EphemeralStore core implementation
- The existing binary encoding format

## References

- [Phase 04 — Ephemeral Store](../design/04-ephemeral-store.md) — original design (this builds on it)
- [mizchi/converge](https://github.com/mizchi/converge) — two-tier architecture inspiration (durable + ephemeral layers, namespace-based organization)
- [Projectional Edit Text Delta Design](2026-03-18-projectional-edit-text-delta-design.md) — no-op operations that need ephemeral sync
- [Phase 03 — Unified Editor](../design/03-unified-editor.md) — SyncEditor integration plan
