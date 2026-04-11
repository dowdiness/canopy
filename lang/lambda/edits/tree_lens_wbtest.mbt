// Tree lens whitebox tests removed — old apply_edit_to_proj path is dead code.
// compute_text_edit tests in text_edit_wbtest.mbt cover all TreeEditOp variants.

///|
test "to_generic: WrapInLambda maps to StructuralEditKeepSelected" {
  let nid = NodeId::from_int(1)
  let op = TreeEditOp::WrapInLambda(node_id=nid, var_name="x")
  let g = op.to_generic()
  inspect(g, content="StructuralEditKeepSelected(node_id=NodeId(1))")
}

///|
test "to_generic: WrapInApp maps to StructuralEditKeepSelected" {
  let nid = NodeId::from_int(2)
  let op = TreeEditOp::WrapInApp(node_id=nid)
  let g = op.to_generic()
  inspect(g, content="StructuralEditKeepSelected(node_id=NodeId(2))")
}

///|
test "to_generic: InsertChild drops kind field" {
  let parent = NodeId::from_int(3)
  let op = TreeEditOp::InsertChild(parent~, index=1, kind=@ast.Term::Int(42))
  let g = op.to_generic()
  inspect(g, content="InsertChild(parent=NodeId(3), index=1)")
}

///|
test "to_generic: structural ops map to StructuralEdit" {
  let nid = NodeId::from_int(4)
  let unwrap = TreeEditOp::Unwrap(node_id=nid, keep_child_index=0).to_generic()
  inspect(unwrap, content="StructuralEdit(node_id=NodeId(4))")
  let rename = TreeEditOp::Rename(node_id=nid, new_name="y").to_generic()
  inspect(rename, content="StructuralEdit(node_id=NodeId(4))")
}

///|
test "to_generic: binding ops map to StructuralEdit with binding_node_id" {
  let nid = NodeId::from_int(5)
  let del = TreeEditOp::DeleteBinding(binding_node_id=nid).to_generic()
  inspect(del, content="StructuralEdit(node_id=NodeId(5))")
  let dup = TreeEditOp::DuplicateBinding(binding_node_id=nid).to_generic()
  inspect(dup, content="StructuralEdit(node_id=NodeId(5))")
}
