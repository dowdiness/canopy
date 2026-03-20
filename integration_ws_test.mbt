// End-to-end integration tests: two SyncEditors wired through a RelayRoom.

///|
test "two editors sync via relay" {
  // Create two editors
  let editor_a = @editor.SyncEditor::new("alice")
  let editor_b = @editor.SyncEditor::new("bob")
  // Create relay room and wire send functions to editors
  let room = @relay.RelayRoom::new()
  let send_to_a : (Bytes) -> Unit = data => editor_a.ws_on_message(data)
  let send_to_b : (Bytes) -> Unit = data => editor_b.ws_on_message(data)
  room.on_connect("alice", send_to_a)
  room.on_connect("bob", send_to_b)
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
  let editor_a = @editor.SyncEditor::new("alice")
  editor_a.set_text("world")
  inspect(editor_a.get_text(), content="world")
  // Bob joins later — simulate catch-up by sending full CRDT state directly
  let editor_b = @editor.SyncEditor::new("bob")
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
  let editor_a = @editor.SyncEditor::new("alice")
  let editor_b = @editor.SyncEditor::new("bob")
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
  room.on_connect("alice", send_to_a)
  room.on_connect("bob", send_to_b)
  // Disconnect bob — relay sends PeerLeft to alice
  room.on_disconnect("bob")
  // Alice's hub should have cleaned up Bob's presence
  let peers_after = editor_a.get_hub().get_online_peers()
  inspect(peers_after.length(), content="0")
}
