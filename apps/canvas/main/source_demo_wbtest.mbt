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
  }
}

///|
test "external rename notification survives deferred graph synchronization" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope(input: osc)"
  let handle = create_source_graph(source)
  defer destroy_source_graph(handle)
  let initial = source_demo_test_model(handle)
  let rename = GraphOperation(RenameNode(handle_token(handle, "osc"), "lfo"))
  let result_json = apply_source_graph_operation(
    handle,
    rename.to_json().stringify(),
  )
  let msg = decode_source_notice("rename", "", result_json)
  guard msg is ExternalOperation(Renamed, result) else {
    fail("expected typed rename result")
  }
  assert_true(result.applied)
  let emit = @cmd.Emit(_ => @rabbita.none)
  let (_, notified) = source_demo_update(emit, msg, initial)
  let (_, synced) = source_demo_update(emit, SyncFromGraph, notified)
  assert_eq(synced.editor, "lfo = sine(freq: 440Hz)\nmeter = scope(input: lfo)")
  assert_true(notified.status_tone == @status.Success)
  assert_eq(synced.status, notified.status)
  assert_true(synced.status_tone == @status.Success)
  assert_false(synced.dirty)
}

///|
test "rejected external operation preserves invalid editing across graph sync" {
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
    decode_source_notice("insert", "plate", ToJson::to_json(result).stringify()),
    invalid,
  )
  let (_, synced) = source_demo_update(emit, SyncFromGraph, rejected)
  assert_eq(synced.editor, invalid_source)
  assert_true(synced.dirty)
  assert_true(rejected.status_tone == @status.Error)
  assert_eq(synced.status, rejected.status)
  assert_true(synced.status_tone == @status.Error)
}

///|
test "unknown external operation cannot become a generic success" {
  let result = source_graph_operation_result_json(true, "", [], 0, None)
  assert_true(
    decode_source_notice("renmae", "", ToJson::to_json(result).stringify())
    is InvalidExternalOperation,
  )
}
