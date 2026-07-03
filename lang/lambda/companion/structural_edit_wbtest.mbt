///|
test "structural_edit_op_to_tree_edit rebuilds known ops with unified label shape" {
  let nid = @core.NodeId::from_int(42)
  let wrap = structural_edit_op_to_tree_edit("WrapInLambda", nid).unwrap()
  inspect(
    wrap.to_generic().to_string(),
    content="StructuralEditKeepSelected(#42)",
  )
  let del = structural_edit_op_to_tree_edit("Delete", nid).unwrap()
  inspect(del.to_generic().to_string(), content="Delete(#42)")
}

///|
test "structural_edit_op_to_tree_edit returns None for unrebuildable ops" {
  let nid = @core.NodeId::from_int(7)
  inspect(structural_edit_op_to_tree_edit("Drop", nid) is None, content="true")
  inspect(structural_edit_op_to_tree_edit("", nid) is None, content="true")
  inspect(
    structural_edit_op_to_tree_edit("UnknownOp", nid) is None,
    content="true",
  )
}
