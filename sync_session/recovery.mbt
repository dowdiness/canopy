// Recovery state machine for WebSocket sync recovery.

///|
/// Maximum number of deferred messages buffered during recovery.
let max_deferred : Int = 32

///|
/// Maximum number of retries AFTER the initial SyncRequest before giving up.
/// With this set to 3, total wire sends per recovery attempt are 1 + 3 = 4
/// (one original request + three retries). Surfaces Error(Exhausted) after
/// the fourth handle_recovery_retry invocation.
let max_retries_after_initial : Int = 3

///|
/// Per-peer recovery state. Tracks the failed message, retry count,
/// and buffered messages from the recovering peer.
struct RecoveryContext {
  peer_id : String
  pending_msg : @text.SyncMessage
  deferred : Array[@text.SyncMessage]
  mut retries : Int
  mut request_id : Int
}

///|
fn RecoveryContext::new(
  peer_id : String,
  pending_msg : @text.SyncMessage,
  request_id : Int,
) -> RecoveryContext {
  { peer_id, pending_msg, deferred: [], retries: 0, request_id }
}

///|
/// Advance to the next retry: increment counter, update request_id.
fn RecoveryContext::advance_retry(
  self : RecoveryContext,
  new_request_id : Int,
) -> Unit {
  self.retries += 1
  self.request_id = new_request_id
}

///|
fn RecoveryContext::is_exhausted(self : RecoveryContext) -> Bool {
  self.retries >= max_retries_after_initial
}

///|
/// Buffer a message from the recovering peer. Drops oldest if at capacity.
/// Note: dropping messages can break convergence if the dropped message
/// contains causal history needed by later messages. The cap prevents
/// memory exhaustion from a flooding peer. In practice, recovery completes
/// within 3 retries (~3.5s) and 32 messages is generous for that window.
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
fn RecoveryContext::matches_request_id(
  self : RecoveryContext,
  id : String,
) -> Bool {
  self.request_id.to_string() == id
}
