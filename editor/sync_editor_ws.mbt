// WebSocket lifecycle methods for SyncEditor.

///|
fn parse_sync_message_json(
  payload : Bytes,
) -> Result[@text.SyncMessage, ProtocolError] {
  let json_str = payload.to_unchecked_string()
  Ok(@text.SyncMessage::from_json_string(json_str)) catch {
    err => Err(ProtocolError::InvalidSyncJson(detail=err.message()))
  }
}

///|
fn parse_sync_request_payload(
  payload : Bytes,
) -> Result[(String, String, String), ProtocolError] {
  let reader = Reader::new(payload)
  let sender = match read_string_field(reader, "sender") {
    Ok(sender) => sender
    Err(err) => return Err(err)
  }
  let request_id = match read_string_field(reader, "request_id") {
    Ok(request_id) => request_id
    Err(err) => return Err(err)
  }
  let version_json = match read_string_field(reader, "version_json") {
    Ok(version_json) => version_json
    Err(err) => return Err(err)
  }
  Ok((sender, request_id, version_json))
}

///|
fn parse_sync_response_payload(
  payload : Bytes,
) -> Result[(String, String, String), ProtocolError] {
  let reader = Reader::new(payload)
  let sender = match read_string_field(reader, "sender") {
    Ok(sender) => sender
    Err(err) => return Err(err)
  }
  let request_id = match read_string_field(reader, "request_id") {
    Ok(request_id) => request_id
    Err(err) => return Err(err)
  }
  let sync_json = match read_string_field(reader, "sync_json") {
    Ok(sync_json) => sync_json
    Err(err) => return Err(err)
  }
  Ok((sender, request_id, sync_json))
}

///|
fn should_retry_sync_error(err : Error) -> Bool {
  match err {
    @text.TextError::SyncFailed(@text.SyncFailure::MissingDependency(..)) =>
      true
    @text.TextError::SyncFailed(@text.SyncFailure::Timeout(..)) => true
    @text.TextError::VersionNotFound => true
    _ => false
  }
}

///|
/// Called when WebSocket connects. Stores the ws reference.
/// Note: the relay server handles PeerJoined broadcast on connect —
/// the client does NOT send PeerJoined itself (that would duplicate it).
pub fn[T] SyncEditor::ws_on_open(
  self : SyncEditor[T],
  ws : JsWebSocket,
) -> Unit {
  self.ws = Some(ws)
  self.set_status(Idle)
}

///|
pub fn[T] SyncEditor::ws_on_message(self : SyncEditor[T], data : Bytes) -> Unit {
  let msg = match decode_message_result(data) {
    Ok(m) => m
    Err(_) => return
  }
  match msg {
    CrdtOps(payload) => {
      // CrdtOps is used for backwards-compatible full-state exchange (PeerJoined).
      // Recovery is not possible here because there is no sender ID.
      // Once all peers use RelayedCrdtOps, this path only handles PeerJoined sync.
      let crdt_msg = match parse_sync_message_json(payload) {
        Ok(crdt_msg) => crdt_msg
        Err(_) => return
      }
      self.apply_sync(crdt_msg) catch {
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
    PeerLeft(peer_id) => {
      self.hub.on_peer_leave(peer_id)
      // Abort recovery if the leaving peer is the one we're recovering from
      match self.recovery {
        Some(ctx) =>
          if ctx.peer_id == peer_id {
            let target = ctx.peer_id
            self.recovery = None
            self.set_status(Error(reason=TargetLeft(peer_id=target)))
          }
        None => ()
      }
    }
    SyncRequest(payload) => {
      let (sender, request_id, version_json) = match
        parse_sync_request_payload(payload) {
        Ok(parts) => parts
        Err(_) => return
      }
      // Parse requester's version and export delta
      let peer_version = @text.Version::from_json_string(version_json) catch {
        _ => {
          self.send_empty_sync_response(sender, request_id)
          return
        }
      }
      let delta = self.export_since(peer_version) catch {
        _ => {
          self.send_empty_sync_response(sender, request_id)
          return
        }
      }
      let sync_json = delta.to_json_string()
      // Cap response size at 1MB
      if sync_json.length() > 1_000_000 {
        self.send_empty_sync_response(sender, request_id)
        return
      }
      let wire = encode_sync_response(target=sender, request_id~, sync_json~)
      self.ws_send(wire)
    }
    SyncResponse(payload) => {
      let (_sender, request_id, sync_json) = match
        parse_sync_response_payload(payload) {
        Ok(parts) => parts
        Err(_) => return
      }
      let ctx = match self.recovery {
        Some(ctx) => ctx
        None => return // Not recovering, ignore
      }
      // Stale response check
      if !ctx.matches_request_id(request_id) {
        return
      }
      // Empty response = responder can't help
      if sync_json == "" {
        self.handle_recovery_retry()
        return
      }
      // Apply the delta
      let delta = @text.SyncMessage::from_json_string(sync_json) catch {
        _ => {
          self.handle_recovery_retry()
          return
        }
      }
      self.apply_sync(delta) catch {
        _ => {
          // Delta failed — partial state possible, retry recovery
          self.handle_recovery_retry()
          return
        }
      }
      // Retry the original pending message
      self.apply_sync(ctx.pending_msg) catch {
        _ => {
          // Re-export version for next retry (delta may have advanced our state)
          self.handle_recovery_retry()
          return
        }
      }
      // Success! Drain deferred messages
      let deferred = ctx.deferred
      self.recovery = None
      for i, msg in deferred {
        self.apply_sync(msg) catch {
          err => {
            // Re-enter recovery with the failed deferred message,
            // carrying over remaining un-applied messages
            if should_retry_sync_error(err) {
              self.recovery_epoch += 1
              let new_ctx = RecoveryContext::new(
                ctx.peer_id,
                msg,
                self.recovery_epoch,
              )
              // Buffer remaining deferred messages
              for j = i + 1; j < deferred.length(); j = j + 1 {
                new_ctx.buffer_message(deferred[j])
              }
              self.recovery = Some(new_ctx)
              // The original recovery has completed — emit Idle first so
              // the fresh Recovering(..,1) is a visible transition even
              // when the peer_id/attempt payload is the same as before.
              self.set_status(Idle)
              self.set_status(
                Recovering(peer_id=ctx.peer_id, attempt=new_ctx.retries + 1),
              )
              self.send_sync_request(ctx.peer_id, self.recovery_epoch)
              break // Retryable — entered new recovery, stop draining
            }
            continue // Non-retryable, skip and try next
          }
        }
      }
      // Only transition to Idle if we didn't re-enter recovery during drain
      if self.recovery is None {
        self.set_status(Idle)
      }
    }
    RelayedCrdtOps(sender~, payload~) => {
      let crdt_msg = match parse_sync_message_json(payload) {
        Ok(crdt_msg) => crdt_msg
        Err(_) => return
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
        err =>
          if should_retry_sync_error(err) {
            self.enter_recovery(sender, crdt_msg)
          }
      }
    }
  }
}

///|
pub fn[T] SyncEditor::ws_on_close(self : SyncEditor[T]) -> Unit {
  self.ws = None
  self.recovery = None
  self.set_status(Disconnected)
}

///|
pub fn[T] SyncEditor::ws_broadcast_edit(self : SyncEditor[T]) -> Unit {
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
pub fn[T] SyncEditor::ws_broadcast_cursor(self : SyncEditor[T]) -> Unit {
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
/// Send an empty SyncResponse (responder can't satisfy the request).
fn[T] SyncEditor::send_empty_sync_response(
  self : SyncEditor[T],
  target : String,
  request_id : String,
) -> Unit {
  self.ws_send(encode_sync_response(target~, request_id~, sync_json=""))
}

///|
/// Enter recovery mode for a specific peer. Sends SyncRequest.
fn[T] SyncEditor::enter_recovery(
  self : SyncEditor[T],
  peer_id : String,
  failed_msg : @text.SyncMessage,
) -> Unit {
  // Only one recovery at a time. If peer Y fails while recovering from X,
  // Y's message is dropped. This is a known limitation — once X's recovery
  // fills the causal gap, Y's future messages should succeed. If not,
  // a page reload triggers full PeerJoined exchange which resyncs.
  if self.recovery is Some(_) {
    return
  }
  self.recovery_epoch += 1
  let request_id = self.recovery_epoch
  self.recovery = Some(RecoveryContext::new(peer_id, failed_msg, request_id))
  self.set_status(Recovering(peer_id~, attempt=1))
  self.send_sync_request(peer_id, request_id)
}

///|
/// Send a SyncRequest to a specific peer via the relay.
/// Always uses the current version (not stale from recovery entry).
fn[T] SyncEditor::send_sync_request(
  self : SyncEditor[T],
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
  // Arm the watchdog for this request; timeout is read fresh so
  // set_watchdog_timeout takes effect on subsequent sends.
  match self.watchdog_scheduler {
    Some(scheduler) => scheduler(request_id, self.watchdog_timeout_ms)
    None => ()
  }
}

///|
/// Handle a failed recovery retry: send another request or give up.
/// Check exhaustion BEFORE advancing so retries=0,1,2 each send a request
/// and retries=3 gives up (3 retries total).
fn[T] SyncEditor::handle_recovery_retry(self : SyncEditor[T]) -> Unit {
  let ctx = match self.recovery {
    Some(ctx) => ctx
    None => return
  }
  if ctx.is_exhausted() {
    // Give up — clear recovery and surface the error
    let peer_id = ctx.peer_id
    self.recovery = None
    self.set_status(Error(reason=Exhausted(peer_id~)))
    return
  }
  // Advance ctx + status BEFORE the wire send so any re-entrant
  // on_watchdog_fire triggered by side-effects of send_sync_request
  // sees the matching request_id. Actual JS setTimeout delivery is
  // async so the real concern is test-driven synchronous re-entry,
  // not production network I/O — but the ordering is still the
  // correct invariant.
  self.recovery_epoch += 1
  ctx.advance_retry(self.recovery_epoch)
  self.set_status(Recovering(peer_id=ctx.peer_id, attempt=ctx.retries + 1))
  self.send_sync_request(ctx.peer_id, self.recovery_epoch)
}
