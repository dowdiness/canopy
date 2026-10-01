// Property-based tests for Editor operations
//
// These tests verify fundamental properties of the Editor using MoonBit's
// built-in quickcheck for random test generation.

///|
/// Property: Inserting empty string doesn't change state
test "property: inserting empty string is no-op" {
  let editor = try! @editor.Editor::new("test-agent")
  let before_text = editor.get_text()
  let before_cursor = editor.get_cursor()
  try! editor.insert("")
  assert_eq(editor.get_text(), before_text)
  assert_eq(editor.get_cursor(), before_cursor)
}

///|
/// Property: Delete on empty editor is safe
test "property: delete on empty editor is safe" {
  let editor = try! @editor.Editor::new("test-agent")
  let result = editor.delete()
  assert_eq(result, false)
  assert_eq(editor.get_text(), "")
}

///|
/// Property: Backspace on empty editor is safe
test "property: backspace on empty editor is safe" {
  let editor = try! @editor.Editor::new("test-agent")
  let result = editor.backspace()
  assert_eq(result, false)
  assert_eq(editor.get_text(), "")
}

///|
/// Property: Insert then delete all characters should give empty text
test "property: insert then delete all gives empty" {
  let texts : Array[String] = @quickcheck.samples(15)
  for text in texts {
    if text.is_empty() {
      continue
    }
    let editor = try! @editor.Editor::new("test-agent")
    try! editor.insert(text)

    // Delete all codepoints one by one
    editor.move_cursor(0)
    for _i = 0; _i < text.to_array().length(); _i = _i + 1 {
      let _ = editor.delete()
    }
    assert_eq(editor.get_text(), "")
  }
}

///|
/// Property: Cursor position advances after insert
test "property: cursor advances after insert" {
  let texts : Array[String] = @quickcheck.samples(15)
  for text in texts {
    let editor = try! @editor.Editor::new("test-agent")
    let start_pos = editor.get_cursor()
    try! editor.insert(text)
    let end_pos = editor.get_cursor()

    // Cursor should advance by the inserted item count.
    assert_eq(end_pos, start_pos + text.to_array().length())
  }
}

///|
/// Property: Sequential operations maintain consistency
test "property: sequential operations maintain invariants" {
  let ops_arrays : Array[Array[Int]] = @quickcheck.samples(10)
  for ops in ops_arrays {
    let editor = try! @editor.Editor::new("test-agent")
    for op in ops {
      // Positive: insert, negative: delete, zero: move cursor
      if op > 0 {
        try! editor.insert("a")
      } else if op < 0 {
        let _ = editor.delete()
      } else {
        editor.move_cursor(0)
      }

      // Verify item-space invariants hold
      let cursor = editor.get_cursor()
      let len = editor.get_text().to_array().length()
      assert_true(cursor >= 0)
      assert_true(cursor <= len)
      assert_true(len >= 0)
    }
  }
}
