// End-to-end integration tests: two SyncEditors wired through a RelayRoom.
// Tests below cover both happy-path sync and v2 recovery protocol.

///|
test "two editors sync via relay" {
  // Create two editors
  let editor_a = @lambda.new_lambda_editor("alice").0
  let editor_b = @lambda.new_lambda_editor("bob").0
  // Create relay room and wire send functions to editors
  let room = @relay.RelayRoom::new()
  let send_to_a : (Bytes) -> Unit = data => editor_a.ws_on_message(data)
  let send_to_b : (Bytes) -> Unit = data => editor_b.ws_on_message(data)
  inspect(room.on_connect("alice", send_to_a), content="true")
  inspect(room.on_connect("bob", send_to_b), content="true")
  // Alice sets text
  editor_a.set_text("hello")
  inspect(editor_a.get_text(), content="hello")
  // Alice exports CRDT state and sends through relay
  let crdt_msg = try! editor_a.export_all()
  let json_str = crdt_msg.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json_str)
  let wire_msg = @editor.encode_message(@editor.CrdtOps(buf.to_bytes()))
  // Alice sends through relay — relay broadcasts to bob
  room.on_message("alice", wire_msg)
  // Bob should now have the same text
  inspect(editor_b.get_text(), content="hello")
}

///|
test "late joiner catches up via CrdtOps frame" {
  // Alice creates editor and sets text before Bob joins
  let editor_a = @lambda.new_lambda_editor("alice").0
  editor_a.set_text("world")
  inspect(editor_a.get_text(), content="world")
  // Bob joins later — simulate catch-up by sending full CRDT state directly
  let editor_b = @lambda.new_lambda_editor("bob").0
  let crdt_msg = try! editor_a.export_all()
  let json_str = crdt_msg.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json_str)
  let wire_msg = @editor.encode_message(@editor.CrdtOps(buf.to_bytes()))
  // Bob receives the full state
  editor_b.ws_on_message(wire_msg)
  inspect(editor_b.get_text(), content="world")
}

///|
test "peer disconnect cleans up ephemeral via relay" {
  // Create two editors
  let editor_a = @lambda.new_lambda_editor("alice").0
  let editor_b = @lambda.new_lambda_editor("bob").0
  // Bob sets presence
  editor_b.set_local_presence("Bob", "#0000ff")
  // Encode Bob's ephemeral state and send to Alice
  let eph_data = editor_b.encode_ephemeral_all()
  editor_a.apply_ephemeral(eph_data)
  // Verify Alice's hub has Bob's presence
  let peers_before = editor_a.get_hub().get_online_peers()
  inspect(peers_before.length(), content="1")
  // Now simulate Bob disconnecting via relay
  let room = @relay.RelayRoom::new()
  let send_to_a : (Bytes) -> Unit = data => editor_a.ws_on_message(data)
  let send_to_b : (Bytes) -> Unit = data => editor_b.ws_on_message(data)
  inspect(room.on_connect("alice", send_to_a), content="true")
  inspect(room.on_connect("bob", send_to_b), content="true")
  // Disconnect bob — relay sends PeerLeft to alice
  room.on_disconnect("bob")
  // Alice's hub should have cleaned up Bob's presence
  let peers_after = editor_a.get_hub().get_online_peers()
  inspect(peers_after.length(), content="0")
}

// ============================================================================
// v2 relay: RelayedCrdtOps wrapping
// ============================================================================

///|
test "v2 relay: CrdtOps wrapped as RelayedCrdtOps with sender" {
  let editor_a = @lambda.new_lambda_editor("alice").0
  let editor_b = @lambda.new_lambda_editor("bob").0
  let room = @relay.RelayRoom::new()
  let send_to_a : (Bytes) -> Unit = data => editor_a.ws_on_message(data)
  let send_to_b : (Bytes) -> Unit = data => editor_b.ws_on_message(data)
  inspect(room.on_connect("alice", send_to_a), content="true")
  inspect(room.on_connect("bob", send_to_b), content="true")
  // Alice sets text and sends CrdtOps through v2 relay
  editor_a.set_text("hello v2")
  let crdt_msg = try! editor_a.export_all()
  let json_str = crdt_msg.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json_str)
  let wire_msg = @editor.encode_message(@editor.CrdtOps(buf.to_bytes()))
  // Relay wraps as RelayedCrdtOps and broadcasts
  room.on_message("alice", wire_msg)
  // Bob receives RelayedCrdtOps and applies it
  inspect(editor_b.get_text(), content="hello v2")
}

///|
test "v2 relay: SyncRequest routed to target peer only" {
  let _editor_a = @lambda.new_lambda_editor("alice").0
  let editor_b = @lambda.new_lambda_editor("bob").0
  let _editor_c = @lambda.new_lambda_editor("charlie").0
  let msgs_a : Array[Bytes] = []
  let msgs_c : Array[Bytes] = []
  let room = @relay.RelayRoom::new()
  let send_to_a : (Bytes) -> Unit = data => msgs_a.push(data)
  let send_to_b : (Bytes) -> Unit = data => editor_b.ws_on_message(data)
  let send_to_c : (Bytes) -> Unit = data => msgs_c.push(data)
  inspect(room.on_connect("alice", send_to_a), content="true")
  inspect(room.on_connect("bob", send_to_b), content="true")
  inspect(room.on_connect("charlie", send_to_c), content="true")
  msgs_a.clear()
  msgs_c.clear()
  // Bob sends SyncRequest targeting alice
  let req = @editor.encode_sync_request(
    target="alice",
    request_id="1",
    version_json="{}",
  )
  room.on_message("bob", req)
  // Only alice should receive it
  inspect(msgs_a.length(), content="1")
  inspect(msgs_c.length(), content="0")
}

///|
test "v2 relay: three peers sync via RelayedCrdtOps" {
  let editor_a = @lambda.new_lambda_editor("alice").0
  let editor_b = @lambda.new_lambda_editor("bob").0
  let editor_c = @lambda.new_lambda_editor("charlie").0
  let room = @relay.RelayRoom::new()
  let send_to_a : (Bytes) -> Unit = data => editor_a.ws_on_message(data)
  let send_to_b : (Bytes) -> Unit = data => editor_b.ws_on_message(data)
  let send_to_c : (Bytes) -> Unit = data => editor_c.ws_on_message(data)
  inspect(room.on_connect("alice", send_to_a), content="true")
  inspect(room.on_connect("bob", send_to_b), content="true")
  inspect(room.on_connect("charlie", send_to_c), content="true")
  // Alice types, broadcasts via relay
  editor_a.set_text("abc")
  let msg_a = try! editor_a.export_all()
  let json_a = msg_a.to_json_string()
  let buf_a = @buffer.new()
  buf_a.write_string(json_a)
  room.on_message(
    "alice",
    @editor.encode_message(@editor.CrdtOps(buf_a.to_bytes())),
  )
  // Both bob and charlie should have the text
  inspect(editor_b.get_text(), content="abc")
  inspect(editor_c.get_text(), content="abc")
}

///|
test "v2 relay: PeerLeft cleans up ephemeral state" {
  let editor_a = @lambda.new_lambda_editor("alice").0
  let editor_b = @lambda.new_lambda_editor("bob").0
  let room = @relay.RelayRoom::new()
  let send_to_a : (Bytes) -> Unit = data => editor_a.ws_on_message(data)
  let send_to_b : (Bytes) -> Unit = data => editor_b.ws_on_message(data)
  inspect(room.on_connect("alice", send_to_a), content="true")
  inspect(room.on_connect("bob", send_to_b), content="true")
  // Bob sets presence and sends to alice
  editor_b.set_local_presence("Bob", "#0000ff")
  let eph_data = editor_b.encode_ephemeral_all()
  editor_a.apply_ephemeral(eph_data)
  inspect(editor_a.get_hub().get_online_peers().length(), content="1")
  // Bob disconnects via relay — alice gets PeerLeft
  room.on_disconnect("bob")
  inspect(editor_a.get_hub().get_online_peers().length(), content="0")
}
