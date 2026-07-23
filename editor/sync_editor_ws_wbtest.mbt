// Whitebox tests for WebSocket lifecycle methods on SyncEditor.

///|
test "ws_on_close: clears ws reference" {
  let editor = try! @probe.new_test_editor("alice")
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  inspect(editor.ws is None, content="false")
  editor.ws_on_close()
  inspect(editor.ws is None, content="true")
}

///|
test "ws_send: does nothing when disconnected" {
  let editor = try! @probe.new_test_editor("alice")
  // ws is None by default — should not panic
  editor.ws_send(Bytes::new(0))
  inspect(editor.ws is None, content="true")
}

///|
test "ws_on_message: PeerLeft removes peer from hub" {
  let editor = try! @probe.new_test_editor("alice")
  // Inject remote cursor presence for "bob" the way it arrives over the wire:
  // encode it from bob's own hub and apply to alice's editor hub.
  let bob_hub = EphemeralHub::new("bob")
  bob_hub.set_cursor(42)
  editor.hub.apply(Cursor, bob_hub.encode(Cursor))
  // Verify bob is present (peer-id-keyed query — no wire-key math needed)
  inspect(editor.hub.get_cursor("bob") is None, content="false")
  // Simulate PeerLeft message
  let wire = @wire.encode_message(PeerLeft("bob"))
  editor.ws_on_message(wire)
  // Bob should be removed
  inspect(editor.hub.get_cursor("bob") is None, content="true")
}

///|
test "ws_on_message: CrdtOps applies remote edits" {
  let editor_a = try! @probe.new_test_editor("alice")
  let editor_b = try! @probe.new_test_editor("bob")
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
  let buf = Buffer()
  buf.write_string_utf16le(json_str.view())
  let wire = @wire.encode_message(CrdtOps(buf.to_bytes()))
  // Bob receives the message
  editor_b.ws_on_message(wire)
  inspect(editor_b.get_text(), content="hello")
}

///|
test "ws_on_message: EphemeralUpdate applies to hub" {
  let editor = try! @probe.new_test_editor("alice")
  // Create some ephemeral data from a different hub
  let other_hub = EphemeralHub::new("bob")
  other_hub.set_cursor(42)
  let cursor_data = other_hub.encode(Cursor)
  // Wrap as wire message
  let wire = @wire.encode_message(EphemeralUpdate(Cursor, cursor_data))
  editor.ws_on_message(wire)
  // Verify bob's cursor is now in alice's hub
  let bob_cursor = editor.hub.get_cursor("bob")
  inspect(bob_cursor is None, content="false")
}

///|
test "ws_on_message: RelayedCrdtOps applies remote edits with sender" {
  let editor_a = try! @probe.new_test_editor("alice")
  let editor_b = try! @probe.new_test_editor("bob")
  editor_a.set_text("hello")
  let crdt_msg = editor_a.export_all() catch {
    _ => {
      fail("export failed")
      return
    }
  }
  let json_str = crdt_msg.to_json_string()
  let buf = Buffer()
  buf.write_string_utf16le(json_str.view())
  let wire = @wire.encode_relayed_crdt_ops("alice", buf.to_bytes())
  editor_b.ws_on_message(wire)
  inspect(editor_b.get_text(), content="hello")
}
