// Tests for SyncEditor

///|
fn insert_each(se : SyncEditor[@ast.Term], text : String) -> Unit raise {
  se.insert(text)
}

///|
fn insert_each_and_record(
  se : SyncEditor[@ast.Term],
  text : String,
  timestamp_ms : Int,
) -> Unit raise {
  se.insert_and_record(text, timestamp_ms)
}

///|
test "SyncEditor: create and insert text" {
  let se = SyncEditor::new_lambda("agent1")
  try! se.insert("x")
  inspect(se.get_text(), content="x")
  let ast = se.get_ast()
  inspect(@ast.print_term(ast), content="x")
}

///|
test "SyncEditor: sequential inserts update AST" {
  let se = SyncEditor::new_lambda("agent1")
  try! se.insert("x")
  inspect(@ast.print_term(se.get_ast()), content="x")
  try! insert_each(se, " + 1")
  inspect(@ast.print_term(se.get_ast()), content="(x + 1)")
}

///|
test "SyncEditor: delete updates AST" {
  let se = SyncEditor::new_lambda("agent1")
  try! insert_each(se, "123")
  inspect(se.get_text(), content="123")
  let deleted = se.backspace()
  inspect(deleted, content="true")
  inspect(se.get_text(), content="12")
}

///|
test "SyncEditor: parse error handling" {
  let se = SyncEditor::new_lambda("agent1")
  try! insert_each(se, "λ.")
  let _ast = se.get_ast()
  inspect(se.is_parse_valid(), content="false")
}

///|
test "SyncEditor: cursor tracking" {
  let se = SyncEditor::new_lambda("agent1")
  inspect(se.get_cursor(), content="0")
  try! insert_each(se, "abc")
  inspect(se.get_cursor(), content="3")
  se.move_cursor(1)
  inspect(se.get_cursor(), content="1")
}

///|
test "SyncEditor: concurrent edits converge" {
  let se1 = SyncEditor::new_lambda("agent1")
  let se2 = SyncEditor::new_lambda("agent2")
  try! se1.insert("x")
  try! se2.apply_sync(try! se1.export_all())
  inspect(se1.get_text(), content="x")
  inspect(se2.get_text(), content="x")
  try! insert_each(se1, " + 1")
  try! insert_each(se2, " - 2")
  try! se1.apply_sync(try! se2.export_all())
  try! se2.apply_sync(try! se1.export_all())
  let text1 = se1.get_text()
  let text2 = se2.get_text()
  inspect(text1 == text2, content="true")
  inspect(
    @ast.print_term(se1.get_ast()) == @ast.print_term(se2.get_ast()),
    content="true",
  )
}

///|
test "SyncEditor: collaborative lambda editing" {
  let se1 = SyncEditor::new_lambda("agent1")
  let se2 = SyncEditor::new_lambda("agent2")
  try! insert_each(se1, "λx.")
  try! se2.apply_sync(try! se1.export_all())
  inspect(se1.get_text(), content="λx.")
  inspect(se2.get_text(), content="λx.")
  try! insert_each(se1, "x + 1")
  try! insert_each(se2, "x - 1")
  try! se1.apply_sync(try! se2.export_all())
  try! se2.apply_sync(try! se1.export_all())
  inspect(se1.get_text() == se2.get_text(), content="true")
  inspect(
    @ast.print_term(se1.get_ast()) == @ast.print_term(se2.get_ast()),
    content="true",
  )
}

///|
test "SyncEditor: incremental parsing vs full reparse" {
  let se = SyncEditor::new_lambda("agent1")
  try! insert_each(se, "λf.λx.if f x then x + 1 else x - 1")
  let _ast1 = se.get_ast()
  se.move_cursor(34)
  let _deleted = se.backspace()
  try! se.insert("2")
  let ast2 = se.get_ast()
  inspect(
    @ast.print_term(ast2),
    content="(λf. (λx. if (f x) then (x + 1) else (x - 2)))",
  )
}

///|
test "SyncEditor: empty document" {
  let se = SyncEditor::new_lambda("agent1")
  inspect(se.get_text(), content="")
  let _ast = se.get_ast()
}

///|
test "SyncEditor: backspace at start returns false" {
  let se = SyncEditor::new_lambda("agent1")
  try! insert_each(se, "abc")
  se.move_cursor(0)
  inspect(se.backspace(), content="false")
  inspect(se.get_text(), content="abc")
}

///|
test "SyncEditor: delete at end returns false" {
  let se = SyncEditor::new_lambda("agent1")
  try! insert_each(se, "abc")
  se.move_cursor(3)
  inspect(se.delete(), content="false")
  inspect(se.get_text(), content="abc")
}

///|
test "SyncEditor: export_all produces non-empty message" {
  let se = SyncEditor::new_lambda("agent1")
  try! se.insert("x")
  let msg = try! se.export_all()
  inspect(msg.op_count() > 0, content="true")
}

///|
test "SyncEditor: lazy AST evaluation" {
  let se = SyncEditor::new_lambda("agent1")
  try! se.insert("x")
  let _ast1 = se.get_ast()
  let ast2 = se.get_ast()
  inspect(@ast.print_term(ast2), content="x")
}

///|
test "SyncEditor: merge invalidates AST cache" {
  let se1 = SyncEditor::new_lambda("agent1")
  let se2 = SyncEditor::new_lambda("agent2")
  try! se1.insert("x")
  try! se2.apply_sync(try! se1.export_all())
  let _ast1 = se1.get_ast()
  try! se2.insert("y")
  try! se1.apply_sync(try! se2.export_all())
  let _ast2 = se1.get_ast()
  inspect(
    se1.get_text(),
    content=(
      #|yx
    ),
  )
}

///|
test "SyncEditor: insert_and_record + undo roundtrip" {
  let se = SyncEditor::new_lambda("agent1")
  try! insert_each_and_record(se, "hello", 1000)
  inspect(se.get_text(), content="hello")
  inspect(se.can_undo(), content="true")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="")
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
  inspect(se.can_redo(), content="true")
  let redone = se.redo()
  inspect(redone, content="true")
  inspect(se.get_text(), content="hello")
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
  try! se.insert_and_record("!", 3000)
  inspect(se.get_text().length(), content="6")
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
}

///|
test "SyncEditor: backspace_and_record + undo" {
  let se = SyncEditor::new_lambda("agent1")
  try! insert_each_and_record(se, "abc", 1000)
  let deleted = se.backspace_and_record(2000)
  inspect(deleted, content="true")
  inspect(se.get_text(), content="ab")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="abc")
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
  try! se.insert_and_record("d", 3000)
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
}

///|
test "SyncEditor: apply_text_edit replaces middle range and updates cursor" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("abc")
  se.move_cursor(0)
  se.apply_text_edit(1, 1, "XYZ", 1000)
  inspect(se.get_text(), content="aXYZc")
  inspect(se.get_cursor(), content="4")
}

///|
test "SyncEditor: apply_text_edit records undo" {
  let se = SyncEditor::new_lambda("agent1")
  try! insert_each_and_record(se, "abc", 1000)
  se.apply_text_edit(1, 1, "XYZ", 2000)
  inspect(se.get_text(), content="aXYZc")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="abc")
}

///|
test "SyncEditor: apply_text_edit records multi-character range undo" {
  let se = SyncEditor::new_lambda("agent1")
  try! insert_each_and_record(se, "abcdef", 1000)
  se.apply_text_edit(1, 3, "XYZ", 2000)
  inspect(se.get_text(), content="aXYZef")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="abcdef")
}

///|
test "SyncEditor: apply_text_edit reuses parser structure on local edit" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("λf.λx.f x")
  ignore(se.get_ast())
  se.apply_text_edit(8, 1, "y", 1000)
  inspect(se.get_text(), content="λf.λx.f y")
  inspect(@ast.print_term(se.get_ast()), content="(λf. (λx. (f y)))")
}

///|
test "SyncEditor: clear_undo empties stacks" {
  let se = SyncEditor::new_lambda("agent1")
  try! se.insert_and_record("x", 1000)
  inspect(se.can_undo(), content="true")
  se.clear_undo()
  inspect(se.can_undo(), content="false")
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
  try! se.insert_and_record("y", 2000)
  inspect(se.get_text(), content="xy")
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
}

///|
test "SyncEditor: non-numeric agent IDs encode and delete presence" {
  let alice = SyncEditor::new_lambda("web-user")
  let bob = SyncEditor::new_lambda("local-user")
  alice.set_text("abcd")
  alice.move_cursor(2)
  alice.set_local_presence("Alice", "#ff0000")
  let initial = alice.encode_ephemeral_all()
  inspect(initial.length() > 0, content="true")
  bob.apply_ephemeral(initial)
  inspect(bob.get_peer_cursors().length(), content="1")
  let alice_cursor = bob.get_peer_cursors().get("web-user").unwrap()
  inspect(alice_cursor.adjusted_cursor, content="2")
  inspect(alice_cursor.display_name, content="Alice")
  alice.delete_local_presence()
  bob.apply_ephemeral(alice.encode_ephemeral_all())
  inspect(bob.get_peer_cursors().length(), content="0")
}

///|
test "SyncEditor: local edits and undo keep peer cursors in sync" {
  let local_editor = SyncEditor::new_lambda("local-user")
  let remote = SyncEditor::new_lambda("remote-user")
  local_editor.set_text("abcd")
  try! remote.apply_sync(try! local_editor.export_all())
  remote.move_cursor(3)
  remote.set_local_presence("Bob", "#00ff00")
  local_editor.apply_ephemeral(remote.encode_ephemeral_all())
  inspect(
    local_editor.get_peer_cursors().get("remote-user").unwrap().adjusted_cursor,
    content="3",
  )
  local_editor.move_cursor(0)
  try! local_editor.insert_and_record("X", 1000)
  // Insert at position 0 correctly places X before "abcd" per Fugue
  // Algorithm 1 (left child of rightOrigin). Peer cursor shifts to 4.
  inspect(
    local_editor.get_text(),
    content=(
      #|Xabcd
    ),
  )
  inspect(
    local_editor.get_peer_cursors().get("remote-user").unwrap().adjusted_cursor,
    content=(
      #|4
    ),
  )
  inspect(local_editor.undo(), content="true")
  inspect(local_editor.get_text(), content="abcd")
  inspect(
    local_editor.get_peer_cursors().get("remote-user").unwrap().adjusted_cursor,
    content="3",
  )
}

///|
test "SyncEditor: remote sync tracks actual merged text positions" {
  let viewer = SyncEditor::new_lambda("viewer")
  let remote = SyncEditor::new_lambda("peer-b")
  viewer.set_text("abcd")
  try! remote.apply_sync(try! viewer.export_all())
  remote.move_cursor(1)
  remote.set_local_presence("Bob", "#00ff00")
  viewer.apply_ephemeral(remote.encode_ephemeral_all())
  remote.move_cursor(0)
  try! remote.insert("X")
  remote.move_cursor(remote.get_text().length())
  try! remote.insert("Y")
  try! viewer.apply_sync(try! remote.export_all())
  // X at position 0 (before "abcd"), Y appended at end → "XabcdY"
  inspect(
    viewer.get_text(),
    content=(
      #|XabcdY
    ),
  )
  inspect(
    viewer.get_peer_cursors().get("peer-b").unwrap().adjusted_cursor,
    content=(
      #|2
    ),
  )
}

///|
test "SyncEditor: apply_sync does not pollute undo stack" {
  let se1 = SyncEditor::new_lambda("alice", capture_timeout_ms=500)
  let se2 = SyncEditor::new_lambda("bob", capture_timeout_ms=500)

  // Alice types
  try! se1.insert_and_record("hello", 1000)

  // Sync to Bob
  try! se2.apply_sync(try! se1.export_all())

  // Bob's undo stack should be empty — remote ops must not be tracked
  inspect(se2.can_undo(), content="false")
}

///|
test "SyncEditor: undo returns sync message for peer broadcast" {
  let se = SyncEditor::new_lambda("alice", capture_timeout_ms=500)

  // Type some text
  try! se.insert_and_record("hello", 1000)

  // Undo
  let msg = se.undo_and_export()
  inspect(se.get_text(), content="")

  // The returned message should contain ops
  match msg {
    Some(m) => inspect(m.is_empty(), content="false")
    None => inspect(false, content="true") // should have returned Some
  }
}

///|
test "SyncEditor: undo sync ops can be applied to peer" {
  let se1 = SyncEditor::new_lambda("alice", capture_timeout_ms=500)
  let se2 = SyncEditor::new_lambda("bob", capture_timeout_ms=500)

  // Alice types
  try! se1.insert_and_record("hello", 1000)

  // Sync initial state to Bob
  try! se2.apply_sync(try! se1.export_all())
  inspect(se2.get_text(), content="hello")

  // Alice undoes and gets sync ops
  let msg = se1.undo_and_export()
  inspect(se1.get_text(), content="")

  // Apply undo ops to Bob
  match msg {
    Some(m) => try! se2.apply_sync(m)
    None => ()
  }

  // Bob should converge with Alice
  inspect(se2.get_text(), content="")
}

///|
test "SyncEditor: get_resolution returns bound/free info" {
  let se = SyncEditor::new_lambda("agent1")
  // λx. (x + y) — x is bound, y is free
  try! insert_each(se, "\\x. x + y")
  let res = se.get_resolution()
  // Pre-order: 0=Lam, 1=Bop, 2=Var(x), 3=Var(y)
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
  inspect(res.vars.get(3), content="Some(Free)")
}

///|
fn count_nodes(node : @proj.ProjNode[@ast.Term]) -> Int {
  let mut count = 1
  for child in node.children {
    count = count + count_nodes(child)
  }
  count
}

///|
test "incremental patch: registry node count stable after tail edit" {
  let editor = SyncEditor::new_lambda("test")
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
  let editor = SyncEditor::new_lambda("test")
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
  let editor = SyncEditor::new_lambda("test")
  editor.set_text("let x = 1\nlet y = 2\ny")
  let proj = editor.get_proj_node().unwrap()
  // Get node ID of x's init (Int(1)) — first child of Module
  let x_init_id = proj.children[0].id()
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
  let editor = SyncEditor::new_lambda("test")
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
  let editor = SyncEditor::new_lambda("test")
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
  let editor = SyncEditor::new_lambda("test")
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
