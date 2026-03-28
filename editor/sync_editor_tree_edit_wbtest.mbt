// Whitebox tests for generic Tier-2 tree edit methods.
// Uses SyncEditor[@ast.Term] via the lambda convenience constructor.

///|
test "delete_node replaces span with placeholder" {
  let editor = SyncEditor::new_lambda("test")
  editor.set_text("(λx. x)")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let result = editor.delete_node(root.id(), 0)
  inspect(result is Ok(_), content="true")
}

///|
test "commit_edit replaces span with new text" {
  let editor = SyncEditor::new_lambda("test")
  editor.set_text("x")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let result = editor.commit_edit(root.id(), "y", 0)
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="y")
}

///|
test "apply_text_transform wraps node in lambda" {
  let editor = SyncEditor::new_lambda("test")
  editor.set_text("x")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let result = editor.apply_text_transform(
    root.id(),
    fn(src, s, e) { Ok("(λy. " + src[s:e].to_string() + ")") },
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="(λy. x)")
}

///|
test "delete_node returns error for unknown node_id" {
  let editor = SyncEditor::new_lambda("test")
  editor.set_text("x")
  let _ = editor.get_proj_node()
  let bad_id = @proj.NodeId::from_int(99999)
  let result = editor.delete_node(bad_id, 0)
  inspect(result is Err(_), content="true")
}

///|
test "commit_edit returns error for unknown node_id" {
  let editor = SyncEditor::new_lambda("test")
  editor.set_text("x")
  let _ = editor.get_proj_node()
  let bad_id = @proj.NodeId::from_int(99999)
  let result = editor.commit_edit(bad_id, "y", 0)
  inspect(result is Err(_), content="true")
}
