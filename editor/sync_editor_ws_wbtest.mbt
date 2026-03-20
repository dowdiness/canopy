// Whitebox tests for WebSocket lifecycle methods on SyncEditor.

///|
test "ws_on_close: clears ws reference" {
  let editor = SyncEditor::new("alice")
  let ws = JsWebSocket(0)
  editor.ws_on_open(ws)
  inspect(editor.ws is None, content="false")
  editor.ws_on_close()
  inspect(editor.ws is None, content="true")
}

///|
test "ws_send: does nothing when disconnected" {
  let editor = SyncEditor::new("alice")
  // ws is None by default — should not panic
  editor.ws_send(Bytes::new(0))
  inspect(editor.ws is None, content="true")
}

///|
test "ws_on_message: PeerLeft removes peer from hub" {
  let editor = SyncEditor::new("alice")
  // Set some presence for "bob" in the hub
  let bob_wire = to_wire_peer_id("bob")
  editor.hub.get_store(Cursor).set(bob_wire, EphemeralValue::I64(42L)) catch {
    _ => ()
  }
  // Verify bob is present
  inspect(editor.hub.get_store(Cursor).get(bob_wire) is None, content="false")
  // Simulate PeerLeft message
  let wire = encode_message(PeerLeft("bob"))
  editor.ws_on_message(wire)
  // Bob should be removed
  inspect(editor.hub.get_store(Cursor).get(bob_wire) is None, content="true")
}

///|
test "ws_on_message: CrdtOps applies remote edits" {
  let editor_a = SyncEditor::new("alice")
  let editor_b = SyncEditor::new("bob")
  // Alice types some text
  editor_a.set_text("hello")
  // Export alice's state as JSON bytes
  let crdt_msg = editor_a.export_all() catch {
    _ => {
      fail("export_all failed")
      return
    }
  }
  let json_str = crdt_msg.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json_str)
  let wire = encode_message(CrdtOps(buf.to_bytes()))
  // Bob receives the message
  editor_b.ws_on_message(wire)
  inspect(editor_b.get_text(), content="hello")
}

///|
test "ws_on_message: EphemeralUpdate applies to hub" {
  let editor = SyncEditor::new("alice")
  // Create some ephemeral data from a different hub
  let other_hub = EphemeralHub::new("bob")
  other_hub.set_cursor(42)
  let cursor_data = other_hub.encode(Cursor)
  // Wrap as wire message
  let wire = encode_message(EphemeralUpdate(Cursor, cursor_data))
  editor.ws_on_message(wire)
  // Verify bob's cursor is now in alice's hub
  let bob_cursor = editor.hub.get_cursor("bob")
  inspect(bob_cursor is None, content="false")
}
