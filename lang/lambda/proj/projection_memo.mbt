// Lambda projection memo builder.
// Uses the shared generic 3-memo projection pipeline: ProjNode, registry,
// and SourceMap. Lambda supplies a small root-module reconciliation hook so
// reordered `let` definitions keep their binding IDs without reviving the
// deleted flat projection memo stack.

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
    reconcile_node=reconcile_lambda_projection,
    label="lambda",
  )
}

///|
/// Reconcile Lambda's root module with definition-name keys before falling
/// back to generic shape-based reconciliation. Generic sibling LCS is correct
/// for ordinary expression children, but top-level `LetDef` siblings all share
/// the same kind; matching those rows by source position would reassign binding
/// IDs when definitions are reordered.
fn reconcile_lambda_projection(
  old : @core.ProjNode[@ast.Term],
  new_ : @core.ProjNode[@ast.Term],
  counter : Ref[Int],
) -> @core.ProjNode[@ast.Term] {
  match (old.kind, new_.kind) {
    (Module(_, _), Module(_, _)) =>
      reconcile_module_projection(
        ModuleProjection::from_proj_node(old),
        ModuleProjection::from_proj_node(new_),
        counter,
      ).to_proj_node_with_prev_module_id(counter, Some(old.node_id))
    _ => @core.reconcile(old, new_, counter)
  }
}
