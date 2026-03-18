// Tests for the tree edit bridge roundtrip:
// TreeEditOp -> ProjNode (structural) -> unparse -> set_text_and_record -> memo reconcile

///|
fn setup_bridge(text : String) -> SyncEditor {
  let editor = SyncEditor::new("test")
  editor.set_text(text)
  editor
}

///|
fn get_root_id(editor : SyncEditor) -> @proj.NodeId {
  match editor.get_proj_node() {
    Some(node) => node.id()
    None => abort("No tree root")
  }
}

///|
fn assert_converged(editor : SyncEditor) -> Unit raise {
  let crdt_text = editor.get_text()
  let proj_text = match editor.get_proj_node() {
    Some(proj) => @ast.print_term(proj.kind)
    None => ""
  }
  assert_eq(crdt_text, proj_text)
}

///|
test "apply_tree_edit - Select preserves text" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(@proj.TreeEditOp::Select(node_id=id), 1)
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="42")
}

///|
test "apply_tree_edit - Collapse preserves text" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(@proj.TreeEditOp::Collapse(node_id=id), 1)
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="42")
}

///|
test "apply_tree_edit - WrapInLambda" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::WrapInLambda(node_id=id, var_name="x"),
    1,
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="(λx. 42)")
}

///|
test "apply_tree_edit - WrapInApp" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::WrapInApp(node_id=id),
    1,
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="(42 a)")
}

///|
test "apply_tree_edit - CommitEdit replaces value" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="99"),
    1,
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="99")
}

///|
test "apply_tree_edit - preserves cursor for follow-up text edits" {
  let editor = setup_bridge("42")
  editor.move_cursor(1)
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="99"),
    1,
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_cursor(), content="1")
  try! editor.insert("x")
  inspect(editor.get_text(), content="9x9")
}

///|
test "apply_tree_edit - CommitEdit with expression" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="λz.z"),
    1,
  )
  inspect(result, content="Ok(())")
  // New path: raw text splice — inserts user's text as-is (no normalization)
  inspect(editor.get_text(), content="λz.z")
}

///|
test "apply_tree_edit - ProjNode and text converge after WrapInLambda" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::WrapInLambda(node_id=id, var_name="y"),
    1,
  )
  inspect(result, content="Ok(())")
  assert_converged(editor)
}

///|
test "apply_tree_edit - ProjNode re-derives after CommitEdit with expression" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="λz.z"),
    1,
  )
  inspect(result, content="Ok(())")
  // New path: raw text splice means CRDT text is "λz.z" (user-typed form).
  // The memo chain re-parses and builds a valid lambda ProjNode.
  inspect(editor.get_text(), content="λz.z")
  match editor.get_proj_node() {
    Some(proj) => inspect(@ast.print_term(proj.kind), content="(λz. z)")
    None => abort("expected ProjNode after CommitEdit")
  }
}

///|
test "apply_tree_edit - WrapInLambda produces valid tree after memo reconcile" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::WrapInLambda(node_id=id, var_name="y"),
    1,
  )
  inspect(result, content="Ok(())")
  // New text path: node IDs are re-derived by the incremental parser,
  // so we verify a valid tree exists rather than ID preservation.
  inspect(editor.get_proj_node() is Some(_), content="true")
  inspect(editor.get_text(), content="(λy. 42)")
}

///|
test "apply_tree_edit - CommitEdit expression re-derives valid tree" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="λz.z"),
    1,
  )
  inspect(result, content="Ok(())")
  // New path: raw text splice — the memo chain re-derives a lambda node.
  match editor.get_proj_node() {
    Some(proj) => inspect(@ast.print_term(proj.kind), content="(λz. z)")
    None => abort("expected ProjNode after CommitEdit")
  }
}

///|
test "apply_tree_edit - Delete non-root node inserts valid placeholder" {
  let editor = setup_bridge("x + 1")
  let target = match editor.get_proj_node() {
    Some(root) => root.children[1].id()
    None => abort("No tree root")
  }
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::Delete(node_id=target),
    1,
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="(x + 0)")
  assert_converged(editor)
}

///|
test "apply_tree_edit - sequential edits" {
  let editor = setup_bridge("42")
  let id1 = get_root_id(editor)
  let result1 = editor.apply_tree_edit(
    @proj.TreeEditOp::WrapInLambda(node_id=id1, var_name="x"),
    1,
  )
  inspect(result1, content="Ok(())")
  inspect(editor.get_text(), content="(λx. 42)")
  let id2 = get_root_id(editor)
  let result2 = editor.apply_tree_edit(
    @proj.TreeEditOp::WrapInApp(node_id=id2),
    2,
  )
  inspect(result2, content="Ok(())")
  inspect(editor.get_text(), content="((λx. 42) a)")
  assert_converged(editor)
}

///|
test "apply_tree_edit - tree edits are undoable" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::WrapInLambda(node_id=id, var_name="x"),
    1,
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="(λx. 42)")
  inspect(editor.can_undo(), content="true")
  inspect(editor.undo(), content="true")
  inspect(editor.get_text(), content="42")
}
