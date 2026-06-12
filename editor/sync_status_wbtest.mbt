// Whitebox tests for SyncEditor's sync-status surface: lifecycle
// transitions, callback plumbing, and the apply_sync ↔ session interaction.
// The recovery/watchdog state-machine tests moved to
// sync_session/session_wbtest.mbt in redesign S2; the tests here drive only
// the public SyncEditor surface.

///|
/// Force the editor into Error(Exhausted) through the public surface:
/// an orphan RelayedCrdtOps delta (parent unknown to the receiver) raises
/// MissingDependency → enter_recovery, then four manual watchdog fires
/// exhaust the three retries. Epochs are deterministic from a fresh
/// editor: enter_recovery → 1, each retry bumps by one.
fn[T : Eq] force_error_exhausted(
  editor : SyncEditor[T],
  feeder : SyncEditor[T],
) -> Unit raise {
  editor.set_watchdog_scheduler(None)
  // Build an orphan delta on the feeder: second edit exported since the
  // version after the first edit.
  feeder.set_text("first")
  let version_after_first = feeder.get_version()
  feeder.set_text("first-second")
  let orphan_delta = feeder.export_since(version_after_first)
  let buf = Buffer()
  buf.write_string_utf16le(orphan_delta.to_json_string().view())
  editor.ws_on_message(encode_relayed_crdt_ops("alice", buf.to_bytes()))
  // Recovery is now active on epoch 1; exhaust it.
  editor.on_watchdog_fire(1)
  editor.on_watchdog_fire(2)
  editor.on_watchdog_fire(3)
  editor.on_watchdog_fire(4)
}

// Initial status and ws_on_open / ws_on_close transitions

///|
test "SyncStatus: initial status is Disconnected" {
  let editor = @probe.new_test_editor("alice")
  inspect(editor.get_sync_status(), content="Disconnected")
}

///|
test "SyncStatus: ws_on_open transitions to Idle" {
  let editor = @probe.new_test_editor("alice")
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  inspect(editor.get_sync_status(), content="Idle")
}

///|
test "SyncStatus: ws_on_close transitions to Disconnected" {
  let editor = @probe.new_test_editor("alice")
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  editor.ws_on_close()
  inspect(editor.get_sync_status(), content="Disconnected")
}

// on_status_change callback fires on transitions, not on no-ops

///|
test "SyncStatus: callback fires on transition" {
  let editor = @probe.new_test_editor("alice")
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
  let editor = @probe.new_test_editor("alice")
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
  let editor = @probe.new_test_editor("alice")
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

// Error → Idle: auto-clear on successful apply_sync

///|
test "SyncStatus: Error → Idle on successful apply_sync" {
  let editor_a = @probe.new_test_editor("alice")
  let editor_b = @probe.new_test_editor("bob")
  let ws = make_test_ws()
  editor_b.ws_on_open(ws)
  // Drive editor_b into Error state through the public surface.
  force_error_exhausted(editor_b, editor_a)
  inspect(
    editor_b.get_sync_status(),
    content=(
      #|Error(reason=Exhausted(peer_id="alice"))
    ),
  )
  // Alice's full state syncs successfully into bob
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
  // Apply a SyncMessage whose parent causal frontier is unknown to the
  // receiving editor: apply_sync raises
  // TextError::SyncFailed(MissingDependency) and the Error → Idle
  // auto-clear must NOT fire.
  let editor_a = @probe.new_test_editor("alice")
  let editor_b = @probe.new_test_editor("bob")
  let ws = make_test_ws()
  editor_b.ws_on_open(ws)
  // Drive editor_b into Error state through the public surface.
  force_error_exhausted(editor_b, editor_a)
  // Build a fresh orphan delta — editor_b still lacks the parent.
  editor_a.set_text("first-second-third")
  let version_before = editor_a.get_version()
  editor_a.set_text("first-second-third-fourth")
  let orphan_delta = editor_a.export_since(version_before) catch {
    _ => {
      fail("export_since failed")
      return
    }
  }
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

// Watchdog scheduler plumbing through the editor surface

///|
test "SyncStatus: watchdog scheduler receives request_id and timeout on send" {
  let editor_a = @probe.new_test_editor("alice")
  let editor = @probe.new_test_editor("bob")
  let ws = make_test_ws()
  editor.ws_on_open(ws)
  let scheduled : Array[(Int, Int)] = []
  editor.set_watchdog_scheduler(
    Some(fn(req_id, ms) { scheduled.push((req_id, ms)) }),
  )
  editor.set_watchdog_timeout(1234) // non-default so we can assert plumbing
  // Enter recovery through the public surface: orphan RelayedCrdtOps.
  editor_a.set_text("first")
  let version_after_first = editor_a.get_version()
  editor_a.set_text("first-second")
  let orphan_delta = editor_a.export_since(version_after_first) catch {
    _ => {
      fail("export_since failed")
      return
    }
  }
  let buf = Buffer()
  buf.write_string_utf16le(orphan_delta.to_json_string().view())
  editor.ws_on_message(encode_relayed_crdt_ops("alice", buf.to_bytes()))
  // enter_recovery sent the initial SyncRequest on epoch 1 with the
  // current timeout.
  inspect(scheduled.length(), content="1")
  inspect(scheduled[0].0, content="1")
  inspect(scheduled[0].1, content="1234")
  // After bumping the timeout, the next retry (watchdog fire) must
  // reflect the new value — set_watchdog_timeout must not be dead.
  editor.set_watchdog_timeout(777)
  editor.on_watchdog_fire(1)
  inspect(scheduled.length(), content="2")
  inspect(scheduled[1].0, content="2")
  inspect(scheduled[1].1, content="777")
}
