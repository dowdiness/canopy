// Test error recovery in SyncEditor
// Verifies that errors clear when syntax is corrected

///|
test "SyncEditor: error recovery - invalid to valid syntax" {
  let editor = SyncEditor::new_lambda("agent1")

  // Start with valid syntax
  try! editor.insert("x")
  let errors1 = editor.get_errors()
  inspect(errors1.length(), content="0") // No errors

  // Add invalid syntax
  try! editor.insert("+") // "x+"
  let errors2 = editor.get_errors()
  inspect(errors2.length() > 0, content="true") // Should have errors

  // Fix the syntax
  try! editor.insert(" 1") // "x+ 1"
  let errors3 = editor.get_errors()
  inspect(errors3.length(), content="0") // Errors should be cleared!
}

///|
test "SyncEditor: error recovery - multiple edits" {
  let editor = SyncEditor::new_lambda("agent2")

  // Type: λx.
  try! editor.insert("λx.")
  let errors1 = editor.get_errors()
  inspect(errors1.length() > 0, content="true") // Incomplete lambda - error

  // Complete it: λx.x
  try! editor.insert("x")
  let errors2 = editor.get_errors()
  inspect(errors2.length(), content="0") // Complete - no errors

  // Break it again: λx.x+
  try! editor.insert("+")
  let errors3 = editor.get_errors()
  inspect(errors3.length() > 0, content="true") // Invalid - error

  // Fix it: λx.x+ 1
  try! editor.insert(" 1")
  let errors4 = editor.get_errors()
  inspect(errors4.length(), content="0") // Valid - no errors
}

///|
test "SyncEditor: incremental parser is used" {
  let editor = SyncEditor::new_lambda("agent3")

  // Insert some text
  try! editor.insert("λf.λx.f x")
  let errors1 = editor.get_errors()
  inspect(errors1.length(), content="0") // Valid

  // Make a small change at the end - change x to y
  let text_len = editor.get_text().length()
  editor.move_cursor(text_len - 1) // Move to 'x'
  let _ = editor.delete() // Delete 'x'
  try! editor.insert("y") // Add 'y'

  // Get errors again - should use incremental parser
  let errors2 = editor.get_errors()
  inspect(errors2.length(), content="0") // Should still be valid

  // Verify text is correct
  let text = editor.get_text()
  inspect(text, content="λf.λx.f y")
}
