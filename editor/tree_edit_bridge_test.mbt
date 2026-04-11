// Tests for the tree edit bridge roundtrip:
// TreeEditOp -> ProjNode (structural) -> unparse -> set_text_and_record -> memo reconcile

///|
fn setup_bridge(
  text : String,
) -> (SyncEditor[@ast.Term], @lambda.LambdaCompanion) {
  let (editor, companion) = @lambda.new_lambda_editor("test")
  editor.set_text(text)
  (editor, companion)
}

///|
fn get_root_id(editor : SyncEditor[@ast.Term]) -> @core.NodeId raise {
  match editor.get_proj_node() {
    Some(node) => node.id()
    None => fail("expected tree root")
  }
}

///|
fn assert_converged(editor : SyncEditor[@ast.Term]) -> Unit raise {
  let crdt_text = editor.get_text()
  let proj_text = match editor.get_proj_node() {
    Some(proj) => @ast.print_term(proj.kind)
    None => ""
  }
  assert_eq(crdt_text, proj_text)
}

///|
test "apply_tree_edit - Select preserves text" {
  let (editor, companion) = setup_bridge("42")
  let id = get_root_id(editor)
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::Select(node_id=id),
    1,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="42")
}

///|
test "apply_tree_edit - Collapse preserves text" {
  let (editor, companion) = setup_bridge("42")
  let id = get_root_id(editor)
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::Collapse(node_id=id),
    1,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="42")
}

///|
test "apply_tree_edit - WrapInLambda" {
  let (editor, companion) = setup_bridge("42")
  let id = get_root_id(editor)
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::WrapInLambda(node_id=id, var_name="x"),
    1,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="(λx. 42)")
}

///|
test "apply_tree_edit - WrapInApp" {
  let (editor, companion) = setup_bridge("42")
  let id = get_root_id(editor)
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::WrapInApp(node_id=id),
    1,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="(42 a)")
}

///|
test "apply_tree_edit - CommitEdit replaces value" {
  let (editor, companion) = setup_bridge("42")
  let id = get_root_id(editor)
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::CommitEdit(node_id=id, new_value="99"),
    1,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="99")
}

///|
test "apply_tree_edit - preserves cursor for follow-up text edits" {
  let (editor, companion) = setup_bridge("42")
  editor.move_cursor(1)
  let id = get_root_id(editor)
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::CommitEdit(node_id=id, new_value="99"),
    1,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_cursor(), content="1")
  try! editor.insert("x")
  inspect(editor.get_text(), content="9x9")
}

///|
test "apply_tree_edit - CommitEdit with expression" {
  let (editor, companion) = setup_bridge("42")
  let id = get_root_id(editor)
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::CommitEdit(node_id=id, new_value="λz.z"),
    1,
  )
  inspect(result is Ok(_), content="true")
  // New path: raw text splice — inserts user's text as-is (no normalization)
  inspect(editor.get_text(), content="λz.z")
}

///|
test "apply_tree_edit - ProjNode and text converge after WrapInLambda" {
  let (editor, companion) = setup_bridge("42")
  let id = get_root_id(editor)
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::WrapInLambda(node_id=id, var_name="y"),
    1,
  )
  inspect(result is Ok(_), content="true")
  assert_converged(editor)
}

///|
test "apply_tree_edit - ProjNode re-derives after CommitEdit with expression" {
  let (editor, companion) = setup_bridge("42")
  let id = get_root_id(editor)
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::CommitEdit(node_id=id, new_value="λz.z"),
    1,
  )
  inspect(result is Ok(_), content="true")
  // New path: raw text splice means CRDT text is "λz.z" (user-typed form).
  // The memo chain re-parses and builds a valid lambda ProjNode.
  inspect(editor.get_text(), content="λz.z")
  guard editor.get_proj_node() is Some(proj)
  inspect(@ast.print_term(proj.kind), content="(λz. z)")
}

///|
test "apply_tree_edit - WrapInLambda produces valid tree after memo reconcile" {
  let (editor, companion) = setup_bridge("42")
  let id = get_root_id(editor)
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::WrapInLambda(node_id=id, var_name="y"),
    1,
  )
  inspect(result is Ok(_), content="true")
  // New text path: node IDs are re-derived by the incremental parser,
  // so we verify a valid tree exists rather than ID preservation.
  inspect(editor.get_proj_node() is Some(_), content="true")
  inspect(editor.get_text(), content="(λy. 42)")
}

///|
test "apply_tree_edit - CommitEdit expression re-derives valid tree" {
  let (editor, companion) = setup_bridge("42")
  let id = get_root_id(editor)
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::CommitEdit(node_id=id, new_value="λz.z"),
    1,
  )
  inspect(result is Ok(_), content="true")
  // New path: raw text splice — the memo chain re-derives a lambda node.
  guard editor.get_proj_node() is Some(proj2)
  inspect(@ast.print_term(proj2.kind), content="(λz. z)")
}

///|
test "apply_tree_edit - Delete non-root node inserts valid placeholder" {
  let (editor, companion) = setup_bridge("x + 1")
  let target = match editor.get_proj_node() {
    Some(root) => root.children[1].id()
    None => fail("expected tree root")
  }
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::Delete(node_id=target),
    1,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="(x + 0)")
  assert_converged(editor)
}

///|
test "apply_tree_edit - sequential edits" {
  let (editor, companion) = setup_bridge("42")
  let id1 = get_root_id(editor)
  let result1 = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::WrapInLambda(node_id=id1, var_name="x"),
    1,
  )
  inspect(result1 is Ok(_), content="true")
  inspect(editor.get_text(), content="(λx. 42)")
  let id2 = get_root_id(editor)
  let result2 = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::WrapInApp(node_id=id2),
    2,
  )
  inspect(result2 is Ok(_), content="true")
  inspect(editor.get_text(), content="((λx. 42) a)")
  assert_converged(editor)
}

///|
test "apply_tree_edit - tree edits are undoable" {
  let (editor, companion) = setup_bridge("42")
  let id = get_root_id(editor)
  let result = @lambda.apply_lambda_tree_edit(
    editor,
    companion,
    @lambda.TreeEditOp::WrapInLambda(node_id=id, var_name="x"),
    1,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="(λx. 42)")
  inspect(editor.can_undo(), content="true")
  inspect(editor.undo(), content="true")
  inspect(editor.get_text(), content="42")
}
