// Whitebox tests for SyncStatus state machine and watchdog behaviour.

///|
/// Test helper: construct an empty SyncMessage or fail the current test.
/// Parse errors here would only indicate a broken fixture, never a bug
/// under test, so we surface them as test failures instead of making
/// every caller repeat the `catch { _ => { fail(..); return } }` dance.
fn empty_msg_or_fail() -> @text.SyncMessage raise {
  @text.SyncMessage::from_json_string("{\"runs\":[],\"heads\":[]}") catch {
    _ => fail("failed to construct empty SyncMessage fixture")
  }
}

// SyncStatus Show

///|
test "SyncStatus: Show impl" {
  inspect(SyncStatus::Disconnected, content="Disconnected")
  inspect(SyncStatus::Idle, content="Idle")
  inspect(
    SyncStatus::Recovering(peer_id="alice", attempt=2),
    content=(
      #|Recovering(peer_id="alice", attempt=2)
    ),
  )
  inspect(
    SyncStatus::Error(reason=Exhausted(peer_id="bob")),
    content=(
      #|Error(reason=Exhausted(peer_id="bob"))
    ),
  )
  inspect(
    SyncStatus::Error(reason=TargetLeft(peer_id="carol")),
    content=(
      #|Error(reason=TargetLeft(peer_id="carol"))
    ),
  )
}

// Initial status and ws_on_open / ws_on_close transitions

///|
test "SyncStatus: initial status is Disconnected" {
  let editor = @lambda.new_lambda_editor("alice").0
  inspect(editor.get_sync_status(), content="Disconnected")
}

///|
test "SyncStatus: ws_on_open transitions to Idle" {
  let editor = @lambda.new_lambda_editor("alice").0
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  inspect(editor.get_sync_status(), content="Idle")
}

///|
test "SyncStatus: ws_on_close transitions to Disconnected" {
  let editor = @lambda.new_lambda_editor("alice").0
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  editor.ws_on_close()
  inspect(editor.get_sync_status(), content="Disconnected")
}

// on_status_change callback fires on transitions, not on no-ops

///|
test "SyncStatus: callback fires on transition" {
  let editor = @lambda.new_lambda_editor("alice").0
  let fired : Array[SyncStatus] = []
  editor.set_on_status_change(Some(fn(s) { fired.push(s) }))
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  inspect(fired.length(), content="1")
  inspect(fired[0], content="Idle")
  editor.ws_on_close()
  inspect(fired.length(), content="2")
  inspect(fired[1], content="Disconnected")
}

///|
test "SyncStatus: equality guard suppresses no-op transitions" {
  let editor = @lambda.new_lambda_editor("alice").0
  let fired : Array[SyncStatus] = []
  editor.set_on_status_change(Some(fn(s) { fired.push(s) }))
  // ws_on_close when already Disconnected → no emission
  editor.ws_on_close()
  inspect(fired.length(), content="0")
  // ws_on_open → Idle
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  inspect(fired.length(), content="1")
  // ws_on_open again → already Idle, no emission
  editor.ws_on_open(ws)
  inspect(fired.length(), content="1")
}

///|
test "SyncStatus: removing callback disables notifications" {
  let editor = @lambda.new_lambda_editor("alice").0
  let fired : Array[SyncStatus] = []
  editor.set_on_status_change(Some(fn(s) { fired.push(s) }))
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  inspect(fired.length(), content="1")
  // Deregister
  editor.set_on_status_change(None)
  editor.ws_on_close()
  inspect(fired.length(), content="1") // no new firing
}

// PeerLeft during recovery → Error(TargetLeft)

///|
test "SyncStatus: PeerLeft during recovery → Error(TargetLeft)" {
  let editor = @lambda.new_lambda_editor("bob").0
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  let empty_msg = empty_msg_or_fail()
  editor.recovery_epoch = 1
  editor.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  editor.set_status(Recovering(peer_id="alice", attempt=1))
  let wire = encode_message(PeerLeft("alice"))
  editor.ws_on_message(wire)
  inspect(editor.recovery is None, content="true")
  inspect(
    editor.get_sync_status(),
    content=(
      #|Error(reason=TargetLeft(peer_id="alice"))
    ),
  )
}

///|
test "SyncStatus: PeerLeft for different peer does not change status" {
  let editor = @lambda.new_lambda_editor("bob").0
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  let empty_msg = empty_msg_or_fail()
  editor.recovery_epoch = 1
  editor.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  editor.set_status(Recovering(peer_id="alice", attempt=1))
  let wire = encode_message(PeerLeft("charlie"))
  editor.ws_on_message(wire)
  inspect(editor.recovery is Some(_), content="true")
  inspect(
    editor.get_sync_status(),
    content=(
      #|Recovering(peer_id="alice", attempt=1)
    ),
  )
}

// Watchdog: stale request_id is ignored

///|
test "SyncStatus: stale watchdog ignored" {
  let editor = @lambda.new_lambda_editor("bob").0
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  let empty_msg = empty_msg_or_fail()
  editor.recovery_epoch = 5
  editor.recovery = Some(RecoveryContext::new("alice", empty_msg, 5))
  editor.set_status(Recovering(peer_id="alice", attempt=1))
  // Fire watchdog with stale request_id 3 (current epoch is 5)
  editor.on_watchdog_fire(3)
  // Status and recovery state should be unchanged
  inspect(
    editor.get_sync_status(),
    content=(
      #|Recovering(peer_id="alice", attempt=1)
    ),
  )
  inspect(editor.recovery is Some(_), content="true")
  inspect(editor.recovery.unwrap().retries, content="0")
}

///|
test "SyncStatus: watchdog for prior epoch is ignored after response-driven retry" {
  // End-to-end stale path: recovery is in progress on request_id=1, an
  // empty SyncResponse for id=1 arrives (triggering retry → epoch bumps
  // to 2), then the now-stale watchdog for id=1 fires. The editor must
  // not double-retry, and the status must stay on Recovering(..,2).
  let editor = @lambda.new_lambda_editor("bob").0
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  let empty_msg = empty_msg_or_fail()
  // Disable scheduler — we're driving watchdog fires manually.
  editor.set_watchdog_scheduler(None)
  editor.recovery_epoch = 1
  editor.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  editor.set_status(Recovering(peer_id="alice", attempt=1))
  // Inject an empty SyncResponse for the current epoch → triggers retry.
  let response_wire = encode_sync_response(
    target="alice",
    request_id="1",
    sync_json="",
  )
  editor.ws_on_message(response_wire)
  // The retry path bumped the epoch and advanced attempt.
  inspect(editor.recovery_epoch, content="2")
  let after_response = editor.recovery.unwrap()
  inspect(after_response.retries, content="1")
  inspect(
    editor.get_sync_status(),
    content=(
      #|Recovering(peer_id="alice", attempt=2)
    ),
  )
  // Now the old watchdog for id=1 fires — must be a no-op.
  editor.on_watchdog_fire(1)
  let after_stale = editor.recovery.unwrap()
  inspect(after_stale.retries, content="1") // unchanged
  inspect(editor.recovery_epoch, content="2") // unchanged
  inspect(
    editor.get_sync_status(),
    content=(
      #|Recovering(peer_id="alice", attempt=2)
    ),
  ) // unchanged
}

///|
test "SyncStatus: watchdog when no recovery does nothing" {
  let editor = @lambda.new_lambda_editor("bob").0
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  // No recovery in progress
  editor.on_watchdog_fire(99)
  inspect(editor.get_sync_status(), content="Idle")
}

// Watchdog: triggers retry and advances status

///|
test "SyncStatus: watchdog fire triggers retry" {
  let editor = @lambda.new_lambda_editor("bob").0
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  let empty_msg = empty_msg_or_fail()
  editor.recovery_epoch = 1
  editor.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  editor.set_status(Recovering(peer_id="alice", attempt=1))
  // Disable watchdog scheduler to avoid infinite re-arms during test
  editor.set_watchdog_scheduler(None)
  // Fire watchdog for the current request_id
  editor.on_watchdog_fire(1)
  // Should have advanced retries
  let recovery = editor.recovery.unwrap()
  inspect(recovery.retries, content="1")
  // Status should show attempt 2
  inspect(
    editor.get_sync_status(),
    content=(
      #|Recovering(peer_id="alice", attempt=2)
    ),
  )
}

// Watchdog: exhaustion surfaces Error(Exhausted)

///|
test "SyncStatus: watchdog exhaustion → Error(Exhausted)" {
  let editor = @lambda.new_lambda_editor("bob").0
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  let empty_msg = empty_msg_or_fail()
  // Disable scheduler to prevent infinite re-arms during test
  editor.set_watchdog_scheduler(None)
  editor.recovery_epoch = 1
  let ctx = RecoveryContext::new("alice", empty_msg, 1)
  editor.recovery = Some(ctx)
  editor.set_status(Recovering(peer_id="alice", attempt=1))
  // Four watchdog fires total are needed to exhaust: the initial
  // recovery attempt plus `max_retries_after_initial` (3) retries.
  // Fires 1-3 advance retries 0→1, 1→2, 2→3. Fire 4 sees retries=3
  // and hits the is_exhausted() branch.
  // After each fire we pass the current recovery_epoch so the
  // stale-check in on_watchdog_fire matches.
  editor.on_watchdog_fire(1) // retries 0 → advances to 1 (epoch bumps to 2)
  inspect(editor.recovery is Some(_), content="true")
  editor.on_watchdog_fire(editor.recovery_epoch) // retries 1 → advances to 2 (epoch → 3)
  inspect(editor.recovery is Some(_), content="true")
  editor.on_watchdog_fire(editor.recovery_epoch) // retries 2 → advances to 3 (epoch → 4)
  inspect(editor.recovery is Some(_), content="true")
  editor.on_watchdog_fire(editor.recovery_epoch) // retries 3 → exhausted, clears
  inspect(editor.recovery is None, content="true")
  inspect(
    editor.get_sync_status(),
    content=(
      #|Error(reason=Exhausted(peer_id="alice"))
    ),
  )
}

// Error → Idle: auto-clear on successful apply_sync

///|
test "SyncStatus: Error → Idle on successful apply_sync" {
  let editor_a = @lambda.new_lambda_editor("alice").0
  let editor_b = @lambda.new_lambda_editor("bob").0
  let ws = make_test_ws()
  editor_b.ws_on_open(ws)
  // Manually force editor_b into Error state
  editor_b.set_status(SyncStatus::Error(reason=Exhausted(peer_id="carol")))
  inspect(
    editor_b.get_sync_status(),
    content=(
      #|Error(reason=Exhausted(peer_id="carol"))
    ),
  )
  // Alice writes something and bob applies it successfully
  editor_a.set_text("hello from alice")
  let crdt_msg = editor_a.export_all() catch {
    _ => {
      fail("export failed")
      return
    }
  }
  editor_b.apply_sync(crdt_msg) catch {
    _ => fail("apply_sync failed")
  }
  // Should auto-clear to Idle
  inspect(editor_b.get_sync_status(), content="Idle")
}

///|
test "SyncStatus: failed apply_sync leaves Error status intact" {
  // Construct a SyncMessage whose parent causal frontier is unknown to the
  // receiving editor: two sequential edits on editor A, export only the
  // second delta (since version-after-first), then apply to a fresh
  // editor B. The delta carries a parent that B doesn't know, so
  // apply_sync raises TextError::SyncFailed(MissingDependency) and the
  // Error → Idle auto-clear must NOT fire.
  let editor_a = @lambda.new_lambda_editor("alice").0
  let editor_b = @lambda.new_lambda_editor("bob").0
  let ws = make_test_ws()
  editor_b.ws_on_open(ws)
  // First edit — captures a baseline version.
  editor_a.set_text("first")
  let version_after_first = editor_a.get_version()
  // Second edit — its delta parents on version_after_first.
  editor_a.set_text("first-second")
  let orphan_delta = editor_a.export_since(version_after_first) catch {
    _ => {
      fail("export_since failed")
      return
    }
  }
  // Force editor_b into Error state.
  editor_b.set_status(SyncStatus::Error(reason=Exhausted(peer_id="alice")))
  // Apply the orphan delta — must raise TextError::SyncFailed with
  // SyncFailure::MissingDependency specifically. Any other exception
  // (or no exception) would mean the test isn't exercising what it claims.
  let mut raised_missing_dep = false
  editor_b.apply_sync(orphan_delta) catch {
    @text.TextError::SyncFailed(@text.SyncFailure::MissingDependency(..)) =>
      raised_missing_dep = true
    other => fail("expected MissingDependency, got: \{other}")
  }
  inspect(raised_missing_dep, content="true")
  // Error must persist — the catch branch in apply_sync must not hit the
  // auto-clear tail.
  inspect(
    editor_b.get_sync_status(),
    content=(
      #|Error(reason=Exhausted(peer_id="alice"))
    ),
  )
}

// Watchdog scheduler: recorded call with request_id

///|
test "SyncStatus: watchdog scheduler receives request_id and timeout on send" {
  let editor = @lambda.new_lambda_editor("alice").0
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  let scheduled : Array[(Int, Int)] = []
  editor.set_watchdog_scheduler(
    Some(fn(req_id, ms) { scheduled.push((req_id, ms)) }),
  )
  editor.set_watchdog_timeout(1234) // non-default so we can assert plumbing
  let empty_msg = empty_msg_or_fail()
  editor.recovery_epoch = 1
  editor.recovery = Some(RecoveryContext::new("bob", empty_msg, 1))
  // handle_recovery_retry bumps recovery_epoch to 2 before sending.
  editor.handle_recovery_retry()
  // Exactly one send, with the new epoch (2) and the current timeout (1234).
  inspect(scheduled.length(), content="1")
  inspect(scheduled[0].0, content="2")
  inspect(scheduled[0].1, content="1234")
  // After bumping the timeout and triggering another retry, the next call
  // should reflect the new value — set_watchdog_timeout must not be dead.
  editor.set_watchdog_timeout(777)
  editor.handle_recovery_retry()
  inspect(scheduled.length(), content="2")
  inspect(scheduled[1].1, content="777")
}
