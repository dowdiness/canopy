///|
test "SyncEditor keeps its projection graph rooted across runtime collection" {
  let editor = try! @probe.new_test_editor("projection-root-owner")
  editor.set_text("x")
  editor.refresh()
  let projection = editor.cached_proj_node()
  let registry = editor.registry_memo()
  let source_map = editor.source_map_memo()

  editor.parser_runtime().gc()
  editor.parser_runtime().gc()

  let _ = projection.read_or_abort()
  let _ = registry.read_or_abort()
  let _ = source_map.read_or_abort()
}

///|
test "SyncEditor source identity is construction-scoped and stable across edits" {
  let first = try! @probe.new_test_editor("shared-agent")
  let second = try! @probe.new_test_editor("shared-agent")
  let initial : @loom_core.SourceId = first.parser_source_id()

  inspect(initial == second.parser_source_id(), content="false")
  first.set_text("x")
  inspect(first.parser_source_id() == initial, content="true")
  first.apply_text_edit(1, 0, "y", 1)
  inspect(first.parser_source_id() == initial, content="true")
}
