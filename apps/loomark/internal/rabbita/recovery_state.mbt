///|
/// Runtime health of the mutable editor session. LocalText owns standalone Raw
/// editing without constructing CRDT state. RawRecovery is terminal for this
/// mount: the user must explicitly reload before another editor exists.
priv enum EditorRuntimeState {
  Healthy
  LocalText(String)
  Restarting
  RawRecovery(String)
} derive(Eq)

///|
/// Events produced by the imperative recovery shell.
priv enum EditorRecoveryEvent {
  Failure
  ReconstructionSucceeded
  ReconstructionFailed(String)
}

///|
/// Pure decisions returned by the runtime-state reducer.
priv enum EditorRecoveryDecision {
  Reconstruct
  Continue
  Reject
}

///|
/// Reduce one recovery event without touching the editor, DOM, or storage.
/// There is deliberately no transition out of RawRecovery: it cannot retry
/// the failed parser or reconstruct a second session.
fn reduce_editor_runtime(
  state : EditorRuntimeState,
  event : EditorRecoveryEvent,
) -> (EditorRuntimeState, EditorRecoveryDecision) {
  match (state, event) {
    (Healthy, EditorRecoveryEvent::Failure) =>
      (EditorRuntimeState::Restarting, EditorRecoveryDecision::Reconstruct)
    (Restarting, EditorRecoveryEvent::ReconstructionSucceeded) =>
      (EditorRuntimeState::Healthy, EditorRecoveryDecision::Continue)
    (Restarting, EditorRecoveryEvent::ReconstructionFailed(source)) =>
      (
        EditorRuntimeState::RawRecovery(source),
        EditorRecoveryDecision::Continue,
      )
    (Restarting, EditorRecoveryEvent::Failure) =>
      (EditorRuntimeState::RawRecovery(""), EditorRecoveryDecision::Continue)
    (LocalText(source), _) =>
      (EditorRuntimeState::LocalText(source), EditorRecoveryDecision::Reject)
    (RawRecovery(source), _) =>
      (EditorRuntimeState::RawRecovery(source), EditorRecoveryDecision::Reject)
    _ => (state, EditorRecoveryDecision::Reject)
  }
}
