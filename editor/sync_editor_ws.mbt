// WebSocket lifecycle methods for SyncEditor.

///|
/// Called when WebSocket connects. Stores the ws reference.
/// Note: the relay server handles PeerJoined broadcast on connect —
/// the client does NOT send PeerJoined itself (that would duplicate it).
pub fn SyncEditor::ws_on_open(self : SyncEditor, ws : JsWebSocket) -> Unit {
  self.ws = Some(ws)
}

///|
pub fn SyncEditor::ws_on_message(self : SyncEditor, data : Bytes) -> Unit {
  let msg = match decode_message(data) {
    Some(m) => m
    None => return
  }
  match msg {
    CrdtOps(payload) => {
      // to_unchecked_string is safe here: malformed data is caught by from_json_string.
      let json_str = payload.to_unchecked_string()
      // TODO: silently dropping malformed/incompatible CrdtOps leaves the editor
      // diverged with no recovery. Implement SyncRequest/SyncResponse resync
      // so peers can request missing state after errors.
      try {
        let crdt_msg = @text.SyncMessage::from_json_string(json_str)
        self.apply_sync(crdt_msg)
      } catch {
        _ => ()
      }
    }
    EphemeralUpdate(ns, payload) => self.hub.apply(ns, payload)
    PeerJoined(_peer_id) => {
      // Send full ephemeral state for catch-up
      for ns in all_namespaces {
        let ns_data = self.hub.encode(ns)
        if ns_data.length() > 0 {
          self.ws_send(encode_message(EphemeralUpdate(ns, ns_data)))
        }
      }
      // Send full CRDT state
      let crdt_msg = self.export_all() catch { _ => return }
      let json_str = crdt_msg.to_json_string()
      let buf = @buffer.new()
      buf.write_string(json_str)
      self.ws_send(encode_message(CrdtOps(buf.to_bytes())))
    }
    PeerLeft(peer_id) => self.hub.on_peer_leave(peer_id)
    SyncRequest(_) | SyncResponse(_) => ()
  }
}

///|
pub fn SyncEditor::ws_on_close(self : SyncEditor) -> Unit {
  self.ws = None
}

///|
pub fn SyncEditor::ws_broadcast_edit(self : SyncEditor) -> Unit {
  match self.ws {
    None => return
    Some(_) => ()
  }
  let crdt_msg = self.export_all() catch { _ => return }
  let json_str = crdt_msg.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json_str)
  self.ws_send(encode_message(CrdtOps(buf.to_bytes())))
}

///|
pub fn SyncEditor::ws_broadcast_cursor(self : SyncEditor) -> Unit {
  match self.ws {
    None => return
    Some(_) => ()
  }
  let cursor_data = self.hub.encode(Cursor)
  if cursor_data.length() > 0 {
    self.ws_send(encode_message(EphemeralUpdate(Cursor, cursor_data)))
  }
}
