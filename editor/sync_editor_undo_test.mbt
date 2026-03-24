// Tests for SyncEditor undo/redo operations

///|
test "undo: empty stack reports not undoable" {
  let se = SyncEditor::new_lambda("agent1")
  inspect(se.can_undo(), content="false")
  inspect(se.can_redo(), content="false")
}

///|
test "undo: insert then undo restores" {
  let se = SyncEditor::new_lambda("agent1")
  try! se.insert_and_record("hello", 1000)
  inspect(se.get_text(), content="hello")
  inspect(se.can_undo(), content="true")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="")
}

///|
test "undo: redo after undo" {
  let se = SyncEditor::new_lambda("agent1")
  try! se.insert_and_record("hello", 1000)
  inspect(se.undo(), content="true")
  inspect(se.get_text(), content="")
  inspect(se.can_redo(), content="true")
  inspect(se.redo(), content="true")
  inspect(se.get_text(), content="hello")
}

///|
test "undo: redo cleared on new edit" {
  let se = SyncEditor::new_lambda("agent1")
  try! se.insert_and_record("a", 1000)
  inspect(se.undo(), content="true")
  inspect(se.get_text(), content="")
  inspect(se.can_redo(), content="true")
  // New edit should clear the redo stack
  try! se.insert_and_record("b", 2000)
  inspect(se.can_redo(), content="false")
}

///|
test "undo: tracking suppression" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_tracking(false)
  try! se.insert_and_record("x", 1000)
  se.set_tracking(true)
  // The edit was not recorded because tracking was disabled
  inspect(se.can_undo(), content="false")
  inspect(se.get_text(), content="x")
}

///|
test "undo: backspace and record" {
  let se = SyncEditor::new_lambda("agent1")
  try! se.insert_and_record("ab", 1000)
  inspect(se.get_text(), content="ab")
  // Cursor is at 2 after insert, backspace deletes "b"
  let deleted = se.backspace_and_record(2000)
  inspect(deleted, content="true")
  inspect(se.get_text(), content="a")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="ab")
}

///|
test "undo: delete and record" {
  let se = SyncEditor::new_lambda("agent1")
  try! se.insert_and_record("ab", 1000)
  inspect(se.get_text(), content="ab")
  // Move cursor to position 0, then delete forward removes "a"
  se.move_cursor(0)
  let deleted = se.delete_and_record(2000)
  inspect(deleted, content="true")
  inspect(se.get_text(), content="b")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="ab")
}

///|
test "undo: multiple undos in sequence" {
  let se = SyncEditor::new_lambda("agent1")
  try! se.insert_and_record("a", 1000)
  try! se.insert_and_record("b", 2000)
  try! se.insert_and_record("c", 3000)
  inspect(se.get_text(), content="abc")
  inspect(se.undo(), content="true")
  inspect(se.get_text(), content="ab")
  inspect(se.undo(), content="true")
  inspect(se.get_text(), content="a")
  inspect(se.undo(), content="true")
  inspect(se.get_text(), content="")
  // No more undos
  inspect(se.can_undo(), content="false")
}

///|
test "undo: clear stacks" {
  let se = SyncEditor::new_lambda("agent1")
  try! se.insert_and_record("hello", 1000)
  inspect(se.can_undo(), content="true")
  se.clear_undo()
  inspect(se.can_undo(), content="false")
  inspect(se.can_redo(), content="false")
  // Text remains intact after clearing undo stacks
  inspect(se.get_text(), content="hello")
}
