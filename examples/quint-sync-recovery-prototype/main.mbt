///|
struct Driver {
  session : @sync_session.SyncSession
  mut phase : Int
  mut attempt : Int
  sent : Array[String]
  scheduled : Array[(Int, Int)]
  apply_count : Array[Int]
  mut fail_next_apply : Bool
  status_events : Array[String]
  peer_leaves : Array[String]
  broken : Bool
}

///|
fn status_text(status : @sync_session.SyncStatus) -> String {
  match status {
    Disconnected => "Disconnected"
    Idle => "Idle"
    Recovering(peer_id~, attempt~) => "Recovering(\{peer_id},\{attempt})"
    Error(reason~) =>
      match reason {
        TargetLeft(peer_id~) => "Error(TargetLeft(peer_id=\{peer_id}))"
        Exhausted(peer_id~) => "Error(Exhausted(peer_id=\{peer_id}))"
      }
  }
}

///|
fn empty_message() -> @text.SyncMessage raise {
  @text.TextState::new("quint-sync-prototype").sync().export_all()
}

///|
fn Driver::new(broken : Bool) -> Driver {
  let driver = {
    session: @sync_session.SyncSession::SyncSession(),
    phase: 0,
    attempt: 0,
    sent: [],
    scheduled: [],
    apply_count: [0],
    fail_next_apply: false,
    status_events: [],
    peer_leaves: [],
    broken,
  }
  driver.session.set_watchdog_scheduler(
    Some((id, timeout) => driver.scheduled.push((id, timeout))),
  )
  driver.session.set_on_status_change(
    Some(status => {
      driver.status_events.push(status_text(status))
      match status {
        Recovering(peer_id=_, attempt~) => driver.attempt = attempt
        Idle => driver.attempt = 0
        _ => ()
      }
    }),
  )
  driver
}

///|
fn Driver::send(self : Driver, bytes : Bytes) -> Unit {
  match @wire.decode_message_result(bytes) {
    Ok(msg) =>
      self.sent.push(
        match msg {
          CrdtOps(_) => "CrdtOps"
          EphemeralUpdate(_, _) => "EphemeralUpdate"
          SyncRequest(_) => "SyncRequest"
          SyncResponse(_) => "SyncResponse"
          PeerJoined(_) => "PeerJoined"
          PeerLeft(_) => "PeerLeft"
          RelayedCrdtOps(..) => "RelayedCrdtOps"
        },
      )
    Err(_) => self.sent.push("decode-error")
  }
}

///|
fn Driver::host(self : Driver) -> @sync_session.SyncHost raise {
  let io = @sync_session.SyncIo::SyncIo(send=bytes => self.send(bytes), current_version=() => {
    @text.Version::empty()
  })
  let apply = fn(msg : @text.SyncMessage) raise {
    self.apply_count[0] += 1
    if self.fail_next_apply {
      self.fail_next_apply = false
      raise @text.TextError::VersionNotFound
    }
    if msg.is_empty() {
      ()
    }
  }
  let msg = empty_message()
  @sync_session.SyncHost::SyncHost(
    io~,
    apply_sync=apply,
    export_all=() => msg,
    export_since=_ => msg,
    apply_ephemeral=(_, _) => (),
    encode_ephemeral=_ => Bytes::new(0),
    on_peer_leave=peer_id => self.peer_leaves.push(peer_id),
  )
}

///|
fn Driver::watchdog(self : Driver, id : Int) -> Unit {
  self.session.on_watchdog_fire(
    id,
    @sync_session.SyncIo::SyncIo(send=bytes => self.send(bytes), current_version=() => {
      @text.Version::empty()
    }),
  )
}

///|
fn Driver::apply_action(self : Driver, action : String) -> Unit raise {
  match action {
    "open" => self.session.on_open()
    "startRecovery" | "startRecoveryAgain" => {
      // Each named recovery explicitly injects its own first retryable failure.
      self.fail_next_apply = true
      let host = self.host()
      let msg = empty_message()
      let buf = Buffer()
      buf.write_string_utf16le(msg.to_json_string().view())
      self.session.on_message(
        @wire.encode_relayed_crdt_ops("alice", buf.to_bytes()),
        host,
      )
    }
    "watchdogCurrent" =>
      if self.broken {
        // Negative control: the real driver skips this named operation.
        ()
      } else {
        let id = self.scheduled[self.scheduled.length() - 1].0
        self.watchdog(id)
      }
    "watchdogStale" => self.watchdog(self.scheduled[0].0)
    "watchdogExhaust" => {
      let id = self.scheduled[self.scheduled.length() - 1].0
      self.watchdog(id)
    }
    "noteSyncApplied" => self.session.note_sync_applied()
    "peerLeftTarget" => {
      let host = self.host()
      self.session.on_message(@wire.encode_message(PeerLeft("alice")), host)
    }
    "done" => return
    _ => raise Failure::Failure("unknown action")
  }
  self.phase += 1
}

///|
fn itf_int(value : Int) -> Json {
  Json::object({ "#bigint": value.to_string().to_json() })
}

///|
fn project(driver : Driver) -> Json {
  let status = status_text(driver.session.get_status())
  Json::object({
    "phase": itf_int(driver.phase),
    "status": status.to_json(),
    "attempt": itf_int(driver.attempt),
    "sent": itf_int(driver.sent.length()),
    "sentKinds": driver.sent.join(",").to_json(),
    "scheduled": itf_int(driver.scheduled.length()),
    "applied": itf_int(driver.apply_count[0]),
    "statusEvents": itf_int(driver.status_events.length()),
    "peerLeaves": itf_int(driver.peer_leaves.length()),
  })
}

///|
fn expected(value : Json) -> Result[Json, String] {
  Ok(value)
}

///|
async fn main {
  let args = @env.args()
  guard args.length() >= 2 else { abort("usage: prototype TRACE [--broken]") }
  let broken = args.any(arg => arg == "--broken")
  let trace = match @quint_connect.parse_itf(@fs.read_file(args[1]).text()) {
    Ok(value) => value
    Err(error) => abort("ITF parse failed: \{@debug.to_string(error)}")
  }
  let result = @quint_connect.replay(
    trace,
    Driver::new(broken),
    fn(driver, action, _) {
      if action == "init" {
        Ok(driver)
      } else {
        driver.apply_action(action) catch {
          _ => return Err("driver error")
        }
        Ok(driver)
      }
    },
    project,
    expected,
  )
  match result {
    Ok(summary) => println("PASS: \{summary.states_checked} states matched")
    Err(error) => abort("DIVERGENCE: \{@debug.to_string(error)}")
  }
}
