///|
fn source_demo_test_model(handle : Int) -> SourceDemoModel {
  {
    handle,
    editor: get_source_graph_source(handle),
    dirty: false,
    parser_failed: false,
    mounted: true,
    status: "previous status",
    status_tone: @status.Info,
    on_change: fn() { () },
    on_terminal: fn() { () },
  }
}

///|
test "canvas rename survives deferred graph synchronization" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope(input: osc)"
  let handle = create_source_graph(source)
  defer destroy_source_graph(handle)
  let initial = source_demo_test_model(handle)
  let rename = GraphOperation(RenameNode(handle_token(handle, "osc"), "lfo"))
  let graph = source_graph_by_handle(handle).unwrap()
  let result = graph.apply_operation(rename)
  let msg = CanvasOperation(Completed(Renamed, result))
  assert_true(result.applied)
  let emit = @cmd.Emit(_ => @rabbita.none)
  let (_, notified) = source_demo_update(emit, msg, initial)
  let (_, synced) = source_demo_update(emit, SyncFromGraph, notified)
  assert_eq(synced.editor, "lfo = sine(freq: 440Hz)\nmeter = scope(input: lfo)")
  assert_false(synced.dirty)
}

///|
test "rejected canvas operation preserves invalid editing across graph sync" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)")
  defer destroy_source_graph(handle)
  let emit = @cmd.Emit(_ => @rabbita.none)
  let invalid_source = "osc = sine(freq: )"
  let (_, edited) = source_demo_update(
    emit,
    EditorSynced(invalid_source),
    source_demo_test_model(handle),
  )
  let (_, invalid) = source_demo_update(emit, ApplySource, edited)
  assert_true(invalid.dirty)
  let result = source_graph_insert_unique_result(handle, "reverb", "plate")
  assert_false(result.applied)
  let (_, rejected) = source_demo_update(
    emit,
    CanvasOperation(Completed(Inserted("plate"), result)),
    invalid,
  )
  let (_, synced) = source_demo_update(emit, SyncFromGraph, rejected)
  assert_eq(synced.editor, invalid_source)
  assert_true(synced.dirty)
}

///|
test "delayed canvas success preserves newer invalid editing across graph sync" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)")
  defer destroy_source_graph(handle)
  let initial = source_demo_test_model(handle)
  let rename = GraphOperation(RenameNode(handle_token(handle, "osc"), "lfo"))
  let result = source_graph_by_handle(handle).unwrap().apply_operation(rename)
  let msg = CanvasOperation(Completed(Renamed, result))
  assert_true(result.applied)
  let emit = @cmd.Emit(_ => @rabbita.none)
  let invalid_source = "osc = sine(freq: )"
  let (_, edited) = source_demo_update(
    emit,
    EditorSynced(invalid_source),
    initial,
  )
  let (_, invalid) = source_demo_update(emit, ApplySource, edited)
  assert_true(invalid.dirty)
  let (_, notified) = source_demo_update(emit, msg, invalid)
  assert_eq(notified.editor, invalid_source)
  assert_true(notified.dirty)
  let (_, synced) = source_demo_update(emit, SyncFromGraph, notified)
  assert_eq(synced.editor, invalid_source)
  assert_true(synced.dirty)
}

///|
async test "typed inspector request completes once with canonical source and action" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)")
  defer destroy_source_graph(handle)
  let replies : Array[CanvasSourceReply] = []
  let (command, next) = source_demo_update(
    @cmd.Emit(_ => @rabbita.none),
    CanvasOperation(
      Request(
        Parameter(handle_token(handle, "osc"), "freq", "880"),
        Some(reply => replies.push(reply)),
      ),
    ),
    source_demo_test_model(handle),
  )
  @rabbita_testing.run_cmd(command)
  assert_true(replies is [Applied])
  assert_eq(next.editor, "osc = sine(freq: 880Hz)")
  assert_false(next.dirty)
  assert_eq(source_graph_by_handle(handle).unwrap().action_log.length(), 1)
}

///|
async test "rejected inspector request completes without replacing invalid source" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)")
  defer destroy_source_graph(handle)
  let node = handle_token(handle, "osc")
  let emit = @cmd.Emit(_ => @rabbita.none)
  let invalid_text = "osc = sine(freq: )"
  let (_, invalid) = source_demo_update(emit, ApplySource, {
    ..source_demo_test_model(handle),
    editor: invalid_text,
  })
  let replies : Array[CanvasSourceReply] = []
  let (command, rejected) = source_demo_update(
    emit,
    CanvasOperation(
      Request(
        Parameter(node, "freq", "880"),
        Some(reply => replies.push(reply)),
      ),
    ),
    invalid,
  )
  @rabbita_testing.run_cmd(command)
  assert_true(replies is [Rejected])
  assert_eq(rejected.editor, invalid_text)
  assert_true(rejected.dirty)
  assert_eq(source_graph_by_handle(handle).unwrap().action_log.length(), 0)
}

///|
async test "sticky parser failure stops requests and preserves editable text" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)")
  defer destroy_source_graph(handle)
  let graph = source_graph_by_handle(handle).unwrap()
  let node = handle_token(handle, "osc")
  let initial = source_demo_test_model(handle)
  let stops = @ref.Ref(0)
  let replies : Array[CanvasSourceReply] = []
  let emit = @cmd.Emit(_ => @rabbita.none)
  let request = CanvasOperation(
    Request(Rename(node, "lfo"), Some(reply => replies.push(reply))),
  )
  // Inject the backing's real terminal latch, not a rejected syntax result.
  graph.parser_failure = Some(Failure("test parser failure"))
  let (command, stopped) = source_demo_update(emit, request, {
    ..initial,
    on_terminal: () => stops.val += 1,
  })
  @rabbita_testing.run_cmd(command)
  assert_true(stopped.parser_failed)
  assert_eq(stopped.editor, initial.editor)
  let (_, edited) = source_demo_update(
    emit,
    EditorSynced("recoverable text"),
    stopped,
  )
  let (later, still_stopped) = source_demo_update(emit, request, edited)
  @rabbita_testing.run_cmd(later)
  assert_eq(stops.val, 1)
  assert_true(replies is [ParserStopped, ParserStopped])
  assert_eq(still_stopped.editor, "recoverable text")
  assert_eq(graph.source, initial.editor)
  assert_eq(graph.action_log.length(), 0)
}
