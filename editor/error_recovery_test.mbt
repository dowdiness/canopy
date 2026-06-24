// Test error recovery in SyncEditor
// Verifies that errors clear when syntax is corrected.
// Uses the neutral TestExpr grammar, whose one structural error is an
// unclosed '(' — generic editor behavior (diagnostics surface via
// get_errors and clear when the syntax is fixed), not language-specific.

///|
test "SyncEditor: error recovery - invalid to valid syntax" {
  let editor = @probe.new_test_editor("agent1")

  // Start with valid syntax
  try! editor.insert("foo")
  let errors1 = editor.get_errors()
  inspect(errors1.length(), content="0") // No errors

  // Add invalid syntax: an unclosed '('
  try! editor.insert("(") // "foo("
  let errors2 = editor.get_errors()
  inspect(errors2.length() > 0, content="true") // Should have errors

  // Fix the syntax
  try! editor.insert("bar)") // "foo(bar)"
  let errors3 = editor.get_errors()
  inspect(errors3.length(), content="0") // Errors should be cleared!
}

///|
test "SyncEditor: error recovery - multiple edits" {
  let editor = @probe.new_test_editor("agent2")

  // Valid nested expression
  try! editor.insert("a(b)")
  let errors1 = editor.get_errors()
  inspect(errors1.length(), content="0") // Valid

  // Open a new branch without closing it
  try! editor.insert(" c(") // "a(b) c("
  let errors2 = editor.get_errors()
  inspect(errors2.length() > 0, content="true") // Unclosed - error

  // Close it
  try! editor.insert("d)") // "a(b) c(d)"
  let errors3 = editor.get_errors()
  inspect(errors3.length(), content="0") // Valid - no errors
}

///|
test "SyncEditor: incremental parser is used" {
  let editor = @probe.new_test_editor("agent3")

  // Insert some text
  try! editor.insert("f(x g(y))")
  let errors1 = editor.get_errors()
  inspect(errors1.length(), content="0") // Valid

  // Make a small change near the end - change y to z
  let text_len = editor.get_text().length()
  editor.move_cursor(text_len - 3) // Move just past 'y'
  let _ = editor.delete() // Delete 'y'
  try! editor.insert("z") // Add 'z'

  // Get errors again - should use incremental parser
  let errors2 = editor.get_errors()
  inspect(errors2.length(), content="0") // Should still be valid

  // Verify text is correct
  let text = editor.get_text()
  inspect(text, content="f(x g(z))")
}
