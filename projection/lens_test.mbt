// Tests for the projection infrastructure after CanonicalModel removal.

///|
test "SourceMap from_ast" {
  let (root, _) = @lambda_proj.parse_to_proj_node("42")
  let source_map = SourceMap::from_ast(root)
  inspect(source_map.node_count() >= 1, content="true")
}

///|
test "parse_to_proj_node preserves child-specific ranges" {
  let (root, _) = @lambda_proj.parse_to_proj_node("x + 1")
  inspect(root.children.length(), content="2")
  inspect(root.children[0].start < root.children[1].start, content="true")
  inspect(root.children[0].end <= root.children[1].start, content="true")
}

///|
test "SourceMap innermost_node_at distinguishes operands" {
  let (root, _) = @lambda_proj.parse_to_proj_node("x + 1")
  let source_map = SourceMap::from_ast(root)
  let left_pos = root.children[0].start
  let right_pos = if root.children[1].end > root.children[1].start {
    root.children[1].end - 1
  } else {
    root.children[1].start
  }
  inspect(
    source_map.innermost_node_at(left_pos) == Some(root.children[0].id()),
    content="true",
  )
  inspect(
    source_map.innermost_node_at(right_pos) == Some(root.children[1].id()),
    content="true",
  )
}

///|
test "TreeEditorState from_projection" {
  let (root, _) = @lambda_proj.parse_to_proj_node("x + 1")
  let state = TreeEditorState::from_projection(
    Some(root),
    SourceMap::from_ast(root),
  )
  inspect(state.tree is Some(_), content="true")
}

///|
test "InteractiveTreeNode from AstNode" {
  let (root, _) = @lambda_proj.parse_to_proj_node("λx.x")
  let tree = InteractiveTreeNode::from_term_node(
    root,
    SourceMap::from_ast(root),
  )
  inspect(tree.label[:1].to_string(), content="λ")
}

///|
test "reconcile_ast preserves IDs for matching nodes" {
  let (old_root, _) = @lambda_proj.parse_to_proj_node("x + 1")
  let (new_root, _) = @lambda_proj.parse_to_proj_node("x + 2")
  let reconciled = @core.reconcile(old_root, new_root, Ref::new(100))
  inspect(reconciled.node_id, content=old_root.node_id.to_string())
  inspect(
    reconciled.children[0].node_id,
    content=old_root.children[0].node_id.to_string(),
  )
  inspect(@ast.print_term(reconciled.kind), content="(x + 2)")
}

///|
test "reconcile_ast preserves IDs across operator-only edits" {
  let (old_root, _) = @lambda_proj.parse_to_proj_node("x + 1")
  let (new_root, _) = @lambda_proj.parse_to_proj_node("x - 1")
  let reconciled = @core.reconcile(old_root, new_root, Ref::new(100))
  inspect(reconciled.node_id, content=old_root.node_id.to_string())
  inspect(
    reconciled.children[0].node_id,
    content=old_root.children[0].node_id.to_string(),
  )
  inspect(
    reconciled.children[1].node_id,
    content=old_root.children[1].node_id.to_string(),
  )
  inspect(@ast.print_term(reconciled.kind), content="(x - 1)")
}

///|
test "reconcile_ast shrinks rebuilt source map when children disappear" {
  let (old_root, _) = @lambda_proj.parse_to_proj_node("1 + 2 + 3")
  let (new_root, _) = @lambda_proj.parse_to_proj_node("1 + 2")
  let reconciled = @core.reconcile(old_root, new_root, Ref::new(100))
  inspect(
    SourceMap::from_ast(reconciled).node_count() <
    SourceMap::from_ast(old_root).node_count(),
    content="true",
  )
}

///|
test "node_at_position covers parenthesis positions" {
  let (root, _) = @lambda_proj.parse_to_proj_node("(x)")
  let source_map = SourceMap::from_ast(root)
  inspect(source_map.innermost_node_at(0) is None, content="false")
  inspect(source_map.innermost_node_at(2) is None, content="false")
  inspect(root.start, content="0")
  inspect(root.end, content="3")
}
