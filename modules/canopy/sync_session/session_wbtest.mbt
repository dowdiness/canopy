// Whitebox tests for the SyncSession state machine: recovery policy,
// watchdog staleness, and status transitions. Relocated from
// editor/sync_editor_ws_wbtest.mbt and editor/sync_status_wbtest.mbt in
// redesign S2 — these tests previously forced SyncEditor's private sync
// fields; they now drive SyncSession directly with fake SyncIo / SyncHost
// records.

///|
/// Test helper: construct an empty SyncMessage or fail the current test.
fn empty_msg_or_fail() -> @text.SyncMessage raise {
  let doc = @text.TextState::new("empty-message-fixture")
  doc.sync().export_all()
}

///|
/// Fake IO: records sent frames, serves a fresh empty version.
fn test_io(sent : Array[Bytes]) -> SyncIo {
  SyncIo(send=data => sent.push(data), current_version=() => {
    try! @text.TextState::new("io-peer").version()
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

// Retry classification

///|
test "SyncSession: retries only causal dependency failures" {
  debug_inspect(
    [
      should_retry_sync_error(
        @text.TextError::SyncFailed(
          @sync.Failure::MissingDependency(replica_id="peer", sequence=1),
        ),
      ),
      should_retry_sync_error(@text.TextError::VersionNotFound),
      should_retry_sync_error(
        @text.TextError::SyncFailed(
          @sync.Failure::MalformedMessage(detail="bad envelope"),
        ),
      ),
      should_retry_sync_error(
        @text.TextError::SyncFailed(
          @sync.Failure::InvalidContent(detail="bad content"),
        ),
      ),
      should_retry_sync_error(
        @text.TextError::SyncFailed(
          @sync.Failure::ConflictingIdentity(replica_id="peer", sequence=1),
        ),
      ),
      should_retry_sync_error(
        @text.TextError::SyncFailed(
          @sync.Failure::LimitExceeded(
            kind=@sync.LimitKind::PendingOperations,
            limit=1,
            actual=2,
          ),
        ),
      ),
    ],
    content="[true, true, false, false, false, false]",
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
  buf.write_string_utf16le(empty_msg.to_json_string().view())
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
test "SyncSession: SyncResponse from wrong sender is ignored" {
  let session = SyncSession()
  session.on_open()
  let empty_msg = empty_msg_or_fail()
  session.recovery_epoch = 1
  session.recovery = Some(RecoveryContext::new("alice", empty_msg, 1))
  session.set_status(Recovering(peer_id="alice", attempt=1))
  let applied : Array[@text.SyncMessage] = []
  let sent : Array[Bytes] = []
  let host = SyncHost(
    io=test_io(sent),
    apply_sync=msg => applied.push(msg),
    export_all=() => empty_msg_or_fail(),
    export_since=_ => empty_msg_or_fail(),
    apply_ephemeral=(_, _) => (),
    encode_ephemeral=_ => Bytes::new(0),
    on_peer_leave=_ => (),
  )
  // Relay delivery replaces the target with authenticated sender "bob".
  // The request ID collides with the active request to "alice".
  let wire = @wire.encode_sync_response(
    target="bob",
    request_id="1",
    sync_json=empty_msg.to_json_string(),
  )
  session.on_message(wire, host)
  inspect(applied.length(), content="0")
  inspect(sent.length(), content="0")
  inspect(session.recovery_epoch, content="1")
  inspect(session.recovery is Some(_), content="true")
  let recovery = session.recovery.unwrap()
  inspect(recovery.peer_id, content="alice")
  inspect(recovery.request_id, content="1")
  inspect(recovery.retries, content="0")
  inspect(recovery.deferred.length(), content="0")
  inspect(
    session.get_status(),
    content=(
      #|Recovering(peer_id="alice", attempt=1)
    ),
  )
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

// Watchdog: no-op and scheduler plumbing

///|
test "SyncSession: watchdog when no recovery does nothing" {
  let session = SyncSession()
  session.on_open()
  // No recovery in progress
  session.on_watchdog_fire(99, test_io([]))
  inspect(session.get_status(), content="Idle")
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
