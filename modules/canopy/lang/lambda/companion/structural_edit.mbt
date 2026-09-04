///|
/// Map a standard Inspector operation string to a typed `TreeEditOp`.
/// Keep this in sync with the dispatch sites in `view_inspector.mbt`.
/// Returns `None` for operations whose complete payload cannot be represented
/// by `(op, node_id)`; rich Structure input uses typed `TreeEditOp` values.
pub fn structural_edit_op_to_tree_edit(
  op : String,
  node_id : @core.NodeId,
) -> @lambda_edits.TreeEditOp? {
  match op {
    "WrapInLambda" => Some(@lambda_edits.WrapInLambda(node_id~, var_name="x"))
    "Delete" => Some(@lambda_edits.Delete(node_id~))
    _ => None
  }
}
