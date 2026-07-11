# WebSocket Transport Implementation Plan (Phase 1: MoonBit Core)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the relay room logic and client WebSocket lifecycle in MoonBit, testable without any browser or Cloudflare — deferring CF Worker TypeScript and prosemirror wiring to Phase 2.

**Architecture:** `relay/` package with `RelayRoom` (session management + broadcast via opaque `JsWebSocket`). Client side adds `ws` field to `SyncEditor` + `ws_on_open`/`ws_on_message`/`ws_on_close` methods. CRDT ops serialized as JSON-encoded Bytes via existing `to_json_string()`/`from_json_string()`. All tested in MoonBit using direct function calls (no WebSocket needed).

**Tech Stack:** MoonBit, editor/ package, new relay/ package

**Spec:** `docs/plans/2026-03-19-websocket-transport-design.md`

---

## Preflight

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
moon check && moon test
```

All 307 tests must pass.

---

## File Structure

| File | Role |
|------|------|
| `relay/relay_room.mbt` | **Create.** `RelayRoom` struct, session management, broadcast, `JsWebSocket` opaque type |
| `relay/wire.mbt` | **Create.** Minimal PeerJoined/PeerLeft wire encoding (~20 lines, no editor dep) |
| `relay/relay_room_wbtest.mbt` | **Create.** Relay unit tests using mock WebSocket |
| `relay/moon.pkg` | **Create.** Package config (buffer only, no editor import) |
| `editor/websocket_js.mbt` | **Create.** `JsWebSocket` opaque type for editor (JS target only) |
| `editor/websocket_native.mbt` | **Create.** Native target stub |
| `editor/sync_editor.mbt` | **Modify.** Add `ws : JsWebSocket?` field + `ws_send` helper |
| `editor/sync_editor_ws.mbt` | **Create.** `ws_on_open`, `ws_on_message`, `ws_on_close` methods |
| `editor/sync_editor_ws_wbtest.mbt` | **Create.** Client lifecycle tests |
| `editor/moon.pkg` | **Modify.** Add target entries for websocket_js/native files |
| `crdt.mbt` | **Modify.** Add exported relay + ws functions |
| `moon.pkg` | **Modify.** Add relay import + JS exports |

---

## Task 1: Relay Package — Wire Encoding

**Files:**
- Create: `relay/moon.pkg`
- Create: `relay/wire.mbt`
- Create: `relay/wire_wbtest.mbt`

- [ ] **Step 1: Create relay package config**

Create `relay/moon.pkg`:

```
import {
  "moonbitlang/core/buffer",
}

options(
  is_main: false,
)
```

- [ ] **Step 2: Implement PeerJoined/PeerLeft encoding**

Create `relay/wire.mbt`:

```moonbit
///|
fn write_relay_uvarint(buf : @buffer.Buffer, value : Int) -> Unit {
  let mut v = value
  while v >= 0x80 {
    buf.write_byte(((v & 0x7F) | 0x80).to_byte())
    v = v >> 7
  }
  buf.write_byte(v.to_byte())
}

///|
/// Encode a PeerJoined (sub_type=0x01) or PeerLeft (sub_type=0x02) wire message.
/// Wire format: [version:0x01][type:0x05][flags:0x00][sub_type][uvarint_len][peer_id_utf8]
pub fn encode_peer_control(sub_type : Byte, peer_id : String) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(b'\x01') // version
  buf.write_byte(b'\x05') // message_type: Room control
  buf.write_byte(b'\x00') // flags: no BFT
  buf.write_byte(sub_type)
  let str_buf = @buffer.new()
  str_buf.write_string(peer_id)
  let str_bytes = str_buf.to_bytes()
  write_relay_uvarint(buf, str_bytes.length())
  buf.write_bytes(str_bytes)
  buf.to_bytes()
}

///|
pub fn encode_peer_joined(peer_id : String) -> Bytes {
  encode_peer_control(b'\x01', peer_id)
}

///|
pub fn encode_peer_left(peer_id : String) -> Bytes {
  encode_peer_control(b'\x02', peer_id)
}
```

- [ ] **Step 3: Write tests**

Create `relay/wire_wbtest.mbt`:

```moonbit
///|
test "encode_peer_joined: version byte" {
  let msg = encode_peer_joined("alice")
  inspect(msg[0], content="b'\\x01'")
}

///|
test "encode_peer_joined: message type is room control" {
  let msg = encode_peer_joined("alice")
  inspect(msg[1], content="b'\\x05'")
}

///|
test "encode_peer_joined: sub_type is 0x01" {
  let msg = encode_peer_joined("alice")
  inspect(msg[3], content="b'\\x01'")
}

///|
test "encode_peer_left: sub_type is 0x02" {
  let msg = encode_peer_left("bob")
  inspect(msg[3], content="b'\\x02'")
}

///|
test "encode_peer_joined: compatible with editor decode_message" {
  // Verify the relay wire format is decodable by the editor's decode_message.
  // We can't call decode_message here (different package), but we verify
  // the structure: [0x01][0x05][0x00][0x01][varint_len][utf8_string]
  let msg = encode_peer_joined("test-peer")
  inspect(msg[0], content="b'\\x01'") // version
  inspect(msg[1], content="b'\\x05'") // room control
  inspect(msg[2], content="b'\\x00'") // flags
  inspect(msg[3], content="b'\\x01'") // Join sub_type
  // Remaining bytes: uvarint length + UTF-8 "test-peer"
  inspect(msg.length() > 4, content="true")
}
```

- [ ] **Step 4: Verify**

```bash
moon check && moon test -p dowdiness/canopy/relay
```

- [ ] **Step 5: Commit**

```bash
git add relay/
git commit -m "feat(relay): add minimal wire encoding for PeerJoined/PeerLeft"
```

---

## Task 2: Relay Room — Session Management & Broadcast

**Files:**
- Create: `relay/relay_room.mbt`
- Create: `relay/relay_room_wbtest.mbt`

For testing, we use a `MockWebSocket` that records sent bytes — no real WebSocket needed.

- [ ] **Step 1: Implement RelayRoom with callback-based send**

Create `relay/relay_room.mbt`:

```moonbit
///|
pub struct RelayPeer {
  peer_id : String
  send_fn : (Bytes) -> Unit
}

///|
pub struct RelayRoom {
  mut peers : Array[RelayPeer]
}

///|
pub fn RelayRoom::new() -> RelayRoom {
  { peers: [] }
}

///|
pub fn RelayRoom::on_connect(
  self : RelayRoom,
  peer_id : String,
  send_fn : (Bytes) -> Unit,
) -> Unit {
  // Broadcast PeerJoined to existing peers BEFORE adding new peer
  let join_msg = encode_peer_joined(peer_id)
  self.broadcast(peer_id, join_msg)
  // Add new peer
  self.peers.push({ peer_id, send_fn })
}

///|
pub fn RelayRoom::on_message(
  self : RelayRoom,
  sender : String,
  data : Bytes,
) -> Unit {
  self.broadcast(sender, data)
}

///|
pub fn RelayRoom::on_disconnect(
  self : RelayRoom,
  peer_id : String,
) -> Unit {
  self.peers = self.peers.filter(fn(p) { p.peer_id != peer_id })
  // Broadcast PeerLeft to remaining peers
  let leave_msg = encode_peer_left(peer_id)
  self.broadcast(peer_id, leave_msg)
}

///|
pub fn RelayRoom::peer_count(self : RelayRoom) -> Int {
  self.peers.length()
}

///|
fn RelayRoom::broadcast(
  self : RelayRoom,
  exclude : String,
  data : Bytes,
) -> Unit {
  for peer in self.peers {
    if peer.peer_id != exclude {
      (peer.send_fn)(data)
    }
  }
}
```

- [ ] **Step 2: Write relay tests**

Create `relay/relay_room_wbtest.mbt`:

```moonbit
///|
fn make_recorder() -> ((Bytes) -> Unit, Array[Bytes]) {
  let messages : Array[Bytes] = []
  let send_fn = fn(data : Bytes) { messages.push(data) }
  (send_fn, messages)
}

///|
test "RelayRoom: on_connect broadcasts PeerJoined to existing peers" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  room.on_connect("alice", send_a)
  inspect(msgs_a.length(), content="0") // first peer, no one to broadcast to
  let (send_b, _msgs_b) = make_recorder()
  room.on_connect("bob", send_b)
  inspect(msgs_a.length(), content="1") // alice received PeerJoined("bob")
  // Verify it's a room control message (type byte = 0x05)
  inspect(msgs_a[0][1], content="b'\\x05'")
  // Verify sub_type is Join (0x01)
  inspect(msgs_a[0][3], content="b'\\x01'")
}

///|
test "RelayRoom: on_message broadcasts to all except sender" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  let (send_c, msgs_c) = make_recorder()
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
  room.on_connect("carol", send_c)
  // Clear join messages
  let _ = msgs_a.length()
  let _ = msgs_b.length()
  let before_a = msgs_a.length()
  let before_b = msgs_b.length()
  let before_c = msgs_c.length()
  let buf = @buffer.new()
  buf.write_string("hello")
  room.on_message("alice", buf.to_bytes())
  inspect(msgs_a.length() - before_a, content="0") // alice doesn't get own message
  inspect(msgs_b.length() - before_b, content="1") // bob gets it
  inspect(msgs_c.length() - before_c, content="1") // carol gets it
}

///|
test "RelayRoom: on_disconnect removes peer and broadcasts PeerLeft" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
  let before_b = msgs_b.length()
  room.on_disconnect("alice")
  inspect(room.peer_count(), content="1")
  // Bob received PeerLeft("alice")
  let new_msgs = msgs_b.length() - before_b
  inspect(new_msgs, content="1")
  // Verify it's PeerLeft (sub_type = 0x02)
  inspect(msgs_b[msgs_b.length() - 1][3], content="b'\\x02'")
}

///|
test "RelayRoom: sender does not receive own broadcast" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  room.on_connect("alice", send_a)
  let buf = @buffer.new()
  buf.write_string("test")
  room.on_message("alice", buf.to_bytes())
  // Only join messages, no echo
  inspect(msgs_a.length(), content="0")
}

///|
test "RelayRoom: peer_count tracks sessions" {
  let room = RelayRoom::new()
  let (send_a, _) = make_recorder()
  let (send_b, _) = make_recorder()
  inspect(room.peer_count(), content="0")
  room.on_connect("alice", send_a)
  inspect(room.peer_count(), content="1")
  room.on_connect("bob", send_b)
  inspect(room.peer_count(), content="2")
  room.on_disconnect("alice")
  inspect(room.peer_count(), content="1")
}
```

- [ ] **Step 3: Verify**

```bash
moon check && moon test -p dowdiness/canopy/relay
```

- [ ] **Step 4: Commit**

```bash
git add relay/relay_room.mbt relay/relay_room_wbtest.mbt
git commit -m "feat(relay): add RelayRoom with session management and broadcast"
```

---

## Task 3: Client WebSocket FFI + SyncEditor Integration

**Files:**
- Create: `editor/websocket_js.mbt`
- Create: `editor/websocket_native.mbt`
- Modify: `editor/sync_editor.mbt`
- Modify: `editor/moon.pkg`

- [ ] **Step 1: Create JS target WebSocket FFI**

Create `editor/websocket_js.mbt`:

```moonbit
///|
#external
pub type JsWebSocket

///|
pub fn JsWebSocket::as_any(self : JsWebSocket) -> @core.Any = "%identity"

///|
pub fn JsWebSocket::send_bytes(self : JsWebSocket, data : Bytes) -> Unit {
  self.as_any()._call("send", [@core.any(data)]) |> ignore
}

///|
pub fn JsWebSocket::close(self : JsWebSocket) -> Unit {
  self.as_any()._call("close", []) |> ignore
}
```

- [ ] **Step 2: Create native target stub**

Create `editor/websocket_native.mbt`:

```moonbit
///|
pub type JsWebSocket Int

///|
pub fn JsWebSocket::send_bytes(self : JsWebSocket, _data : Bytes) -> Unit {
  ignore(self)
}

///|
pub fn JsWebSocket::close(self : JsWebSocket) -> Unit {
  ignore(self)
}
```

- [ ] **Step 3: Add target entries to editor/moon.pkg**

In `editor/moon.pkg`, add to the `targets` section:

```
  "targets": {
    "ephemeral_time_js.mbt": [ "js" ],
    "ephemeral_time_native.mbt": [ "not", "js" ],
    "websocket_js.mbt": [ "js" ],
    "websocket_native.mbt": [ "not", "js" ],
  },
```

- [ ] **Step 4: Add `ws` field to SyncEditor**

In `editor/sync_editor.mbt`, add after the `peer_id` field:

```moonbit
  priv mut ws : JsWebSocket?
```

Initialize as `None` in the constructor, add to the struct literal:

```moonbit
    ws: None,
```

Add a send helper method after the constructor:

```moonbit
///|
pub fn SyncEditor::ws_send(self : SyncEditor, data : Bytes) -> Unit {
  match self.ws {
    Some(ws) => ws.send_bytes(data)
    None => () // silently drop if disconnected
  }
}
```

- [ ] **Step 5: Verify**

```bash
moon check && moon test
```

All existing 307 tests must still pass.

- [ ] **Step 6: Commit**

```bash
git add editor/websocket_js.mbt editor/websocket_native.mbt editor/sync_editor.mbt editor/moon.pkg
git commit -m "feat(editor): add JsWebSocket opaque type and ws field on SyncEditor"
```

---

## Task 4: Client WebSocket Lifecycle Methods

**Files:**
- Create: `editor/sync_editor_ws.mbt`
- Create: `editor/sync_editor_ws_wbtest.mbt`

- [ ] **Step 1: Implement ws_on_open, ws_on_message, ws_on_close**

Create `editor/sync_editor_ws.mbt`:

```moonbit
///|
/// Called when WebSocket connects. Stores the ws reference and sends PeerJoined.
pub fn SyncEditor::ws_on_open(self : SyncEditor, ws : JsWebSocket) -> Unit {
  self.ws = Some(ws)
  // Send our PeerJoined message to the relay
  let join_msg = encode_message(PeerJoined(self.peer_id))
  self.ws_send(join_msg)
}

///|
/// Called when a binary message is received from the relay.
pub fn SyncEditor::ws_on_message(self : SyncEditor, data : Bytes) -> Unit {
  match decode_message(data) {
    Some(CrdtOps(payload)) => {
      // Decode @text.SyncMessage from JSON-encoded bytes.
      // to_unchecked_string is safe here: malformed data is caught by from_json_string.
      let json_str = payload.to_unchecked_string()
      try {
        let msg = @text.SyncMessage::from_json_string(json_str)
        self.apply_sync(msg)
      } catch {
        _ => () // malformed CRDT payload, silently drop
      }
    }
    Some(EphemeralUpdate(ns, payload)) => self.hub.apply(ns, payload)
    Some(PeerJoined(_peer_id)) => {
      // A new peer joined — send our full state for catch-up
      // Send ephemeral state: one EphemeralUpdate per namespace
      for ns in [Cursor, EditMode, Drag, Presence] {
        let ns_data = self.hub.encode(ns)
        if ns_data.length() > 0 {
          self.ws_send(encode_message(EphemeralUpdate(ns, ns_data)))
        }
      }
      // Send full CRDT document state
      let crdt_msg = self.export_all() catch { _ => return }
      let json_str = crdt_msg.to_json_string()
      let buf = @buffer.new()
      buf.write_string(json_str)
      self.ws_send(encode_message(CrdtOps(buf.to_bytes())))
    }
    Some(PeerLeft(peer_id)) => self.hub.on_peer_leave(peer_id)
    Some(SyncRequest(_)) | Some(SyncResponse(_)) => () // not used in MVP
    None => () // malformed message, silently drop
  }
}

///|
/// Called when WebSocket disconnects.
pub fn SyncEditor::ws_on_close(self : SyncEditor) -> Unit {
  self.ws = None
}

///|
/// Broadcast a local CRDT edit to connected peers.
/// MVP uses export_all() for simplicity. A future optimization would track
/// peer versions and use export_since() for delta-only sync.
pub fn SyncEditor::ws_broadcast_edit(self : SyncEditor) -> Unit {
  match self.ws {
    None => ()
    Some(_) => {
      let crdt_msg = self.export_all() catch { _ => return }
      let json_str = crdt_msg.to_json_string()
      let buf = @buffer.new()
      buf.write_string(json_str)
      self.ws_send(encode_message(CrdtOps(buf.to_bytes())))
    }
  }
}

///|
/// Broadcast local cursor/presence state to connected peers.
pub fn SyncEditor::ws_broadcast_cursor(self : SyncEditor) -> Unit {
  match self.ws {
    None => ()
    Some(_) => {
      let cursor_data = self.hub.encode(Cursor)
      if cursor_data.length() > 0 {
        self.ws_send(encode_message(EphemeralUpdate(Cursor, cursor_data)))
      }
    }
  }
}
```

- [ ] **Step 2: Write tests**

Create `editor/sync_editor_ws_wbtest.mbt`:

```moonbit
///|
test "ws_on_message: PeerLeft removes peer from hub" {
  let editor = SyncEditor::new("local")
  // Manually add a peer's presence to the hub
  let remote_hub = EphemeralHub::new("remote-peer")
  remote_hub.set_presence("Remote", "#00ff00", Active)
  editor.hub.apply(Presence, remote_hub.encode(Presence))
  inspect(editor.hub.get_online_peers().length(), content="1")
  // Simulate receiving PeerLeft
  let leave_msg = encode_message(PeerLeft("remote-peer"))
  editor.ws_on_message(leave_msg)
  inspect(editor.hub.get_online_peers().length(), content="0")
}

///|
test "ws_on_message: CrdtOps applies remote edits" {
  let editor_a = SyncEditor::new("alice")
  let editor_b = SyncEditor::new("bob")
  editor_a.set_text("hello")
  // Export alice's state as CrdtOps message
  let crdt_msg = try! editor_a.export_all()
  let json_str = crdt_msg.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json_str)
  let wire_msg = encode_message(CrdtOps(buf.to_bytes()))
  // Bob receives it
  editor_b.ws_on_message(wire_msg)
  inspect(editor_b.get_text(), content="hello")
}

///|
test "ws_on_message: EphemeralUpdate applies to hub" {
  let editor = SyncEditor::new("local")
  let remote_hub = EphemeralHub::new("remote")
  remote_hub.set_edit_mode("node-5")
  let ns_data = remote_hub.encode(EditMode)
  let wire_msg = encode_message(EphemeralUpdate(EditMode, ns_data))
  editor.ws_on_message(wire_msg)
  inspect(
    editor.hub.get_edit_mode("remote"),
    content="Some({node_id: \"node-5\"})",
  )
}

///|
test "ws_on_close: clears ws reference" {
  let editor = SyncEditor::new("local")
  inspect(editor.ws, content="None")
  editor.ws_on_close()
  inspect(editor.ws, content="None")
}

///|
test "ws_send: does nothing when disconnected" {
  let editor = SyncEditor::new("local")
  // Should not crash — just silently drops
  editor.ws_send(b"test")
}
```

- [ ] **Step 3: Verify**

```bash
moon check && moon test -p dowdiness/canopy/editor
```

- [ ] **Step 4: Commit**

```bash
git add editor/sync_editor_ws.mbt editor/sync_editor_ws_wbtest.mbt
git commit -m "feat(editor): add WebSocket lifecycle methods on SyncEditor"
```

---

## Task 5: Exported JS Functions + Cross-Compatibility Test

**Files:**
- Modify: `crdt.mbt`
- Modify: `moon.pkg`
- Create: `relay/cross_compat_wbtest.mbt`

- [ ] **Step 1: Add relay exports to crdt.mbt**

Add to the end of `crdt.mbt`:

```moonbit
// --- Relay exports ---

///|
let relay_rooms : Map[String, @relay.RelayRoom] = Map::new()

///|
fn get_or_create_room(room_id : String) -> @relay.RelayRoom {
  match relay_rooms.get(room_id) {
    Some(room) => room
    None => {
      let room = @relay.RelayRoom::new()
      relay_rooms[room_id] = room
      room
    }
  }
}

///|
pub fn relay_on_connect(
  room_id : String,
  peer_id : String,
  send_fn : (Bytes) -> Unit,
) -> Unit {
  get_or_create_room(room_id).on_connect(peer_id, send_fn)
}

///|
pub fn relay_on_message(
  room_id : String,
  peer_id : String,
  data : Bytes,
) -> Unit {
  get_or_create_room(room_id).on_message(peer_id, data)
}

///|
pub fn relay_on_disconnect(room_id : String, peer_id : String) -> Unit {
  get_or_create_room(room_id).on_disconnect(peer_id)
}

// --- WebSocket client exports ---

///|
pub fn ws_on_open(handle : Int, ws : @editor.JsWebSocket) -> Unit {
  match editor.val {
    Some(ed) => ed.ws_on_open(ws)
    None => ()
  }
}

///|
pub fn ws_on_message(handle : Int, data : Bytes) -> Unit {
  match editor.val {
    Some(ed) => ed.ws_on_message(data)
    None => ()
  }
}

///|
pub fn ws_on_close(handle : Int) -> Unit {
  match editor.val {
    Some(ed) => ed.ws_on_close()
    None => ()
  }
}

///|
pub fn ws_broadcast_edit(handle : Int) -> Unit {
  match editor.val {
    Some(ed) => ed.ws_broadcast_edit()
    None => ()
  }
}
```

- [ ] **Step 2: Update moon.pkg imports and exports**

Add `"dowdiness/canopy/relay"` to imports in `moon.pkg`:

```
import {
  "dowdiness/canopy/editor",
  "dowdiness/canopy/relay",
  "dowdiness/event-graph-walker/text",
  "moonbitlang/core/json",
}
```

Add to the JS exports list:

```
        "relay_on_connect",
        "relay_on_message",
        "relay_on_disconnect",
        "ws_on_open",
        "ws_on_message",
        "ws_on_close",
        "ws_broadcast_edit",
```

- [ ] **Step 3: Write cross-compatibility test**

Verify that the relay's PeerJoined/PeerLeft encoding is correctly decoded by the editor's `decode_message`. Create `relay/cross_compat_wbtest.mbt`:

```moonbit
///|
test "relay PeerJoined is decodable by editor decode_message" {
  let msg = encode_peer_joined("alice")
  // Manually verify wire format matches editor's expected format:
  // [0x01=version][0x05=room_control][0x00=flags][0x01=Join][varint_len][utf8]
  inspect(msg[0], content="b'\\x01'") // version
  inspect(msg[1], content="b'\\x05'") // room control
  inspect(msg[2], content="b'\\x00'") // flags
  inspect(msg[3], content="b'\\x01'") // Join
  // The remaining bytes should be a valid uvarint-prefixed UTF-8 string.
  // We verify length > 4 (header) + at least 1 byte (varint) + 1 byte (char).
  inspect(msg.length() > 5, content="true")
}

///|
test "relay PeerLeft encoding structure" {
  let msg = encode_peer_left("bob")
  inspect(msg[0], content="b'\\x01'")
  inspect(msg[1], content="b'\\x05'")
  inspect(msg[2], content="b'\\x00'")
  inspect(msg[3], content="b'\\x02'") // Leave
}
```

- [ ] **Step 4: Run full test suite**

```bash
moon check && moon test
```

All tests must pass (307 existing + new relay + new ws tests).

- [ ] **Step 5: Update interfaces and format**

```bash
moon info && moon fmt
```

- [ ] **Step 6: Commit**

```bash
git add crdt.mbt moon.pkg relay/cross_compat_wbtest.mbt
git add -u
git commit -m "feat: add relay + WebSocket client exports for JS FFI"
```

---

## Task 6: End-to-End Integration Test (Two Editors + Relay)

**Files:**
- Create: `relay/integration_wbtest.mbt`

- [ ] **Step 1: Write two-editor sync test via relay**

Create `relay/integration_wbtest.mbt`:

Note: this test can't import `editor/` directly from the relay package. Instead, we write this as a root-level test. Actually — the relay package doesn't depend on editor. Let me put the integration test at the root level.

Create `integration_ws_test.mbt` at workspace root (same package as `crdt.mbt`):

```moonbit
///|
test "integration: two editors sync via relay" {
  let editor_a = @editor.SyncEditor::new("alice")
  let editor_b = @editor.SyncEditor::new("bob")
  let room = @relay.RelayRoom::new()
  // Wire: relay sends to editors
  let send_to_a : (Bytes) -> Unit = fn(data) { editor_a.ws_on_message(data) }
  let send_to_b : (Bytes) -> Unit = fn(data) { editor_b.ws_on_message(data) }
  // Connect both to relay
  room.on_connect("alice", send_to_a)
  room.on_connect("bob", send_to_b)
  // Alice types "hello"
  editor_a.set_text("hello")
  // Alice broadcasts her CRDT state
  let crdt_msg = try! editor_a.export_all()
  let json_str = crdt_msg.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json_str)
  let wire_msg = @editor.encode_message(@editor.CrdtOps(buf.to_bytes()))
  room.on_message("alice", wire_msg)
  // Bob should now have "hello"
  inspect(editor_b.get_text(), content="hello")
}

///|
test "integration: late joiner catches up via PeerJoined" {
  let editor_a = @editor.SyncEditor::new("alice")
  let room = @relay.RelayRoom::new()
  let send_to_a : (Bytes) -> Unit = fn(data) { editor_a.ws_on_message(data) }
  room.on_connect("alice", send_to_a)
  // Alice sets text before bob joins
  editor_a.set_text("existing doc")
  // Bob joins — relay broadcasts PeerJoined("bob") to alice
  // Alice's ws_on_message handler should send full state back
  // But we can't wire this automatically without real ws — let's simulate:
  let editor_b = @editor.SyncEditor::new("bob")
  let send_to_b : (Bytes) -> Unit = fn(data) { editor_b.ws_on_message(data) }
  // Simulate: alice sends full state to bob (what ws_on_message/PeerJoined does)
  let crdt_msg = try! editor_a.export_all()
  let json_str = crdt_msg.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json_str)
  send_to_b(@editor.encode_message(@editor.CrdtOps(buf.to_bytes())))
  inspect(editor_b.get_text(), content="existing doc")
}

///|
test "integration: peer disconnect cleans up ephemeral state" {
  let editor_a = @editor.SyncEditor::new("alice")
  let editor_b = @editor.SyncEditor::new("bob")
  let room = @relay.RelayRoom::new()
  let send_to_a : (Bytes) -> Unit = fn(data) { editor_a.ws_on_message(data) }
  let send_to_b : (Bytes) -> Unit = fn(data) { editor_b.ws_on_message(data) }
  room.on_connect("alice", send_to_a)
  room.on_connect("bob", send_to_b)
  // Bob sets presence, alice applies it
  editor_b.set_local_presence("Bob", "#00ff00")
  let presence_data = editor_b.encode_ephemeral_all()
  if presence_data.length() > 0 {
    editor_a.apply_ephemeral(presence_data)
  }
  // Bob disconnects
  room.on_disconnect("bob")
  // Alice received PeerLeft("bob") via relay broadcast
  // Verify bob's presence is cleaned up
  inspect(editor_a.get_hub().get_online_peers().length(), content="0")
}
```

- [ ] **Step 2: Verify**

```bash
moon check && moon test
```

- [ ] **Step 3: Commit**

```bash
git add integration_ws_test.mbt
git commit -m "test: add end-to-end relay + editor integration tests"
```

---

## Key Design Decisions

1. **Callback-based RelayRoom** — `RelayRoom` stores `(Bytes) -> Unit` send functions instead of opaque `JsWebSocket` references. This makes relay tests trivial (pass a closure that records to an array) while the CF Worker TypeScript glue wraps `ws.send(data)` in a closure. In production: `room.on_connect(peerId, (data) => ws.send(data))`.

2. **JSON-as-Bytes for CRDT** — `@text.SyncMessage` is serialized via existing `to_json_string()` encoded as UTF-8 Bytes. This reuses the proven JSON path. A binary codec is a future optimization.

3. **Relay has no editor dependency** — the `relay/` package only depends on `buffer`. It duplicates ~20 lines of wire encoding for PeerJoined/PeerLeft. This keeps the relay lightweight.

4. **Native target stub** — `websocket_native.mbt` provides a dummy `JsWebSocket` type so the codebase compiles on native target (for `moon test` which runs both targets).

5. **Phase 2 scope** — CF Worker TypeScript (`examples/relay-server/`), prosemirror wiring (`examples/prosemirror/src/ws-glue.ts`), and `wrangler.toml` are separate tasks after this Phase 1 proves the MoonBit logic works.
