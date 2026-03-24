// Whitebox tests for WebSocket lifecycle methods on SyncEditor.

///|
test "ws_on_close: clears ws reference" {
  let editor = SyncEditor::new_lambda("alice")
  let ws = JsWebSocket(0)
  editor.ws_on_open(ws)
  inspect(editor.ws is None, content="false")
  editor.ws_on_close()
  inspect(editor.ws is None, content="true")
}

///|
test "ws_send: does nothing when disconnected" {
  let editor = SyncEditor::new_lambda("alice")
  // ws is None by default — should not panic
  editor.ws_send(Bytes::new(0))
  inspect(editor.ws is None, content="true")
}

///|
test "ws_on_message: PeerLeft removes peer from hub" {
  let editor = SyncEditor::new_lambda("alice")
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
  let editor_a = SyncEditor::new_lambda("alice")
  let editor_b = SyncEditor::new_lambda("bob")
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
  let editor = SyncEditor::new_lambda("alice")
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

///|
test "ws_on_message: RelayedCrdtOps applies remote edits with sender" {
  let editor_a = SyncEditor::new_lambda("alice")
  let editor_b = SyncEditor::new_lambda("bob")
  editor_a.set_text("hello")
  let crdt_msg = editor_a.export_all() catch {
    _ => {
      fail("export failed")
      return
    }
  }
  let json_str = crdt_msg.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json_str)
  let wire = encode_relayed_crdt_ops("alice", buf.to_bytes())
  editor_b.ws_on_message(wire)
  inspect(editor_b.get_text(), content="hello")
}

///|
test "ws_on_message: RelayedCrdtOps buffers during recovery" {
  let editor = SyncEditor::new_lambda("bob")
  let empty_msg = @text.SyncMessage::from_json_string(
    "{\"runs\":[],\"heads\":[]}",
  ) catch {
    _ => {
      fail("parse failed")
      return
    }
  }
  // Manually set recovery state for "alice"
  editor.recovery_epoch = 1
  editor.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  // Send RelayedCrdtOps from "alice" — should be buffered, not applied
  let buf = @buffer.new()
  buf.write_string("{\"runs\":[],\"heads\":[]}")
  let wire = encode_relayed_crdt_ops("alice", buf.to_bytes())
  editor.ws_on_message(wire)
  // Message should be buffered
  inspect(editor.recovery.unwrap().deferred.length(), content="1")
}

///|
test "ws_on_message: SyncResponse with stale request_id is ignored" {
  let editor = SyncEditor::new_lambda("bob")
  let empty_msg = @text.SyncMessage::from_json_string(
    "{\"runs\":[],\"heads\":[]}",
  ) catch {
    _ => {
      fail("parse")
      return
    }
  }
  editor.recovery_epoch = 5
  editor.recovery = Some(RecoveryContext::new("alice", empty_msg, 5))
  // Send SyncResponse with wrong request_id "3" (current is "5")
  let buf = @buffer.new()
  buf.write_byte(b'\x02') // v2
  buf.write_byte(b'\x04') // SyncResponse
  buf.write_byte(b'\x00')
  write_string(buf, "alice") // sender
  write_string(buf, "3") // stale request_id
  write_string(buf, "") // empty delta
  editor.ws_on_message(buf.to_bytes())
  // Recovery should still be active (response was ignored)
  inspect(editor.recovery is Some(_), content="true")
  inspect(editor.recovery.unwrap().retries, content="0") // no retry increment
}

///|
test "ws_on_message: SyncResponse with empty delta increments retries" {
  let editor = SyncEditor::new_lambda("bob")
  let empty_msg = @text.SyncMessage::from_json_string(
    "{\"runs\":[],\"heads\":[]}",
  ) catch {
    _ => {
      fail("parse")
      return
    }
  }
  editor.recovery_epoch = 1
  editor.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  // Send SyncResponse with matching request_id but empty delta
  let buf = @buffer.new()
  buf.write_byte(b'\x02')
  buf.write_byte(b'\x04')
  buf.write_byte(b'\x00')
  write_string(buf, "alice")
  write_string(buf, "1") // matches
  write_string(buf, "") // empty = can't help
  editor.ws_on_message(buf.to_bytes())
  // Should have incremented retries
  inspect(editor.recovery is Some(_), content="true")
  inspect(editor.recovery.unwrap().retries, content="1")
}

///|
test "ws_on_message: PeerLeft aborts recovery for that peer" {
  let editor = SyncEditor::new_lambda("bob")
  let empty_msg = @text.SyncMessage::from_json_string(
    "{\"runs\":[],\"heads\":[]}",
  ) catch {
    _ => {
      fail("parse")
      return
    }
  }
  editor.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  let wire = encode_message(PeerLeft("alice"))
  editor.ws_on_message(wire)
  inspect(editor.recovery is None, content="true")
}

///|
test "ws_on_message: PeerLeft for other peer does not abort recovery" {
  let editor = SyncEditor::new_lambda("bob")
  let empty_msg = @text.SyncMessage::from_json_string(
    "{\"runs\":[],\"heads\":[]}",
  ) catch {
    _ => {
      fail("parse")
      return
    }
  }
  editor.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  let wire = encode_message(PeerLeft("charlie"))
  editor.ws_on_message(wire)
  // Recovery for alice should still be active
  inspect(editor.recovery is Some(_), content="true")
}

///|
test "ws_on_close: clears recovery state" {
  let editor = SyncEditor::new_lambda("bob")
  let empty_msg = @text.SyncMessage::from_json_string(
    "{\"runs\":[],\"heads\":[]}",
  ) catch {
    _ => {
      fail("parse")
      return
    }
  }
  editor.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  editor.ws_on_close()
  inspect(editor.recovery is None, content="true")
  inspect(editor.ws is None, content="true")
}
