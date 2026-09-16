///|
fn source_demo_test_model() -> SourceDemoModel {
  {
    handle: -1,
    editor: "osc = sine(freq: 440Hz)",
    dirty: true,
    parser_failed: false,
    mounted: true,
    status: "previous status",
    status_tone: @status.Info,
    on_change: fn() { () },
  }
}

///|
test "external source operation result is folded into the Source model" {
  let result = source_graph_operation_result_json(
    true,
    "lfo = sine(freq: 440Hz)",
    [],
    1,
    None,
  )
  let emit = @cmd.Emit(_ => @rabbita.none)
  let (_, next) = source_demo_update(
    emit,
    ExternalOperation("rename", "", ToJson::to_json(result).stringify()),
    source_demo_test_model(),
  )
  inspect(next.editor, content="lfo = sine(freq: 440Hz)")
  inspect(next.dirty, content="false")
  inspect(next.status, content="Renamed node binding through graph-dsl source.")
  assert_true(next.status_tone == @status.Success)
}

///|
test "external source rejection preserves editor validity and reports through the Source model" {
  let result = source_graph_operation_result_json(
    false,
    "osc = sine(freq: 440Hz)",
    ["meter still references deleted binding osc"],
    0,
    None,
  )
  let emit = @cmd.Emit(_ => @rabbita.none)
  let (_, next) = source_demo_update(
    emit,
    ExternalOperation("delete", "", ToJson::to_json(result).stringify()),
    source_demo_test_model(),
  )
  inspect(next.editor, content="osc = sine(freq: 440Hz)")
  inspect(next.dirty, content="true")
  inspect(
    next.status,
    content="Source delete rejected: meter still references deleted binding osc",
  )
  assert_true(next.status_tone == @status.Error)
}
