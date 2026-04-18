// SyncStatus: observable state of the WebSocket sync recovery lifecycle.

///|
/// The current synchronization state of the editor's WebSocket connection.
/// Transitions are emitted via the on_status_change callback.
///
/// Contract: callbacks must not call back into SyncEditor synchronously —
/// re-entry could cause double emissions that the equality guard cannot absorb.
pub enum SyncStatus {
  /// No WebSocket connection established.
  Disconnected
  /// Connected and fully synchronized.
  Idle
  /// Actively recovering from a causal gap with a specific peer.
  Recovering(peer_id~ : String, attempt~ : Int)
  /// Recovery failed or aborted; last-known bad state.
  Error(reason~ : SyncErrorReason)
} derive(Debug, Eq)

///|
/// Reason for entering the Error state.
pub enum SyncErrorReason {
  /// All three retries were used with no successful response.
  Exhausted(peer_id~ : String)
  /// The target peer disconnected while recovery was in progress.
  TargetLeft(peer_id~ : String)
} derive(Debug, Eq)

///|
pub impl Show for SyncStatus with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for SyncErrorReason with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
