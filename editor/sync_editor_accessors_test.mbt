// Tests for SyncEditor typed accessor methods.
// Verifies that each accessor returns a Derived cell that can be read
// on a freshly-constructed editor with empty source.

///|
test "SyncEditor exposes typed accessors for protected cells" {
  // Use the neutral TestExpr editor as a known concrete instance; this test
  // demonstrates that each accessor returns a Derived cell whose read
  // does not abort on a freshly-constructed editor with empty source.
  // The `let typed : T = ...` lines pin the return types; the
  // `.read_or_abort()` calls exercise the cells so a regression that
  // makes any of them abort at construction time would fail the test.
  let editor = try! @probe.new_test_editor("test")
  let source_cell : @incr.Derived[String] = editor.parser_source()
  let _ = source_cell.read_or_abort()
  let ast_cell : @incr.Derived[@probe.TestExpr] = editor.parser_ast()
  let _ = ast_cell.read_or_abort()
  let diag_cell : @incr.Derived[@loom.DiagnosticSet] = editor.parser_diagnostics()
  let _ = diag_cell.read_or_abort()
  let proj_cell : @incr.Derived[@core.ProjNode[@probe.TestExpr]?] = editor.cached_proj_node()
  let _ = proj_cell.read_or_abort()
  let registry_cell : @incr.Derived[
    Map[@core.NodeId, @core.ProjNode[@probe.TestExpr]],
  ] = editor.registry_memo()
  let _ = registry_cell.read_or_abort()
  let source_map_cell : @incr.Derived[@core.SourceMap] = editor.source_map_memo()
  let _ = source_map_cell.read_or_abort()
}
