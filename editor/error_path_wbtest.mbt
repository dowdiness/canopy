// Error path tests for sync, WebSocket, and protocol handling.
//
// These tests verify the system handles malformed input gracefully:
// no panics, no aborts, correct state after errors.

// ============================================================================
// Wire protocol: decode_message error paths
// ============================================================================

///|
test "decode_message: empty bytes returns None" {
  inspect(decode_message(Bytes::new(0)) is None, content="true")
}

///|
test "decode_message: 1-byte too short returns None" {
  inspect(decode_message(b"\x02") is None, content="true")
}

///|
test "decode_message: 2-byte too short returns None" {
  inspect(decode_message(b"\x02\x01") is None, content="true")
}

///|
test "decode_message: wrong protocol version returns None" {
  inspect(decode_message(b"\xFF\x01\x00") is None, content="true")
}

///|
test "decode_message: unknown message type returns None" {
  inspect(decode_message(b"\x02\xFF\x00") is None, content="true")
}

///|
test "decode_message: CrdtOps with empty payload" {
  let msg = decode_message(b"\x02\x01\x00")
  inspect(msg is Some(CrdtOps(_)), content="true")
}

///|
test "decode_message: EphemeralUpdate missing namespace byte returns None" {
  // Header only, no namespace byte after it
  inspect(decode_message(b"\x02\x02\x00") is None, content="true")
}

///|
test "decode_message: EphemeralUpdate invalid namespace returns None" {
  // Header + invalid namespace byte 0xFF
  inspect(decode_message(b"\x02\x02\x00\xFF") is None, content="true")
}

///|
test "decode_message: PeerJoined missing sub_type returns None" {
  // Header for peer message (0x05) but no sub_type byte
  inspect(decode_message(b"\x02\x05\x00") is None, content="true")
}

///|
test "decode_message: PeerJoined truncated peer_id returns None" {
  // Header + sub_type Join (0x01) but no peer_id string
  inspect(decode_message(b"\x02\x05\x00\x01") is None, content="true")
}

///|
test "decode_message: PeerJoined unknown sub_type returns None" {
  // Header + unknown sub_type 0xFF
  inspect(decode_message(b"\x02\x05\x00\xFF") is None, content="true")
}

///|
test "decode_message: roundtrip preserves all message types" {
  let messages : Array[SyncMessage] = [
    CrdtOps(b"\x42\x43"),
    EphemeralUpdate(Cursor, b"\x01\x02"),
    SyncRequest(b"\x10"),
    SyncResponse(b"\x20"),
    PeerJoined("alice"),
    PeerLeft("bob"),
  ]
  for msg in messages {
    let encoded = encode_message(msg)
    let decoded = decode_message(encoded)
    inspect(decoded == Some(msg), content="true")
  }
}

// ============================================================================
// ws_on_message: error paths
// ============================================================================

///|
test "ws_on_message: empty bytes does not panic" {
  let editor = SyncEditor::new_lambda("alice")
  editor.ws_on_message(Bytes::new(0))
  // Editor should be in default state
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: truncated wire does not panic" {
  let editor = SyncEditor::new_lambda("alice")
  editor.ws_on_message(b"\x02")
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: wrong protocol version ignored" {
  let editor = SyncEditor::new_lambda("alice")
  editor.ws_on_message(b"\xFF\x01\x00some payload")
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: CrdtOps with invalid JSON does not panic" {
  let editor = SyncEditor::new_lambda("alice")
  let buf = @buffer.new()
  buf.write_string("this is not valid json {{{")
  let wire = encode_message(CrdtOps(buf.to_bytes()))
  editor.ws_on_message(wire)
  // Editor should remain unchanged
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: CrdtOps with wrong JSON schema does not panic" {
  let editor = SyncEditor::new_lambda("alice")
  let buf = @buffer.new()
  buf.write_string("{\"wrong\": \"schema\"}")
  let wire = encode_message(CrdtOps(buf.to_bytes()))
  editor.ws_on_message(wire)
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: CrdtOps with empty JSON object does not panic" {
  let editor = SyncEditor::new_lambda("alice")
  let buf = @buffer.new()
  buf.write_string("{}")
  let wire = encode_message(CrdtOps(buf.to_bytes()))
  editor.ws_on_message(wire)
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: CrdtOps with empty payload does not panic" {
  let editor = SyncEditor::new_lambda("alice")
  let wire = encode_message(CrdtOps(Bytes::new(0)))
  editor.ws_on_message(wire)
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: PeerLeft for unknown peer does not panic" {
  let editor = SyncEditor::new_lambda("alice")
  let wire = encode_message(PeerLeft("nonexistent_peer"))
  editor.ws_on_message(wire)
  inspect(editor.get_text(), content="")
}

///|
test "ws_on_message: malformed message after valid sync preserves text" {
  let editor_a = SyncEditor::new_lambda("alice")
  let editor_b = SyncEditor::new_lambda("bob")
  // Valid sync: alice types, bob receives
  editor_a.set_text("hello")
  let crdt_msg = editor_a.export_all() catch {
    _ => {
      fail("export_all failed")
      return
    }
  }
  let json_str = crdt_msg.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json_str)
  editor_b.ws_on_message(encode_message(CrdtOps(buf.to_bytes())))
  inspect(editor_b.get_text(), content="hello")
  // Now send malformed message — bob's text should be preserved
  let bad_buf = @buffer.new()
  bad_buf.write_string("not json")
  editor_b.ws_on_message(encode_message(CrdtOps(bad_buf.to_bytes())))
  inspect(editor_b.get_text(), content="hello")
}

// ============================================================================
// apply_sync: error paths
// ============================================================================

///|
test "apply_sync: empty SyncMessage is safe" {
  let editor = SyncEditor::new_lambda("alice")
  editor.set_text("hello")
  let empty_msg = @text.SyncMessage::from_json_string(
    "{\"runs\":[],\"heads\":[]}",
  ) catch {
    _ => {
      fail("from_json_string failed")
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
test "apply_sync: error does not corrupt editor state" {
  let editor = SyncEditor::new_lambda("alice")
  editor.set_text("hello world")
  let original_text = editor.get_text()
  // Try to apply a message with invalid JSON — should raise
  try {
    let bad_msg = @text.SyncMessage::from_json_string("invalid json")
    editor.apply_sync(bad_msg)
  } catch {
    _ => () // Expected
  }
  // Editor text should be preserved
  inspect(editor.get_text() == original_text, content="true")
}

// ============================================================================
// export_since: edge cases
// ============================================================================

///|
test "export_since: empty version exports all" {
  let editor = SyncEditor::new_lambda("alice")
  editor.set_text("hello")
  let empty_version = editor.get_version()
  // Create a fresh editor to get an empty version
  let fresh = SyncEditor::new_lambda("bob")
  let fresh_version = fresh.get_version()
  try {
    let msg = editor.export_since(fresh_version)
    // Should contain ops (alice's edits)
    let json = msg.to_json_string()
    inspect(json.contains("runs"), content="true")
  } catch {
    _ => () // VersionNotFound is acceptable
  }
  let _ = empty_version
}

// ============================================================================
// ws_broadcast: when disconnected
// ============================================================================

///|
test "ws_broadcast_edit: no-op when disconnected" {
  let editor = SyncEditor::new_lambda("alice")
  editor.set_text("hello")
  // Should not panic when ws is None
  editor.ws_broadcast_edit()
  inspect(editor.get_text(), content="hello")
}

///|
test "ws_broadcast_cursor: no-op when disconnected" {
  let editor = SyncEditor::new_lambda("alice")
  editor.hub.set_cursor(5)
  // Should not panic when ws is None
  editor.ws_broadcast_cursor()
}
