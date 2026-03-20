///|
fn make_recorder() -> ((Bytes) -> Unit, Array[Bytes]) {
  let messages : Array[Bytes] = []
  let send_fn = (data : Bytes) => messages.push(data)
  (send_fn, messages)
}

///|
test "on_connect first peer receives no broadcast" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  room.on_connect("alice", send_a)
  inspect(room.peer_count(), content="1")
  inspect(msgs_a.length(), content="0")
}

///|
test "on_connect broadcasts PeerJoined to existing peers" {
  let room = RelayRoom::new()
  let (send_a, msgs_a) = make_recorder()
  let (send_b, _msgs_b) = make_recorder()
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
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
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
  room.on_connect("charlie", send_c)
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
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
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
  room.on_connect("alice", send_a)
  room.on_connect("bob", send_b)
  msgs_a.clear()
  msgs_b.clear()
  room.on_message("bob", b"\xFF")
  inspect(msgs_b.length(), content="0")
  inspect(msgs_a.length(), content="1")
}

///|
test "peer_count tracks sessions correctly" {
  let room = RelayRoom::new()
  inspect(room.peer_count(), content="0")
  let (send_a, _) = make_recorder()
  room.on_connect("alice", send_a)
  inspect(room.peer_count(), content="1")
  let (send_b, _) = make_recorder()
  room.on_connect("bob", send_b)
  inspect(room.peer_count(), content="2")
  let (send_c, _) = make_recorder()
  room.on_connect("charlie", send_c)
  inspect(room.peer_count(), content="3")
  room.on_disconnect("bob")
  inspect(room.peer_count(), content="2")
  room.on_disconnect("alice")
  inspect(room.peer_count(), content="1")
  room.on_disconnect("charlie")
  inspect(room.peer_count(), content="0")
}
