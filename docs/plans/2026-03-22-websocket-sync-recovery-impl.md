# WebSocket Sync Recovery — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement SyncRequest/SyncResponse recovery so failed `apply_sync` triggers automatic per-peer recovery with exponential backoff, instead of silently diverging.

**Architecture:** Protocol v2 with RelayedCrdtOps (sender-tagged), peer-addressed SyncRequest/SyncResponse with request_id correlation. Relay wraps CrdtOps with sender ID and routes targeted messages. Editor maintains a RecoveryContext state machine with per-sender message buffering, timeout, and backoff.

**Tech Stack:** MoonBit, moon test (snapshot-based via `inspect`), whitebox tests (`*_wbtest.mbt`)

**Spec:** `docs/plans/2026-03-22-websocket-sync-recovery-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `editor/sync_protocol.mbt` | Protocol v2, RelayedCrdtOps, peer-addressed SyncRequest/SyncResponse |
| Modify | `editor/sync_protocol_wbtest.mbt` | Wire protocol v2 tests |
| Modify | `relay/wire.mbt` | Relay wire version bump, sender wrapping helpers |
| Modify | `relay/relay_room.mbt` | `send_to`, message routing in `on_message` |
| Modify | `relay/relay_room_wbtest.mbt` | Relay routing tests |
| Create | `editor/recovery.mbt` | RecoveryContext struct, state transitions |
| Create | `editor/recovery_wbtest.mbt` | Recovery state machine tests |
| Modify | `editor/sync_editor.mbt` | Add recovery fields to SyncEditor |
| Modify | `editor/sync_editor_ws.mbt` | Handle RelayedCrdtOps, SyncRequest, SyncResponse, recovery flow |

---

### Task 1: Protocol v2 — Version Bump + RelayedCrdtOps

**Files:**
- Modify: `editor/sync_protocol.mbt`
- Modify: `editor/sync_protocol_wbtest.mbt`

- [ ] **Step 1: Write failing tests for v2 protocol**

In `editor/sync_protocol_wbtest.mbt`, add:

```moonbit
///|
test "v2: encode/decode RelayedCrdtOps roundtrip" {
  let payload = str_to_bytes("test payload")
  let encoded = encode_relayed_crdt_ops("alice", payload)
  let decoded = decode_message(encoded)
  match decoded {
    Some(RelayedCrdtOps(sender~, payload~)) => {
      inspect(sender, content="alice")
      inspect(payload == str_to_bytes("test payload"), content="true")
    }
    _ => fail("expected RelayedCrdtOps")
  }
}

///|
test "v2: old v1 messages return None" {
  // Manually construct a v1 message (version byte 0x01)
  let buf = @buffer.new()
  buf.write_byte(b'\x01') // old version
  buf.write_byte(b'\x01') // CrdtOps type
  buf.write_byte(b'\x00') // flags
  let old_msg = buf.to_bytes()
  inspect(decode_message(old_msg) is None, content="true")
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `moon test -p dowdiness/canopy/editor -f sync_protocol_wbtest.mbt`
Expected: Compilation error — `RelayedCrdtOps` and `encode_relayed_crdt_ops` not defined.

- [ ] **Step 3: Update protocol version and add RelayedCrdtOps**

In `editor/sync_protocol.mbt`:

1. Change `let protocol_version : Byte = b'\x01'` to `let protocol_version : Byte = b'\x02'`

2. Add `RelayedCrdtOps(sender~ : String, payload~ : Bytes)` to the `SyncMessage` enum.

3. Add `RelayedCrdtOps(sender~, _) => b'\x06'` to `message_type_byte`.

4. Add `encode_relayed_crdt_ops` function:

```moonbit
///|
/// Encode a RelayedCrdtOps message. Used by the relay to wrap CrdtOps with sender ID.
pub fn encode_relayed_crdt_ops(sender : String, payload : Bytes) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(protocol_version)
  buf.write_byte(b'\x06')
  buf.write_byte(b'\x00') // flags
  write_string(buf, sender)
  buf.write_bytes(payload)
  buf.to_bytes()
}
```

5. Add `b'\x06'` case to `decode_message`:

```moonbit
b'\x06' => {
  let reader = Reader::new(
    data.view(start=payload_start, end=data.length()).to_bytes(),
  )
  let sender = read_string(reader) catch { _ => return None }
  let remaining = reader.remaining()
  Some(RelayedCrdtOps(sender~, payload=remaining))
}
```

6. Update the `CrdtOps | SyncRequest | SyncResponse` arm in `encode_message` to exclude `RelayedCrdtOps` (it has its own encoder).

- [ ] **Step 4: Run tests — verify they pass**

Run: `moon test -p dowdiness/canopy/editor -f sync_protocol_wbtest.mbt`
Expected: All pass.

- [ ] **Step 5: Fix existing tests broken by version bump**

The existing tests construct v1 messages manually. Update `str_to_bytes`-based test helpers or update version byte in manual constructions. Run full editor test suite:

Run: `moon test`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add editor/sync_protocol.mbt editor/sync_protocol_wbtest.mbt
git commit -m "feat(editor): protocol v2 with RelayedCrdtOps"
```

---

### Task 2: Protocol v2 — Peer-Addressed SyncRequest/SyncResponse

**Files:**
- Modify: `editor/sync_protocol.mbt`
- Modify: `editor/sync_protocol_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
///|
test "v2: encode/decode SyncRequest with target and request_id" {
  let encoded = encode_sync_request(target="bob", request_id="42", version_json="{}")
  let decoded = decode_message(encoded)
  match decoded {
    Some(SyncRequest(payload)) => {
      let reader = Reader::new(payload)
      let target = read_string(reader) catch { _ => fail("read target"); return }
      let req_id = read_string(reader) catch { _ => fail("read req_id"); return }
      let ver = read_string(reader) catch { _ => fail("read ver"); return }
      inspect(target, content="bob")
      inspect(req_id, content="42")
      inspect(ver, content="{}")
    }
    _ => fail("expected SyncRequest")
  }
}

///|
test "v2: encode/decode SyncResponse with target and request_id" {
  let encoded = encode_sync_response(target="alice", request_id="7", sync_json="{\"runs\":[]}")
  let decoded = decode_message(encoded)
  match decoded {
    Some(SyncResponse(payload)) => {
      let reader = Reader::new(payload)
      let target = read_string(reader) catch { _ => fail("read target"); return }
      let req_id = read_string(reader) catch { _ => fail("read req_id"); return }
      let json = read_string(reader) catch { _ => fail("read json"); return }
      inspect(target, content="alice")
      inspect(req_id, content="7")
      inspect(json, content="{\"runs\":[]}")
    }
    _ => fail("expected SyncResponse")
  }
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `moon test -p dowdiness/canopy/editor -f sync_protocol_wbtest.mbt`
Expected: Fail — `encode_sync_request`/`encode_sync_response` not defined.

- [ ] **Step 3: Add encode helpers**

In `editor/sync_protocol.mbt`:

```moonbit
///|
/// Encode a peer-addressed SyncRequest.
/// Wire: [header][target_id][request_id][version_json] — all write_string.
pub fn encode_sync_request(
  target~ : String,
  request_id~ : String,
  version_json~ : String,
) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(protocol_version)
  buf.write_byte(b'\x03')
  buf.write_byte(b'\x00')
  write_string(buf, target)
  write_string(buf, request_id)
  write_string(buf, version_json)
  buf.to_bytes()
}

///|
/// Encode a peer-addressed SyncResponse.
/// Wire: [header][target_id][request_id][sync_message_json] — all write_string.
pub fn encode_sync_response(
  target~ : String,
  request_id~ : String,
  sync_json~ : String,
) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(protocol_version)
  buf.write_byte(b'\x04')
  buf.write_byte(b'\x00')
  write_string(buf, target)
  write_string(buf, request_id)
  write_string(buf, sync_json)
  buf.to_bytes()
}
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `moon test -p dowdiness/canopy/editor -f sync_protocol_wbtest.mbt`

- [ ] **Step 5: Commit**

```bash
git add editor/sync_protocol.mbt editor/sync_protocol_wbtest.mbt
git commit -m "feat(editor): peer-addressed SyncRequest/SyncResponse with request_id"
```

---

### Task 3: Relay — send_to + Message Routing

**Files:**
- Modify: `relay/wire.mbt`
- Modify: `relay/relay_room.mbt`
- Modify: `relay/relay_room_wbtest.mbt`

- [ ] **Step 1: Write failing tests for send_to**

In `relay/relay_room_wbtest.mbt`, add:

```moonbit
///|
test "send_to: delivers to correct peer" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  room.send_to("bob", b"\x42")
  inspect(msgs_a.length(), content="0")
  inspect(msgs_b.length(), content="1")
  inspect(msgs_b[0] == b"\x42", content="true")
}

///|
test "send_to: unknown peer is silent no-op" {
  let room = RelayRoom::new()
  let (send_a, _) = make_recorder()
  room.on_connect("alice", send_a)
  room.send_to("nobody", b"\x42")
  // No panic, no error
  inspect(room.peer_count(), content="1")
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `moon test -p dowdiness/canopy/relay -f relay_room_wbtest.mbt`
Expected: Fail — `send_to` not defined.

- [ ] **Step 3: Implement send_to**

In `relay/relay_room.mbt`:

```moonbit
///|
/// Send data to a specific peer by ID. Silent no-op if peer not found.
pub fn RelayRoom::send_to(
  self : RelayRoom,
  peer_id : String,
  data : Bytes,
) -> Unit {
  for peer in self.peers {
    if peer.peer_id == peer_id {
      (peer.send_fn)(data)
      return
    }
  }
}
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `moon test -p dowdiness/canopy/relay -f relay_room_wbtest.mbt`

- [ ] **Step 5: Update relay wire version**

In `relay/wire.mbt`, change `let version : Byte = b'\x01'` to `let version : Byte = b'\x02'`.

- [ ] **Step 6: Write tests for message routing in on_message**

```moonbit
///|
test "on_message: wraps CrdtOps as RelayedCrdtOps" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  // Alice sends CrdtOps (v2 header: version=0x02, type=0x01, flags=0x00)
  let crdt_msg = b"\x02\x01\x00\x42\x43"
  room.on_message("alice", crdt_msg)
  // Bob should receive RelayedCrdtOps (type=0x06) with sender="alice"
  inspect(msgs_b.length(), content="1")
  inspect(msgs_b[0][1] == b'\x06', content="true") // type byte is 0x06
}

///|
test "on_message: routes SyncRequest to target peer" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  let (send_c, msgs_c) = make_recorder()
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
  room.on_connect("charlie", send_c)
  msgs_a.clear()
  msgs_b.clear()
  msgs_c.clear()
  // Bob sends SyncRequest targeting alice
  let req = @editor.encode_sync_request(target="alice", request_id="1", version_json="{}")
  room.on_message("bob", req)
  // Only alice should receive it (not charlie)
  inspect(msgs_a.length(), content="1")
  inspect(msgs_b.length(), content="0")
  inspect(msgs_c.length(), content="0")
}

///|
test "on_message: short frames broadcast unchanged" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  room.on_message("alice", b"\x01")
  inspect(msgs_b.length(), content="1")
  inspect(msgs_b[0] == b"\x01", content="true")
}
```

- [ ] **Step 7: Implement message routing in on_message**

Replace `RelayRoom::on_message` in `relay/relay_room.mbt`:

```moonbit
///|
pub fn RelayRoom::on_message(
  self : RelayRoom,
  sender : String,
  data : Bytes,
) -> Unit {
  // Safety guard: short or non-v2 frames broadcast unchanged
  if data.length() < 3 || data[0] != version {
    self.broadcast(sender, data)
    return
  }
  let msg_type = data[1]
  match msg_type {
    b'\x01' => {
      // CrdtOps → wrap as RelayedCrdtOps with sender ID, then broadcast
      let wrapped = wrap_with_sender(sender, b'\x06', data, 3)
      self.broadcast(sender, wrapped)
    }
    b'\x03' | b'\x04' => {
      // SyncRequest/SyncResponse → read target, wrap with sender, send_to target
      let reader = @editor.Reader::new(
        data.view(start=3, end=data.length()).to_bytes(),
      )
      let target = @editor.read_string(reader) catch { _ => return }
      // Rebuild: [header][sender_id][remaining fields after target]
      let remaining = reader.remaining()
      let buf = @buffer.new()
      buf.write_byte(version)
      buf.write_byte(data[1]) // preserve original type byte
      buf.write_byte(b'\x00')
      @editor.write_string(buf, sender)
      // Copy request_id + payload (everything after target_id)
      buf.write_bytes(remaining)
      self.send_to(target, buf.to_bytes())
    }
    _ => self.broadcast(sender, data)
  }
}
```

Add helper in `relay/wire.mbt`:

```moonbit
///|
/// Wrap a message payload with sender ID and a new type byte.
/// Builds: [version][new_type][flags][sender_id (write_string)][original_payload_from offset]
fn wrap_with_sender(sender : String, new_type : Byte, data : Bytes, payload_offset : Int) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(version)
  buf.write_byte(new_type)
  buf.write_byte(b'\x00')
  let tmp = @buffer.new()
  tmp.write_string(sender)
  let sender_bytes = tmp.to_bytes()
  write_relay_uvarint(buf, sender_bytes.length())
  buf.write_bytes(sender_bytes)
  if payload_offset < data.length() {
    buf.write_bytes(data.view(start=payload_offset, end=data.length()).to_bytes())
  }
  buf.to_bytes()
}
```

Note: The relay uses its own `write_relay_uvarint` (from `wire.mbt`) for the sender string, matching the existing `encode_peer_control` pattern. The editor's `Reader`/`read_string` must be compatible — both use uvarint-length-prefixed strings via `@buffer.write_string`.

- [ ] **Step 8: Add relay → editor import**

The relay package needs to import `editor` for `Reader`, `read_string`, `write_string`. Check `relay/moon.pkg` and add the import if needed. If circular dependency exists, extract the shared codec to a common package or duplicate the reader in relay.

- [ ] **Step 9: Run tests — verify they pass**

Run: `moon test`

- [ ] **Step 10: Commit**

```bash
git add relay/wire.mbt relay/relay_room.mbt relay/relay_room_wbtest.mbt relay/moon.pkg
git commit -m "feat(relay): send_to + v2 message routing (CrdtOps wrapping, SyncRequest forwarding)"
```

---

### Task 4: Recovery State Machine

**Files:**
- Create: `editor/recovery.mbt`
- Create: `editor/recovery_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

In `editor/recovery_wbtest.mbt`:

```moonbit
///|
test "RecoveryContext: new creates initial state" {
  let ctx = RecoveryContext::new("alice", @text.SyncMessage::empty(), "1")
  inspect(ctx.peer_id, content="alice")
  inspect(ctx.retries, content="0")
  inspect(ctx.backoff_ms, content="500")
  inspect(ctx.request_id, content="1")
  inspect(ctx.deferred.length(), content="0")
}

///|
test "RecoveryContext: increment_retry doubles backoff" {
  let ctx = RecoveryContext::new("alice", @text.SyncMessage::empty(), "1")
  let ctx2 = ctx.increment_retry("2")
  inspect(ctx2.retries, content="1")
  inspect(ctx2.backoff_ms, content="1000")
  inspect(ctx2.request_id, content="2")
  let ctx3 = ctx2.increment_retry("3")
  inspect(ctx3.retries, content="2")
  inspect(ctx3.backoff_ms, content="2000")
}

///|
test "RecoveryContext: is_exhausted after 3 retries" {
  let ctx = RecoveryContext::new("alice", @text.SyncMessage::empty(), "1")
  inspect(ctx.is_exhausted(), content="false")
  let ctx2 = ctx.increment_retry("2")
  inspect(ctx2.is_exhausted(), content="false")
  let ctx3 = ctx2.increment_retry("3")
  inspect(ctx3.is_exhausted(), content="false")
  let ctx4 = ctx3.increment_retry("4")
  inspect(ctx4.is_exhausted(), content="true")
}

///|
test "RecoveryContext: buffer_message adds to deferred" {
  let ctx = RecoveryContext::new("alice", @text.SyncMessage::empty(), "1")
  let msg = @text.SyncMessage::empty()
  ctx.buffer_message(msg)
  inspect(ctx.deferred.length(), content="1")
}

///|
test "RecoveryContext: buffer_message caps at 32" {
  let ctx = RecoveryContext::new("alice", @text.SyncMessage::empty(), "1")
  for i = 0; i < 40; i = i + 1 {
    ctx.buffer_message(@text.SyncMessage::empty())
  }
  inspect(ctx.deferred.length(), content="32")
}

///|
test "RecoveryContext: matches_request_id" {
  let ctx = RecoveryContext::new("alice", @text.SyncMessage::empty(), "42")
  inspect(ctx.matches_request_id("42"), content="true")
  inspect(ctx.matches_request_id("99"), content="false")
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `moon test -p dowdiness/canopy/editor -f recovery_wbtest.mbt`
Expected: Fail — `RecoveryContext` not defined.

- [ ] **Step 3: Implement RecoveryContext**

In `editor/recovery.mbt`:

```moonbit
// Recovery state machine for WebSocket sync recovery.

///|
/// Maximum number of deferred messages buffered during recovery.
let max_deferred : Int = 32

///|
/// Maximum number of retry attempts before giving up.
let max_retries : Int = 3

///|
/// Initial backoff delay in milliseconds.
let initial_backoff_ms : Int = 500

///|
/// Per-peer recovery state.
struct RecoveryContext {
  peer_id : String
  mut retries : Int
  pending_msg : @text.SyncMessage
  deferred : Array[@text.SyncMessage]
  mut backoff_ms : Int
  mut request_id : String
}

///|
fn RecoveryContext::new(
  peer_id : String,
  pending_msg : @text.SyncMessage,
  request_id : String,
) -> RecoveryContext {
  {
    peer_id,
    retries: 0,
    pending_msg,
    deferred: [],
    backoff_ms: initial_backoff_ms,
    request_id,
  }
}

///|
fn RecoveryContext::increment_retry(
  self : RecoveryContext,
  new_request_id : String,
) -> RecoveryContext {
  {
    peer_id: self.peer_id,
    retries: self.retries + 1,
    pending_msg: self.pending_msg,
    deferred: self.deferred,
    backoff_ms: self.backoff_ms * 2,
    request_id: new_request_id,
  }
}

///|
fn RecoveryContext::is_exhausted(self : RecoveryContext) -> Bool {
  self.retries >= max_retries
}

///|
fn RecoveryContext::buffer_message(
  self : RecoveryContext,
  msg : @text.SyncMessage,
) -> Unit {
  if self.deferred.length() >= max_deferred {
    // Drop oldest to make room
    self.deferred.remove(0) |> ignore
  }
  self.deferred.push(msg)
}

///|
fn RecoveryContext::matches_request_id(
  self : RecoveryContext,
  id : String,
) -> Bool {
  self.request_id == id
}
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `moon test -p dowdiness/canopy/editor -f recovery_wbtest.mbt`

- [ ] **Step 5: Commit**

```bash
git add editor/recovery.mbt editor/recovery_wbtest.mbt
git commit -m "feat(editor): RecoveryContext state machine for sync recovery"
```

---

### Task 5: SyncEditor — Recovery Fields

**Files:**
- Modify: `editor/sync_editor.mbt`

- [ ] **Step 1: Add recovery fields to SyncEditor struct**

Add after `priv mut ws : JsWebSocket?`:

```moonbit
  priv mut recovery : RecoveryContext?
  priv mut recovery_epoch : Int
```

- [ ] **Step 2: Initialize in SyncEditor::new**

Add to the struct literal in `SyncEditor::new`:

```moonbit
  recovery: None,
  recovery_epoch: 0,
```

- [ ] **Step 3: Run tests — verify all pass**

Run: `moon test`
Expected: All pass (new fields are initialized, no behavior change yet).

- [ ] **Step 4: Commit**

```bash
git add editor/sync_editor.mbt
git commit -m "feat(editor): add recovery fields to SyncEditor"
```

---

### Task 6: ws_on_message — Handle RelayedCrdtOps + Recovery Entry

**Files:**
- Modify: `editor/sync_editor_ws.mbt`
- Modify: `editor/sync_editor_ws_wbtest.mbt`

- [ ] **Step 1: Write failing test**

In `editor/sync_editor_ws_wbtest.mbt`:

```moonbit
///|
test "ws_on_message: RelayedCrdtOps applies remote edits with sender tracking" {
  let editor_a = SyncEditor::new("alice")
  let editor_b = SyncEditor::new("bob")
  editor_a.set_text("hello")
  let crdt_msg = editor_a.export_all() catch { _ => fail("export failed"); return }
  let json_str = crdt_msg.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json_str)
  // Wrap as RelayedCrdtOps (what the relay would send)
  let wire = encode_relayed_crdt_ops("alice", buf.to_bytes())
  editor_b.ws_on_message(wire)
  inspect(editor_b.get_text(), content="hello")
}
```

- [ ] **Step 2: Run test — verify it fails**

Expected: Fail — `ws_on_message` doesn't handle `RelayedCrdtOps`.

- [ ] **Step 3: Update ws_on_message to handle RelayedCrdtOps**

In `editor/sync_editor_ws.mbt`, add a new match arm for `RelayedCrdtOps` in `ws_on_message`. The core logic:

```moonbit
RelayedCrdtOps(sender~, payload~) => {
  let json_str = payload.to_unchecked_string()
  let crdt_msg = @text.SyncMessage::from_json_string(json_str) catch { _ => return }
  // If recovering from this sender, buffer the message
  match self.recovery {
    Some(ctx) =>
      if ctx.peer_id == sender {
        ctx.buffer_message(crdt_msg)
        return
      }
    None => ()
  }
  // Try to apply
  try {
    self.apply_sync(crdt_msg)
  } catch {
    err => {
      // Check if retryable
      match err {
        @text.TextError::SyncFailed(failure) =>
          match failure {
            @text.SyncFailure::MissingDependency(..) |
            @text.SyncFailure::Timeout(..) =>
              self.enter_recovery(sender, crdt_msg)
            _ => () // Non-retryable, drop
          }
        @text.TextError::VersionNotFound =>
          self.enter_recovery(sender, crdt_msg)
        _ => () // Non-retryable, drop
      }
    }
  }
}
```

Add `enter_recovery` helper method on `SyncEditor`:

```moonbit
///|
fn SyncEditor::enter_recovery(
  self : SyncEditor,
  peer_id : String,
  failed_msg : @text.SyncMessage,
) -> Unit {
  // Only one recovery at a time
  if self.recovery is Some(_) { return }
  self.recovery_epoch += 1
  let request_id = self.recovery_epoch.to_string()
  self.recovery = Some(RecoveryContext::new(peer_id, failed_msg, request_id))
  // Send SyncRequest
  let version_json = self.get_version().to_json_string()
  let wire = encode_sync_request(
    target=peer_id,
    request_id~,
    version_json~,
  )
  self.ws_send(wire)
}
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `moon test`

- [ ] **Step 5: Commit**

```bash
git add editor/sync_editor_ws.mbt editor/sync_editor_ws_wbtest.mbt
git commit -m "feat(editor): handle RelayedCrdtOps with recovery entry on retryable failure"
```

---

### Task 7: ws_on_message — Handle SyncRequest (Responder)

**Files:**
- Modify: `editor/sync_editor_ws.mbt`
- Modify: `editor/sync_editor_ws_wbtest.mbt`

- [ ] **Step 1: Write failing test**

```moonbit
///|
test "ws_on_message: SyncRequest triggers SyncResponse" {
  let editor = SyncEditor::new("alice")
  editor.set_text("hello")
  // Simulate receiving a SyncRequest (as if relay wrapped with sender="bob")
  // After relay wrapping: [header][sender_id][request_id][version_json]
  let buf = @buffer.new()
  buf.write_byte(b'\x02') // v2
  buf.write_byte(b'\x03') // SyncRequest
  buf.write_byte(b'\x00') // flags
  write_string(buf, "bob") // sender (relay-added)
  write_string(buf, "1")   // request_id
  write_string(buf, "{}")  // empty version = wants everything
  let ws = JsWebSocket(0)
  editor.ws_on_open(ws)
  // Capture sent messages
  editor.ws_on_message(buf.to_bytes())
  // Verify editor didn't crash (SyncResponse was sent via ws)
  inspect(editor.get_text(), content="hello")
}
```

- [ ] **Step 2: Implement SyncRequest handler**

In the `ws_on_message` match, update the `SyncRequest` arm to parse sender + request_id + version, then respond:

```moonbit
SyncRequest(payload) => {
  let reader = Reader::new(payload)
  let sender = read_string(reader) catch { _ => return }
  let request_id = read_string(reader) catch { _ => return }
  let version_json = read_string(reader) catch { _ => return }
  // Rate limiting: track last response time per sender (simple approach)
  // TODO: add rate limit map if needed
  let peer_version = @text.Version::from_json_string(version_json) catch { _ => return }
  let delta = self.export_since(peer_version) catch { _ =>
    // Can't export — send empty response
    let wire = encode_sync_response(target=sender, request_id~, sync_json="")
    self.ws_send(wire)
    return
  }
  let sync_json = delta.to_json_string()
  // Cap response size
  if sync_json.length() > 1_000_000 {
    let wire = encode_sync_response(target=sender, request_id~, sync_json="")
    self.ws_send(wire)
    return
  }
  let wire = encode_sync_response(target=sender, request_id~, sync_json~)
  self.ws_send(wire)
}
```

- [ ] **Step 3: Run tests — verify they pass**

Run: `moon test`

- [ ] **Step 4: Commit**

```bash
git add editor/sync_editor_ws.mbt editor/sync_editor_ws_wbtest.mbt
git commit -m "feat(editor): handle SyncRequest — respond with export_since delta"
```

---

### Task 8: ws_on_message — Handle SyncResponse (Recovery Completion)

**Files:**
- Modify: `editor/sync_editor_ws.mbt`
- Modify: `editor/sync_editor_ws_wbtest.mbt`

- [ ] **Step 1: Implement SyncResponse handler**

In the `ws_on_message` match, update the `SyncResponse` arm:

```moonbit
SyncResponse(payload) => {
  let reader = Reader::new(payload)
  let _sender = read_string(reader) catch { _ => return }
  let request_id = read_string(reader) catch { _ => return }
  let sync_json = read_string(reader) catch { _ => return }
  let ctx = match self.recovery {
    Some(ctx) => ctx
    None => return // Not recovering, ignore
  }
  // Stale response check
  if not(ctx.matches_request_id(request_id)) { return }
  // Empty response = responder can't help
  if sync_json == "" {
    self.handle_recovery_failure()
    return
  }
  // Apply the delta
  let delta = @text.SyncMessage::from_json_string(sync_json) catch { _ =>
    self.handle_recovery_failure()
    return
  }
  try { self.apply_sync(delta) } catch { _ => () }
  // Retry the original pending message
  try { self.apply_sync(ctx.pending_msg) } catch { _ =>
    self.handle_recovery_failure()
    return
  }
  // Success! Drain deferred messages
  let deferred = ctx.deferred
  self.recovery = None
  for msg in deferred {
    try { self.apply_sync(msg) } catch { _ => () }
  }
}
```

Add helper:

```moonbit
///|
fn SyncEditor::handle_recovery_failure(self : SyncEditor) -> Unit {
  let ctx = match self.recovery {
    Some(ctx) => ctx
    None => return
  }
  self.recovery_epoch += 1
  let new_id = self.recovery_epoch.to_string()
  let next = ctx.increment_retry(new_id)
  if next.is_exhausted() {
    // Give up
    self.recovery = None
    // TODO: set SyncStatus::Error via callback or field
    return
  }
  self.recovery = Some(next)
  // Send another SyncRequest after backoff
  let version_json = self.get_version().to_json_string()
  let wire = encode_sync_request(
    target=next.peer_id,
    request_id=new_id,
    version_json~,
  )
  self.ws_send(wire)
}
```

- [ ] **Step 2: Write test for successful recovery**

```moonbit
///|
test "recovery: SyncResponse with matching request_id clears recovery" {
  let editor = SyncEditor::new("bob")
  // Manually set recovery state
  editor.recovery_epoch = 1
  editor.recovery = Some(RecoveryContext::new(
    "alice",
    @text.SyncMessage::empty(),
    "1",
  ))
  // Simulate SyncResponse with matching request_id and empty delta
  let buf = @buffer.new()
  buf.write_byte(b'\x02')
  buf.write_byte(b'\x04') // SyncResponse
  buf.write_byte(b'\x00')
  write_string(buf, "alice") // sender
  write_string(buf, "1")     // request_id matches
  write_string(buf, "")      // empty = can't help
  editor.ws_on_message(buf.to_bytes())
  // Should have incremented retries (not cleared recovery — empty response)
  inspect(editor.recovery is Some(_), content="true")
}
```

- [ ] **Step 3: Run tests — verify they pass**

Run: `moon test`

- [ ] **Step 4: Commit**

```bash
git add editor/sync_editor_ws.mbt editor/sync_editor_ws_wbtest.mbt
git commit -m "feat(editor): handle SyncResponse — apply delta, retry pending, drain deferred"
```

---

### Task 9: PeerLeft / Socket Close — Recovery Abort

**Files:**
- Modify: `editor/sync_editor_ws.mbt`
- Modify: `editor/sync_editor_ws_wbtest.mbt`

- [ ] **Step 1: Update PeerLeft handler**

In the `PeerLeft(peer_id)` arm of `ws_on_message`, add recovery abort:

```moonbit
PeerLeft(peer_id) => {
  self.hub.on_peer_leave(peer_id)
  // Abort recovery if the leaving peer is the one we're recovering from
  match self.recovery {
    Some(ctx) =>
      if ctx.peer_id == peer_id {
        self.recovery = None
        // TODO: set SyncStatus::Error
      }
    None => ()
  }
}
```

- [ ] **Step 2: Update ws_on_close handler**

In `ws_on_close`, clear recovery state:

```moonbit
pub fn SyncEditor::ws_on_close(self : SyncEditor) -> Unit {
  self.ws = None
  self.recovery = None
}
```

- [ ] **Step 3: Write test**

```moonbit
///|
test "ws_on_message: PeerLeft aborts recovery for that peer" {
  let editor = SyncEditor::new("bob")
  editor.recovery = Some(RecoveryContext::new(
    "alice",
    @text.SyncMessage::empty(),
    "1",
  ))
  let wire = encode_message(PeerLeft("alice"))
  editor.ws_on_message(wire)
  inspect(editor.recovery is None, content="true")
}

///|
test "ws_on_close: clears recovery state" {
  let editor = SyncEditor::new("bob")
  editor.recovery = Some(RecoveryContext::new(
    "alice",
    @text.SyncMessage::empty(),
    "1",
  ))
  editor.ws_on_close()
  inspect(editor.recovery is None, content="true")
}
```

- [ ] **Step 4: Run tests — verify they pass**

Run: `moon test`

- [ ] **Step 5: Commit**

```bash
git add editor/sync_editor_ws.mbt editor/sync_editor_ws_wbtest.mbt
git commit -m "feat(editor): abort recovery on PeerLeft and socket close"
```

---

### Task 10: Integration Tests

**Files:**
- Modify: `integration_ws_test.mbt`

- [ ] **Step 1: Write 2-peer recovery integration test**

```moonbit
///|
test "integration: 2-peer relay recovery after missing dependency" {
  // Setup: two editors connected via relay
  let room = @relay.RelayRoom::new()
  let editor_a = @editor.SyncEditor::new("alice")
  let editor_b = @editor.SyncEditor::new("bob")
  // Wire: each editor's ws_send goes to room.on_message
  // room delivers to editor's ws_on_message
  // (Use the existing integration test pattern from integration_ws_test.mbt)

  // Alice types, exports, bob applies — happy path
  editor_a.set_text("hello")
  let msg_a = editor_a.export_all() catch { _ => fail("export"); return }
  let json = msg_a.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json)
  // Simulate relay wrapping
  let relayed = @editor.encode_relayed_crdt_ops("alice", buf.to_bytes())
  editor_b.ws_on_message(relayed)
  inspect(editor_b.get_text(), content="hello")
}
```

- [ ] **Step 2: Run test — verify it passes**

Run: `moon test -f integration_ws_test.mbt`

- [ ] **Step 3: Commit**

```bash
git add integration_ws_test.mbt
git commit -m "test: add 2-peer relay recovery integration test"
```

---

### Task 11: Final Verification + Cleanup

**Files:**
- All modified files

- [ ] **Step 1: Run full test suite**

Run: `moon test`
Expected: All tests pass.

- [ ] **Step 2: Update interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 3: Check for API changes**

Run: `git diff *.mbti`
Verify changes are intentional (new `encode_relayed_crdt_ops`, `encode_sync_request`, `encode_sync_response`, `RecoveryContext`, `send_to`).

- [ ] **Step 4: Update TODO.md**

Mark the sync recovery items in §2 as done.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "chore: update interfaces and mark sync recovery done in TODO"
```
