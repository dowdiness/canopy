///|
priv struct Replica {
  state : @text.TextState
  undo : @undo.UndoManager
}

///|
priv struct Session {
  document : String
  db : Database
  editor : Replica
  merged : Replica
  history_rows : Array[JournalRow]
  mut cursor : Double
  mut offer : Offer?
  mut offer_sequence : Double
  mut last_command : AcceptedCommand?
}

///|
priv struct WorkerState {
  mut api : NativeModule?
  mut session : Session?
  queue : Array[QueuedRequest]
  mut queue_head : Int
  mut consuming : Bool
}

///|
fn replica(actor : String, archive : String, version : String) -> Replica raise {
  let state = if archive == "" {
    @text.TextState::new(actor)
  } else {
    @text.TextState::restore_compact_direct_experimental(
      archive, actor, version,
    )
  }
  { state, undo: @undo.UndoManager::new(actor), }
}

///|
fn info(replica : Replica) -> Info raise {
  {
    text: replica.state.text(),
    version: replica.state.version().to_json_string(),
    count: replica.state.causal_snapshot().op_count(),
    pending: replica.state.sync().pending_sync_count(),
    can_undo: replica.undo.can_undo(),
    can_redo: replica.undo.can_redo(),
  }
}

///|
fn checkpoint(request : Request, phase : String) -> Unit {
  post_raw(
    object([
      ("epoch", as_value(request.epoch)),
      ("id", as_value(request.id)),
      ("document", as_value(request.document)),
      ("checkpoint", as_value(phase)),
    ]),
  )
}

///|
fn bounded_packet(api : NativeModule, payload : String) -> @js.Value raise {
  native_call(api, "boundedPacket", [as_value(payload)])
}

///|
fn decode_message(
  api : NativeModule,
  payload : String,
) -> @text.SyncMessage raise {
  ignore(bounded_packet(api, payload))
  @text.SyncMessage::from_json_string(payload)
}

///|
fn apply_changes(replica : Replica, message : @text.SyncMessage) -> Unit raise {
  let report = replica.state.sync().apply(message)
  if report.pending_operations() != 0 {
    raise Failure("Durable operation union is not causally closed")
  }
}

///|
fn packet_in_basis(
  api : NativeModule,
  known : @js.Value,
  payload : String,
) -> Bool raise {
  let operations = js_field(bounded_packet(api, payload), "operations")
  for operation in native_array(operations) {
    let included : Bool = native_call(api, "contains", [
      known,
      js_field(operation, "id"),
    ]).cast()
    if !included {
      return false
    }
  }
  true
}

///|
async fn open_request(
  worker : WorkerState,
  api : NativeModule,
  request : Request,
  text : String,
  basis : String?,
  retained : Array[Packet],
) -> @js.Value {
  let db : Database = native_promise(api, "openStore", []).cast()
  let db_value = @js.Value::cast_from(db)
  let seed = native_promise(api, "readSeed", [
    db_value,
    as_value(request.document),
  ])
  let start = now(api)
  let seed = if seed.is_undefined() || seed.is_null() {
    if !text_is_well_formed(text) || text.iter().count() > 100000 {
      raise Failure("Invalid or oversized synthetic seed")
    }
    let initial = replica("seed-" + uuid(api), "", "")
    initial.state.replace_range_and_record(
      @text.Range::from_ints(0, 0),
      text,
      initial.undo,
      timestamp_ms=0,
    )
    native_promise(api, "initialize", [
      db_value,
      as_value(request.document),
      object([
        ("archive", as_value(initial.state.export_compact_experimental())),
        ("version", as_value(initial.state.version().to_json_string())),
      ]),
    ])
  } else {
    seed
  }
  let seed_ms = now(api) - start
  let restore_start = now(api)
  let archive = field_string(seed, "archive")
  let version = field_string(seed, "version")
  let writer = uuid(api)
  let editor = replica(writer, archive, version)
  checkpoint(request, "editor-restored")
  let merged = replica(uuid(api), archive, version)
  checkpoint(request, "merged-restored")
  let restore_ms = now(api) - restore_start
  let replay_start = now(api)
  let rows = read_rows(api, db, request.document, 0.0)
  let known = match basis {
    Some(version) => native_call(api, "knowledge", [as_value(version)])
    None => js_undefined()
  }
  let mut cursor = 0.0
  for row in rows {
    let message = decode_message(api, row.packet.payload)
    apply_changes(merged, message)
    checkpoint(request, "merged-replayed")
    if basis is None || packet_in_basis(api, known, row.packet.payload) {
      apply_changes(editor, message)
      checkpoint(request, "editor-replayed")
    }
    cursor = row.cursor
  }
  for packet in retained {
    let message = decode_message(api, packet.payload)
    apply_changes(editor, message)
    checkpoint(request, "editor-retained")
    apply_changes(merged, message)
    checkpoint(request, "merged-retained")
  }
  let restored = info(editor)
  if basis is Some(version) && restored.version != version {
    raise Failure(
      "Recovery basis unavailable; retained draft was not overwritten",
    )
  }
  let replay_ms = now(api) - replay_start
  worker.session = Some({
    document: request.document,
    db,
    editor,
    merged,
    history_rows: rows,
    cursor,
    offer: None,
    offer_sequence: 0.0,
    last_command: None,
  })
  object([
    ("info", restored.to_wire()),
    ("writer", as_value(writer)),
    ("undoReset", as_value(basis is Some(_))),
    (
      "timings",
      object([
        ("seedMs", as_value(seed_ms)),
        ("restoreMs", as_value(restore_ms)),
        ("replayMs", as_value(replay_ms)),
      ]),
    ),
  ])
}

///|
priv struct Replacement {
  start : Int
  end : Int
  inserted : String
}

///|
fn replace_intent(
  api : NativeModule,
  editor : Replica,
  before : String,
  input : Input,
  after : String,
) -> Unit raise {
  let changes = match input {
    ReplaceAll(text) => {
      if !text_is_well_formed(text) {
        raise Failure("Malformed UTF-16")
      }
      snapshot_changes(api, before, text).items
    }
    Change(change) => [change]
  }
  // Compute sequential coordinates and cost before mutating EGW. Each native
  // intent starts one Undo group, not a new group for every alignment hunk.
  let replacements : Array[Replacement] = []
  let max_ops : Int = native_call(api, "MAX_OPS", []).cast()
  let mut projected = before
  let mut cost = 0
  for change in changes {
    if !text_is_well_formed(change.inserted) {
      raise Failure("Malformed UTF-16")
    }
    let start = scalar_at(api, projected, change.start)
    let end = scalar_at(api, projected, change.start + change.deleted)
    cost += change.inserted.iter().count() + end - start
    if cost > max_ops {
      raise Failure("Input exceeds per-packet operation limit; draft retained")
    }
    replacements.push({ start, end, inserted: change.inserted, })
    projected = text_slice(projected, 0.0, change.start) +
      change.inserted +
      text_slice(
        projected,
        change.start + change.deleted,
        projected.length().to_double(),
      )
  }
  if projected != after {
    raise Failure("Native TextChange result mismatch")
  }
  if !replacements.is_empty() {
    editor.undo.stop_capturing()
  }
  for replacement in replacements {
    editor.state.replace_range_and_record(
      @text.Range::from_ints(replacement.start, replacement.end),
      replacement.inserted,
      editor.undo,
      timestamp_ms=0,
    )
  }
  if editor.state.text() != after {
    raise Failure("Native TextChange result mismatch")
  }
}

///|
fn edit_request(
  api : NativeModule,
  session : Session,
  command : EditCommand,
) -> EditResult raise {
  if session.last_command is Some(previous) &&
    command.sequence <= previous.command.sequence {
    if !same_intent(previous.command, command) {
      raise Failure("Stale or conflicting command")
    }
    return previous.result
  }
  let editor = session.editor
  if editor.state.text() != command.before {
    raise Failure("Edit basis mismatch; draft retained")
  }
  let before_version = editor.state.version()
  session.offer = None
  match command.action {
    Edit(input, after) =>
      replace_intent(api, editor, command.before, input, after)
    History(redo) => {
      editor.undo.stop_capturing()
      if redo {
        ignore(editor.undo.redo(editor.state))
      } else {
        ignore(editor.undo.undo(editor.state))
      }
    }
  }
  let after = info(editor)
  let message = editor.state.sync().export_since(before_version)
  let payload = message.to_json_string()
  ignore(bounded_packet(api, payload))
  apply_changes(editor, message)
  apply_changes(session.merged, message)
  let packet = if message.is_empty() {
    None
  } else {
    Some({
      id: command.id,
      payload,
      version: after.version,
      created_at: command.created_at,
    })
  }
  let changes = match command.action {
    History(_) => snapshot_changes(api, command.before, after.text)
    Edit(_, _) => { items: [], approximate: false, }
  }
  let result : EditResult = { info: after, packet, changes, }
  session.last_command = Some({ command, result, })
  result
}

///|
async fn save_request(
  api : NativeModule,
  session : Session,
  request : Request,
  packet : Packet,
  fault : SaveFault,
) -> @js.Value {
  apply_changes(session.merged, decode_message(api, packet.payload))
  let options = save_options(fault.abort, fault.hold, fault.before_commit, () => {
    checkpoint(request, "before-commit")
  })
  let timings = native_promise(api, "append", [
    @js.Value::cast_from(session.db),
    as_value(session.document),
    packet.to_wire(),
    options,
  ])
  if fault.crash_after_commit {
    ignore(native_call(api, "close", []))
    never_resolves().wait()
  }
  object([("packetId", as_value(packet.id)), ("timings", timings)])
}

///|
async fn pull_request(
  api : NativeModule,
  session : Session,
  request : Request,
  revision : Double,
) -> @js.Value {
  let rows = read_rows(api, session.db, session.document, session.cursor)
  session.history_rows.append(rows)
  for row in rows {
    apply_changes(session.merged, decode_message(api, row.packet.payload))
    session.cursor = row.cursor
    checkpoint(request, "pulled-packet")
  }
  let before = info(session.editor)
  let after = info(session.merged)
  if before.version == after.version {
    return object([("offer", js_null())])
  }
  let known = native_call(api, "knowledge", [as_value(before.version)])
  let payloads : Array[String] = []
  for row in session.history_rows {
    if !packet_in_basis(api, known, row.packet.payload) {
      payloads.push(row.packet.payload)
    }
  }
  session.offer_sequence += 1.0
  session.offer = Some({ token: session.offer_sequence, payloads, info: after, })
  object([
    (
      "offer",
      object([
        ("token", as_value(session.offer_sequence)),
        ("payloads", js_undefined()),
        ("before", as_value(before.text)),
        ("info", after.to_wire()),
        ("revision", as_value(revision)),
        ("changes", snapshot_changes(api, before.text, after.text).to_wire()),
      ]),
    ),
  ])
}

///|
fn project_request(
  api : NativeModule,
  session : Session,
  request : Request,
  token : Double,
) -> @js.Value raise {
  guard session.offer is Some(offer) && offer.token == token else {
    raise Failure("Stale projection acknowledgement")
  }
  for payload in offer.payloads {
    apply_changes(session.editor, decode_message(api, payload))
    checkpoint(request, "projected-packet")
  }
  let current = info(session.editor)
  if current.version != offer.info.version || current.text != offer.info.text {
    raise Failure("Projection acknowledgement mismatch")
  }
  session.offer = None
  object([("info", current.to_wire())])
}

///|
fn inject_request(
  api : NativeModule,
  session : Session,
  payload : String,
) -> @js.Value raise {
  let transition = session.merged.state
    .sync()
    .apply_transition(decode_message(api, payload))
  let effects = @js.JsArray::new()
  let availability = match transition.effect_availability() {
    Exact(exact) => {
      for effect in exact {
        effects.push(
          match effect {
            Insert(position, text) =>
              object([
                ("kind", as_value("insert")),
                ("start", as_value(position.value())),
                ("text", as_value(text)),
              ])
            Delete(range) =>
              object([
                ("kind", as_value("delete")),
                ("start", as_value(range.start().value())),
                ("end", as_value(range.end().value())),
              ])
          },
        )
      }
      "exact"
    }
    SnapshotRequired => "snapshot"
    Unavailable => "unavailable"
  }
  let before = transition.version_before().to_json_string()
  let after = transition.version_after().to_json_string()
  let report = transition.report()
  if report.pending_operations() != 0 {
    raise Failure("Durable operation union is not causally closed")
  }
  object([
    (
      "transition",
      object([
        ("ok", as_value(true)),
        ("availability", as_value(availability)),
        ("effects", @js.Value::cast_from(effects)),
        ("before", as_value(before)),
        ("after", as_value(after)),
        ("pending", as_value(report.pending_operations())),
      ]),
    ),
  ])
}

///|
async fn test_replay(api : NativeModule, session : Session) -> @js.Value {
  let seed = native_promise(api, "readSeed", [
    @js.Value::cast_from(session.db),
    as_value(session.document),
  ])
  let rows = read_rows(api, session.db, session.document, 0.0)
  let replay = replica(
    uuid(api),
    field_string(seed, "archive"),
    field_string(seed, "version"),
  )
  let pending = @js.JsArray::new()
  for index = rows.length() - 1; index >= 0; index = index - 1 {
    let message = @text.SyncMessage::from_json_string(
      rows[index].packet.payload,
    )
    pending.push(replay.state.sync().apply(message).pending_operations())
  }
  for row in rows {
    ignore(
      replay.state
      .sync()
      .apply(@text.SyncMessage::from_json_string(row.packet.payload)),
    )
  }
  object([
    ("info", info(replay).to_wire()),
    ("pending", @js.Value::cast_from(pending)),
  ])
}

///|
fn test_apply_changes(api : NativeModule, session : Session) -> @js.Value raise {
  let before = info(session.editor)
  let temporary = replica(uuid(api), "", "")
  let empty = temporary.state.version()
  temporary.state.replace_range_and_record(
    @text.Range::from_ints(0, 0),
    "X",
    temporary.undo,
    timestamp_ms=0,
  )
  let payload = temporary.state.sync().export_since(empty).to_json_string()
  let oversized = checked_string(
    native_call(api, "oversizedPayload", [as_value(payload)]),
  )
  let errors = @js.JsArray::new()
  for invalid in ["{}", "{\"schema\":1,\"operations\":[]}", oversized] {
    ignore(
      session.editor.state
      .sync()
      .apply(@text.SyncMessage::from_json_string(invalid)),
    ) catch {
      error => errors.push(error_text(error))
    }
  }
  object([
    ("before", before.to_wire()),
    ("after", info(session.editor).to_wire()),
    ("errors", @js.Value::cast_from(errors)),
  ])
}

///|
async fn ensure_api(worker : WorkerState) -> NativeModule {
  match worker.api {
    Some(api) => api
    None => {
      let result = load_native().wait()
      if !optional_bool(result, "ok") {
        raise Failure(field_string(result, "error"))
      }
      let api : NativeModule = js_field(result, "value").cast()
      worker.api = Some(api)
      api
    }
  }
}

///|
async fn execute(worker : WorkerState, request : Request) -> @js.Value {
  let api = ensure_api(worker)
  match request.command {
    Open(text, basis, packets) =>
      open_request(worker, api, request, text, basis, packets)
    Invalid(message) => raise Failure(message)
    command => {
      guard worker.session is Some(session) else {
        raise Failure("Worker is not ready")
      }
      if request.document != session.document {
        raise Failure("Wrong document")
      }
      match command {
        Edit(command) => edit_request(api, session, command).to_wire()
        Save(packet, fault) =>
          save_request(api, session, request, packet, fault)
        Pull(revision) => pull_request(api, session, request, revision)
        Project(token) => project_request(api, session, request, token)
        Inspect =>
          object([
            ("info", info(session.editor).to_wire()),
            ("merged", info(session.merged).to_wire()),
          ])
        Durable => {
          let seed = native_promise(api, "readSeed", [
            @js.Value::cast_from(session.db),
            as_value(session.document),
          ])
          let rows = native_promise(api, "readJournal", [
            @js.Value::cast_from(session.db),
            as_value(session.document),
            as_value(0.0),
          ])
          object([("seed", seed), ("journal", rows)])
        }
        Inject(payload) => inject_request(api, session, payload)
        TestReplay => test_replay(api, session)
        TestApplyChanges => test_apply_changes(api, session)
        Open(_, _, _) | Invalid(_) => abort("handled above")
      }
    }
  }
}

///|
async fn consume(worker : WorkerState) -> Unit {
  while worker.queue_head < worker.queue.length() {
    let queued = worker.queue[worker.queue_head]
    worker.queue_head += 1
    let request = match queued {
      Valid(request) => request
      InvalidEnvelope => {
        // A later malformed message must not cancel an older accepted reply.
        invalid_envelope()
        return
      }
    }
    let response = try {
      let result = execute(worker, request)
      if request.delay != 0.0 {
        ignore(
          native_promise(ensure_api(worker), "delay", [as_value(request.delay)]),
        )
      }
      object([
        ("epoch", as_value(request.epoch)),
        ("id", as_value(request.id)),
        ("document", as_value(request.document)),
        ("ok", as_value(true)),
        ("result", result),
      ])
    } catch {
      error =>
        object([
          ("epoch", as_value(request.epoch)),
          ("id", as_value(request.id)),
          ("document", as_value(request.document)),
          ("ok", as_value(false)),
          ("error", as_value(error_text(error))),
        ])
    }
    post_raw(response)
  }
  worker.queue.clear()
  worker.queue_head = 0
  worker.consuming = false
}

///|
fn on_message(worker : WorkerState, raw : @js.Value) -> Unit {
  let id = js_field(raw, "id")
  let epoch = js_field(raw, "epoch")
  let document = js_field(raw, "document")
  let queued = if !js_is_safe_integer(id) ||
    !js_is_safe_integer(epoch) ||
    !document.is_string() {
    QueuedRequest::InvalidEnvelope
  } else {
    let (command, delay) = (decode_command(raw), optional_double(raw, "delay")) catch {
      error => (Command::Invalid(error_text(error)), 0.0)
    }
    QueuedRequest::Valid({
      id: id.cast(),
      epoch: epoch.cast(),
      document: document.cast(),
      command,
      delay,
    })
  }
  worker.queue.push(queued)
  if !worker.consuming {
    worker.consuming = true
    ignore(@js.Promise::from_async(() => consume(worker)))
  }
}

///|
fn main {
  let worker : WorkerState = {
    api: None,
    session: None,
    queue: [],
    queue_head: 0,
    consuming: false,
  }
  // Register before the first dynamic import can yield; the first open may be
  // posted immediately after Worker construction. Only this consumer awaits.
  install_worker_listener(raw => on_message(worker, raw))
}
