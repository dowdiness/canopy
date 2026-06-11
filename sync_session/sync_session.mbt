// Transport-agnostic sync session: status, recovery state machine, and
// message dispatch. Extracted from editor/sync_editor.mbt and
// editor/sync_editor_ws.mbt in redesign S2. The owning editor stays the
// document authority — document and presence operations are supplied per
// call through SyncIo / SyncHost closure records (the LanguageCapabilities
// record-over-trait pattern).

///|
/// Default watchdog timeout in milliseconds.
const DEFAULT_WATCHDOG_MS : Int = 5000

///|
/// Narrow IO record: the operations needed by the retry/send paths
/// (send_sync_request, handle_recovery_retry, on_watchdog_fire). Kept
/// separate from SyncHost because the editor's `on_watchdog_fire` surface
/// has no `Eq` bound and therefore cannot build the full host (whose
/// apply_sync closure requires it).
pub struct SyncIo {
  send : (Bytes) -> Unit
  current_version : () -> @text.Version
}

///|
pub fn SyncIo::SyncIo(
  send~ : (Bytes) -> Unit,
  current_version~ : () -> @text.Version,
) -> SyncIo {
  { send, current_version }
}

///|
/// Full dispatch host: document sync application/export plus ephemeral
/// routing. Consumed only by `on_message`. Ephemeral payloads are routed
/// through closures so this package never depends on the ephemeral engine.
pub struct SyncHost {
  io : SyncIo
  apply_sync : (@text.SyncMessage) -> Unit raise
  export_all : () -> @text.SyncMessage raise
  export_since : (@text.Version) -> @text.SyncMessage raise
  apply_ephemeral : (@wire.EphemeralNamespace, Bytes) -> Unit
  encode_ephemeral : (@wire.EphemeralNamespace) -> Bytes
  on_peer_leave : (String) -> Unit
}

///|
pub fn SyncHost::SyncHost(
  io~ : SyncIo,
  apply_sync~ : (@text.SyncMessage) -> Unit raise,
  export_all~ : () -> @text.SyncMessage raise,
  export_since~ : (@text.Version) -> @text.SyncMessage raise,
  apply_ephemeral~ : (@wire.EphemeralNamespace, Bytes) -> Unit,
  encode_ephemeral~ : (@wire.EphemeralNamespace) -> Bytes,
  on_peer_leave~ : (String) -> Unit,
) -> SyncHost {
  {
    io,
    apply_sync,
    export_all,
    export_since,
    apply_ephemeral,
    encode_ephemeral,
    on_peer_leave,
  }
}

///|
/// Sync-side state previously held directly on SyncEditor.
pub struct SyncSession {
  priv mut recovery : RecoveryContext?
  priv mut recovery_epoch : Int
  priv mut status : SyncStatus
  priv mut on_status_change : ((SyncStatus) -> Unit)?
  priv mut watchdog_scheduler : ((Int, Int) -> Unit)?
  priv mut watchdog_timeout_ms : Int
}

///|
pub fn SyncSession::SyncSession() -> SyncSession {
  {
    recovery: None,
    recovery_epoch: 0,
    status: SyncStatus::Disconnected,
    on_status_change: None,
    watchdog_scheduler: None,
    watchdog_timeout_ms: DEFAULT_WATCHDOG_MS,
  }
}

// ── Status API ───────────────────────────────────────────────────────────

///|
/// Get the current sync status.
pub fn SyncSession::get_status(self : SyncSession) -> SyncStatus {
  self.status
}

///|
/// Register a callback that fires on every distinct status transition.
/// Setting again replaces the previous callback. Pass `None` to disable.
pub fn SyncSession::set_on_status_change(
  self : SyncSession,
  callback : ((SyncStatus) -> Unit)?,
) -> Unit {
  self.on_status_change = callback
}

///|
/// Register a watchdog scheduler. The session calls
/// `scheduler(request_id, timeout_ms)` after each SyncRequest send.
/// `timeout_ms` is the current value of `watchdog_timeout_ms` at send time,
/// so calling `set_watchdog_timeout` takes effect on the next send.
pub fn SyncSession::set_watchdog_scheduler(
  self : SyncSession,
  scheduler : ((Int, Int) -> Unit)?,
) -> Unit {
  self.watchdog_scheduler = scheduler
}

///|
/// Set the watchdog timeout in milliseconds. Default is 5000ms.
pub fn SyncSession::set_watchdog_timeout(self : SyncSession, ms : Int) -> Unit {
  self.watchdog_timeout_ms = ms
}

///|
/// Internal: transition to a new status, emitting callback only on change.
fn SyncSession::set_status(self : SyncSession, new_status : SyncStatus) -> Unit {
  if self.status == new_status {
    return
  }
  self.status = new_status
  if self.on_status_change is Some(cb) {
    cb(new_status)
  }
}

///|
/// A sync message applied successfully outside the dispatch path. Clears a
/// prior Error status — another peer (via RelayedCrdtOps) having filled the
/// causal gap counts as recovery.
pub fn SyncSession::note_sync_applied(self : SyncSession) -> Unit {
  if self.status is Error(_) {
    self.set_status(Idle)
  }
}

// ── Connection lifecycle ─────────────────────────────────────────────────

///|
/// Called when the transport connects.
pub fn SyncSession::on_open(self : SyncSession) -> Unit {
  self.set_status(Idle)
}

///|
/// Called when the transport disconnects. Clears recovery state.
pub fn SyncSession::on_close(self : SyncSession) -> Unit {
  self.recovery = None
  self.set_status(Disconnected)
}

///|
/// Called by the host when the watchdog timer fires. The `request_id` is
/// compared against the current recovery epoch to detect and discard stale
/// firings (e.g. response already arrived).
pub fn SyncSession::on_watchdog_fire(
  self : SyncSession,
  request_id : Int,
  io : SyncIo,
) -> Unit {
  guard self.recovery is Some(ctx) else { return }
  guard ctx.matches_request_id(request_id.to_string()) else { return }
  self.handle_recovery_retry(io)
}

// ── Message dispatch ─────────────────────────────────────────────────────

///|
pub fn SyncSession::on_message(
  self : SyncSession,
  data : Bytes,
  host : SyncHost,
) -> Unit {
  guard @wire.decode_message_result(data) is Ok(msg) else { return }
  match msg {
    CrdtOps(payload) => {
      // CrdtOps is used for backwards-compatible full-state exchange (PeerJoined).
      // Recovery is not possible here because there is no sender ID.
      // Once all peers use RelayedCrdtOps, this path only handles PeerJoined sync.
      guard parse_sync_message_json(payload) is Ok(crdt_msg) else { return }
      (host.apply_sync)(crdt_msg) catch {
        _ => ()
      }
    }
    EphemeralUpdate(ns, payload) => (host.apply_ephemeral)(ns, payload)
    PeerJoined(_peer_id) => {
      // Send full ephemeral state for catch-up
      for ns in @wire.all_namespaces() {
        let ns_data = (host.encode_ephemeral)(ns)
        if ns_data.length() > 0 {
          (host.io.send)(@wire.encode_message(EphemeralUpdate(ns, ns_data)))
        }
      }
      // Send full CRDT state
      let crdt_msg = (host.export_all)() catch { _ => return }
      let json_str = crdt_msg.to_json_string()
      let buf = Buffer()
      buf.write_string_utf16le(json_str.view())
      (host.io.send)(@wire.encode_message(CrdtOps(buf.to_bytes())))
    }
    PeerLeft(peer_id) => {
      (host.on_peer_leave)(peer_id)
      // Abort recovery if the leaving peer is the one we're recovering from
      if self.recovery is Some(ctx) && ctx.peer_id == peer_id {
        let target = ctx.peer_id
        self.recovery = None
        self.set_status(Error(reason=TargetLeft(peer_id=target)))
      }
    }
    SyncRequest(payload) => {
      guard parse_sync_request_payload(payload)
        is Ok((sender, request_id, version_json)) else {
        return
      }
      // Parse requester's version and export delta
      let peer_version = @text.Version::from_json_string(version_json) catch {
        _ => {
          self.send_empty_sync_response(sender, request_id, host.io)
          return
        }
      }
      let delta = (host.export_since)(peer_version) catch {
        _ => {
          self.send_empty_sync_response(sender, request_id, host.io)
          return
        }
      }
      let sync_json = delta.to_json_string()
      // Cap response size at 1MB
      if sync_json.length() > 1_000_000 {
        self.send_empty_sync_response(sender, request_id, host.io)
        return
      }
      let wire = @wire.encode_sync_response(
        target=sender,
        request_id~,
        sync_json~,
      )
      (host.io.send)(wire)
    }
    SyncResponse(payload) => {
      guard parse_sync_response_payload(payload)
        is Ok((_sender, request_id, sync_json)) else {
        return
      }
      guard self.recovery is Some(ctx) else { // Not recovering, ignore
        return
      }
      // Stale response check
      if !ctx.matches_request_id(request_id) {
        return
      }
      // Empty response = responder can't help
      if sync_json == "" {
        self.handle_recovery_retry(host.io)
        return
      }
      // Apply the delta
      let delta = @text.SyncMessage::from_json_string(sync_json) catch {
        _ => {
          self.handle_recovery_retry(host.io)
          return
        }
      }
      (host.apply_sync)(delta) catch {
        _ => {
          // Delta failed — partial state possible, retry recovery
          self.handle_recovery_retry(host.io)
          return
        }
      }
      // Retry the original pending message
      (host.apply_sync)(ctx.pending_msg) catch {
        _ => {
          // Re-export version for next retry (delta may have advanced our state)
          self.handle_recovery_retry(host.io)
          return
        }
      }
      // Success! Drain deferred messages
      let deferred = ctx.deferred
      self.recovery = None
      for i, msg in deferred {
        (host.apply_sync)(msg) catch {
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
              for j in (i + 1)..<deferred.length() {
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
              self.send_sync_request(ctx.peer_id, self.recovery_epoch, host.io)
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
      guard parse_sync_message_json(payload) is Ok(crdt_msg) else { return }
      // If recovering from this sender, buffer instead of applying
      if self.recovery is Some(ctx) && ctx.peer_id == sender {
        ctx.buffer_message(crdt_msg)
        return
      }
      (host.apply_sync)(crdt_msg) catch {
        err =>
          if should_retry_sync_error(err) {
            self.enter_recovery(sender, crdt_msg, host.io)
          }
      }
    }
  }
}

// ── Recovery driver ──────────────────────────────────────────────────────

///|
/// Send an empty SyncResponse (responder can't satisfy the request).
fn SyncSession::send_empty_sync_response(
  self : SyncSession,
  target : String,
  request_id : String,
  io : SyncIo,
) -> Unit {
  ignore(self)
  (io.send)(@wire.encode_sync_response(target~, request_id~, sync_json=""))
}

///|
/// Enter recovery mode for a specific peer. Sends SyncRequest.
fn SyncSession::enter_recovery(
  self : SyncSession,
  peer_id : String,
  failed_msg : @text.SyncMessage,
  io : SyncIo,
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
  self.send_sync_request(peer_id, request_id, io)
}

///|
/// Send a SyncRequest to a specific peer via the relay.
/// Always uses the current version (not stale from recovery entry).
fn SyncSession::send_sync_request(
  self : SyncSession,
  target : String,
  request_id : Int,
  io : SyncIo,
) -> Unit {
  let version_json = (io.current_version)().to_json_string()
  let wire = @wire.encode_sync_request(
    target~,
    request_id=request_id.to_string(),
    version_json~,
  )
  (io.send)(wire)
  // Arm the watchdog for this request; timeout is read fresh so
  // set_watchdog_timeout takes effect on subsequent sends.
  if self.watchdog_scheduler is Some(scheduler) {
    scheduler(request_id, self.watchdog_timeout_ms)
  }
}

///|
/// Handle a failed recovery retry: send another request or give up.
/// Check exhaustion BEFORE advancing so retries=0,1,2 each send a request
/// and retries=3 gives up (3 retries total).
fn SyncSession::handle_recovery_retry(self : SyncSession, io : SyncIo) -> Unit {
  guard self.recovery is Some(ctx) else { return }
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
  self.send_sync_request(ctx.peer_id, self.recovery_epoch, io)
}
