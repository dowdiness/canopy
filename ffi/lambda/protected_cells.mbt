// Lambda protected-cell bundle — typed view onto the editor surface that
// participates in workspace coordination.
//
// Each field wraps an editor or companion `Derived[T]` in a long-lived
// `Watch` (the GC root) via `ProtectedCell::from_derived`. The bundle is
// constructed from a freshly-built editor + companion inside
// `assemble_lambda_handle` (lifecycle.mbt) and erased to
// `Array[ProtectedRead]` for registration with the coordinator.
//
// See docs/superpowers/specs/2026-05-24-p0b-phase1-skeleton-design.md §8.1.

///|
/// Internal FFI assembly bundle. `priv` so the protected-surface shape
/// stays an implementation detail — Phase 1b production accessors live
/// in this same package and reach the fields directly. If a future
/// cross-package consumer (e.g., a separate workspace introspection
/// crate) needs the bundle, promote to `pub` then.
priv struct LambdaProtectedCells {
  parser_syntax_tree : @workspace.ProtectedCell[@seam.SyntaxNode]
  parser_ast : @workspace.ProtectedCell[@ast.Term]
  parser_source : @workspace.ProtectedCell[String]
  parser_diagnostics : @workspace.ProtectedCell[@loom.DiagnosticSet]
  cached_proj_node : @workspace.ProtectedCell[@core.ProjNode[@ast.Term]?]
  registry_memo : @workspace.ProtectedCell[
    Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  ]
  source_map_memo : @workspace.ProtectedCell[@core.SourceMap]
  proj_memo : @workspace.ProtectedCell[@lambda_flat.VersionedFlatProj]
  escalation_memo : @workspace.ProtectedCell[Array[@lambda_eval.EvalResult]]
  typecheck_output : @workspace.ProtectedCell[@typecheck.ModuleTypeResult]
}

///|
fn LambdaProtectedCells::LambdaProtectedCells(
  editor : @editor.SyncEditor[@ast.Term],
  companion : @lang_lambda.LambdaCompanion,
) -> LambdaProtectedCells {
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
    proj_memo: @workspace.ProtectedCell::from_derived(
      "proj_flat",
      companion.proj_memo(),
    ),
    escalation_memo: @workspace.ProtectedCell::from_derived(
      "escalation_memo",
      companion.escalation_memo(),
    ),
    typecheck_output: @workspace.ProtectedCell::from_derived(
      "typecheck_pipeline",
      companion.typecheck_output(),
    ),
  }
}

///|
/// Erase every typed cell to a registration-ready `ProtectedRead`. Order
/// is stable; downstream consumers must not depend on order.
fn LambdaProtectedCells::to_protected_reads(
  self : LambdaProtectedCells,
) -> Array[@workspace.ProtectedRead] {
  [
    self.parser_syntax_tree.erase(),
    self.parser_ast.erase(),
    self.parser_source.erase(),
    self.parser_diagnostics.erase(),
    self.cached_proj_node.erase(),
    self.registry_memo.erase(),
    self.source_map_memo.erase(),
    self.proj_memo.erase(),
    self.escalation_memo.erase(),
    self.typecheck_output.erase(),
  ]
}
