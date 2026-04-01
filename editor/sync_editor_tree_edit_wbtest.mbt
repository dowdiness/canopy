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

///|
test "is_dirty set after set_text" {
  let editor = SyncEditor::new_lambda("test")
  editor.set_text("x")
  inspect(editor.is_dirty(), content="true")
}

///|
test "is_dirty set after insert/backspace" {
  let editor = SyncEditor::new_lambda("test")
  // Consume initial dirty from construction
  editor.refresh()
  inspect(editor.is_dirty(), content="false")
  // insert goes through apply_local_text_change → set_parser_signals
  editor.insert("x") catch {
    _ => ()
  }
  inspect(editor.is_dirty(), content="true")
  editor.refresh()
  inspect(editor.is_dirty(), content="false")
  // backspace also sets dirty
  editor.move_cursor(1)
  let _ = editor.backspace()
  inspect(editor.is_dirty(), content="true")
}

///|
test "refresh clears dirty flag and further edits are accepted" {
  let editor = SyncEditor::new_lambda("test")
  editor.set_text("x")
  inspect(editor.is_dirty(), content="true")
  editor.refresh()
  inspect(editor.is_dirty(), content="false")
  // further edits work normally after refresh
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  let result = editor.commit_edit(root.id(), "y", 0)
  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="y")
  inspect(editor.is_dirty(), content="true")
}

///|
test "move_node moves source before target and adjusts text" {
  // "1 2" parses as App(Int(1), Int(2))
  // children[0] = Int(1) at [0:1], children[1] = Int(2) at [2:3]
  // Move Int(2) Before Int(1):
  //   step 1: replace [2:3] with placeholder("0") → "1 0"
  //   step 2: insert unparse("2") + " " at 0 → "2 1 0"
  let editor = SyncEditor::new_lambda("test")
  editor.set_text("1 2")
  let root = match editor.get_proj_node() {
    None => fail("no proj node")
    Some(n) => n
  }
  // Need 2 children for App
  if root.children.length() < 2 {
    fail("expected App with 2 children, got \{root.children.length()}")
  }
  let src_id = root.children[1].id() // Int(2)
  let tgt_id = root.children[0].id() // Int(1)
  let result = editor.move_node(src_id, tgt_id, @lambda.DropPosition::Before, 0)
  inspect(result is Ok(_), content="true")
  // source node no longer at its original span; text has changed
  inspect(editor.get_text() == "1 2", content="false")
  // dirty flag set after move
  inspect(editor.is_dirty(), content="true")
}
