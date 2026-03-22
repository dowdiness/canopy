// Recovery state machine for WebSocket sync recovery.

///|
/// Maximum number of deferred messages buffered during recovery.
let max_deferred : Int = 32

///|
/// Maximum number of retry attempts before giving up.
let max_retries : Int = 3

///|
/// Initial backoff delay in milliseconds.
let initial_backoff_ms : Int = 500

///|
/// Per-peer recovery state. Tracks the failed message, retry count,
/// backoff timing, and buffered messages from the recovering peer.
struct RecoveryContext {
  peer_id : String
  pending_msg : @text.SyncMessage
  deferred : Array[@text.SyncMessage]
  mut retries : Int
  mut backoff_ms : Int
  mut request_id : Int
}

///|
fn RecoveryContext::new(
  peer_id : String,
  pending_msg : @text.SyncMessage,
  request_id : Int,
) -> RecoveryContext {
  {
    peer_id,
    pending_msg,
    deferred: [],
    retries: 0,
    backoff_ms: initial_backoff_ms,
    request_id,
  }
}

///|
/// Advance to the next retry: increment counter, double backoff, update request_id.
fn RecoveryContext::advance_retry(
  self : RecoveryContext,
  new_request_id : Int,
) -> Unit {
  self.retries += 1
  self.backoff_ms *= 2
  self.request_id = new_request_id
}

///|
fn RecoveryContext::is_exhausted(self : RecoveryContext) -> Bool {
  self.retries >= max_retries
}

///|
/// Buffer a message from the recovering peer. Drops oldest if at capacity.
fn RecoveryContext::buffer_message(
  self : RecoveryContext,
  msg : @text.SyncMessage,
) -> Unit {
  if self.deferred.length() >= max_deferred {
    self.deferred.remove(0) |> ignore
  }
  self.deferred.push(msg)
}

///|
/// Convert request_id to wire format string for encode_sync_request/response.
fn RecoveryContext::request_id_string(self : RecoveryContext) -> String {
  self.request_id.to_string()
}

///|
fn RecoveryContext::matches_request_id(
  self : RecoveryContext,
  id : String,
) -> Bool {
  self.request_id.to_string() == id
}
