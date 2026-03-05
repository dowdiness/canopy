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
