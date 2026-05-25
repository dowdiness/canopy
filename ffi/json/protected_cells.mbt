// JSON protected-cell bundle — typed view onto the editor surface that
// participates in workspace coordination.
//
// Each field wraps an editor `Derived[T]` in a long-lived `Watch` (the GC
// root) via `ProtectedCell::from_derived`. The bundle is constructed from a
// freshly-built editor inside `assemble_json_handle` (json_ffi.mbt) and
// erased to `Array[ProtectedRead]` for registration with the coordinator.
//
// 7-cell SyncEditor-generic subset (no language companion + no typecheck
// pipeline). See docs/superpowers/specs/2026-05-25-p0b-phase1b-ws2-design.md
// §5.1.

///|
priv struct JsonProtectedCells {
  parser_syntax_tree : @workspace.ProtectedCell[@seam.SyntaxNode]
  parser_ast : @workspace.ProtectedCell[@djson.JsonValue]
  parser_source : @workspace.ProtectedCell[String]
  parser_diagnostics : @workspace.ProtectedCell[@loom.DiagnosticSet]
  cached_proj_node : @workspace.ProtectedCell[@core.ProjNode[@djson.JsonValue]?]
  registry_memo : @workspace.ProtectedCell[
    Map[@core.NodeId, @core.ProjNode[@djson.JsonValue]],
  ]
  source_map_memo : @workspace.ProtectedCell[@core.SourceMap]
}

///|
fn JsonProtectedCells::JsonProtectedCells(
  editor : @editor.SyncEditor[@djson.JsonValue],
) -> JsonProtectedCells {
  {
    parser_syntax_tree: @workspace.ProtectedCell::from_derived(
      "parser_syntax_view",
      editor.parser_syntax_tree(),
    ),
    parser_ast: @workspace.ProtectedCell::from_derived(
      "parser_ast_view",
      editor.parser_ast(),
    ),
    parser_source: @workspace.ProtectedCell::from_derived(
      "parser_source_view",
      editor.parser_source(),
    ),
    parser_diagnostics: @workspace.ProtectedCell::from_derived(
      "parser_diagnostics_view",
      editor.parser_diagnostics(),
    ),
    cached_proj_node: @workspace.ProtectedCell::from_derived(
      "cached_proj_node",
      editor.cached_proj_node(),
    ),
    registry_memo: @workspace.ProtectedCell::from_derived(
      "proj_registry",
      editor.registry_memo(),
    ),
    source_map_memo: @workspace.ProtectedCell::from_derived(
      "source_map",
      editor.source_map_memo(),
    ),
  }
}

///|
fn JsonProtectedCells::to_protected_reads(
  self : JsonProtectedCells,
) -> Array[@workspace.ProtectedRead] {
  [
    self.parser_syntax_tree.erase(),
    self.parser_ast.erase(),
    self.parser_source.erase(),
    self.parser_diagnostics.erase(),
    self.cached_proj_node.erase(),
    self.registry_memo.erase(),
    self.source_map_memo.erase(),
  ]
}
