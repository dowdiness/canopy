///|
/// Map a standard structural-edit op string to a typed `TreeEditOp`. Used
/// on both the direct-apply path (`apply_structural_edit_request`, from
/// Inspector / Web Component `STRUCTURAL_EDIT_REQUEST`) and the FFI-applied
/// path (`StructureStructuralEdit`, from `STRUCTURAL_EDIT_APPLIED`) so the
/// Op Log row shape matches in both. Must stay in sync with the dispatch
/// sites in `view_inspector.mbt` and `web/src/keymap.ts`. Returns `None`
/// for ops outside the standard set — notably `"Drop"`, whose `source` /
/// `position` payload is not recoverable from `(op, node_id)` alone.
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
