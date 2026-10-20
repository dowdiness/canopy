// Error path tests for sync and WebSocket handling.
//
// These tests verify the system handles malformed input gracefully:
// no panics, no aborts, correct state after errors.

// ============================================================================
// ws_on_message: error paths
// ============================================================================

///|
test "ws_on_message: empty bytes does not panic" {
  let editor = try! @probe.new_test_editor("alice")
  editor.ws_on_message(Bytes::new(0))
  // Editor should be in default state
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: truncated wire does not panic" {
  let editor = try! @probe.new_test_editor("alice")
  editor.ws_on_message(b"\x02")
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: wrong protocol version ignored" {
  let editor = try! @probe.new_test_editor("alice")
  editor.ws_on_message(b"\xFF\x01\x00some payload")
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: CrdtOps with invalid JSON does not panic" {
  let editor = try! @probe.new_test_editor("alice")
  let buf = Buffer()
  buf.write_string_utf16le("this is not valid json {{{".view())
  let wire = @wire.encode_message(CrdtOps(buf.to_bytes()))
  editor.ws_on_message(wire)
  // Editor should remain unchanged
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: CrdtOps with wrong JSON schema does not panic" {
  let editor = try! @probe.new_test_editor("alice")
  let buf = Buffer()
  buf.write_string_utf16le("{\"wrong\": \"schema\"}".view())
  let wire = @wire.encode_message(CrdtOps(buf.to_bytes()))
  editor.ws_on_message(wire)
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: CrdtOps with empty JSON object does not panic" {
  let editor = try! @probe.new_test_editor("alice")
  let buf = Buffer()
  buf.write_string_utf16le("{}".view())
  let wire = @wire.encode_message(CrdtOps(buf.to_bytes()))
  editor.ws_on_message(wire)
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: CrdtOps with empty payload does not panic" {
  let editor = try! @probe.new_test_editor("alice")
  let wire = @wire.encode_message(CrdtOps(Bytes::new(0)))
  editor.ws_on_message(wire)
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: PeerLeft for unknown peer does not panic" {
  let editor = try! @probe.new_test_editor("alice")
  let wire = @wire.encode_message(PeerLeft("nonexistent_peer"))
  editor.ws_on_message(wire)
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: malformed message after valid sync preserves text" {
  let editor_a = try! @probe.new_test_editor("alice")
  let editor_b = try! @probe.new_test_editor("bob")
  // Valid sync: alice types, bob receives
  editor_a.set_text("hello")
  let crdt_msg = editor_a.export_all() catch {
    _ => {
      fail("export_all failed")
      return
    }
  }
  let json_str = crdt_msg.to_json_string()
  let buf = Buffer()
  buf.write_string_utf16le(json_str.view())
  editor_b.ws_on_message(@wire.encode_message(CrdtOps(buf.to_bytes())))
  inspect(editor_b.get_text(), content="hello")
  // Now send malformed message — bob's text should be preserved
  let bad_buf = Buffer()
  bad_buf.write_string_utf16le("not json".view())
  editor_b.ws_on_message(@wire.encode_message(CrdtOps(bad_buf.to_bytes())))
  inspect(editor_b.get_text(), content="hello")
}

// ============================================================================
// apply_sync: error paths
// ============================================================================

///|
test "apply_sync: empty SyncMessage is safe" {
  let editor = try! @probe.new_test_editor("alice")
  editor.set_text("hello")
  let empty_msg = try! @probe.new_test_editor("empty-message").export_all() catch {
    _ => {
      fail("export_all failed")
      return
    }
  }
  editor.apply_sync(empty_msg) catch {
    _ => ()
  }
  // Text should be unchanged
  inspect(editor.get_text(), content="hello")
}

///|
test "apply_sync: missing dependency preserves text and version" {
  let editor = try! @probe.new_test_editor("alice")
  editor.set_text("hello world")
  let original_text = editor.get_text()
  let original_version = editor.get_version()
  let sender = try! @probe.new_test_editor("bob")
  sender.set_text("parent")
  let parent_version = sender.get_version()
  sender.set_text("parent-child")
  let orphan_delta = try! sender.export_since(parent_version)
  // Decode succeeds; the receiving editor has never seen the parent.
  let mut raised_pending = false
  editor.apply_sync(orphan_delta) catch {
    @text.TextError::VersionNotFound => raised_pending = true
    other => fail("expected pending dependency, got: \{other}")
  }
  inspect(raised_pending, content="true")
  assert_eq(editor.get_text(), original_text)
  assert_eq(editor.get_version(), original_version)
}

// ============================================================================
// export_since: edge cases
// ============================================================================

///|
test "export_since: empty version exports all" {
  let editor = try! @probe.new_test_editor("alice")
  let empty_version = editor.get_version()
  editor.set_text("hello")
  let msg = try! editor.export_since(empty_version)
  inspect(msg.op_count() > 0, content="true")
}

// ============================================================================
// ws_broadcast: when disconnected
// ============================================================================

///|
test "ws_broadcast_edit: no-op when disconnected" {
  let editor = try! @probe.new_test_editor("alice")
  editor.set_text("hello")
  // Should not panic when ws is None
  editor.ws_broadcast_edit()
  inspect(editor.get_text(), content="hello")
}

///|
test "ws_broadcast_cursor: no-op when disconnected" {
  let editor = try! @probe.new_test_editor("alice")
  editor.interaction.hub.set_cursor(5)
  // Should not panic when ws is None
  editor.ws_broadcast_cursor()
}
