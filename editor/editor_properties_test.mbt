// Property-based tests for Editor operations
//
// These tests verify fundamental properties of the Editor using MoonBit's
// built-in quickcheck for random test generation.

///|
/// Property: New editor is always empty
test "property: new editor is empty" {
  let editor = Editor::new("test-agent")
  assert_eq(editor.get_text(), "")
  assert_eq(editor.get_cursor(), 0)
}

///|
/// Property: Text length matches inserted text length
test "property: insert updates length correctly" {
  let texts : Array[String] = @quickcheck.samples(20)
  for text in texts {
    let editor = Editor::new("test-agent")
    try! editor.insert(text)
    assert_eq(editor.get_text().length(), text.length())
  }
}

///|
/// Property: Cursor is always within valid bounds [0, text.length()]
test "property: cursor bounds after insert" {
  let texts : Array[String] = @quickcheck.samples(20)
  for text in texts {
    let editor = Editor::new("test-agent")
    try! editor.insert(text)
    let cursor = editor.get_cursor()
    let len = editor.get_text().length()
    assert_true(cursor >= 0)
    assert_true(cursor <= len)
  }
}

///|
/// Property: Inserting empty string doesn't change state
test "property: inserting empty string is no-op" {
  let editor = Editor::new("test-agent")
  let before_text = editor.get_text()
  let before_cursor = editor.get_cursor()
  try! editor.insert("")
  assert_eq(editor.get_text(), before_text)
  assert_eq(editor.get_cursor(), before_cursor)
}

///|
/// Property: Delete on empty editor is safe
test "property: delete on empty editor is safe" {
  let editor = Editor::new("test-agent")
  let result = editor.delete()
  assert_eq(result, false)
  assert_eq(editor.get_text(), "")
}

///|
/// Property: Backspace on empty editor is safe
test "property: backspace on empty editor is safe" {
  let editor = Editor::new("test-agent")
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
    let editor = Editor::new("test-agent")
    try! editor.insert(text)

    // Delete all characters one by one
    editor.move_cursor(0)
    for _i = 0; _i < text.length(); _i = _i + 1 {
      let _ = editor.delete()
    }
    assert_eq(editor.get_text(), "")
  }
}

///|
/// Property: Text length never becomes negative
test "property: text length is never negative" {
  let ops_arrays : Array[Array[Bool]] = @quickcheck.samples(10)
  for ops in ops_arrays {
    let editor = Editor::new("test-agent")
    for is_insert in ops {
      if is_insert {
        try! editor.insert("x")
      } else {
        let _ = editor.delete()
      }

      // Check length is valid after each operation
      assert_true(editor.get_text().length() >= 0)
    }
  }
}

///|
/// Property: Moving cursor beyond bounds clamps to valid position
test "property: cursor move clamps to bounds" {
  let positions : Array[Int] = @quickcheck.samples(20)
  for position in positions {
    let editor = Editor::new("test-agent")
    try! editor.insert("hello")
    editor.move_cursor(position)
    let cursor = editor.get_cursor()
    let len = editor.get_text().length()
    assert_true(cursor >= 0)
    assert_true(cursor <= len)
  }
}

///|
/// Property: Inserting text at position 0 is handled correctly
test "property: insert at start position" {
  let texts : Array[String] = @quickcheck.samples(15)
  for text in texts {
    if text.is_empty() {
      continue
    }
    let editor = Editor::new("test-agent")
    try! editor.insert("world")
    let original_len = editor.get_text().length()
    editor.move_cursor(0)
    try! editor.insert(text)

    // After insert, total length should be sum of both
    assert_eq(editor.get_text().length(), original_len + text.length())
  }
}

///|
/// Property: Multiple inserts accumulate text
test "property: multiple inserts accumulate length" {
  let text_arrays : Array[Array[String]] = @quickcheck.samples(10)
  for texts in text_arrays {
    let editor = Editor::new("test-agent")
    let mut expected_len = 0
    for text in texts {
      try! editor.insert(text)
      expected_len = expected_len + text.length()
    }
    assert_eq(editor.get_text().length(), expected_len)
  }
}

///|
/// Property: Cursor position advances after insert
test "property: cursor advances after insert" {
  let texts : Array[String] = @quickcheck.samples(15)
  for text in texts {
    let editor = Editor::new("test-agent")
    let start_pos = editor.get_cursor()
    try! editor.insert(text)
    let end_pos = editor.get_cursor()

    // Cursor should advance by text length
    assert_eq(end_pos, start_pos + text.length())
  }
}

///|
/// Property: Delete reduces length by at most 1
test "property: delete reduces length by at most 1" {
  let texts : Array[String] = @quickcheck.samples(15)
  for text in texts {
    if text.is_empty() {
      continue
    }
    let editor = Editor::new("test-agent")
    try! editor.insert(text)
    let before_len = editor.get_text().length()
    editor.move_cursor(0)
    let deleted = editor.delete()
    let after_len = editor.get_text().length()
    if deleted {
      assert_eq(after_len, before_len - 1)
    } else {
      assert_eq(after_len, before_len)
    }
  }
}

///|
/// Property: Backspace at position 0 does nothing
test "property: backspace at start is no-op" {
  let texts : Array[String] = @quickcheck.samples(15)
  for text in texts {
    let editor = Editor::new("test-agent")
    try! editor.insert(text)
    editor.move_cursor(0)
    let before_text = editor.get_text()
    let result = editor.backspace()
    let after_text = editor.get_text()
    assert_eq(result, false)
    assert_eq(after_text, before_text)
  }
}

///|
/// Property: Sequential operations maintain consistency
test "property: sequential operations maintain invariants" {
  let ops_arrays : Array[Array[Int]] = @quickcheck.samples(10)
  for ops in ops_arrays {
    let editor = Editor::new("test-agent")
    for op in ops {
      // Positive: insert, negative: delete, zero: move cursor
      if op > 0 {
        try! editor.insert("a")
      } else if op < 0 {
        let _ = editor.delete()
      } else {
        editor.move_cursor(0)
      }

      // Verify invariants hold
      let cursor = editor.get_cursor()
      let len = editor.get_text().length()
      assert_true(cursor >= 0)
      assert_true(cursor <= len)
      assert_true(len >= 0)
    }
  }
}

///|
/// Property: Cursor never exceeds text length after any operation
test "property: cursor invariant holds after operations" {
  let op_sequences : Array[Array[Bool]] = @quickcheck.samples(10)
  for ops in op_sequences {
    let editor = Editor::new("test-agent")
    for is_insert in ops {
      if is_insert {
        try! editor.insert("x")
      } else {
        editor.move_cursor(0)
        let _ = editor.delete()
      }
      let cursor = editor.get_cursor()
      let len = editor.get_text().length()
      assert_true(cursor <= len)
    }
  }
}
