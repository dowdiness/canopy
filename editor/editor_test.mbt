///|
/// Tests for Editor
test "create new editor" {
  let editor = Editor::new("alice")
  inspect(editor.get_text(), content="")
  inspect(editor.get_cursor(), content="0")
}

///|
test "insert at cursor" {
  let editor = Editor::new("alice")
  try! editor.insert("Hello")
  inspect(editor.get_text(), content="Hello")
  inspect(editor.get_cursor(), content="5")
}

///|
test "multiple inserts" {
  let editor = Editor::new("alice")
  try! editor.insert("Hello")
  try! editor.insert(" ")
  try! editor.insert("World")
  inspect(editor.get_text(), content="Hello World")
  inspect(editor.get_cursor(), content="11")
}

///|
test "insert at specific position" {
  let editor = Editor::new("alice")
  try! editor.insert("Heo")
  editor.move_cursor(2)
  try! editor.insert("ll")
  inspect(editor.get_text(), content="Hello")
}

///|
test "move cursor" {
  let editor = Editor::new("alice")
  try! editor.insert("Hello")
  editor.move_cursor(0)
  inspect(editor.get_cursor(), content="0")
  try! editor.insert("X")
  inspect(
    editor.get_text(),
    content=(
      #|XHello
    ),
  )
}

///|
test "delete at cursor" {
  let editor = Editor::new("alice")
  try! editor.insert("Hello")
  editor.move_cursor(1)
  let success = editor.delete()
  inspect(success, content="true")
  inspect(editor.get_text(), content="Hllo")
}

///|
test "backspace" {
  let editor = Editor::new("alice")
  try! editor.insert("Hello")
  let success = editor.backspace()
  inspect(success, content="true")
  inspect(editor.get_text(), content="Hell")
  inspect(editor.get_cursor(), content="4")
}

///|
test "backspace at start" {
  let editor = Editor::new("alice")
  try! editor.insert("H")
  editor.move_cursor(0)
  let success = editor.backspace()
  inspect(success, content="false")
  inspect(editor.get_text(), content="H")
}

///|
test "delete beyond end" {
  let editor = Editor::new("alice")
  try! editor.insert("Hi")
  editor.move_cursor(10) // Move beyond end
  let success = editor.delete()
  inspect(success, content="false")
  inspect(editor.get_text(), content="Hi")
}

///|
test "cursor bounds checking" {
  let editor = Editor::new("alice")
  try! editor.insert("Hello")
  editor.move_cursor(-5) // Should clamp to 0
  inspect(editor.get_cursor(), content="0")
  editor.move_cursor(100) // Should clamp to length
  inspect(editor.get_cursor(), content="5")
}

///|
test "concurrent edits from two editors" {
  // Create two editors
  let alice = Editor::new("alice")
  let bob = Editor::new("bob")

  // Alice types "Hello"
  try! alice.insert("Hello")

  // Bob types "World"
  try! bob.insert("World")

  // They exchange all operations via SyncMessage
  let alice_msg = try! alice.export_all()
  let bob_msg = try! bob.export_all()

  // Alice receives Bob's operations
  try! alice.apply_sync(bob_msg)

  // Bob receives Alice's operations
  try! bob.apply_sync(alice_msg)

  // Both should have converged to same text
  let alice_text = alice.get_text()
  let bob_text = bob.get_text()

  // Verify convergence - both should have the same text
  inspect(alice_text == bob_text, content="true")

  // Text should contain both contributions
  inspect(alice_text.contains("Hello"), content="true")
  inspect(alice_text.contains("World"), content="true")
}

///|
test "concurrent inserts at same position" {
  // Create two editors with initial text "AC"
  let alice = Editor::new("alice")
  let bob = Editor::new("bob")

  // Both start with "AC"
  try! alice.insert("A")
  try! alice.insert("C")
  try! bob.apply_sync(try! alice.export_all())

  // Verify both have "AC"
  inspect(alice.get_text(), content="AC")
  inspect(bob.get_text(), content="AC")

  // Both insert between A and C concurrently
  alice.move_cursor(1)
  try! alice.insert("X")
  bob.move_cursor(1)
  try! bob.insert("Y")

  // Cross-merge via export_all
  try! alice.apply_sync(try! bob.export_all())
  try! bob.apply_sync(try! alice.export_all())

  // Both should converge to same text
  let alice_text = alice.get_text()
  let bob_text = bob.get_text()

  // After merge, both should have the same text
  inspect(alice_text == bob_text, content="true")

  // With FugueMax: Both X and Y are inserted between A and C with origin_left=A, origin_right=C
  // Since A is ancestor of C, both become left children of C
  // With agent tiebreaking, alice < bob alphabetically, so X comes before Y
  inspect(alice_text, content="AYXC")

  // Verify both contributions are present
  inspect(alice_text.contains("A"), content="true")
  inspect(alice_text.contains("C"), content="true")
  inspect(alice_text.contains("X"), content="true")
  inspect(alice_text.contains("Y"), content="true")
}
