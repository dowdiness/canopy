///|
fn make_recorder() -> ((Bytes) -> Unit, Array[Bytes]) {
  let messages : Array[Bytes] = []
  let send_fn = (data : Bytes) => messages.push(data)
  (send_fn, messages)
}

///|
/// Test helper: connect and assert success. Tests fail loudly if
/// validation ever rejects a call that was expected to succeed.
fn connect_ok(
  room : RelayRoom,
  peer_id : String,
  send_fn : (Bytes) -> Unit,
) -> Unit raise {
  inspect(room.on_connect(peer_id, send_fn), content="true")
}

///|
test "on_connect first peer receives no broadcast" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  connect_ok(room, "alice", send_a)
  inspect(room.peer_count(), content="1")
  inspect(msgs_a.length(), content="0")
}

///|
test "on_connect broadcasts PeerJoined to existing peers" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, _msgs_b) = make_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  inspect(room.peer_count(), content="2")
  // Alice should have received PeerJoined("bob")
  inspect(msgs_a.length(), content="1")
  let expected = encode_peer_joined("bob")
  inspect(msgs_a[0] == expected, content="true")
}

///|
test "on_message broadcasts to all except sender" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  let (send_c, msgs_c) = make_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  connect_ok(room, "charlie", send_c)
  // Clear join notifications
  msgs_a.clear()
  msgs_b.clear()
  msgs_c.clear()
  let data = b"\x01\x02\x03"
  room.on_message("alice", data)
  // Alice (sender) should NOT receive the message
  inspect(msgs_a.length(), content="0")
  // Bob and Charlie should each receive it
  inspect(msgs_b.length(), content="1")
  inspect(msgs_c.length(), content="1")
  inspect(msgs_b[0] == data, content="true")
  inspect(msgs_c[0] == data, content="true")
}

///|
test "on_disconnect removes peer and broadcasts PeerLeft" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  // Clear join notifications
  msgs_a.clear()
  msgs_b.clear()
  room.on_disconnect("bob")
  inspect(room.peer_count(), content="1")
  // Alice should have received PeerLeft("bob")
  inspect(msgs_a.length(), content="1")
  let expected = encode_peer_left("bob")
  inspect(msgs_a[0] == expected, content="true")
  // Bob should NOT receive PeerLeft (already removed)
  inspect(msgs_b.length(), content="0")
}

///|
test "sender does not receive own broadcast" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  room.on_message("bob", b"\xFF")
  inspect(msgs_b.length(), content="0")
  inspect(msgs_a.length(), content="1")
  inspect(msgs_a[0] == b"\xFF", content="true")
}

///|
test "send_to: delivers to correct peer" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
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
  let (send_a, msgs_a) = make_recorder()
  connect_ok(room, "alice", send_a)
  msgs_a.clear()
  room.send_to("nobody", b"\x42")
  inspect(room.peer_count(), content="1")
  // Alice should not receive anything
  inspect(msgs_a.length(), content="0")
}

///|
test "on_message: wraps CrdtOps as RelayedCrdtOps" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  // Alice sends CrdtOps: [v2=0x02][type=0x01][flags=0x00][payload]
  room.on_message("alice", b"\x02\x01\x00\x42\x43")
  // Alice (sender) should NOT receive the message
  inspect(msgs_a.length(), content="0")
  inspect(msgs_b.length(), content="1")
  // Bob receives RelayedCrdtOps: type byte should be 0x06
  inspect(msgs_b[0][1] == b'\x06', content="true")
}

///|
test "on_message: short frames broadcast unchanged" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  room.on_message("alice", b"\x01")
  inspect(msgs_a.length(), content="0")
  inspect(msgs_b.length(), content="1")
  inspect(msgs_b[0] == b"\x01", content="true")
}

///|
test "on_message: unknown type broadcasts unchanged" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  // Unknown type 0xFF
  room.on_message("alice", b"\x02\xFF\x00")
  inspect(msgs_a.length(), content="0")
  inspect(msgs_b.length(), content="1")
  inspect(msgs_b[0] == b"\x02\xFF\x00", content="true")
}

///|
test "on_message: SyncRequest routes to target peer" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  let (send_c, msgs_c) = make_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  connect_ok(room, "charlie", send_c)
  msgs_a.clear()
  msgs_b.clear()
  msgs_c.clear()
  // Build SyncRequest targeting "bob": [0x02][0x03][0x00][write_string("bob")][payload]
  let buf = Buffer()
  buf.write_byte(b'\x02')
  buf.write_byte(b'\x03')
  buf.write_byte(b'\x00')
  write_string(buf, "bob")
  buf.write_byte(b'\xAA') // payload
  room.on_message("alice", buf.to_bytes())
  // Only bob should receive it, not alice or charlie
  inspect(msgs_a.length(), content="0")
  inspect(msgs_b.length(), content="1")
  inspect(msgs_c.length(), content="0")
  // Full forwarded frame: target "bob" is replaced by sender "alice" and the
  // 0xAA payload after the target survives. Pinning the whole frame exercises
  // read_relay_string's `after_target` offset end-to-end — an off-by-one there
  // would keep/drop the target or payload and is caught here.
  // [0x02][0x03][0x00][write_string("alice")][0xAA]
  let received = msgs_b[0]
  inspect(
    received == b"\x02\x03\x00\x0a\x61\x00\x6c\x00\x69\x00\x63\x00\x65\x00\xaa",
    content="true",
  )
}

///|
test "on_message: SyncResponse routes to target peer" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  // Build SyncResponse targeting "alice": [0x02][0x04][0x00][write_string("alice")][payload]
  let buf = Buffer()
  buf.write_byte(b'\x02')
  buf.write_byte(b'\x04')
  buf.write_byte(b'\x00')
  write_string(buf, "alice")
  buf.write_byte(b'\xBB') // payload
  room.on_message("bob", buf.to_bytes())
  // Only alice should receive it
  inspect(msgs_a.length(), content="1")
  inspect(msgs_b.length(), content="0")
  // Full forwarded frame: target "alice" replaced by sender "bob", 0xBB payload
  // preserved. [0x02][0x04][0x00][write_string("bob")][0xBB]
  let received = msgs_a[0]
  inspect(
    received == b"\x02\x04\x00\x06\x62\x00\x6f\x00\x62\x00\xbb",
    content="true",
  )
}

///|
test "on_message: SyncRequest to unknown target is dropped" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, msgs_b) = make_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  // Build SyncRequest targeting "nobody"
  let buf = Buffer()
  buf.write_byte(b'\x02')
  buf.write_byte(b'\x03')
  buf.write_byte(b'\x00')
  write_string(buf, "nobody")
  room.on_message("alice", buf.to_bytes())
  // Nobody should receive anything
  inspect(msgs_a.length(), content="0")
  inspect(msgs_b.length(), content="0")
}

///|
test "peer_count tracks sessions correctly" {
  let room = RelayRoom::new()
  inspect(room.peer_count(), content="0")
  let (send_a, _) = make_recorder()
  connect_ok(room, "alice", send_a)
  inspect(room.peer_count(), content="1")
  let (send_b, _) = make_recorder()
  connect_ok(room, "bob", send_b)
  inspect(room.peer_count(), content="2")
  let (send_c, _) = make_recorder()
  connect_ok(room, "charlie", send_c)
  inspect(room.peer_count(), content="3")
  room.on_disconnect("bob")
  inspect(room.peer_count(), content="2")
  room.on_disconnect("alice")
  inspect(room.peer_count(), content="1")
  room.on_disconnect("charlie")
  inspect(room.peer_count(), content="0")
}
