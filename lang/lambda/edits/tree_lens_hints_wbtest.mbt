// Whitebox tests for TreeEditOp::to_identity_transform.
// Uses a stub get_node that returns None (covers the common Opaque/degrade path).

///|
fn no_node(_ : @core.NodeId) -> @core.ProjNode[@ast.Term]? {
  None
}

///|
test "WrapInLambda returns Wrap(inner=node_id)" {
  let id = @core.NodeId::from_int(5)
  let hint = TreeEditOp::WrapInLambda(node_id=id, var_name="x").to_identity_transform(
    no_node,
  )
  inspect(hint is @core.IdentityTransform::Wrap(inner=_), content="true")
  match hint {
    @core.IdentityTransform::Wrap(inner~) =>
      inspect(inner == id, content="true")
    _ => fail("expected Wrap")
  }
}

///|
test "WrapInApp returns Wrap(inner=node_id)" {
  let id = @core.NodeId::from_int(7)
  let hint = TreeEditOp::WrapInApp(node_id=id).to_identity_transform(no_node)
  inspect(hint is @core.IdentityTransform::Wrap(inner=_), content="true")
}

///|
test "WrapInIf returns Wrap(inner=node_id)" {
  let id = @core.NodeId::from_int(8)
  let hint = TreeEditOp::WrapInIf(node_id=id).to_identity_transform(no_node)
  inspect(hint is @core.IdentityTransform::Wrap(inner=_), content="true")
}

///|
test "ExtractToLet returns Opaque (not a structural Wrap; T3 conservative)" {
  let id = @core.NodeId::from_int(9)
  let hint = TreeEditOp::ExtractToLet(node_id=id, var_name="x").to_identity_transform(
    no_node,
  )
  inspect(hint is @core.IdentityTransform::Opaque, content="true")
}

///|
test "Unwrap returns Opaque when get_node returns None (T3: degrade)" {
  let wrapper_id = @core.NodeId::from_int(10)
  let hint = TreeEditOp::Unwrap(node_id=wrapper_id, keep_child_index=0).to_identity_transform(
    no_node,
  )
  inspect(hint is @core.IdentityTransform::Opaque, content="true")
}

///|
test "CommitEdit returns Replace" {
  let id = @core.NodeId::from_int(11)
  let hint = TreeEditOp::CommitEdit(node_id=id, new_value="x").to_identity_transform(
    no_node,
  )
  inspect(hint is @core.IdentityTransform::Replace(old=_), content="true")
  match hint {
    @core.IdentityTransform::Replace(old=old_id) =>
      inspect(old_id == id, content="true")
    _ => fail("expected Replace")
  }
}

///|
test "Rename returns RenameLeaf" {
  let id = @core.NodeId::from_int(12)
  let hint = TreeEditOp::Rename(node_id=id, new_name="bar").to_identity_transform(
    no_node,
  )
  inspect(hint is @core.IdentityTransform::RenameLeaf(node=_), content="true")
}

///|
test "InlineDefinition returns Replace" {
  let id = @core.NodeId::from_int(13)
  let hint = TreeEditOp::InlineDefinition(node_id=id).to_identity_transform(
    no_node,
  )
  inspect(hint is @core.IdentityTransform::Replace(old=_), content="true")
}

///|
test "Delete returns Opaque (LCS handles deletion natively)" {
  let id = @core.NodeId::from_int(14)
  let hint = TreeEditOp::Delete(node_id=id).to_identity_transform(no_node)
  inspect(hint is @core.IdentityTransform::Opaque, content="true")
}

///|
test "Drop returns Opaque (move_node taints instead)" {
  let src = @core.NodeId::from_int(15)
  let tgt = @core.NodeId::from_int(16)
  let hint = TreeEditOp::Drop(
    source=src,
    target=tgt,
    position=@core.DropPosition::Before,
  ).to_identity_transform(no_node)
  inspect(hint is @core.IdentityTransform::Opaque, content="true")
}

///|
test "SwapChildren returns Opaque" {
  let id = @core.NodeId::from_int(17)
  let hint = TreeEditOp::SwapChildren(node_id=id).to_identity_transform(no_node)
  inspect(hint is @core.IdentityTransform::Opaque, content="true")
}
