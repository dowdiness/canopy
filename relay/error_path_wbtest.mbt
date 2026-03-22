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
  room.on_connect("alice", send_a)
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
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
  room.on_disconnect("bob")
  inspect(room.peer_count(), content="1")
  // Disconnect bob again — should not panic
  room.on_disconnect("bob")
  inspect(room.peer_count(), content="1")
}

///|
test "on_message: non-existent sender does not panic" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_err_recorder()
  room.on_connect("alice", send_a)
  msgs_a.clear()
  // Message from unknown peer — should broadcast to alice anyway
  room.on_message("ghost", b"\x01\x02\x03")
  // Alice receives because ghost != alice (broadcast excludes sender by ID)
  inspect(msgs_a.length(), content="1")
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
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  room.on_message("alice", Bytes::new(0))
  inspect(msgs_b.length(), content="1")
  inspect(msgs_b[0].length(), content="0")
}

///|
test "on_connect: duplicate peer_id adds second entry" {
  let room = RelayRoom::new()
  let (send_a1, msgs_a1) = make_err_recorder()
  let (send_a2, msgs_a2) = make_err_recorder()
  room.on_connect("alice", send_a1)
  // Connect "alice" again with a different send_fn
  room.on_connect("alice", send_a2)
  // Both entries exist (no dedup — documented as caller responsibility)
  inspect(room.peer_count(), content="2")
  // broadcast excludes by peer_id, so first alice does NOT receive PeerJoined
  // because sender "alice" == receiver "alice" — this is the duplicate-ID pitfall
  inspect(msgs_a1.length(), content="0")
  let _ = msgs_a2
}

///|
test "on_connect: empty peer_id does not panic" {
  let room = RelayRoom::new()
  let (send_fn, _) = make_err_recorder()
  room.on_connect("", send_fn)
  inspect(room.peer_count(), content="1")
  room.on_disconnect("")
  inspect(room.peer_count(), content="0")
}

///|
test "peer_count: after all peers disconnect" {
  let room = RelayRoom::new()
  let (send_a, _) = make_err_recorder()
  let (send_b, _) = make_err_recorder()
  let (send_c, _) = make_err_recorder()
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
  room.on_connect("charlie", send_c)
  room.on_disconnect("alice")
  room.on_disconnect("bob")
  room.on_disconnect("charlie")
  inspect(room.peer_count(), content="0")
  // Room is empty — operations should still be safe
  room.on_message("nobody", b"\xFF")
  inspect(room.peer_count(), content="0")
}
