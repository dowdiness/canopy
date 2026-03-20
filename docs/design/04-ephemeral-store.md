# Design 04: Ephemeral Store (Awareness Protocol)

**Parent:** [Grand Design](./GRAND_DESIGN.md)
**Status:** ✅ Implemented (EphemeralStore + EphemeralHub integrated into SyncEditor)
**Updated:** 2026-03-20

---

## Problem

`Editor.cursor` is local-only. In a collaborative editor, peers need to see each other's cursors and selections. This information must:

1. Travel over the network
2. **Not** be stored in the CRDT (cursors are ephemeral, not part of document history)
3. Survive remote edits (cursor positions shift when remote text changes)

---

## Design Overview

Following Loro's `EphemeralStore` and Lomo's MoonBit port, we adopt a **generic key-value ephemeral store** rather than a cursor-specific awareness struct. Cursor positions, selections, and display names are just values stored under string keys.

### Ephemeral Store vs. Document State

| | Document State | Ephemeral Store |
|---|---|---|
| **Persistence** | Permanent (OpLog) | In-memory only |
| **Conflict resolution** | CRDT convergence | LWW per key (logical clock) |
| **Transport** | `SyncMessage` | Binary-encoded updates |
| **Loss tolerance** | Must not lose | Can lose (re-sent periodically) |
| **Scope** | Shared document | Per-session presence |

### Key Design Decisions

**Generic KV, not cursor-specific.** The store maps `String → EphemeralValue?` with no opinion on what the values represent. Cursor positions, selections, user names, and colors are stored as structured values. This means:
- New presence data (e.g., "user is typing", "viewport range") requires no store changes
- The store is reusable beyond cursor awareness

**One writer per key.** Each key is owned by exactly one peer (the key is the peer's ID). Only the owner calls `set()` on its key; other peers receive updates via `apply()`. This avoids the need for a tiebreaker when concurrent writes produce equal clocks. (See [Limitations](#limitations) for details.)

**Logical clock for LWW, wall clock for timeout.** Following Lomo's design (which improves on Loro's timestamp-only approach):
- `clock: Int64` — monotonically incrementing counter per key, used for conflict resolution
- `updated_at: UInt64` — wall-clock timestamp, used only for timeout/expiry
- This avoids relying on synchronized clocks across peers for ordering

**Event-driven subscriptions.** Two subscription types:
- `subscribe_local_updates` — receives encoded bytes when local state changes (for sending to network)
- `subscribe` — receives structured events (`added`/`updated`/`removed` keys) for all changes (local, import, timeout)

**Cursor positions are derived, not stored adjusted.** The ephemeral store holds raw cursor positions as authored by each peer. After remote edits, a local-only derived view computes adjusted positions for rendering. The store itself is never mutated by non-owners. (See [Cursor Awareness Layer](#cursor-awareness-layer) for details.)

### Limitations

**No convergence for multi-writer keys.** If two peers both `set()` the same key concurrently without having received each other's updates, they may produce equal clock values. With the `existing.clock >= incoming.clock → discard` rule, both peers discard each other's write and permanently diverge. This is acceptable because the one-writer-per-key invariant prevents this scenario. If multi-writer keys are ever needed, add a tiebreaker (e.g., higher peer ID wins on equal clock).

**Keys are numeric peer IDs at the wire level.** The binary encoding format represents keys as `UInt64` for compactness and Loro wire compatibility. Non-numeric string keys are silently dropped during encoding. The in-memory API accepts `String` keys, but only numeric strings survive a network roundtrip. **`set()` should validate keys** — call `parse_peer_id(key)` and raise/return an error on failure, rather than silently succeeding locally while producing empty bytes for `subscribe_local_updates` callbacks.

---

## Data Model

### EphemeralStore

```moonbit
/// Generic ephemeral key-value store for presence data.
/// Keys are peer ID strings, values are EphemeralValue.
/// Conflict resolution: LWW using logical clock.
/// Expiry: entries older than timeout_ms are considered stale.
pub struct EphemeralStore {
  timeout_ms : UInt64
  mut next_sub_id : Int
  mut states : Map[String, EphemeralRecord]
  mut local_subs : Array[EphemeralLocalEntry]
  mut subs : Array[EphemeralSubscriberEntry]
}

/// Ephemeral value type — a JSON-like tagged union for presence data.
/// Mirrors the value types supported by the binary encoding format.
pub enum EphemeralValue {
  Null
  Bool(Bool)
  I64(Int64)
  F64(Double)
  String(String)
  Bytes(Bytes)
  List(Array[EphemeralValue])
  Map(Map[String, EphemeralValue])
}

struct EphemeralRecord {
  value : EphemeralValue?   // None = deleted
  clock : Int64             // Logical clock for LWW ordering
  updated_at : UInt64       // Wall-clock ms for timeout expiry
}
```

### Event System

```moonbit
pub enum EphemeralEventTrigger {
  Local    // set() or delete() was called locally
  Import   // apply() received remote update
  Timeout  // remove_outdated() pruned expired entries
}

pub struct EphemeralStoreEvent {
  by : EphemeralEventTrigger
  added : Array[String]     // Keys that appeared (value was None or absent -> Some)
  updated : Array[String]   // Keys whose value changed (Some -> different Some)
  removed : Array[String]   // Keys that disappeared (Some -> None or expired)
}

/// Receives encoded bytes for network transport
pub type LocalEphemeralCallback = (Bytes) -> Bool

/// Receives structured change events
pub type EphemeralSubscriber = (EphemeralStoreEvent) -> Bool
```

Callbacks return `Bool`: `true` to stay subscribed, `false` to auto-unsubscribe.

### Subscription Handle

```moonbit
pub struct EphemeralSubscription {
  store : EphemeralStore
  id : Int
}

pub fn EphemeralSubscription::unsubscribe(self : EphemeralSubscription) -> Unit
```

---

## Core API

### Construction

```moonbit
/// Create a store with given timeout in milliseconds.
/// Entries not updated within timeout_ms are considered expired.
pub fn EphemeralStore::new(timeout_ms : UInt64) -> EphemeralStore
```

### Read/Write

```moonbit
/// Set a key's value. Increments the logical clock.
/// Triggers: local_subs with encoded bytes, subs with Local event.
pub fn EphemeralStore::set(self : EphemeralStore, key : String, value : EphemeralValue) -> Unit

/// Mark a key as deleted (value = None). Increments the logical clock.
/// The tombstone remains until timeout so peers learn about the deletion.
pub fn EphemeralStore::delete(self : EphemeralStore, key : String) -> Unit

/// Get the current value for a key (None if absent or deleted).
pub fn EphemeralStore::get(self : EphemeralStore, key : String) -> EphemeralValue?

/// Get all non-deleted key-value pairs.
pub fn EphemeralStore::get_all_states(self : EphemeralStore) -> Map[String, EphemeralValue]

/// Get all keys with non-None values.
pub fn EphemeralStore::keys(self : EphemeralStore) -> Array[String]
```

### Sync

```moonbit
/// Encode a single key's record as binary. Expired keys produce empty bytes.
pub fn EphemeralStore::encode(self : EphemeralStore, key : String) -> Bytes

/// Encode all non-expired records as binary.
pub fn EphemeralStore::encode_all(self : EphemeralStore) -> Bytes

/// Apply binary-encoded updates from a remote peer.
/// LWW resolution: incoming record wins only if its clock > existing clock.
/// Triggers: subs with Import event listing added/updated/removed keys.
pub fn EphemeralStore::apply(self : EphemeralStore, data : Bytes) -> Result[Unit, DecodeError]
```

### Lifecycle

```moonbit
/// Remove entries whose updated_at + timeout_ms < now.
/// Triggers: subs with Timeout event listing removed keys.
/// Must be called periodically (caller's responsibility in MoonBit;
/// in JS/WASM wrapper, a timer runs automatically).
pub fn EphemeralStore::remove_outdated(self : EphemeralStore) -> Unit
```

### Subscriptions

```moonbit
/// Subscribe to encoded bytes on local changes (for network send).
pub fn EphemeralStore::subscribe_local_updates(
  self : EphemeralStore,
  callback : LocalEphemeralCallback,
) -> EphemeralSubscription

/// Subscribe to structured change events (all triggers).
pub fn EphemeralStore::subscribe(
  self : EphemeralStore,
  callback : EphemeralSubscriber,
) -> EphemeralSubscription
```

---

## LWW Conflict Resolution

When `apply()` receives a remote record for key `k`:

```
if existing.clock >= incoming.clock:
    discard (local wins)
else:
    accept incoming, set updated_at = now()
```

When `set()` is called locally:

```
next_clock = (existing.clock or 0) + 1
record = { value: Some(v), clock: next_clock, updated_at: now() }
```

This guarantees:
- A peer's own writes always have increasing clock values
- No dependence on wall-clock synchronization for ordering
- `updated_at` is set to **local** wall-clock on both set and apply, so timeout is always relative to when this node last saw the entry

---

## Binary Encoding Format

Keys are encoded as `UInt64` peer IDs for compactness (compatible with Loro's wire format):

```
[uvarint: entry_count]
  for each entry:
    [uvarint: peer_id]       // key as UInt64
    [ivarint: clock]         // logical clock
    [tagged_value: value]    // tag byte + value payload
```

Value tags:
| Tag | Type | Payload |
|-----|------|---------|
| `0x00` | Null | (none) |
| `0x01` | Bool | `0x00` or `0x01` |
| `0x02` | F64 | 8 bytes little-endian |
| `0x03` | I64 | ivarint |
| `0x04` | String | length-prefixed UTF-8 |
| `0x05` | List | uvarint count + recursive values |
| `0x06` | Map | uvarint count + (string key + recursive value)* |
| `0x08` | Bytes | length-prefixed raw bytes |

This is more compact than JSON and avoids string escaping overhead for real-time updates.

---

## Cursor Awareness Layer

Cursor/selection tracking is built **on top of** the generic ephemeral store, not baked into it.

### Data Convention

Each peer stores its presence as a Map value under its own peer ID key:

```moonbit
/// Convention: each peer stores a Map with these fields.
/// { "cursor": Int, "selection": [Int, Int], "name": String, "color": String }
///
/// Example:
///   store.set(my_peer_id, EphemeralValue::Map({
///     "cursor": EphemeralValue::I64(42),
///     "name": EphemeralValue::String("Alice"),
///     "color": EphemeralValue::String("#ff6b6b"),
///   }))
```

### Why Cursor Adjustment Cannot Happen Inside the Store

When peer C inserts text at position 5, peer B's cursor at position 10 should shift to 11 on every peer's screen. The naive approach — calling `store.set("B", adjusted_value)` from peer A — is wrong because:

1. **Ownership violation:** Only peer B should write to key `"B"`. If A writes, it bumps the clock and broadcasts, making other peers think B moved their cursor.
2. **Value loss:** `get()` returns a copy. Mutating the returned Map in place has no effect on the store. Calling `set()` to persist the change overwrites the whole value, losing any concurrent updates from B.

### Solution: Derived View

The ephemeral store holds **raw** cursor positions exactly as each peer authored them. A separate local-only derived map computes adjusted positions for rendering:

```moonbit
/// Local-only view of remote peer cursors, adjusted for local edits.
/// Not stored in the ephemeral store. Not sent over the network.
struct PeerCursorView {
  cursors : Map[String, PeerCursor]
}

struct PeerCursor {
  raw_cursor : Int       // As received from the peer
  adjusted_cursor : Int  // After local edit adjustments
  selection : (Int, Int)? // Adjusted selection range
  display_name : String
  color : String
}

/// Rebuild the derived view from the ephemeral store.
/// Called when the store emits an Import or Timeout event.
fn PeerCursorView::from_store(
  store : EphemeralStore,
  local_peer : String,
) -> PeerCursorView

/// Adjust all derived cursor positions after a remote CRDT edit.
/// Does NOT touch the ephemeral store.
fn PeerCursorView::adjust_for_edit(
  self : PeerCursorView,
  edit_start : Int,
  old_len : Int,
  new_len : Int,
) -> Unit {
  for _peer_id, cursor in self.cursors {
    cursor.adjusted_cursor = adjust_position(
      cursor.adjusted_cursor, edit_start, old_len, new_len,
    )
    match cursor.selection {
      Some((start, end)) =>
        cursor.selection = Some((
          adjust_position(start, edit_start, old_len, new_len),
          adjust_position(end, edit_start, old_len, new_len),
        ))
      None => ()
    }
  }
}

/// When the store receives a new raw value from a peer,
/// reset that peer's adjusted position to match the new raw value.
fn PeerCursorView::apply_raw_update(
  self : PeerCursorView,
  peer_id : String,
  value : EphemeralValue,
) -> Unit

/// Adjust a cursor position after a text edit.
fn adjust_position(pos : Int, edit_start : Int, old_len : Int, new_len : Int) -> Int {
  if pos <= edit_start {
    pos  // Before edit — unchanged
  } else if pos <= edit_start + old_len {
    edit_start + new_len  // Inside deleted region — move to edit end
  } else {
    pos - old_len + new_len  // After edit — shift by delta
  }
}
```

**Data flow:**
1. Peer B calls `store.set("B", { cursor: 10, ... })` → encoded bytes sent over network
2. Peer A receives bytes → `store.apply(data)` → `Import` event fires
3. A's event handler calls `cursor_view.apply_raw_update("B", value)` → sets `raw_cursor = 10`, `adjusted_cursor = 10`
4. Peer C's CRDT edit inserts at position 5 → A calls `cursor_view.adjust_for_edit(5, 0, 1)` → B's `adjusted_cursor` becomes `11`
5. A renders B's cursor at position 11

When B sends a new awareness update (e.g., `cursor: 12`), A resets B's adjusted position to 12, discarding the stale local adjustments.

### Future: Relative Positions

A more principled long-term approach is to store cursor positions as **CRDT-relative positions** — references to item IDs in the eg-walker OpLog rather than absolute text indices. Each peer independently resolves the relative position to an absolute index, and edits never require adjustment. This eliminates the derived view entirely but requires deeper integration with the CRDT internals.

---

## Connection Lifecycle

### Initial Sync

When a new peer joins, it must learn about existing peers' presence. The server (or an existing peer) sends `encode_all()` on connection setup:

```typescript
// Server-side (or relay peer)
ws.on("connection", (newPeer) => {
  // Send current ephemeral state to the new peer
  const snapshot = store.encodeAll();
  newPeer.send(encode({ type: "ephemeral", payload: snapshot }));
});
```

### Heartbeat

Peers periodically re-send their full local state (every ~30s) by calling `store.set()` with their current values. This resets `updated_at` on remote peers, preventing timeout while the peer is still connected. Without heartbeats, an idle peer (cursor not moving) would be timed out after `timeout_ms` even though it's still present.

### Graceful Disconnect

On tab close or explicit leave, peers should immediately delete their key rather than waiting for timeout:

```typescript
window.addEventListener("beforeunload", () => {
  store.delete(myPeerId);
  // subscribe_local_updates callback sends the deletion over the wire
});
```

This gives instant cursor removal instead of a 60s delay. Crashes and network failures still rely on timeout.

### Cleanup

Call `store.remove_outdated()` on a timer (~10s interval). In the JS/WASM wrapper, this timer runs automatically while the store is non-empty and stops when all entries are cleared.

---

## Transport Integration

Ephemeral updates travel **out-of-band** from CRDT sync, piggybacking on the same connection:

```typescript
// JavaScript side
type Message =
  | { type: "sync",      payload: Uint8Array }  // CRDT ops
  | { type: "ephemeral", payload: Uint8Array }  // Presence updates (binary)

// subscribe_local_updates provides ready-to-send bytes:
store.subscribeLocalUpdates((bytes: Uint8Array) => {
  ws.send(encode({ type: "ephemeral", payload: bytes }));
  return true; // keep subscription
});

// On receive:
ws.onmessage = (msg) => {
  const { type, payload } = decode(msg.data);
  if (type === "ephemeral") {
    store.apply(payload);
  } else if (type === "sync") {
    doc.apply(payload);
  }
};
```

Send triggers:
1. **Cursor move** — debounced (~50ms)
2. **Selection change** — immediate
3. **Heartbeat** — every ~30s, re-sends full local state via `set()`
4. **Disconnect** — `delete()` on `beforeunload`

---

## Integration with SyncEditor (§3)

```moonbit
pub struct SyncEditor {
  // ...
  ephemeral : EphemeralStore
  cursor_view : PeerCursorView   // Derived, local-only
  peer_id : String
}

pub fn SyncEditor::set_local_presence(self : SyncEditor) -> Unit {
  // Build the full presence Map from current editor state.
  // Called on cursor move (debounced), selection change, and heartbeat.
  self.ephemeral.set(self.peer_id, EphemeralValue::Map({
    "cursor": EphemeralValue::I64(self.cursor.to_int64()),
    "name": EphemeralValue::String(self.display_name),
    "color": EphemeralValue::String(self.color),
  }))
}

pub fn SyncEditor::apply_sync(self : SyncEditor, msg : SyncMessage) -> Unit raise {
  let old_text = self.doc.text()
  self.doc.sync().apply(msg)
  let new_text = self.doc.text()
  // Adjust the derived cursor view — does NOT touch the ephemeral store
  let edits = @loom.to_edits(@loom.text_to_delta(old_text, new_text))
  for edit in edits {
    self.cursor_view.adjust_for_edit(
      edit.start(), edit.old_len(), edit.new_len(),
    )
  }
}
```

The `SyncEditor` subscribes to the store's events to update `cursor_view` when remote peers send new presence data:

```moonbit
// During SyncEditor initialization:
store.subscribe(fn(event) {
  // On Import: rebuild affected peers in cursor_view from raw store values
  for key in event.added {
    match store.get(key) {
      Some(value) => cursor_view.apply_raw_update(key, value)
      None => ()
    }
  }
  for key in event.updated {
    match store.get(key) {
      Some(value) => cursor_view.apply_raw_update(key, value)
      None => ()
    }
  }
  for key in event.removed {
    cursor_view.cursors.remove(key)
  }
  true // keep subscription
})
```

---

## FFI Surface

```moonbit
/// Encode local ephemeral state as binary
pub fn ephemeral_encode_all(handle : Int) -> Bytes

/// Apply remote ephemeral update (binary)
pub fn ephemeral_apply(handle : Int, data : Bytes) -> Unit

/// Set local presence (key + JSON value)
pub fn ephemeral_set(handle : Int, key : String, value_json : String) -> Unit

/// Delete local presence key (graceful disconnect)
pub fn ephemeral_delete(handle : Int, key : String) -> Unit

/// Get all peer states as JSON (raw, from store)
/// Returns: {"peer1": {"cursor": 5, "color": "#ff0000"}, ...}
pub fn ephemeral_get_all_json(handle : Int) -> String

/// Get adjusted peer cursors as JSON (derived view, for rendering)
/// Returns: [{"peer_id": "123", "cursor": 8, "color": "#ff0000", "name": "Alice"}, ...]
pub fn ephemeral_get_peer_cursors_json(handle : Int) -> String

/// Remove expired entries
pub fn ephemeral_remove_outdated(handle : Int) -> Unit
```

---

## Location

| File | Content |
|------|---------|
| `editor/ephemeral.mbt` | `EphemeralStore`, `EphemeralRecord`, `EphemeralValue`, event types |
| `editor/ephemeral_encoding.mbt` | Binary encode/decode for `EphemeralValue` |
| `editor/ephemeral_test.mbt` | LWW, timeout, encode/decode roundtrip tests |
| `editor/cursor_view.mbt` | `PeerCursorView`, `adjust_position`, derived cursor logic |

---

## Verification

1. **LWW ordering:** Two peers set the same key — higher clock wins regardless of wall-clock time.
2. **Clock increment:** Local `set()` always produces `clock = previous + 1`.
3. **Timeout expiry:** Entry not updated within `timeout_ms` is removed by `remove_outdated()` and triggers a `Timeout` event with the key in `removed`.
4. **Encode/decode roundtrip:** All `EphemeralValue` variants survive binary encode → decode.
5. **Event correctness:** `set` triggers `Local` event; `apply` triggers `Import`; `remove_outdated` triggers `Timeout`. Each event correctly classifies keys as `added`/`updated`/`removed`.
6. **Subscription auto-unsubscribe:** Callback returning `false` is removed from the subscription list.
7. **Cursor adjustment (derived view):** Insert at position 3 → derived cursor at position 7 becomes 8; delete at position 3..5 → derived cursor at position 7 becomes 5. Store values are unchanged.
8. **Raw update resets adjustment:** After adjusting peer B's cursor from 10 to 11 locally, receiving a new raw value (cursor: 12) from B resets the derived position to 12.
9. **Initial sync:** New peer receives `encode_all()` and sees all existing peer cursors.
10. **Graceful disconnect:** `delete()` immediately removes the peer's cursor from all connected peers.
11. **Heartbeat keeps alive:** Idle peer that re-sends state every 30s is not timed out at 60s.
12. **No CRDT contamination:** Ephemeral data never appears in `OpLog` or `SyncMessage`.

---

## Implementation Notes (from Lomo review)

Notes from reviewing [Lomo's `awareness.mbt`](https://github.com/Lampese/lomo/blob/main/awareness.mbt) as the primary reference implementation. Lomo's LWW state machine, subscription plumbing, and binary codec are directly reusable with `EphemeralValue` replacing `@types.LoroValue`.

### Encoding dependency

Lomo imports `@encoding.write_uvarint`, `@encoding.read_uvarint`, `@encoding.write_ivarint`, `@encoding.read_ivarint`, `@encoding.write_string`, `@encoding.read_string`, and `@encoding.Reader` from its own codebase (~100 lines of varint/length-prefixed encoding). Before writing `ephemeral_encoding.mbt`, audit `event-graph-walker` for equivalent exports. Either reuse them or vendor the encoding utilities into the `editor/` package.

### Testing timeout without time injection

Lomo hardcodes `now_ms()` as `@env.now()`. Rather than injecting a clock parameter into the public API (adds noise to `set()`, `apply()`, `remove_outdated()`), use **whitebox tests** that directly backdate `EphemeralRecord.updated_at`:

```moonbit
// whitebox test — controls time by manipulating internal state
test "timeout removes stale entries" {
  let store = EphemeralStore::new(1000UL)
  store.set("1", EphemeralValue::I64(42L))
  // Backdate: set updated_at to 0 so now() >> 0 + 1000
  store.states["1"] = { value: Some(EphemeralValue::I64(42L)), clock: 1L, updated_at: 0UL }
  store.remove_outdated()
  inspect!(store.get("1"), content="None")
}
```

LWW ordering tests only depend on `clock` values, not wall time — no special setup needed.

### Null-as-delete semantics

Lomo treats `set(key, Null)` as deletion (calls `set_state(key, None)`). On the wire, deleted entries and explicit `Null` values both encode to tag `0x00`. After a network roundtrip they are indistinguishable. This is acceptable — presence data uses `Map`, `I64`, `String` values; no consumer stores top-level `Null` intentionally. Preserve this behavior; do not attempt to distinguish stored-null from deleted.

### Cursor adjustment on heartbeat (known, deferred)

When peer B heartbeats with an unchanged raw cursor position, `apply_raw_update` resets B's derived (adjusted) cursor to the raw value, undoing local adjustments from intervening edits. This produces a brief visual cursor jump. The race window is ~100ms/30s ≈ 0.3% of heartbeats, and the glitch self-corrects on B's next real cursor move. Addressing this properly requires **CRDT-relative positions** (see [Future: Relative Positions](#future-relative-positions)), not a raw-value equality check (which breaks when non-cursor Map fields change while cursor stays the same).

---

## References

- [Loro Ephemeral Store](https://loro.dev/docs/tutorial/ephemeral) — generic KV ephemeral store design
- [Loro awareness.rs](https://github.com/loro-dev/loro/blob/main/crates/loro-internal/src/awareness.rs) — Rust implementation with `EphemeralStore` (replaces deprecated `Awareness`)
- [Lomo awareness.mbt](https://github.com/Lampese/lomo/blob/main/awareness.mbt) — MoonBit port with improved clock/timestamp separation
- [Yjs Awareness Protocol](https://docs.yjs.dev/api/about-awareness) — original inspiration

---

## Dependencies

- **Depends on:** [§1 Edit Bridge](./01-edit-bridge.md) (optional optimization for per-op cursor adjustment)
- **Depends on:** [§3 Unified Editor](./03-unified-editor.md) (`SyncEditor` holds the `EphemeralStore`)
- **Depended on by:** None (leaf node)
