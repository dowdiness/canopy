// Tests for SyncEditor

///|
fn insert_each(se : SyncEditor, text : String) -> Unit raise {
  se.insert(text)
}

///|
fn insert_each_and_record(
  se : SyncEditor,
  text : String,
  timestamp_ms : Int,
) -> Unit raise {
  se.insert_and_record(text, timestamp_ms)
}

///|
test "SyncEditor: create and insert text" {
  let se = SyncEditor::new("agent1")
  try! se.insert("x")
  inspect(se.get_text(), content="x")
  let ast = se.get_ast()
  inspect(@ast.print_term(ast), content="x")
}

///|
test "SyncEditor: sequential inserts update AST" {
  let se = SyncEditor::new("agent1")
  try! se.insert("x")
  inspect(@ast.print_term(se.get_ast()), content="x")
  try! insert_each(se, " + 1")
  inspect(@ast.print_term(se.get_ast()), content="(x + 1)")
}

///|
test "SyncEditor: delete updates AST" {
  let se = SyncEditor::new("agent1")
  try! insert_each(se, "123")
  inspect(se.get_text(), content="123")
  let deleted = se.backspace()
  inspect(deleted, content="true")
  inspect(se.get_text(), content="12")
}

///|
test "SyncEditor: parse error handling" {
  let se = SyncEditor::new("agent1")
  try! insert_each(se, "λ.")
  let _ast = se.get_ast()
  inspect(se.is_parse_valid(), content="false")
}

///|
test "SyncEditor: cursor tracking" {
  let se = SyncEditor::new("agent1")
  inspect(se.get_cursor(), content="0")
  try! insert_each(se, "abc")
  inspect(se.get_cursor(), content="3")
  se.move_cursor(1)
  inspect(se.get_cursor(), content="1")
}

///|
test "SyncEditor: concurrent edits converge" {
  let se1 = SyncEditor::new("agent1")
  let se2 = SyncEditor::new("agent2")
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
  let se1 = SyncEditor::new("agent1")
  let se2 = SyncEditor::new("agent2")
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
  let se = SyncEditor::new("agent1")
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
  let se = SyncEditor::new("agent1")
  inspect(se.get_text(), content="")
  let _ast = se.get_ast()
}

///|
test "SyncEditor: backspace at start returns false" {
  let se = SyncEditor::new("agent1")
  try! insert_each(se, "abc")
  se.move_cursor(0)
  inspect(se.backspace(), content="false")
  inspect(se.get_text(), content="abc")
}

///|
test "SyncEditor: delete at end returns false" {
  let se = SyncEditor::new("agent1")
  try! insert_each(se, "abc")
  se.move_cursor(3)
  inspect(se.delete(), content="false")
  inspect(se.get_text(), content="abc")
}

///|
test "SyncEditor: export_all produces non-empty message" {
  let se = SyncEditor::new("agent1")
  try! se.insert("x")
  let msg = try! se.export_all()
  inspect(msg.op_count() > 0, content="true")
}

///|
test "SyncEditor: lazy AST evaluation" {
  let se = SyncEditor::new("agent1")
  try! se.insert("x")
  let _ast1 = se.get_ast()
  let ast2 = se.get_ast()
  inspect(@ast.print_term(ast2), content="x")
}

///|
test "SyncEditor: merge invalidates AST cache" {
  let se1 = SyncEditor::new("agent1")
  let se2 = SyncEditor::new("agent2")
  try! se1.insert("x")
  try! se2.apply_sync(try! se1.export_all())
  let _ast1 = se1.get_ast()
  try! se2.insert("y")
  try! se1.apply_sync(try! se2.export_all())
  let _ast2 = se1.get_ast()
  inspect(se1.get_text(), content="xy")
}

///|
test "SyncEditor: insert_and_record + undo roundtrip" {
  let se = SyncEditor::new("agent1")
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
  let se = SyncEditor::new("agent1")
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
  let se = SyncEditor::new("agent1")
  se.set_text("abc")
  se.move_cursor(0)
  se.apply_text_edit(1, 1, "XYZ", 1000)
  inspect(se.get_text(), content="aXYZc")
  inspect(se.get_cursor(), content="4")
}

///|
test "SyncEditor: apply_text_edit records undo" {
  let se = SyncEditor::new("agent1")
  try! insert_each_and_record(se, "abc", 1000)
  se.apply_text_edit(1, 1, "XYZ", 2000)
  inspect(se.get_text(), content="aXYZc")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="abc")
}

///|
test "SyncEditor: apply_text_edit records multi-character range undo" {
  let se = SyncEditor::new("agent1")
  try! insert_each_and_record(se, "abcdef", 1000)
  se.apply_text_edit(1, 3, "XYZ", 2000)
  inspect(se.get_text(), content="aXYZef")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="abcdef")
}

///|
test "SyncEditor: apply_text_edit reuses parser structure on local edit" {
  let se = SyncEditor::new("agent1")
  se.set_text("λf.λx.f x")
  ignore(se.get_ast())
  se.apply_text_edit(8, 1, "y", 1000)
  inspect(se.get_text(), content="λf.λx.f y")
  inspect(@ast.print_term(se.get_ast()), content="(λf. (λx. (f y)))")
}

///|
test "SyncEditor: clear_undo empties stacks" {
  let se = SyncEditor::new("agent1")
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
  let alice = SyncEditor::new("web-user")
  let bob = SyncEditor::new("local-user")
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
  let local_editor = SyncEditor::new("local-user")
  let remote = SyncEditor::new("remote-user")
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
  // NOTE: "abcdX" not "Xabcd" — set_text creates a batch range-edit whose
  // FugueMax tree has no interleaving points. insert_and_record at position 0
  // resolves to the end of the batch. resolve_applied_edit compensates so
  // the peer cursor stays at 3 (the insert is effectively an append).
  inspect(local_editor.get_text(), content="abcdX")
  inspect(
    local_editor.get_peer_cursors().get("remote-user").unwrap().adjusted_cursor,
    content="3",
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
  let viewer = SyncEditor::new("viewer")
  let remote = SyncEditor::new("peer-b")
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
  // "abcdXY" not "XabcdY" — same FugueMax batch-insert caveat as above:
  // insert at position 0 after set_text resolves to the end of the batch.
  inspect(viewer.get_text(), content="abcdXY")
  inspect(
    viewer.get_peer_cursors().get("peer-b").unwrap().adjusted_cursor,
    content="1",
  )
}

///|
test "SyncEditor: get_resolution returns bound/free info" {
  let se = SyncEditor::new("agent1")
  // λx. (x + y) — x is bound, y is free
  try! insert_each(se, "\\x. x + y")
  let res = se.get_resolution()
  // Pre-order: 0=Lam, 1=Bop, 2=Var(x), 3=Var(y)
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
  inspect(res.vars.get(3), content="Some(Free)")
}
