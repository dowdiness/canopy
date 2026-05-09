// Whitebox tests for position-based edit API (insert_at / delete_at).

///|
test "insert_at inserts at specified position without moving cursor" {
  let editor = @lambda.new_lambda_editor("test-agent").0
  editor.set_text("hello")
  editor.move_cursor(0) // cursor at start
  editor.insert_at(5, "!", 0) // insert at end
  inspect(editor.get_text(), content="hello!")
  inspect(editor.get_cursor(), content="0") // cursor unchanged
}

///|
test "delete_at deletes at specified position without moving cursor" {
  let editor = @lambda.new_lambda_editor("test-agent").0
  editor.set_text("hello!")
  editor.move_cursor(0)
  let deleted = editor.delete_at(5, 0) // delete '!' at position 5
  inspect(deleted, content="true")
  inspect(editor.get_text(), content="hello")
  inspect(editor.get_cursor(), content="0")
}

///|
test "insert_at in middle does not move cursor" {
  let editor = @lambda.new_lambda_editor("test-agent").0
  editor.set_text("abcd")
  editor.move_cursor(2) // cursor in middle
  editor.insert_at(2, "X", 0) // insert at cursor position
  inspect(editor.get_text(), content="abXcd")
  // cursor stays at 2, NOT moved to 3
  inspect(editor.get_cursor(), content="2")
}

///|
test "delete_at before cursor clamps cursor to text length" {
  let editor = @lambda.new_lambda_editor("test-agent").0
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
  let editor = @lambda.new_lambda_editor("test-agent").0
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
  let editor = @lambda.new_lambda_editor("test-agent").0
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
  let editor = @lambda.new_lambda_editor("test-agent").0
  editor.set_text("abc")
  editor.move_cursor(0)
  let result = editor.delete_at(3, 0) // position == length, nothing to delete
  inspect(result, content="false")
  inspect(editor.get_text(), content="abc")
}

///|
test "insert_at with multi-char text" {
  let editor = @lambda.new_lambda_editor("test-agent").0
  editor.set_text("ac")
  editor.move_cursor(0)
  editor.insert_at(1, "b", 0)
  inspect(editor.get_text(), content="abc")
  inspect(editor.get_cursor(), content="0")
}

// ─── Non-ASCII safety probes (issue #216) ────────────────────────────────
//
// Surveys the editor's behavior on non-ASCII inputs so the bugs documented
// in issue #216 are visible and so the test suite goes red the moment any
// of the underlying layers is fixed. The tests split along the actual
// failure modes observed today:
//
//   1. BMP-only inputs (combining marks): the editor runs without aborting
//      but produces wrong output (deletes only the combining mark, not the
//      grapheme). Pinned with `inspect`. When moji-based fixes land, these
//      assertions need to be updated to the grapheme-correct values.
//
//   2. Surrogate-pair inputs (emoji, ZWJ family, flag): the CRDT layer
//      (event-graph-walker) currently *aborts* via `String::sub` when an
//      insert lands on a UTF-16 code-unit boundary mid-surrogate. Marked
//      with the `panic ` test prefix, which expects abort. When the CRDT
//      issue (eg-walker, related to #216) is fixed, these tests will start
//      failing because the abort no longer fires — at which point they
//      should be rewritten as inspect-style tests against the new
//      post-fix surface behavior.

///|
/// BMP single-code-unit char (Japanese Hiragana). Sanity baseline.
test "insert: BMP single-code-unit char advances cursor by 1 (baseline)" {
  let editor = @lambda.new_lambda_editor("test-agent").0
  editor.insert("あ") catch {
    _ => ()
  }
  inspect(editor.get_text(), content="あ")
  inspect(editor.get_cursor(), content="1")
}

///|
/// #216: backspace after a combining acute accent (NFD form of "é")
/// currently deletes only the combining mark, leaving the bare "e".
/// The user pressed backspace expecting the whole grapheme to go.
/// Post-fix (moji): text="", cursor=0.
test "#216 xfail: backspace removes only combining mark, not grapheme" {
  let editor = @lambda.new_lambda_editor("test-agent").0
  editor.insert("e") catch {
    _ => ()
  }
  editor.insert("\u{0301}") catch {
    _ => ()
  } // COMBINING ACUTE
  let _ = editor.backspace()
  inspect(editor.get_text(), content="e")
  inspect(editor.get_cursor(), content="1")
}

///|
/// #216: insert of a surrogate-pair emoji currently aborts in the CRDT
/// (`String::sub` mid-surrogate). The whole call stack — `SyncEditor::insert`
/// → `TextState::insert` → `Document::insert` → `String::sub` — panics, not
/// just the editor layer. Tracked separately as the eg-walker CRDT issue
/// referenced from #216.
test "panic #216: insert non-BMP emoji aborts in CRDT" {
  let editor = @lambda.new_lambda_editor("test-agent").0
  editor.insert("😀") catch {
    _ => ()
  }
}

///|
/// #216: same abort path triggered through a ZWJ family. Each insert of a
/// single non-BMP component goes through the same `Document::insert` path.
test "panic #216: insert ZWJ family member aborts in CRDT" {
  let editor = @lambda.new_lambda_editor("test-agent").0
  editor.insert("👨") catch {
    _ => ()
  }
}

///|
/// #216: regional indicator (flag half) is also non-BMP — same crash path.
test "panic #216: insert regional indicator aborts in CRDT" {
  let editor = @lambda.new_lambda_editor("test-agent").0
  editor.insert("🇯") catch {
    _ => ()
  }
}

///|
/// #216: `set_text` of a string containing a surrogate pair routes through
/// the same CRDT insert and aborts. This is the path used by the
/// ProseMirror bridge, so external text coming in over the bridge can
/// crash the editor.
test "panic #216: set_text with non-BMP content aborts" {
  let editor = @lambda.new_lambda_editor("test-agent").0
  editor.set_text("😀")
}
