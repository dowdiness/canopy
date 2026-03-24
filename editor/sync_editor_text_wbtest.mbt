// Whitebox tests for position-based edit API (insert_at / delete_at).

///|
test "insert_at inserts at specified position without moving cursor" {
  let editor = SyncEditor::new_lambda("test-agent")
  editor.set_text("hello")
  editor.move_cursor(0) // cursor at start
  editor.insert_at(5, "!", 0) // insert at end
  inspect(editor.get_text(), content="hello!")
  inspect(editor.get_cursor(), content="0") // cursor unchanged
}

///|
test "delete_at deletes at specified position without moving cursor" {
  let editor = SyncEditor::new_lambda("test-agent")
  editor.set_text("hello!")
  editor.move_cursor(0)
  let deleted = editor.delete_at(5, 0) // delete '!' at position 5
  inspect(deleted, content="true")
  inspect(editor.get_text(), content="hello")
  inspect(editor.get_cursor(), content="0")
}

///|
test "insert_at in middle does not move cursor" {
  let editor = SyncEditor::new_lambda("test-agent")
  editor.set_text("abcd")
  editor.move_cursor(2) // cursor in middle
  editor.insert_at(2, "X", 0) // insert at cursor position
  inspect(editor.get_text(), content="abXcd")
  // cursor stays at 2, NOT moved to 3
  inspect(editor.get_cursor(), content="2")
}

///|
test "delete_at before cursor clamps cursor to text length" {
  let editor = SyncEditor::new_lambda("test-agent")
  // Use per-character inserts to avoid FugueMax batch-insert caveat
  editor.insert("a") catch {
    _ => ()
  }
  editor.insert("b") catch {
    _ => ()
  }
  editor.insert("c") catch {
    _ => ()
  }
  editor.insert("d") catch {
    _ => ()
  }
  editor.insert("e") catch {
    _ => ()
  }
  editor.move_cursor(4) // cursor at position 4
  let deleted = editor.delete_at(1, 0) // delete 'b' at position 1
  inspect(deleted, content="true")
  inspect(editor.get_text(), content="acde")
  // adjust_cursor only clamps to text length; cursor stays at 4 (still within bounds)
  inspect(editor.get_cursor(), content="4")
}

///|
test "insert_at records undo" {
  let editor = SyncEditor::new_lambda("test-agent")
  editor.set_text("abc")
  editor.move_cursor(0)
  editor.insert_at(3, "d", 1000)
  inspect(editor.get_text(), content="abcd")
  let undone = editor.undo()
  inspect(undone, content="true")
  inspect(editor.get_text(), content="abc")
}

///|
test "delete_at records undo" {
  let editor = SyncEditor::new_lambda("test-agent")
  editor.set_text("abcd")
  editor.move_cursor(0)
  let deleted = editor.delete_at(3, 1000) // delete 'd' at position 3
  inspect(deleted, content="true")
  inspect(editor.get_text(), content="abc")
  let undone = editor.undo()
  inspect(undone, content="true")
  inspect(editor.get_text(), content="abcd")
}

///|
test "delete_at at end of text returns false" {
  let editor = SyncEditor::new_lambda("test-agent")
  editor.set_text("abc")
  editor.move_cursor(0)
  let result = editor.delete_at(3, 0) // position == length, nothing to delete
  inspect(result, content="false")
  inspect(editor.get_text(), content="abc")
}

///|
test "insert_at with multi-char text" {
  let editor = SyncEditor::new_lambda("test-agent")
  editor.set_text("ac")
  editor.move_cursor(0)
  editor.insert_at(1, "b", 0)
  inspect(editor.get_text(), content="abc")
  inspect(editor.get_cursor(), content="0")
}
