// Tests for the tree edit bridge roundtrip:
// TreeEditOp -> CanonicalModel (structural) -> unparse -> set_text -> reparse

///|
/// Helper: create a SyncEditor + CanonicalModel pair initialized with the same text
fn setup_bridge(text : String) -> (SyncEditor, @proj.CanonicalModel) {
  let editor = SyncEditor::new("test")
  editor.set_text(text)
  let canonical = @proj.CanonicalModel::new()
  let _ = @proj.text_lens_put(canonical, text)
  (editor, canonical)
}

///|
/// Helper: get root NodeId from canonical model via TreeEditorState
fn get_root_id(canonical : @proj.CanonicalModel) -> @proj.NodeId {
  let state = @proj.TreeEditorState::from_model(canonical)
  match state.tree {
    Some(node) => node.id
    None => abort("No tree root")
  }
}

///|
/// Helper: assert CRDT text and canonical model text are equal
fn assert_converged(
  editor : SyncEditor,
  canonical : @proj.CanonicalModel,
) -> Unit raise {
  let crdt_text = editor.get_text()
  let canonical_text = match @proj.text_lens_get(canonical) {
    Ok(t) => t
    Err(msg) => abort("text_lens_get failed: " + msg)
  }
  assert_eq(crdt_text, canonical_text)
}

///|
test "apply_tree_edit - Select preserves text" {
  let (editor, canonical) = setup_bridge("42")
  let id = get_root_id(canonical)
  let result = editor.apply_tree_edit(
    canonical,
    @proj.TreeEditOp::Select(node_id=id),
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="42")
}

///|
test "apply_tree_edit - Collapse preserves text" {
  let (editor, canonical) = setup_bridge("42")
  let id = get_root_id(canonical)
  let result = editor.apply_tree_edit(
    canonical,
    @proj.TreeEditOp::Collapse(node_id=id),
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="42")
}

///|
test "apply_tree_edit - WrapInLambda" {
  let (editor, canonical) = setup_bridge("42")
  let id = get_root_id(canonical)
  let result = editor.apply_tree_edit(
    canonical,
    @proj.TreeEditOp::WrapInLambda(node_id=id, var_name="x"),
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="(λx. 42)")
}

///|
test "apply_tree_edit - WrapInApp" {
  let (editor, canonical) = setup_bridge("42")
  let id = get_root_id(canonical)
  let result = editor.apply_tree_edit(
    canonical,
    @proj.TreeEditOp::WrapInApp(node_id=id),
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="(42 a)")
}

///|
test "apply_tree_edit - CommitEdit replaces value" {
  let (editor, canonical) = setup_bridge("42")
  let id = get_root_id(canonical)
  let result = editor.apply_tree_edit(
    canonical,
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="99"),
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="99")
}

///|
test "apply_tree_edit - preserves cursor for follow-up text edits" {
  let (editor, canonical) = setup_bridge("42")
  editor.move_cursor(1)
  let id = get_root_id(canonical)
  let result = editor.apply_tree_edit(
    canonical,
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="99"),
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_cursor(), content="1")
  try! editor.insert("x")
  inspect(editor.get_text(), content="9x9")
}

///|
test "apply_tree_edit - CommitEdit with expression" {
  let (editor, canonical) = setup_bridge("42")
  let id = get_root_id(canonical)
  let result = editor.apply_tree_edit(
    canonical,
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="λz.z"),
  )
  inspect(result, content="Ok(())")
  // Parser canonicalizes λz.z -> (λz. z)
  inspect(editor.get_text(), content="(λz. z)")
}

///|
test "apply_tree_edit - CRDT and canonical converge after WrapInLambda" {
  let (editor, canonical) = setup_bridge("42")
  let id = get_root_id(canonical)
  let result = editor.apply_tree_edit(
    canonical,
    @proj.TreeEditOp::WrapInLambda(node_id=id, var_name="y"),
  )
  inspect(result, content="Ok(())")
  assert_converged(editor, canonical)
}

///|
test "apply_tree_edit - CRDT and canonical converge after CommitEdit" {
  let (editor, canonical) = setup_bridge("42")
  let id = get_root_id(canonical)
  let result = editor.apply_tree_edit(
    canonical,
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="λz.z"),
  )
  inspect(result, content="Ok(())")
  assert_converged(editor, canonical)
}

///|
test "apply_tree_edit - sequential edits" {
  let (editor, canonical) = setup_bridge("42")
  // First: wrap in lambda
  let id1 = get_root_id(canonical)
  let result1 = editor.apply_tree_edit(
    canonical,
    @proj.TreeEditOp::WrapInLambda(node_id=id1, var_name="x"),
  )
  inspect(result1, content="Ok(())")
  inspect(editor.get_text(), content="(λx. 42)")
  // Second: wrap the whole thing in an application
  let id2 = get_root_id(canonical)
  let result2 = editor.apply_tree_edit(
    canonical,
    @proj.TreeEditOp::WrapInApp(node_id=id2),
  )
  inspect(result2, content="Ok(())")
  inspect(editor.get_text(), content="((λx. 42) a)")
  // Verify convergence
  assert_converged(editor, canonical)
}
