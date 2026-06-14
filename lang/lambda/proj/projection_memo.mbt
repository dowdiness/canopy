// Lambda projection memo builder.
// Uses the shared generic 3-memo projection pipeline: ProjNode, registry,
// and SourceMap. Legacy ModuleProjection helpers remain in this package for
// tests and the #634 follow-up, not in the editor-facing stack.

///|
/// Build the 3-memo pipeline (proj, registry, source_map) for the Lambda
/// editor-facing projection.
pub fn build_lambda_projection_memos(
  parser : @loom.Parser[@ast.Term],
) -> (
  @incr.Derived[@core.ProjNode[@ast.Term]?],
  @incr.Derived[Map[@core.NodeId, @core.ProjNode[@ast.Term]]],
  @incr.Derived[@core.SourceMap],
) {
  @core.build_projection_memos(
    parser.runtime(),
    parser.syntax_tree(),
    to_proj_node,
    populate_token_spans,
    label="lambda",
  )
}
