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
/// Stub Show — currently a Debug dump. Cluster awaiting Collaboration panel
/// adoption (see docs/TODO.md §9 "Inspector — Collaboration panel"): the
/// following 11 types share this pattern and all need real short-label Show
/// impls when the panel is built — SyncStatus, SyncErrorReason, SyncMessage
/// (this file + sync_protocol.mbt); PeerCursor (cursor_view.mbt);
/// PeerPresence, PresenceStatus, DragState, EditModeState (presence_types.mbt);
/// EphemeralValue, EphemeralEventTrigger (ephemeral.mbt); EphemeralNamespace
/// (ephemeral_hub.mbt). Per the §15 Show-unification workstream pattern, real
/// impls should produce short structural labels (e.g. SyncStatus →
/// `"connected"`, PeerPresence → `"alice (editing)"`).
pub impl Show for SyncStatus with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for SyncErrorReason with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
