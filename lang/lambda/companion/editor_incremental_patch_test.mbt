// Lambda resolution + lambda-flat incremental-projection tests for the lambda
// editor. Moved here from editor/sync_editor_test.mbt as part of the
// editor-neutral-test-grammar work (#599): these depend on lambda's
// resolution and on the lambda-flat incremental projection (Module / def-index
// / final_expr / synthesized Unit body), which the language-agnostic editor's
// generic projection does not provide.

///|
fn count_nodes(node : @core.ProjNode[@ast.Term]) -> Int {
  let mut count = 1
  for child in node.children {
    count = count + count_nodes(child)
  }
  count
}

///|
test "SyncEditor: get_resolution returns bound/free info" {
  let se = new_lambda_editor("agent1").0
  // λx. (x + y) — x is bound, y is free
  try! se.insert("\\x. x + y")
  let res = get_lambda_resolution(se)
  // Pre-order: 0=Lam, 1=Bop, 2=Var(x), 3=Var(y)
  @debug.debug_inspect(res.vars.get(2), content="Some(Bound(depth=1))")
  @debug.debug_inspect(res.vars.get(3), content="Some(Free)")
}

///|
test "incremental patch: registry node count stable after tail edit" {
  let editor = new_lambda_editor("test").0
  editor.set_text("let x = 1\nlet y = 2\nlet z = 0\nz")
  ignore(editor.get_proj_node())
  ignore(editor.get_source_map())
  let node_count_before = match editor.get_proj_node() {
    Some(r) => count_nodes(r)
    None => 0
  }
  // Edit tail def value: 0 → 9
  let text = editor.get_text()
  let pos = text.length() - 3 // position of '0' in "z = 0"
  editor.move_cursor(pos)
  ignore(editor.backspace())
  try! editor.insert("9")
  let node_count_after = match editor.get_proj_node() {
    Some(r) => count_nodes(r)
    None => 0
  }
  inspect(node_count_before == node_count_after, content="true")
}

///|
test "incremental patch: source_map position queries work after edit" {
  let editor = new_lambda_editor("test").0
  editor.set_text("let x = 1\nlet y = 2\ny")
  ignore(editor.get_source_map()) // warm up
  // Edit: y=2 → y=3
  let text = editor.get_text()
  let pos = text.length() - 3 // position of '2'
  editor.move_cursor(pos)
  ignore(editor.backspace())
  try! editor.insert("3")
  let sm = editor.get_source_map()
  // Position query should still find nodes
  inspect(sm.innermost_node_at(0) is Some(_), content="true")
  inspect(sm.innermost_node_at(pos) is Some(_), content="true")
}

///|
test "incremental patch: get_node returns correct node after edit" {
  let editor = new_lambda_editor("test").0
  editor.set_text("let x = 1\nlet y = 2\ny")
  let proj = editor.get_proj_node().unwrap()
  // Get node ID of x's init (Int(1)) — child of the first LetDef
  let x_init_id = proj.children[0].children[0].id()
  // Edit y's init: 2 → 3
  let text = editor.get_text()
  let pos = text.length() - 3
  editor.move_cursor(pos)
  ignore(editor.backspace())
  try! editor.insert("3")
  // x's init should still be retrievable with same ID
  match editor.get_node(x_init_id) {
    Some(node) => inspect(node.kind, content="Int(1)")
    None => fail("x init node not found after y edit")
  }
}

///|
test "incremental patch: expression-only document edit works" {
  // Expression-only: no defs, ProjNode is NOT a Module.
  // Patch path must fall back to full rebuild.
  let editor = new_lambda_editor("test").0
  editor.set_text("42")
  let sm1 = editor.get_source_map()
  inspect(sm1.innermost_node_at(0) is Some(_), content="true")
  // Edit: 42 → 99
  editor.move_cursor(0)
  ignore(editor.backspace())
  ignore(editor.backspace())
  try! editor.insert("9")
  try! editor.insert("9")
  let sm2 = editor.get_source_map()
  inspect(sm2.innermost_node_at(0) is Some(_), content="true")
}

///|
test "incremental patch: final_expr removal triggers full rebuild" {
  // Remove final expression: "let x = 1\nx" → "let x = 1\n"
  let editor = new_lambda_editor("test").0
  editor.set_text("let x = 1\nx")
  ignore(editor.get_proj_node())
  ignore(editor.get_source_map())
  // Delete the final 'x'
  let text = editor.get_text()
  editor.move_cursor(text.length())
  ignore(editor.backspace())
  let proj = editor.get_proj_node()
  // Should still have a valid projection (Module with Unit body)
  inspect(proj is Some(_), content="true")
}

///|
test "incremental patch: no-final-expr module keeps body node registered" {
  // Module with no trailing expression: "let x = 1\n"
  // to_proj_node_with_prev_module_id synthesizes a Unit body each time.
  // The patch path must update the body even when only defs change.
  let editor = new_lambda_editor("test").0
  editor.set_text("let x = 0\nlet y = 2\n")
  let proj1 = editor.get_proj_node().unwrap()
  // Body is the last child (synthesized Unit)
  let _body1_id = proj1.children[proj1.children.length() - 1].id()
  ignore(editor.get_source_map())
  // Edit def x: 0 → 9
  editor.move_cursor(9) // position after '0' in "let x = 0" (index 8 is '0', cursor at 9)
  ignore(editor.backspace())
  try! editor.insert("9")
  let proj2 = editor.get_proj_node().unwrap()
  let body2_id = proj2.children[proj2.children.length() - 1].id()
  // The new body node should be findable in the registry
  inspect(editor.get_node(body2_id) is Some(_), content="true")
  // The new body node range should be in the source map
  inspect(editor.get_node_range(body2_id) is Some(_), content="true")
}
