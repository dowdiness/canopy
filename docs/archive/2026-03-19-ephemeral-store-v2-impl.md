# Ephemeral Store v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add namespace-based EphemeralHub, presence view types, multiplexed sync protocol, and InMemoryTransport to enable multi-peer collaboration.

**Architecture:** EphemeralHub wraps per-namespace EphemeralStore instances (cursor/edit_mode/drag/presence) with typed APIs. SyncMessage enum + encode/decode provides multiplexed wire format. SyncTransport trait with InMemoryTransport enables full in-process testing. Existing EphemeralStore, binary encoding, and PeerCursorView are reused as-is.

**Tech Stack:** MoonBit, editor/ package (no new external deps)

**Spec:** `docs/plans/2026-03-19-ephemeral-store-v2-design.md`

---

## Preflight

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
moon check && moon test
```

All 273 tests must pass.

---

## File Structure

| File | Role |
|------|------|
| `editor/presence_types.mbt` | **Create.** `EditModeState`, `DragState`, `DragPosition`, `PeerPresence`, `PresenceStatus` with `to_ephemeral()`/`from_ephemeral()` |
| `editor/presence_types_test.mbt` | **Create.** Roundtrip tests for presence type serialization |
| `editor/ephemeral_hub.mbt` | **Create.** `EphemeralNamespace`, `EphemeralHub` struct with typed read/write/sync/lifecycle API |
| `editor/ephemeral_hub_test.mbt` | **Create.** Hub tests (namespace routing, encode_all, on_peer_leave) |
| `editor/sync_protocol.mbt` | **Create.** `SyncTransport` trait, `SyncMessage` enum, `encode_message()`/`decode_message()` |
| `editor/sync_protocol_test.mbt` | **Create.** Wire format roundtrip tests |
| `editor/in_memory_transport.mbt` | **Create.** `InMemoryRoom`, `InMemoryTransport` for testing |
| `editor/in_memory_transport_test.mbt` | **Create.** Multi-peer relay tests |

**Not modified in this plan** (deferred to a follow-up integration task):
- `editor/sync_editor.mbt` — SyncEditor field replacement (hub + transport) is a separate step after the new types are proven
- `editor/cursor_view.mbt` — split into cursor + presence subscriptions deferred
- `editor/sync_editor_sync.mbt` — message demuxer deferred

This plan builds all new types and tests independently, then a final task wires a basic integration smoke test. SyncEditor refactoring is a follow-up.

---

## Task 1: Presence View Types

**Files:**
- Create: `editor/presence_types.mbt`
- Create: `editor/presence_types_test.mbt`

- [ ] **Step 1: Define types**

Create `editor/presence_types.mbt`:

```moonbit
///|
pub(all) struct EditModeState {
  node_id : String
} derive(Show, Eq)

///|
pub(all) enum DragPosition {
  Before
  After
  Inside
} derive(Show, Eq)

///|
pub(all) struct DragState {
  source_id : String
  target : (String, DragPosition)?
} derive(Show, Eq)

///|
pub(all) enum PresenceStatus {
  Active
  Idle
} derive(Show, Eq)

///|
pub(all) struct PeerPresence {
  peer_id : String
  display_name : String
  color : String
  status : PresenceStatus
} derive(Show, Eq)
```

- [ ] **Step 2: Add `to_ephemeral` / `from_ephemeral` for EditModeState**

```moonbit
///|
pub fn EditModeState::to_ephemeral(self : EditModeState) -> EphemeralValue {
  let map : Map[String, EphemeralValue] = {}
  map["node_id"] = EphemeralValue::String(self.node_id)
  EphemeralValue::Map(map)
}

///|
pub fn EditModeState::from_ephemeral(value : EphemeralValue) -> EditModeState? {
  match value {
    EphemeralValue::Map(map) =>
      match map.get("node_id") {
        Some(EphemeralValue::String(id)) => Some({ node_id: id })
        _ => None
      }
    _ => None
  }
}
```

- [ ] **Step 3: Add `to_ephemeral` / `from_ephemeral` for DragState**

```moonbit
///|
fn drag_position_to_string(pos : DragPosition) -> String {
  match pos {
    Before => "before"
    After => "after"
    Inside => "inside"
  }
}

///|
fn drag_position_from_string(s : String) -> DragPosition? {
  match s {
    "before" => Some(Before)
    "after" => Some(After)
    "inside" => Some(Inside)
    _ => None
  }
}

///|
pub fn DragState::to_ephemeral(self : DragState) -> EphemeralValue {
  let map : Map[String, EphemeralValue] = {}
  map["source_id"] = EphemeralValue::String(self.source_id)
  match self.target {
    Some((target_id, position)) => {
      map["target_id"] = EphemeralValue::String(target_id)
      map["position"] = EphemeralValue::String(drag_position_to_string(position))
    }
    None => ()
  }
  EphemeralValue::Map(map)
}

///|
pub fn DragState::from_ephemeral(value : EphemeralValue) -> DragState? {
  match value {
    EphemeralValue::Map(map) =>
      match map.get("source_id") {
        Some(EphemeralValue::String(source_id)) => {
          let target = match (map.get("target_id"), map.get("position")) {
            (Some(EphemeralValue::String(tid)), Some(EphemeralValue::String(pos))) =>
              match drag_position_from_string(pos) {
                Some(dp) => Some((tid, dp))
                None => None
              }
            _ => None
          }
          Some({ source_id, target })
        }
        _ => None
      }
    _ => None
  }
}
```

- [ ] **Step 4: Add `to_ephemeral` / `from_ephemeral` for PeerPresence**

```moonbit
///|
pub fn PeerPresence::to_ephemeral(self : PeerPresence) -> EphemeralValue {
  let map : Map[String, EphemeralValue] = {}
  map["peer_id"] = EphemeralValue::String(self.peer_id)
  map["display_name"] = EphemeralValue::String(self.display_name)
  map["color"] = EphemeralValue::String(self.color)
  map["status"] = EphemeralValue::String(
    match self.status {
      Active => "active"
      Idle => "idle"
    },
  )
  EphemeralValue::Map(map)
}

///|
pub fn PeerPresence::from_ephemeral(value : EphemeralValue) -> PeerPresence? {
  match value {
    EphemeralValue::Map(map) => {
      let peer_id = match map.get("peer_id") {
        Some(EphemeralValue::String(s)) => s
        _ => return None
      }
      let display_name = match map.get("display_name") {
        Some(EphemeralValue::String(s)) => s
        _ => return None
      }
      let color = match map.get("color") {
        Some(EphemeralValue::String(s)) => s
        _ => return None
      }
      let status = match map.get("status") {
        Some(EphemeralValue::String("active")) => Active
        Some(EphemeralValue::String("idle")) => Idle
        _ => Active
      }
      Some({ peer_id, display_name, color, status })
    }
    _ => None
  }
}
```

- [ ] **Step 5: Write tests**

Create `editor/presence_types_test.mbt`:

```moonbit
///|
test "EditModeState roundtrip" {
  let state : EditModeState = { node_id: "node-42" }
  let ephemeral = state.to_ephemeral()
  inspect!(EditModeState::from_ephemeral(ephemeral), content="Some({node_id: \"node-42\"})")
}

///|
test "EditModeState from_ephemeral rejects non-Map" {
  inspect!(EditModeState::from_ephemeral(EphemeralValue::Null), content="None")
}

///|
test "DragState roundtrip with target" {
  let state : DragState = { source_id: "src", target: Some(("tgt", Before)) }
  let result = DragState::from_ephemeral(state.to_ephemeral())
  inspect!(result, content="Some({source_id: \"src\", target: Some((\"tgt\", Before))})")
}

///|
test "DragState roundtrip without target" {
  let state : DragState = { source_id: "src", target: None }
  let result = DragState::from_ephemeral(state.to_ephemeral())
  inspect!(result, content="Some({source_id: \"src\", target: None})")
}

///|
test "PeerPresence roundtrip" {
  let p : PeerPresence = {
    peer_id: "alice",
    display_name: "Alice",
    color: "#ff0000",
    status: Active,
  }
  let result = PeerPresence::from_ephemeral(p.to_ephemeral())
  inspect!(
    result,
    content="Some({peer_id: \"alice\", display_name: \"Alice\", color: \"#ff0000\", status: Active})",
  )
}

///|
test "PeerPresence idle status roundtrip" {
  let p : PeerPresence = {
    peer_id: "bob",
    display_name: "Bob",
    color: "#0000ff",
    status: Idle,
  }
  let result = PeerPresence::from_ephemeral(p.to_ephemeral())
  match result {
    Some(presence) => inspect!(presence.status, content="Idle")
    None => fail!("expected Some")
  }
}
```

- [ ] **Step 6: Verify**

```bash
moon check && moon test -p dowdiness/canopy/editor -f presence_types_test.mbt
```

- [ ] **Step 7: Commit**

```bash
git add editor/presence_types.mbt editor/presence_types_test.mbt
git commit -m "feat(editor): add presence view types with EphemeralValue serialization"
```

---

## Task 2: EphemeralHub & Namespace

**Files:**
- Create: `editor/ephemeral_hub.mbt`
- Create: `editor/ephemeral_hub_test.mbt`

- [ ] **Step 1: Define EphemeralNamespace and EphemeralHub**

Create `editor/ephemeral_hub.mbt`:

```moonbit
///|
pub enum EphemeralNamespace {
  Cursor
  EditMode
  Drag
  Presence
} derive(Show, Eq, Compare, Hash)

///|
fn default_timeout(ns : EphemeralNamespace) -> UInt64 {
  match ns {
    Cursor => 30_000UL
    EditMode => 60_000UL
    Drag => 5_000UL
    Presence => 120_000UL
  }
}

///|
fn namespace_to_byte(ns : EphemeralNamespace) -> Byte {
  match ns {
    Cursor => b'\x01'
    EditMode => b'\x02'
    Drag => b'\x03'
    Presence => b'\x04'
  }
}

///|
fn namespace_from_byte(b : Byte) -> EphemeralNamespace? {
  match b {
    b'\x01' => Some(Cursor)
    b'\x02' => Some(EditMode)
    b'\x03' => Some(Drag)
    b'\x04' => Some(Presence)
    _ => None
  }
}

///|
let all_namespaces : Array[EphemeralNamespace] = [Cursor, EditMode, Drag, Presence]

///|
pub struct EphemeralHub {
  local_peer_id : String
  wire_peer_id : String
  stores : Map[EphemeralNamespace, EphemeralStore]
}

///|
pub fn EphemeralHub::new(local_peer_id : String) -> EphemeralHub {
  let stores : Map[EphemeralNamespace, EphemeralStore] = {}
  for ns in all_namespaces {
    stores[ns] = EphemeralStore::new(default_timeout(ns))
  }
  let wire_peer_id = to_wire_peer_id(local_peer_id)
  { local_peer_id, wire_peer_id, stores }
}
```

- [ ] **Step 2: Add typed write methods**

```moonbit
///|
pub fn EphemeralHub::set_cursor(
  self : EphemeralHub,
  position : Int,
  selection? : (Int, Int)? = None,
) -> Unit {
  let map : Map[String, EphemeralValue] = {}
  map["position"] = EphemeralValue::I64(position.to_int64())
  match selection {
    Some((start, end)) =>
      map["selection"] = EphemeralValue::List([
        EphemeralValue::I64(start.to_int64()),
        EphemeralValue::I64(end.to_int64()),
      ])
    None => ()
  }
  self.stores[Cursor].set(self.wire_peer_id, EphemeralValue::Map(map)) catch {
    _ => ()
  }
}

///|
pub fn EphemeralHub::set_edit_mode(self : EphemeralHub, node_id : String) -> Unit {
  let state : EditModeState = { node_id, }
  self.stores[EditMode].set(self.wire_peer_id, state.to_ephemeral()) catch {
    _ => ()
  }
}

///|
pub fn EphemeralHub::clear_edit_mode(self : EphemeralHub) -> Unit {
  self.stores[EditMode].delete(self.wire_peer_id) catch {
    _ => ()
  }
}

///|
pub fn EphemeralHub::set_drag(
  self : EphemeralHub,
  source_id : String,
  target? : (String, DragPosition)? = None,
) -> Unit {
  let state : DragState = { source_id, target }
  self.stores[Drag].set(self.wire_peer_id, state.to_ephemeral()) catch {
    _ => ()
  }
}

///|
pub fn EphemeralHub::clear_drag(self : EphemeralHub) -> Unit {
  self.stores[Drag].delete(self.wire_peer_id) catch {
    _ => ()
  }
}

///|
pub fn EphemeralHub::set_presence(
  self : EphemeralHub,
  display_name : String,
  color : String,
  status : PresenceStatus,
) -> Unit {
  let presence : PeerPresence = {
    peer_id: self.local_peer_id,
    display_name,
    color,
    status,
  }
  self.stores[Presence].set(self.wire_peer_id, presence.to_ephemeral()) catch {
    _ => ()
  }
}
```

- [ ] **Step 3: Add typed read methods**

```moonbit
///|
pub fn EphemeralHub::get_cursor(
  self : EphemeralHub,
  peer_id : String,
) -> (Int, (Int, Int)?)? {
  let wire_id = to_wire_peer_id(peer_id)
  match self.stores[Cursor].get(wire_id) {
    Some(EphemeralValue::Map(map)) => {
      let position = match map.get("position") {
        Some(EphemeralValue::I64(n)) => n.to_int()
        _ => return None
      }
      let selection = match map.get("selection") {
        Some(EphemeralValue::List(arr)) =>
          if arr.length() == 2 {
            match (arr[0], arr[1]) {
              (EphemeralValue::I64(a), EphemeralValue::I64(b)) =>
                Some((a.to_int(), b.to_int()))
              _ => None
            }
          } else {
            None
          }
        _ => None
      }
      Some((position, selection))
    }
    _ => None
  }
}

///|
pub fn EphemeralHub::get_edit_mode(
  self : EphemeralHub,
  peer_id : String,
) -> EditModeState? {
  let wire_id = to_wire_peer_id(peer_id)
  match self.stores[EditMode].get(wire_id) {
    Some(value) => EditModeState::from_ephemeral(value)
    None => None
  }
}

///|
pub fn EphemeralHub::get_all_editing(
  self : EphemeralHub,
) -> Map[String, EditModeState] {
  let result : Map[String, EditModeState] = {}
  for key, value in self.stores[EditMode].get_all_states() {
    match EditModeState::from_ephemeral(value) {
      Some(state) => result[key] = state
      None => ()
    }
  }
  result
}

///|
pub fn EphemeralHub::get_presence(
  self : EphemeralHub,
  peer_id : String,
) -> PeerPresence? {
  let wire_id = to_wire_peer_id(peer_id)
  match self.stores[Presence].get(wire_id) {
    Some(value) => PeerPresence::from_ephemeral(value)
    None => None
  }
}

///|
pub fn EphemeralHub::get_online_peers(
  self : EphemeralHub,
) -> Array[PeerPresence] {
  let result : Array[PeerPresence] = []
  for _key, value in self.stores[Presence].get_all_states() {
    match PeerPresence::from_ephemeral(value) {
      Some(presence) => result.push(presence)
      None => ()
    }
  }
  result
}
```

- [ ] **Step 4: Add sync and lifecycle methods**

```moonbit
///|
pub fn EphemeralHub::get_store(
  self : EphemeralHub,
  ns : EphemeralNamespace,
) -> EphemeralStore {
  self.stores[ns]
}

///|
pub fn EphemeralHub::encode(
  self : EphemeralHub,
  ns : EphemeralNamespace,
) -> Bytes {
  self.stores[ns].encode_all()
}

///|
pub fn EphemeralHub::encode_all(self : EphemeralHub) -> Bytes {
  // Encode each namespace once, collect non-empty results
  let entries : Array[(EphemeralNamespace, Bytes)] = []
  for ns in all_namespaces {
    let data = self.stores[ns].encode_all()
    if data.length() > 0 {
      entries.push((ns, data))
    }
  }
  let buf = @buffer.new()
  buf.write_byte(entries.length().to_byte())
  for entry in entries {
    let (ns, data) = entry
    buf.write_byte(namespace_to_byte(ns))
    // Write data length as 4 bytes LE for framing
    let len = data.length()
    buf.write_byte((len & 0xFF).to_byte())
    buf.write_byte(((len >> 8) & 0xFF).to_byte())
    buf.write_byte(((len >> 16) & 0xFF).to_byte())
    buf.write_byte(((len >> 24) & 0xFF).to_byte())
    buf.write_bytes(data)
  }
  buf.to_bytes()
}

///|
pub fn EphemeralHub::apply(
  self : EphemeralHub,
  ns : EphemeralNamespace,
  data : Bytes,
) -> Unit {
  self.stores[ns].apply(data) catch {
    _ => ()
  }
}

///|
pub fn EphemeralHub::apply_all(self : EphemeralHub, data : Bytes) -> Unit {
  if data.length() == 0 {
    return
  }
  let count = data[0].to_int()
  let mut offset = 1
  for _i = 0; _i < count; _i = _i + 1 {
    if offset >= data.length() {
      break
    }
    let ns = match namespace_from_byte(data[offset]) {
      Some(ns) => ns
      None => break
    }
    offset = offset + 1
    if offset + 4 > data.length() {
      break
    }
    let len = data[offset].to_int() |
      (data[offset + 1].to_int() << 8) |
      (data[offset + 2].to_int() << 16) |
      (data[offset + 3].to_int() << 24)
    offset = offset + 4
    if offset + len > data.length() {
      break
    }
    let ns_data = data.view(start=offset, end=offset + len).to_bytes()
    self.apply(ns, ns_data)
    offset = offset + len
  }
}

///|
pub fn EphemeralHub::remove_outdated(self : EphemeralHub) -> Unit {
  for ns in all_namespaces {
    self.stores[ns].remove_outdated()
  }
}

///|
pub fn EphemeralHub::on_peer_leave(self : EphemeralHub, peer_id : String) -> Unit {
  let wire_id = to_wire_peer_id(peer_id)
  for ns in all_namespaces {
    self.stores[ns].delete(wire_id) catch {
      _ => ()
    }
  }
}
```

- [ ] **Step 5: Write tests**

Create `editor/ephemeral_hub_test.mbt`:

```moonbit
///|
test "hub: set and get edit mode" {
  let hub = EphemeralHub::new("alice")
  hub.set_edit_mode("node-1")
  inspect!(hub.get_edit_mode("alice"), content="Some({node_id: \"node-1\"})")
}

///|
test "hub: clear edit mode" {
  let hub = EphemeralHub::new("alice")
  hub.set_edit_mode("node-1")
  hub.clear_edit_mode()
  inspect!(hub.get_edit_mode("alice"), content="None")
}

///|
test "hub: set presence and get online peers" {
  let hub = EphemeralHub::new("alice")
  hub.set_presence("Alice", "#ff0000", Active)
  let peers = hub.get_online_peers()
  inspect!(peers.length(), content="1")
  inspect!(peers[0].display_name, content="Alice")
}

///|
test "hub: on_peer_leave clears all namespaces" {
  let hub = EphemeralHub::new("alice")
  hub.set_cursor(42)
  hub.set_edit_mode("node-1")
  hub.set_presence("Alice", "#ff0000", Active)
  hub.on_peer_leave("alice")
  inspect!(hub.get_edit_mode("alice"), content="None")
  inspect!(hub.get_online_peers().length(), content="0")
}

///|
test "hub: encode_all and apply_all roundtrip" {
  let hub_a = EphemeralHub::new("alice")
  hub_a.set_edit_mode("node-5")
  hub_a.set_presence("Alice", "#ff0000", Active)
  let bytes = hub_a.encode_all()
  let hub_b = EphemeralHub::new("bob")
  hub_b.apply_all(bytes)
  inspect!(hub_b.get_edit_mode("alice"), content="Some({node_id: \"node-5\"})")
}

///|
test "hub: per-namespace encode/apply" {
  let hub_a = EphemeralHub::new("alice")
  hub_a.set_edit_mode("node-3")
  let bytes = hub_a.encode(EditMode)
  let hub_b = EphemeralHub::new("bob")
  hub_b.apply(EditMode, bytes)
  inspect!(hub_b.get_edit_mode("alice"), content="Some({node_id: \"node-3\"})")
}

///|
test "hub: get_all_editing" {
  let hub = EphemeralHub::new("alice")
  hub.set_edit_mode("node-7")
  let editing = hub.get_all_editing()
  inspect!(editing.size(), content="1")
}

///|
test "hub: apply_all with empty bytes" {
  let hub = EphemeralHub::new("alice")
  hub.apply_all(Bytes::new(0))
  inspect!(hub.get_online_peers().length(), content="0")
}
```

- [ ] **Step 6: Verify**

```bash
moon check && moon test -p dowdiness/canopy/editor -f ephemeral_hub_test.mbt
```

- [ ] **Step 7: Update interfaces and format**

```bash
moon info && moon fmt
```

- [ ] **Step 8: Commit**

```bash
git add editor/ephemeral_hub.mbt editor/ephemeral_hub_test.mbt
git commit -m "feat(editor): add EphemeralHub with namespace-based store routing"
```

---

## Task 3: Sync Protocol (SyncTransport + SyncMessage)

**Files:**
- Create: `editor/sync_protocol.mbt`
- Create: `editor/sync_protocol_test.mbt`

- [ ] **Step 1: Define SyncTransport trait and SyncMessage enum**

Create `editor/sync_protocol.mbt`:

```moonbit
///|
pub(open) trait SyncTransport {
  send(Self, Bytes) -> Unit
  on_receive(Self, (Bytes) -> Unit) -> Unit
  close(Self) -> Unit
}

///|
pub enum SyncMessage {
  CrdtOps(Bytes)
  EphemeralUpdate(EphemeralNamespace, Bytes)
  SyncRequest(Bytes)
  SyncResponse(Bytes)
  PeerJoined(String)
  PeerLeft(String)
} derive(Show, Eq)
```

- [ ] **Step 2: Implement encode_message**

```moonbit
///|
let protocol_version : Byte = b'\x01'

///|
fn message_type_byte(msg : SyncMessage) -> Byte {
  match msg {
    CrdtOps(_) => b'\x01'
    EphemeralUpdate(_, _) => b'\x02'
    SyncRequest(_) => b'\x03'
    SyncResponse(_) => b'\x04'
    PeerJoined(_) | PeerLeft(_) => b'\x05'
  }
}

///|
fn write_msg_uvarint(buf : @buffer.Buffer, value : Int) -> Unit {
  let mut v = value
  while v >= 0x80 {
    buf.write_byte((v & 0x7F | 0x80).to_byte())
    v = v >> 7
  }
  buf.write_byte(v.to_byte())
}

///|
fn write_msg_string(buf : @buffer.Buffer, s : String) -> Unit {
  let tmp = @buffer.new()
  tmp.write_string(s)
  let bytes = tmp.to_bytes()
  write_msg_uvarint(buf, bytes.length())
  buf.write_bytes(bytes)
}

///|
pub fn encode_message(msg : SyncMessage) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(protocol_version)
  buf.write_byte(message_type_byte(msg))
  buf.write_byte(b'\x00') // flags: no BFT
  match msg {
    CrdtOps(payload) | SyncRequest(payload) | SyncResponse(payload) =>
      for i = 0; i < payload.length(); i = i + 1 {
        buf.write_byte(payload[i])
      }
    EphemeralUpdate(ns, payload) => {
      buf.write_byte(namespace_to_byte(ns))
      for i = 0; i < payload.length(); i = i + 1 {
        buf.write_byte(payload[i])
      }
    }
    PeerJoined(peer_id) => {
      buf.write_byte(b'\x01') // sub_type: Join
      write_msg_string(buf, peer_id)
    }
    PeerLeft(peer_id) => {
      buf.write_byte(b'\x02') // sub_type: Leave
      write_msg_string(buf, peer_id)
    }
  }
  buf.to_bytes()
}
```

- [ ] **Step 3: Implement decode_message**

```moonbit
///|
fn read_msg_uvarint(data : Bytes, offset : Ref[Int]) -> Int {
  let mut result = 0
  let mut shift = 0
  while offset.val < data.length() {
    let b = data[offset.val].to_int()
    offset.val = offset.val + 1
    result = result | ((b & 0x7F) << shift)
    if b & 0x80 == 0 {
      break
    }
    shift = shift + 7
  }
  result
}

///|
fn read_msg_string(data : Bytes, offset : Ref[Int]) -> String {
  let len = read_msg_uvarint(data, offset)
  if offset.val + len > data.length() {
    return ""
  }
  let str_bytes = data.view(start=offset.val, end=offset.val + len).to_bytes()
  offset.val = offset.val + len
  str_bytes.to_unchecked_string()
}

///|
fn slice_from(data : Bytes, start : Int) -> Bytes {
  if start >= data.length() {
    return Bytes::new(0)
  }
  data.view(start~, end=data.length()).to_bytes()
}

///|
pub fn decode_message(data : Bytes) -> SyncMessage? {
  if data.length() < 3 {
    return None
  }
  let version = data[0]
  if version != protocol_version {
    return None
  }
  let msg_type = data[1]
  // data[2] = flags (ignored in v1)
  let payload = slice_from(data, 3)
  match msg_type {
    b'\x01' => Some(CrdtOps(payload))
    b'\x02' => {
      if payload.length() < 1 {
        return None
      }
      match namespace_from_byte(payload[0]) {
        Some(ns) => Some(EphemeralUpdate(ns, slice_from(payload, 1)))
        None => None
      }
    }
    b'\x03' => Some(SyncRequest(payload))
    b'\x04' => Some(SyncResponse(payload))
    b'\x05' => {
      if payload.length() < 1 {
        return None
      }
      let sub_type = payload[0]
      let offset = Ref::new(1)
      let peer_id = read_msg_string(payload, offset)
      match sub_type {
        b'\x01' => Some(PeerJoined(peer_id))
        b'\x02' => Some(PeerLeft(peer_id))
        _ => None
      }
    }
    _ => None
  }
}
```

- [ ] **Step 4: Write tests**

Create `editor/sync_protocol_test.mbt`:

```moonbit
///|
fn str_to_bytes(s : String) -> Bytes {
  let buf = @buffer.new()
  buf.write_string(s)
  buf.to_bytes()
}

///|
test "encode/decode CrdtOps roundtrip" {
  let payload = str_to_bytes("hello")
  let msg = CrdtOps(payload)
  match decode_message(encode_message(msg)) {
    Some(CrdtOps(decoded_payload)) =>
      inspect!(decoded_payload.length(), content="5")
    _ => fail!("expected CrdtOps")
  }
}

///|
test "encode/decode EphemeralUpdate roundtrip" {
  let payload = str_to_bytes("data")
  let msg = EphemeralUpdate(Cursor, payload)
  match decode_message(encode_message(msg)) {
    Some(EphemeralUpdate(ns, _)) => inspect!(ns, content="Cursor")
    _ => fail!("expected EphemeralUpdate")
  }
}

///|
test "encode/decode SyncRequest roundtrip" {
  let msg = SyncRequest(str_to_bytes("req"))
  match decode_message(encode_message(msg)) {
    Some(SyncRequest(_)) => ()
    _ => fail!("expected SyncRequest")
  }
}

///|
test "encode/decode PeerJoined roundtrip" {
  let msg = PeerJoined("alice")
  inspect!(decode_message(encode_message(msg)), content="Some(PeerJoined(\"alice\"))")
}

///|
test "encode/decode PeerLeft roundtrip" {
  let msg = PeerLeft("bob")
  inspect!(decode_message(encode_message(msg)), content="Some(PeerLeft(\"bob\"))")
}

///|
test "decode rejects wrong version" {
  let data = Bytes::new(4)
  data[0] = b'\xFF' // bad version
  data[1] = b'\x01'
  data[2] = b'\x00'
  inspect!(decode_message(data), content="None")
}

///|
test "decode rejects too short" {
  inspect!(decode_message(Bytes::new(2)), content="None")
}

///|
test "wire format: version byte is 0x01" {
  let encoded = encode_message(CrdtOps(Bytes::new(0)))
  inspect!(encoded[0], content="b'\\x01'")
}

///|
test "wire format: flags byte is 0x00" {
  let encoded = encode_message(CrdtOps(Bytes::new(0)))
  inspect!(encoded[2], content="b'\\x00'")
}

///|
test "EphemeralUpdate all namespaces" {
  let namespaces : Array[EphemeralNamespace] = [Cursor, EditMode, Drag, Presence]
  for ns in namespaces {
    let msg = EphemeralUpdate(ns, str_to_bytes("x"))
    match decode_message(encode_message(msg)) {
      Some(EphemeralUpdate(decoded_ns, _)) =>
        if decoded_ns != ns {
          fail!("namespace mismatch")
        }
      _ => fail!("expected EphemeralUpdate")
    }
  }
}
```

- [ ] **Step 5: Verify**

```bash
moon check && moon test -p dowdiness/canopy/editor -f sync_protocol_test.mbt
```

- [ ] **Step 6: Commit**

```bash
git add editor/sync_protocol.mbt editor/sync_protocol_test.mbt
git commit -m "feat(editor): add SyncTransport trait and SyncMessage wire protocol"
```

---

## Task 4: InMemoryTransport

**Files:**
- Create: `editor/in_memory_transport.mbt`
- Create: `editor/in_memory_transport_test.mbt`

- [ ] **Step 1: Implement InMemoryRoom and InMemoryTransport**

Create `editor/in_memory_transport.mbt`:

```moonbit
///|
pub struct InMemoryRoom {
  peers : Map[String, Array[(Bytes) -> Unit]]
}

///|
pub fn InMemoryRoom::new() -> InMemoryRoom {
  { peers: Map::new() }
}

///|
fn InMemoryRoom::broadcast(
  self : InMemoryRoom,
  sender : String,
  data : Bytes,
) -> Unit {
  for peer_id, handlers in self.peers {
    if peer_id != sender {
      for handler in handlers {
        handler(data)
      }
    }
  }
}

///|
fn InMemoryRoom::register(
  self : InMemoryRoom,
  peer_id : String,
) -> Unit {
  match self.peers.get(peer_id) {
    Some(_) => ()
    None => self.peers[peer_id] = []
  }
}

///|
fn InMemoryRoom::unregister(
  self : InMemoryRoom,
  peer_id : String,
) -> Unit {
  self.peers.remove(peer_id)
}

///|
pub struct InMemoryTransport {
  peer_id : String
  room : InMemoryRoom
}

///|
pub fn InMemoryTransport::new(
  peer_id : String,
  room : InMemoryRoom,
) -> InMemoryTransport {
  room.register(peer_id)
  { peer_id, room }
}

///|
pub impl SyncTransport for InMemoryTransport with send(self, data) {
  self.room.broadcast(self.peer_id, data)
}

///|
pub impl SyncTransport for InMemoryTransport with on_receive(self, handler) {
  match self.room.peers.get(self.peer_id) {
    Some(handlers) => handlers.push(handler)
    None => ()
  }
}

///|
pub impl SyncTransport for InMemoryTransport with close(self) {
  self.room.unregister(self.peer_id)
}
```

- [ ] **Step 2: Write tests**

Create `editor/in_memory_transport_test.mbt`:

```moonbit
///|
fn test_bytes(s : String) -> Bytes {
  let buf = @buffer.new()
  buf.write_string(s)
  buf.to_bytes()
}

///|
test "InMemoryTransport: two peers exchange messages" {
  let room = InMemoryRoom::new()
  let t_a = InMemoryTransport::new("alice", room)
  let t_b = InMemoryTransport::new("bob", room)
  let received : Array[Int] = []
  t_b.on_receive(fn(data) { received.push(data.length()) })
  t_a.send(test_bytes("hello"))
  inspect!(received.length(), content="1")
}

///|
test "InMemoryTransport: sender does not receive own message" {
  let room = InMemoryRoom::new()
  let t_a = InMemoryTransport::new("alice", room)
  let received : Array[Int] = []
  t_a.on_receive(fn(data) { received.push(data.length()) })
  t_a.send(test_bytes("hello"))
  inspect!(received.length(), content="0")
}

///|
test "InMemoryTransport: three peers broadcast" {
  let room = InMemoryRoom::new()
  let t_a = InMemoryTransport::new("alice", room)
  let t_b = InMemoryTransport::new("bob", room)
  let t_c = InMemoryTransport::new("carol", room)
  let b_msgs : Array[Int] = []
  let c_msgs : Array[Int] = []
  t_b.on_receive(fn(data) { b_msgs.push(data.length()) })
  t_c.on_receive(fn(data) { c_msgs.push(data.length()) })
  t_a.send(test_bytes("from-alice"))
  inspect!(b_msgs.length(), content="1")
  inspect!(c_msgs.length(), content="1")
}

///|
test "InMemoryTransport: close unregisters peer" {
  let room = InMemoryRoom::new()
  let t_a = InMemoryTransport::new("alice", room)
  let _t_b = InMemoryTransport::new("bob", room)
  let received : Array[Int] = []
  _t_b.on_receive(fn(data) { received.push(data.length()) })
  t_a.close()
  // After close, alice's messages should not reach bob (alice unregistered)
  // But bob should still receive from other peers
  inspect!(received.length(), content="0")
}

///|
test "InMemoryTransport: protocol message roundtrip" {
  let room = InMemoryRoom::new()
  let t_a = InMemoryTransport::new("alice", room)
  let t_b = InMemoryTransport::new("bob", room)
  let received_msgs : Array[SyncMessage] = []
  t_b.on_receive(fn(data) {
    match decode_message(data) {
      Some(msg) => received_msgs.push(msg)
      None => ()
    }
  })
  t_a.send(encode_message(PeerJoined("alice")))
  inspect!(received_msgs.length(), content="1")
  inspect!(received_msgs[0], content="PeerJoined(\"alice\")")
}
```

- [ ] **Step 3: Verify**

```bash
moon check && moon test -p dowdiness/canopy/editor -f in_memory_transport_test.mbt
```

- [ ] **Step 4: Commit**

```bash
git add editor/in_memory_transport.mbt editor/in_memory_transport_test.mbt
git commit -m "feat(editor): add InMemoryTransport for in-process multi-peer testing"
```

---

## Task 5: Integration Smoke Test

**Files:**
- Create: `editor/ephemeral_hub_integration_test.mbt`

- [ ] **Step 1: Write two-peer hub sync test via InMemoryTransport**

Create `editor/ephemeral_hub_integration_test.mbt`:

```moonbit
///|
test "integration: two hubs sync via InMemoryTransport" {
  let room = InMemoryRoom::new()
  let hub_a = EphemeralHub::new("alice")
  let hub_b = EphemeralHub::new("bob")
  let t_a = InMemoryTransport::new("alice", room)
  let t_b = InMemoryTransport::new("bob", room)
  // Wire: when alice sends ephemeral, bob applies
  t_b.on_receive(fn(data) {
    match decode_message(data) {
      Some(EphemeralUpdate(ns, payload)) => hub_b.apply(ns, payload)
      _ => ()
    }
  })
  // Alice sets presence and sends
  hub_a.set_presence("Alice", "#ff0000", Active)
  let presence_bytes = hub_a.encode(Presence)
  t_a.send(encode_message(EphemeralUpdate(Presence, presence_bytes)))
  // Bob should see alice's presence
  let peers = hub_b.get_online_peers()
  inspect!(peers.length(), content="1")
  inspect!(peers[0].display_name, content="Alice")
}

///|
test "integration: peer leave clears state across hubs" {
  let hub_a = EphemeralHub::new("alice")
  let hub_b = EphemeralHub::new("bob")
  // Simulate: alice's presence applied to bob's hub
  hub_a.set_presence("Alice", "#ff0000", Active)
  hub_b.apply(Presence, hub_a.encode(Presence))
  inspect!(hub_b.get_online_peers().length(), content="1")
  // Alice leaves
  hub_b.on_peer_leave("alice")
  inspect!(hub_b.get_online_peers().length(), content="0")
}

///|
test "integration: encode_all catches up new peer" {
  let hub_a = EphemeralHub::new("alice")
  hub_a.set_edit_mode("node-42")
  hub_a.set_presence("Alice", "#ff0000", Active)
  let full_state = hub_a.encode_all()
  // New peer joins and receives full state
  let hub_c = EphemeralHub::new("carol")
  hub_c.apply_all(full_state)
  inspect!(hub_c.get_edit_mode("alice"), content="Some({node_id: \"node-42\"})")
  inspect!(hub_c.get_online_peers().length(), content="1")
}

///|
test "integration: drag state lifecycle" {
  let hub_a = EphemeralHub::new("alice")
  let hub_b = EphemeralHub::new("bob")
  // Alice starts drag
  hub_a.set_drag("src-node", target=Some(("tgt-node", After)))
  hub_b.apply(Drag, hub_a.encode(Drag))
  // Bob sees drag
  let drag_states = hub_b.get_store(Drag).get_all_states()
  inspect!(drag_states.size(), content="1")
  // Alice cancels drag
  hub_a.clear_drag()
  hub_b.apply(Drag, hub_a.encode(Drag))
  let after_clear = hub_b.get_store(Drag).get_all_states()
  inspect!(after_clear.size(), content="0")
}
```

- [ ] **Step 2: Run full test suite**

```bash
moon check && moon test
```

All tests must pass (273 existing + new tests).

- [ ] **Step 3: Update interfaces and format**

```bash
moon info && moon fmt
```

- [ ] **Step 4: Commit**

```bash
git add editor/ephemeral_hub_integration_test.mbt
moon info && moon fmt
git add -u
git commit -m "test(editor): add hub + transport integration smoke tests"
```

---

## Key Design Decisions

1. **Hub encode_all uses 4-byte LE length framing** per namespace — simpler than uvarint for framing and consistent with the existing encoding format. The count byte at the start tells `apply_all` how many namespaces to expect.

2. **SyncEditor integration is deferred** — this plan builds and tests all new types independently. Wiring hub/transport into SyncEditor (replacing the current `ephemeral` + `cursor_view` fields) is a follow-up task to keep this plan focused and reviewable.

3. **`to_wire_peer_id` reused from existing ephemeral encoding** — the hub delegates peer ID mapping to the same function used by the current EphemeralStore, ensuring wire compatibility.

4. **DragState target is `(String, DragPosition)?`** — both target_id and position are present or both absent. This matches the spec and avoids partial drag states.

5. **InMemoryTransport broadcast is synchronous** — handlers fire immediately on `send()`, matching the spec's "identical semantics to a real relay" requirement. This makes tests deterministic.
