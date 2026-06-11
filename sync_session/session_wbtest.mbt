// Whitebox tests for the SyncSession state machine: recovery policy,
// watchdog staleness, and status transitions. Relocated from
// editor/sync_editor_ws_wbtest.mbt and editor/sync_status_wbtest.mbt in
// redesign S2 — these tests previously forced SyncEditor's private sync
// fields; they now drive SyncSession directly with fake SyncIo / SyncHost
// records.

///|
/// Test helper: construct an empty SyncMessage or fail the current test.
fn empty_msg_or_fail() -> @text.SyncMessage raise {
  @text.SyncMessage::from_json_string("{\"runs\":[],\"heads\":[]}") catch {
    _ => fail("failed to construct empty SyncMessage fixture")
  }
}

///|
/// Fake IO: records sent frames, serves a fresh empty version.
fn test_io(sent : Array[Bytes]) -> SyncIo {
  SyncIo(send=data => sent.push(data), current_version=() => {
    @text.TextState::new("io-peer").version()
  })
}

///|
/// Fake host whose document closures are inert: apply_sync succeeds,
/// exports return an empty SyncMessage, ephemeral payloads vanish.
/// `left` records on_peer_leave calls.
fn test_host(sent : Array[Bytes], left : Array[String]) -> SyncHost {
  SyncHost(
    io=test_io(sent),
    apply_sync=_ => (),
    export_all=() => empty_msg_or_fail(),
    export_since=_ => empty_msg_or_fail(),
    apply_ephemeral=(_, _) => (),
    encode_ephemeral=_ => Bytes::new(0),
    on_peer_leave=peer_id => left.push(peer_id),
  )
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

// Dispatch: recovery buffering and response staleness

///|
test "SyncSession: RelayedCrdtOps buffers during recovery" {
  let session = SyncSession()
  let empty_msg = empty_msg_or_fail()
  // Manually set recovery state for "alice"
  session.recovery_epoch = 1
  session.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  // Send RelayedCrdtOps from "alice" — should be buffered, not applied
  let buf = Buffer()
  buf.write_string_utf16le("{\"runs\":[],\"heads\":[]}".view())
  let wire = @wire.encode_relayed_crdt_ops("alice", buf.to_bytes())
  session.on_message(wire, test_host([], []))
  // Message should be buffered
  inspect(session.recovery.unwrap().deferred.length(), content="1")
}

///|
test "SyncSession: SyncResponse with stale request_id is ignored" {
  let session = SyncSession()
  let empty_msg = empty_msg_or_fail()
  session.recovery_epoch = 5
  session.recovery = Some(RecoveryContext::new("alice", empty_msg, 5))
  // SyncResponse with wrong request_id "3" (current is "5")
  let wire = @wire.encode_sync_response(
    target="alice",
    request_id="3",
    sync_json="",
  )
  session.on_message(wire, test_host([], []))
  // Recovery should still be active (response was ignored)
  inspect(session.recovery is Some(_), content="true")
  inspect(session.recovery.unwrap().retries, content="0") // no retry increment
}

///|
test "SyncSession: SyncResponse with empty delta increments retries" {
  let session = SyncSession()
  let empty_msg = empty_msg_or_fail()
  session.recovery_epoch = 1
  session.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  // SyncResponse with matching request_id but empty delta
  let wire = @wire.encode_sync_response(
    target="alice",
    request_id="1",
    sync_json="",
  )
  session.on_message(wire, test_host([], []))
  // Should have incremented retries
  inspect(session.recovery is Some(_), content="true")
  inspect(session.recovery.unwrap().retries, content="1")
}

///|
test "SyncSession: PeerLeft aborts recovery for that peer" {
  let session = SyncSession()
  let empty_msg = empty_msg_or_fail()
  session.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  let wire = @wire.encode_message(PeerLeft("alice"))
  let left : Array[String] = []
  session.on_message(wire, test_host([], left))
  inspect(session.recovery is None, content="true")
  // The leave is also routed to the host (hub cleanup on the editor side).
  inspect(left.length(), content="1")
  inspect(left[0], content="alice")
}

///|
test "SyncSession: PeerLeft for other peer does not abort recovery" {
  let session = SyncSession()
  let empty_msg = empty_msg_or_fail()
  session.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  let wire = @wire.encode_message(PeerLeft("charlie"))
  session.on_message(wire, test_host([], []))
  // Recovery for alice should still be active
  inspect(session.recovery is Some(_), content="true")
}

///|
test "SyncSession: on_close clears recovery state" {
  let session = SyncSession()
  let empty_msg = empty_msg_or_fail()
  session.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  session.on_close()
  inspect(session.recovery is None, content="true")
  inspect(session.get_status(), content="Disconnected")
}

// Status transitions around PeerLeft during recovery

///|
test "SyncSession: PeerLeft during recovery → Error(TargetLeft)" {
  let session = SyncSession()
  session.on_open()
  let empty_msg = empty_msg_or_fail()
  session.recovery_epoch = 1
  session.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  session.set_status(Recovering(peer_id="alice", attempt=1))
  let wire = @wire.encode_message(PeerLeft("alice"))
  session.on_message(wire, test_host([], []))
  inspect(session.recovery is None, content="true")
  inspect(
    session.get_status(),
    content=(
      #|Error(reason=TargetLeft(peer_id="alice"))
    ),
  )
}

///|
test "SyncSession: PeerLeft for different peer does not change status" {
  let session = SyncSession()
  session.on_open()
  let empty_msg = empty_msg_or_fail()
  session.recovery_epoch = 1
  session.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  session.set_status(Recovering(peer_id="alice", attempt=1))
  let wire = @wire.encode_message(PeerLeft("charlie"))
  session.on_message(wire, test_host([], []))
  inspect(session.recovery is Some(_), content="true")
  inspect(
    session.get_status(),
    content=(
      #|Recovering(peer_id="alice", attempt=1)
    ),
  )
}

// Watchdog: staleness, retry, exhaustion

///|
test "SyncSession: stale watchdog ignored" {
  let session = SyncSession()
  session.on_open()
  let empty_msg = empty_msg_or_fail()
  session.recovery_epoch = 5
  session.recovery = Some(RecoveryContext::new("alice", empty_msg, 5))
  session.set_status(Recovering(peer_id="alice", attempt=1))
  // Fire watchdog with stale request_id 3 (current epoch is 5)
  session.on_watchdog_fire(3, test_io([]))
  // Status and recovery state should be unchanged
  inspect(
    session.get_status(),
    content=(
      #|Recovering(peer_id="alice", attempt=1)
    ),
  )
  inspect(session.recovery is Some(_), content="true")
  inspect(session.recovery.unwrap().retries, content="0")
}

///|
test "SyncSession: watchdog for prior epoch is ignored after response-driven retry" {
  // End-to-end stale path: recovery is in progress on request_id=1, an
  // empty SyncResponse for id=1 arrives (triggering retry → epoch bumps
  // to 2), then the now-stale watchdog for id=1 fires. The session must
  // not double-retry, and the status must stay on Recovering(..,2).
  let session = SyncSession()
  session.on_open()
  let empty_msg = empty_msg_or_fail()
  // No scheduler — we're driving watchdog fires manually.
  session.set_watchdog_scheduler(None)
  session.recovery_epoch = 1
  session.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  session.set_status(Recovering(peer_id="alice", attempt=1))
  // Inject an empty SyncResponse for the current epoch → triggers retry.
  let response_wire = @wire.encode_sync_response(
    target="alice",
    request_id="1",
    sync_json="",
  )
  session.on_message(response_wire, test_host([], []))
  // The retry path bumped the epoch and advanced attempt.
  inspect(session.recovery_epoch, content="2")
  let after_response = session.recovery.unwrap()
  inspect(after_response.retries, content="1")
  inspect(
    session.get_status(),
    content=(
      #|Recovering(peer_id="alice", attempt=2)
    ),
  )
  // Now the old watchdog for id=1 fires — must be a no-op.
  session.on_watchdog_fire(1, test_io([]))
  let after_stale = session.recovery.unwrap()
  inspect(after_stale.retries, content="1") // unchanged
  inspect(session.recovery_epoch, content="2") // unchanged
  inspect(
    session.get_status(),
    content=(
      #|Recovering(peer_id="alice", attempt=2)
    ),
  ) // unchanged
}

///|
test "SyncSession: watchdog when no recovery does nothing" {
  let session = SyncSession()
  session.on_open()
  // No recovery in progress
  session.on_watchdog_fire(99, test_io([]))
  inspect(session.get_status(), content="Idle")
}

///|
test "SyncSession: watchdog fire triggers retry" {
  let session = SyncSession()
  session.on_open()
  let empty_msg = empty_msg_or_fail()
  session.recovery_epoch = 1
  session.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  session.set_status(Recovering(peer_id="alice", attempt=1))
  // No scheduler — avoid infinite re-arms during test
  session.set_watchdog_scheduler(None)
  // Fire watchdog for the current request_id
  let sent : Array[Bytes] = []
  session.on_watchdog_fire(1, test_io(sent))
  // The retry actually sent a SyncRequest frame
  inspect(sent.length(), content="1")
  // Should have advanced retries
  let recovery = session.recovery.unwrap()
  inspect(recovery.retries, content="1")
  // Status should show attempt 2
  inspect(
    session.get_status(),
    content=(
      #|Recovering(peer_id="alice", attempt=2)
    ),
  )
}

///|
test "SyncSession: watchdog exhaustion → Error(Exhausted)" {
  let session = SyncSession()
  session.on_open()
  let empty_msg = empty_msg_or_fail()
  // No scheduler — prevent infinite re-arms during test
  session.set_watchdog_scheduler(None)
  session.recovery_epoch = 1
  let ctx = RecoveryContext::new("alice", empty_msg, 1)
  session.recovery = Some(ctx)
  session.set_status(Recovering(peer_id="alice", attempt=1))
  // Four watchdog fires total are needed to exhaust: the initial
  // recovery attempt plus `max_retries_after_initial` (3) retries.
  // Fires 1-3 advance retries 0→1, 1→2, 2→3. Fire 4 sees retries=3
  // and hits the is_exhausted() branch.
  // After each fire we pass the current recovery_epoch so the
  // stale-check in on_watchdog_fire matches.
  let sent : Array[Bytes] = []
  let io = test_io(sent)
  session.on_watchdog_fire(1, io) // retries 0 → advances to 1 (epoch bumps to 2)
  inspect(session.recovery is Some(_), content="true")
  session.on_watchdog_fire(session.recovery_epoch, io) // retries 1 → advances to 2 (epoch → 3)
  inspect(session.recovery is Some(_), content="true")
  session.on_watchdog_fire(session.recovery_epoch, io) // retries 2 → advances to 3 (epoch → 4)
  inspect(session.recovery is Some(_), content="true")
  session.on_watchdog_fire(session.recovery_epoch, io) // retries 3 → exhausted, clears
  inspect(session.recovery is None, content="true")
  // Exactly three retry SyncRequests went out; the exhausted fire sends none.
  inspect(sent.length(), content="3")
  inspect(
    session.get_status(),
    content=(
      #|Error(reason=Exhausted(peer_id="alice"))
    ),
  )
}

// Watchdog scheduler: recorded call with request_id

///|
test "SyncSession: watchdog scheduler receives request_id and timeout on send" {
  let session = SyncSession()
  session.on_open()
  let scheduled : Array[(Int, Int)] = []
  session.set_watchdog_scheduler(
    Some(fn(req_id, ms) { scheduled.push((req_id, ms)) }),
  )
  session.set_watchdog_timeout(1234) // non-default so we can assert plumbing
  let empty_msg = empty_msg_or_fail()
  session.recovery_epoch = 1
  session.recovery = Some(RecoveryContext::new("bob", empty_msg, 1))
  // handle_recovery_retry bumps recovery_epoch to 2 before sending.
  session.handle_recovery_retry(test_io([]))
  // Exactly one send, with the new epoch (2) and the current timeout (1234).
  inspect(scheduled.length(), content="1")
  inspect(scheduled[0].0, content="2")
  inspect(scheduled[0].1, content="1234")
  // After bumping the timeout and triggering another retry, the next call
  // should reflect the new value — set_watchdog_timeout must not be dead.
  session.set_watchdog_timeout(777)
  session.handle_recovery_retry(test_io([]))
  inspect(scheduled.length(), content="2")
  inspect(scheduled[1].1, content="777")
}
