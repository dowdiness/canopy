///|
test "editor recovery state starts one reconstruction" {
  let (state, decision) = reduce_editor_runtime(
    EditorRuntimeState::Healthy,
    EditorRecoveryEvent::Failure,
  )
  match state {
    EditorRuntimeState::Restarting => ()
    _ => fail("expected Restarting")
  }
  match decision {
    EditorRecoveryDecision::Reconstruct => ()
    _ => fail("expected one reconstruction")
  }
}

///|
test "successful reconstruction returns to healthy editing" {
  let (state, decision) = reduce_editor_runtime(
    EditorRuntimeState::Restarting,
    EditorRecoveryEvent::ReconstructionSucceeded,
  )
  match state {
    EditorRuntimeState::Healthy => ()
    _ => fail("expected Healthy")
  }
  match decision {
    EditorRecoveryDecision::Continue => ()
    _ => fail("expected continuation")
  }
}

///|
test "failed reconstruction enters terminal raw recovery" {
  let (state, decision) = reduce_editor_runtime(
    EditorRuntimeState::Restarting,
    EditorRecoveryEvent::ReconstructionFailed("accepted"),
  )
  match state {
    EditorRuntimeState::RawRecovery(source) => assert_eq(source, "accepted")
    _ => fail("expected RawRecovery")
  }
  match decision {
    EditorRecoveryDecision::Continue => ()
    _ => fail("expected terminal continuation")
  }
}

///|
test "raw recovery never retries or leaves the terminal state" {
  let (after_failure, failure_decision) = reduce_editor_runtime(
    EditorRuntimeState::RawRecovery("accepted"),
    EditorRecoveryEvent::Failure,
  )
  let (after_success, success_decision) = reduce_editor_runtime(
    EditorRuntimeState::RawRecovery("accepted"),
    EditorRecoveryEvent::ReconstructionSucceeded,
  )
  match (after_failure, after_success) {
    (
      EditorRuntimeState::RawRecovery(first),
      EditorRuntimeState::RawRecovery(second),
    ) => {
      assert_eq(first, "accepted")
      assert_eq(second, "accepted")
    }
    _ => fail("expected terminal RawRecovery")
  }
  match (failure_decision, success_decision) {
    (EditorRecoveryDecision::Reject, EditorRecoveryDecision::Reject) => ()
    _ => fail("expected both events to be rejected")
  }
}
