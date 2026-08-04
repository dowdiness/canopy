// Error path tests for RelayRoom.
//
// These tests verify the relay handles edge cases gracefully:
// duplicate peers, non-existent peers, empty rooms.

///|
fn make_err_recorder() -> ((Bytes) -> Unit, Array[Bytes]) {
  let messages : Array[Bytes] = []
  let send_fn = (data : Bytes) => messages.push(data)
  (send_fn, messages)
}

///|
test "on_disconnect: non-existent peer does not panic" {
  let room = RelayRoom::new()
  let (send_a, _) = make_err_recorder()
  connect_ok(room, "alice", send_a)
  // Disconnect a peer that was never connected
  room.on_disconnect("nonexistent")
  // Alice should still be in the room
  inspect(room.peer_count(), content="1")
}

///|
test "on_disconnect: empty room does not panic" {
  let room = RelayRoom::new()
  room.on_disconnect("nobody")
  inspect(room.peer_count(), content="0")
}

///|
test "on_disconnect: double disconnect does not panic" {
  let room = RelayRoom::new()
  let (send_a, _) = make_err_recorder()
  let (send_b, _) = make_err_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  room.on_disconnect("bob")
  inspect(room.peer_count(), content="1")
  // Disconnect bob again — should not panic
  room.on_disconnect("bob")
  inspect(room.peer_count(), content="1")
}

///|
test "on_disconnect: non-member does not broadcast PeerLeft" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_err_recorder()
  connect_ok(room, "alice", send_a)
  msgs_a.clear()
  // Disconnecting a peer that was never registered is a no-op — no
  // ghost PeerLeft reaches alice (prevents spurious ephemeral-state
  // resets in editor/sync_editor_ws).
  room.on_disconnect("ghost")
  inspect(msgs_a.length(), content="0")
  inspect(room.peer_count(), content="1")
  // Same property holds for a second disconnect after a real removal.
  let (send_b, msgs_b) = make_err_recorder()
  connect_ok(room, "bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  room.on_disconnect("bob")
  // First disconnect delivers PeerLeft("bob") to alice.
  inspect(msgs_a.length(), content="1")
  msgs_a.clear()
  room.on_disconnect("bob")
  // Second disconnect of same id is a no-op — no duplicate PeerLeft.
  inspect(msgs_a.length(), content="0")
}

///|
test "on_message: non-member sender is dropped" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_err_recorder()
  connect_ok(room, "alice", send_a)
  msgs_a.clear()
  // Message from a peer that never called on_connect — must not be relayed.
  room.on_message("ghost", b"\x01\x02\x03")
  inspect(msgs_a.length(), content="0")
}

///|
test "on_message: empty room does not panic" {
  let room = RelayRoom::new()
  room.on_message("nobody", b"\x01\x02\x03")
  inspect(room.peer_count(), content="0")
}

///|
test "on_message: empty data is forwarded" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_err_recorder()
  let (send_b, msgs_b) = make_err_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  room.on_message("alice", Bytes::new(0))
  inspect(msgs_b.length(), content="1")
  inspect(msgs_b[0].length(), content="0")
}

///|
test "on_connect: duplicate peer_id is rejected" {
  let room = RelayRoom::new()
  let (send_a1, msgs_a1) = make_err_recorder()
  let (send_a2, msgs_a2) = make_err_recorder()
  inspect(room.on_connect("alice", send_a1), content="true")
  msgs_a1.clear()
  // Connect "alice" again — the second call is rejected, room unchanged.
  inspect(room.on_connect("alice", send_a2), content="false")
  inspect(room.peer_count(), content="1")
  // No PeerJoined broadcast on rejection.
  inspect(msgs_a1.length(), content="0")
  // A subsequent join proves the original send_fn is still the delivery
  // target and the rejected send_fn never became one: bob's PeerJoined
  // reaches send_a1 but not send_a2. (Broadcasting via alice as sender
  // cannot distinguish the two, because broadcast excludes by peer_id.)
  let (send_b, _) = make_err_recorder()
  connect_ok(room, "bob", send_b)
  inspect(msgs_a1.length(), content="1")
  inspect(msgs_a2.length(), content="0")
}

///|
test "on_connect: reconnect after disconnect succeeds" {
  let room = RelayRoom::new()
  let (send_a1, _) = make_err_recorder()
  let (send_a2, _) = make_err_recorder()
  inspect(room.on_connect("alice", send_a1), content="true")
  room.on_disconnect("alice")
  // After disconnect, the same peer_id can reconnect.
  inspect(room.on_connect("alice", send_a2), content="true")
  inspect(room.peer_count(), content="1")
}

///|
test "on_connect: empty peer_id is rejected" {
  let room = RelayRoom::new()
  let (send_fn, _) = make_err_recorder()
  inspect(room.on_connect("", send_fn), content="false")
  inspect(room.peer_count(), content="0")
}

///|
test "peer_count: after all peers disconnect" {
  let room = RelayRoom::new()
  let (send_a, _) = make_err_recorder()
  let (send_b, _) = make_err_recorder()
  let (send_c, _) = make_err_recorder()
  connect_ok(room, "alice", send_a)
  connect_ok(room, "bob", send_b)
  connect_ok(room, "charlie", send_c)
  room.on_disconnect("alice")
  room.on_disconnect("bob")
  room.on_disconnect("charlie")
  inspect(room.peer_count(), content="0")
  // Room is empty — operations should still be safe
  room.on_message("nobody", b"\xFF")
  inspect(room.peer_count(), content="0")
}
