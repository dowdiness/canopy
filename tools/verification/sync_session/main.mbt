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
enum ChoreoCommand {
  Init
  OpenPeer(String)
  StartRecovery(String)
  Respond(String, Int)
  DeliverResponse(String, Int, Bool)
  FireWatchdog(Int)
  SyncApplied
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
        LocalVersionLimitExceeded(kind~, limit~, actual~) =>
          "Error(LocalVersionLimitExceeded(kind=\{kind},limit=\{limit},actual=\{actual}))"
        LocalVersionEncodingFailed => "Error(LocalVersionEncodingFailed)"
      }
  }
}

///|
fn empty_message() -> @text.SyncMessage raise {
  @text.TextState::new("quint-sync-verification").sync().export_all()
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
  let io = @sync_session.SyncIo::SyncIo(send=bytes => self.send(bytes), current_version_json=() => {
    @text.Version::empty().to_json_string()
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
    @sync_session.SyncIo::SyncIo(send=bytes => self.send(bytes), current_version_json=() => {
      @text.Version::empty().to_json_string()
    }),
  )
}

///|
fn Driver::start_recovery(self : Driver, peer : String) -> Unit raise {
  // Each named recovery explicitly injects its own first retryable failure.
  self.fail_next_apply = true
  let host = self.host()
  let msg = empty_message()
  let buf = Buffer()
  buf.write_string_utf16le(msg.to_json_string().view())
  self.session.on_message(
    @wire.encode_relayed_crdt_ops(peer, buf.to_bytes()),
    host,
  )
}

///|
fn Driver::receive_response(
  self : Driver,
  sender : String,
  request_id : Int,
  helpful : Bool,
) -> Unit raise {
  let sync_json = if helpful { empty_message().to_json_string() } else { "" }
  let host = self.host()
  self.session.on_message(
    @wire.encode_sync_response(
      target=sender,
      request_id=request_id.to_string(),
      sync_json~,
    ),
    host,
  )
}

///|
fn Driver::apply_action(self : Driver, action : String) -> Unit raise {
  match action {
    "open" => self.session.on_open()
    "startRecovery" | "startRecoveryAgain" => self.start_recovery("alice")
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
    _ => raise Failure::Failure("unknown local action")
  }
  self.phase += 1
}

///|
fn required_string(picks : Json, name : String) -> Result[String, String] {
  match @quint_connect.required_nondet(picks, name) {
    Ok(String(value)) => Ok(value)
    Ok(_) => Err("nondeterministic pick \{name} must be a string")
    Err(reason) => Err(reason)
  }
}

///|
fn required_int(picks : Json, name : String) -> Result[Int, String] {
  match @quint_connect.required_nondet(picks, name) {
    Ok(value) => @quint_connect.decode_itf_int(value)
    Err(reason) => Err(reason)
  }
}

///|
fn decode_choreo_command(
  action : String,
  picks : Json,
) -> Result[ChoreoCommand, String] {
  match action {
    "Init" => Ok(Init)
    "OpenPeer" => required_string(picks, "peer").map(peer => OpenPeer(peer))
    "StartRecovery" =>
      required_string(picks, "target").map(target => StartRecovery(target))
    "RespondEmpty" | "RespondHelpful" => {
      let sender = match required_string(picks, "sender") {
        Ok(sender) => sender
        Err(reason) => return Err(reason)
      }
      let id = match required_int(picks, "id") {
        Ok(id) => id
        Err(reason) => return Err(reason)
      }
      Ok(Respond(sender, id))
    }
    "DeliverEmpty" | "DeliverHelpful" => {
      let sender = match required_string(picks, "sender") {
        Ok(sender) => sender
        Err(reason) => return Err(reason)
      }
      let id = match required_int(picks, "id") {
        Ok(id) => id
        Err(reason) => return Err(reason)
      }
      Ok(DeliverResponse(sender, id, action == "DeliverHelpful"))
    }
    "FireWatchdog" => required_int(picks, "id").map(id => FireWatchdog(id))
    "SyncAppliedCommand" => Ok(SyncApplied)
    "UnsafeAttemptFive" => Err("model mutation command is not replayable")
    _ => Err("unknown Choreo command \{action}")
  }
}

///|
fn Driver::apply_choreo_command(
  self : Driver,
  command : ChoreoCommand,
) -> Unit raise {
  match command {
    Init => return
    OpenPeer(peer) => if peer == "alice" { self.session.on_open() }
    StartRecovery(target) => self.start_recovery(target)
    Respond(sender, id) =>
      if sender.is_empty() || id <= 0 {
        raise Failure::Failure("invalid responder command")
      }
    DeliverResponse(sender, id, helpful) =>
      if self.broken && !helpful {
        // Negative control: skip a real implementation input.
        ()
      } else {
        self.receive_response(sender, id, helpful)
      }
    FireWatchdog(id) => self.watchdog(id)
    SyncApplied => self.session.note_sync_applied()
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
fn project_choreo(driver : Driver) -> Json {
  guard project(driver) is Object(fields) else {
    abort("project must be an object")
  }
  let projected = fields.copy()
  let request_id = if driver.scheduled.is_empty() {
    0
  } else {
    driver.scheduled[driver.scheduled.length() - 1].0
  }
  projected["requestId"] = itf_int(request_id)
  Json::object(projected)
}

///|
fn expected(value : Json) -> Result[Json, String] {
  Ok(value)
}

///|
fn expected_choreo(value : Json) -> Result[Json, String] {
  guard value is Object(fields) else {
    return Err("Choreo display must be an object")
  }
  let status = match fields.get("status") {
    Some(String(status)) => status
    _ => return Err("Choreo display is missing status")
  }
  let target = match fields.get("target") {
    Some(String(target)) => target
    _ => return Err("Choreo display is missing target")
  }
  let attempt = match fields.get("attempt") {
    Some(value) =>
      match @quint_connect.decode_itf_int(value) {
        Ok(attempt) => attempt
        Err(reason) => return Err(reason)
      }
    None => return Err("Choreo display is missing attempt")
  }
  let normalized_status = match status {
    "Recovering" => "Recovering(\{target},\{attempt})"
    "Error(Exhausted)" => "Error(Exhausted(peer_id=\{target}))"
    "Error(TargetLeft)" => "Error(TargetLeft(peer_id=\{target}))"
    other => other
  }
  let normalized = fields.copy()
  // Target is observable through public Recovering/Error status while active;
  // requestId remains explicit and is compared with the scheduler callback ID.
  normalized.remove("target")
  normalized["status"] = normalized_status.to_json()
  Ok(Json::object(normalized))
}

///|
async fn main {
  let args = @env.args()
  guard args.length() >= 2 else {
    abort("usage: verification TRACE... [--choreo] [--broken]")
  }
  let broken = args.any(arg => arg == "--broken")
  let choreo = args.any(arg => arg == "--choreo")
  let paths : Array[String] = []
  for index = 1; index < args.length(); index = index + 1 {
    let arg = args[index]
    if arg == "--broken" || arg == "--choreo" {
      ()
    } else if arg.has_prefix("--") {
      abort("unknown option: \{arg}")
    } else {
      paths.push(arg)
    }
  }
  guard !paths.is_empty() else { abort("at least one trace is required") }
  let traces = []
  for path in paths {
    let trace_text = @fs.read_file(path).text()
    let trace_result = if choreo {
      @quint_connect.parse_itf_with_config(trace_text, {
        state_path: ["RecoveryChoreo::choreo::display"],
        nondet_path: ["RecoveryChoreo::choreo::s", "extensions", "command"],
      })
    } else {
      @quint_connect.parse_itf(trace_text)
    }
    match trace_result {
      Ok(trace) => traces.push(trace)
      Err(error) =>
        abort("ITF parse failed for \{path}: \{@debug.to_string(error)}")
    }
  }
  let result = @quint_connect.replay_suite(
    traces,
    () => Driver::new(broken),
    fn(driver, action, picks) {
      if choreo {
        let command = match decode_choreo_command(action, picks) {
          Ok(command) => command
          Err(reason) => return Err(reason)
        }
        driver.apply_choreo_command(command) catch {
          error => return Err("driver error: \{@debug.to_string(error)}")
        }
      } else if action != "init" {
        driver.apply_action(action) catch {
          error => return Err("driver error: \{@debug.to_string(error)}")
        }
      }
      Ok(driver)
    },
    if choreo {
      project_choreo
    } else {
      project
    },
    if choreo {
      expected_choreo
    } else {
      expected
    },
  )
  match result {
    Ok(summary) =>
      println(
        "PASS: \{summary.traces_checked} traces, \{summary.states_checked} states matched",
      )
    Err(error) => abort("DIVERGENCE: \{@debug.to_string(error)}")
  }
}
