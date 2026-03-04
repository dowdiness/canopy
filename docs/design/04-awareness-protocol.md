# Design 04: Awareness Protocol

**Parent:** [Grand Design](./GRAND_DESIGN.md)
**Status:** Draft
**Updated:** 2026-03-05

---

## Problem

`Editor.cursor` is local-only. In a collaborative editor, peers need to see each other's cursors and selections. This information must:

1. Travel over the network
2. **Not** be stored in the CRDT (cursors are ephemeral, not part of document history)
3. Survive remote edits (cursor positions shift when remote text changes)

---

## Design

### Awareness vs. Document State

| | Document State | Awareness |
|---|---|---|
| **Persistence** | Permanent (OpLog) | Ephemeral (in-memory) |
| **Conflict resolution** | CRDT convergence | Last-writer-wins per peer |
| **Transport** | `SyncMessage` | `AwarenessMessage` |
| **Loss tolerance** | Must not lose | Can lose (re-sent periodically) |

### Awareness Message

```moonbit
/// Ephemeral peer state — not stored in CRDT
pub struct AwarenessMessage {
  peer_id : String
  cursor : Int?                    // Cursor position (None = no cursor)
  selection : (Int, Int)?          // Selection range (start, end), None = no selection
  display_name : String?          // Human-readable name
  color : String?                 // CSS color for cursor rendering
  timestamp_ms : Int64            // Unix epoch milliseconds; Int would overflow
}
```

`timestamp_ms` is explicitly `Int64` because Unix epoch milliseconds are already well
beyond 32-bit range. On the JS side this is still safe to transport as `number`
(`Date.now()` values are currently far below `2^53 - 1`), then converted to `Int64`
at the FFI boundary.

### Awareness State (Per Peer)

```moonbit
/// Local awareness state tracking all known peers
pub struct AwarenessState {
  local_peer : String
  peers : Map[String, PeerState]
  stale_timeout_ms : Int64         // Remove peer after this many ms of silence
}

pub struct PeerState {
  cursor : Int?
  selection : (Int, Int)?
  display_name : String
  color : String
  last_seen_ms : Int64
}
```

### Cursor Position Adjustment

When a remote CRDT op is applied, all awareness cursor positions must be adjusted:

```moonbit
/// Adjust a cursor position after a text edit
/// Uses the same logic as Editor.adjust_cursor but generalized
fn adjust_position(pos : Int, edit_start : Int, old_len : Int, new_len : Int) -> Int {
  if pos <= edit_start {
    pos  // Before edit — unchanged
  } else if pos <= edit_start + old_len {
    edit_start + new_len  // Inside deleted region — move to edit end
  } else {
    pos - old_len + new_len  // After edit — shift by delta
  }
}

/// Adjust all peer cursors after a remote edit
pub fn AwarenessState::adjust_for_edit(
  self : AwarenessState,
  edit_start : Int,
  old_len : Int,
  new_len : Int,
) -> Unit {
  for _peer_id, state in self.peers {
    match state.cursor {
      Some(pos) => state.cursor = Some(adjust_position(pos, edit_start, old_len, new_len))
      None => ()
    }
    match state.selection {
      Some((start, end)) => {
        state.selection = Some((
          adjust_position(start, edit_start, old_len, new_len),
          adjust_position(end, edit_start, old_len, new_len),
        ))
      }
      None => ()
    }
  }
}
```

### Transport

Awareness messages are sent **out-of-band** from CRDT sync. They piggyback on the same WebSocket/WebRTC connection but use a different message type:

```typescript
// JavaScript side
type Message =
  | { type: "sync", payload: SyncMessage }        // CRDT ops
  | { type: "awareness", payload: AwarenessMessage } // Cursors

// Send awareness on:
// 1. Cursor move (debounced, ~50ms)
// 2. Selection change
// 3. Periodic heartbeat (~30s)
```

### Staleness and Cleanup

Peers that haven't sent awareness in `stale_timeout_ms` (default: 60s) are removed:

```moonbit
pub fn AwarenessState::cleanup_stale(self : AwarenessState, now_ms : Int64) -> Unit {
  let stale_peers : Array[String] = []
  for peer_id, state in self.peers {
    if now_ms - state.last_seen_ms > self.stale_timeout_ms {
      stale_peers.push(peer_id)
    }
  }
  for peer_id in stale_peers {
    self.peers.remove(peer_id)
  }
}
```

---

## Integration with SyncEditor (§3)

```moonbit
// In SyncEditor:
pub fn move_cursor(self : SyncEditor, position : Int) -> Unit {
  self.cursor = position
  // Awareness message will be sent by the JS layer on next tick
}

// After applying remote CRDT ops:
pub fn apply_sync(self : SyncEditor, msg : SyncMessage) -> Unit raise {
  let old_text = self.doc.text()
  self.doc.sync().apply(msg)
  let new_text = self.doc.text()
  // Minimum-correct fallback: derive one coarse edit from old/new text.
  // Later, switch to per-op edits from §1 for better cursor fidelity.
  let edits = @loom.to_edits(@loom.text_to_delta(old_text, new_text))
  for edit in edits {
    self.awareness.adjust_for_edit(
      edit.start(),
      edit.old_len(),
      edit.new_len(),
    )
  }
}
```

---

## FFI Surface

```moonbit
/// Export local awareness as JSON
pub fn get_awareness_json(handle : Int) -> String

/// Apply remote awareness update
pub fn apply_awareness_json(handle : Int, json : String) -> Unit

/// Get all peer cursors as JSON
/// Returns: [{"peer_id": "bob", "cursor": 5, "color": "#ff0000"}, ...]
pub fn get_peer_cursors_json(handle : Int) -> String

/// Cleanup stale peers
pub fn awareness_cleanup(handle : Int, now_ms : Int64) -> Unit
```

---

## Location

| File | Content |
|------|---------|
| `editor/awareness.mbt` | `AwarenessMessage`, `AwarenessState`, `PeerState` |
| `editor/awareness_test.mbt` | Position adjustment tests |

---

## Verification

1. **Position adjustment:** Insert at position 3 on a document of length 10 → cursor at position 7 becomes 8.
2. **Staleness:** Peer not seen for >60s is removed from state.
3. **JSON roundtrip:** `AwarenessMessage` serializes and deserializes correctly.
4. **No CRDT contamination:** Awareness data never appears in `OpLog` or `SyncMessage`.

---

## References

- [Yjs Awareness Protocol](https://docs.yjs.dev/api/about-awareness) — inspiration for the design
- [Loro Awareness](https://loro.dev/docs/tutorial/awareness) — similar approach

---

## Dependencies

- **Depends on:** [§1 Edit Bridge](./01-edit-bridge.md) (optional optimization for per-op cursor adjustment)
- **Depends on:** [§3 Unified Editor](./03-unified-editor.md) (awareness field in `SyncEditor`)
- **Depended on by:** None (leaf node)
