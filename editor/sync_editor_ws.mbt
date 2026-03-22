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
    SyncRequest(payload) => {
      let reader = Reader::new(payload)
      let sender = read_string(reader) catch { _ => return }
      let request_id = read_string(reader) catch { _ => return }
      let version_json = read_string(reader) catch { _ => return }
      // Parse requester's version and export delta
      let peer_version = @text.Version::from_json_string(version_json) catch {
        _ => {
          // Can't parse version — send empty response
          let wire = encode_sync_response(
            target=sender,
            request_id~,
            sync_json="",
          )
          self.ws_send(wire)
          return
        }
      }
      let delta = self.export_since(peer_version) catch {
        _ => {
          let wire = encode_sync_response(
            target=sender,
            request_id~,
            sync_json="",
          )
          self.ws_send(wire)
          return
        }
      }
      let sync_json = delta.to_json_string()
      // Cap response size at 1MB
      if sync_json.length() > 1_000_000 {
        let wire = encode_sync_response(
          target=sender,
          request_id~,
          sync_json="",
        )
        self.ws_send(wire)
        return
      }
      let wire = encode_sync_response(target=sender, request_id~, sync_json~)
      self.ws_send(wire)
    }
    SyncResponse(_) => ()
    RelayedCrdtOps(sender~, payload~) => {
      let json_str = payload.to_unchecked_string()
      let crdt_msg = @text.SyncMessage::from_json_string(json_str) catch {
        _ => return
      }
      // If recovering from this sender, buffer instead of applying
      match self.recovery {
        Some(ctx) =>
          if ctx.peer_id == sender {
            ctx.buffer_message(crdt_msg)
            return
          }
        None => ()
      }
      self.apply_sync(crdt_msg) catch {
        @text.TextError::SyncFailed(@text.SyncFailure::MissingDependency(..)) =>
          self.enter_recovery(sender, crdt_msg)
        @text.TextError::SyncFailed(@text.SyncFailure::Timeout(..)) =>
          self.enter_recovery(sender, crdt_msg)
        @text.TextError::VersionNotFound =>
          self.enter_recovery(sender, crdt_msg)
        // Non-retryable errors are silently dropped (same as before)
        _ => ()
      }
    }
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

///|
/// Enter recovery mode for a specific peer. Sends SyncRequest.
fn SyncEditor::enter_recovery(
  self : SyncEditor,
  peer_id : String,
  failed_msg : @text.SyncMessage,
) -> Unit {
  // Only one recovery at a time
  if self.recovery is Some(_) {
    return
  }
  self.recovery_epoch += 1
  let request_id = self.recovery_epoch
  self.recovery = Some(RecoveryContext::new(peer_id, failed_msg, request_id))
  self.send_sync_request(peer_id, request_id)
}

///|
/// Send a SyncRequest to a specific peer via the relay.
fn SyncEditor::send_sync_request(
  self : SyncEditor,
  target : String,
  request_id : Int,
) -> Unit {
  let version_json = self.get_version().to_json_string()
  let wire = encode_sync_request(
    target~,
    request_id=request_id.to_string(),
    version_json~,
  )
  self.ws_send(wire)
}
