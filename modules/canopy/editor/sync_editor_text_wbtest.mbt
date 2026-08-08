// Whitebox tests for position-based edit API (insert_at / delete_at).

///|
test "set_text_with_change returns the applied splice" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("hello")
  let (change, accepted) = editor.set_text_with_change("hello!")
  assert_true(accepted)
  inspect(change.start, content="5")
  inspect(change.delete_len, content="0")
  inspect(change.inserted, content="!")
  inspect(editor.get_text(), content="hello!")
}

///|
test "set_text_with_change returns a replacement splice" {
  let editor = try! @probe.new_test_editor("replacement-agent")
  editor.set_text("hello")
  let (change, accepted) = editor.set_text_with_change("jello")
  assert_true(accepted)
  inspect(change.start, content="0")
  inspect(change.delete_len, content="1")
  inspect(change.inserted, content="j")
  inspect(editor.get_text(), content="jello")
}

///|
test "set_text_with_change preserves grapheme-aware append fallbacks" {
  let combining = try! @probe.new_test_editor("combining-agent")
  combining.set_text("e")
  let (combining_change, combining_accepted) = combining.set_text_with_change(
    "é",
  )
  assert_true(combining_accepted)
  inspect(combining_change.start, content="0")
  inspect(combining_change.delete_len, content="1")
  inspect(combining_change.inserted, content="é")
  inspect(combining.get_text(), content="é")

  let crlf = try! @probe.new_test_editor("crlf-agent")
  crlf.set_text("\r")
  let (crlf_change, crlf_accepted) = crlf.set_text_with_change("\r\n")
  assert_true(crlf_accepted)
  inspect(crlf_change.start, content="0")
  inspect(crlf_change.delete_len, content="1")
  inspect(crlf_change.inserted, content="\r\n")
  inspect(crlf.get_text(), content="\r\n")

  let emoji_append = try! @probe.new_test_editor("emoji-append-agent")
  emoji_append.set_text("a😀")
  let (emoji_append_change, emoji_append_accepted) = emoji_append.set_text_with_change(
    "a😀x",
  )
  assert_true(emoji_append_accepted)
  inspect(emoji_append_change.start, content="3")
  inspect(emoji_append_change.delete_len, content="0")
  inspect(emoji_append_change.inserted, content="x")
  inspect(emoji_append.get_text(), content="a😀x")

  let emoji_insert = try! @probe.new_test_editor("emoji-insert-agent")
  emoji_insert.set_text("a")
  let (emoji_insert_change, emoji_insert_accepted) = emoji_insert.set_text_with_change(
    "a😀",
  )
  assert_true(emoji_insert_accepted)
  inspect(emoji_insert_change.start, content="1")
  inspect(emoji_insert_change.delete_len, content="0")
  inspect(emoji_insert_change.inserted, content="😀")
  inspect(emoji_insert.get_text(), content="a😀")
}

///|
test "insert_at inserts at specified position without moving cursor" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("hello")
  editor.move_cursor(0) // cursor at start
  editor.insert_at(5, "!", 0) // insert at end
  inspect(editor.get_text(), content="hello!")
  inspect(editor.get_cursor(), content="0") // cursor unchanged
}

///|
test "delete_at deletes at specified position without moving cursor" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("hello!")
  editor.move_cursor(0)
  let deleted = editor.delete_at(5, 0) // delete '!' at position 5
  inspect(deleted, content="true")
  inspect(editor.get_text(), content="hello")
  inspect(editor.get_cursor(), content="0")
}

///|
test "insert_at in middle does not move cursor" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("abcd")
  editor.move_cursor(2) // cursor in middle
  editor.insert_at(2, "X", 0) // insert at cursor position
  inspect(editor.get_text(), content="abXcd")
  // cursor stays at 2, NOT moved to 3
  inspect(editor.get_cursor(), content="2")
}

///|
test "delete_at before cursor clamps cursor to text length" {
  let editor = try! @probe.new_test_editor("test-agent")
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
  let editor = try! @probe.new_test_editor("test-agent")
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
  let editor = try! @probe.new_test_editor("test-agent")
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
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("abc")
  editor.move_cursor(0)
  let result = editor.delete_at(3, 0) // position == length, nothing to delete
  inspect(result, content="false")
  inspect(editor.get_text(), content="abc")
}

///|
test "insert_at with multi-char text" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("ac")
  editor.move_cursor(0)
  editor.insert_at(1, "b", 0)
  inspect(editor.get_text(), content="abc")
  inspect(editor.get_cursor(), content="0")
}

// ─── Non-ASCII safety probes (issue #216) ────────────────────────────────
//
// Surveys the editor's behavior on non-ASCII inputs so the issue #216 layers
// stay visible:
//
//   1. BMP-only inputs (combining marks): editor cursors and splice endpoints
//      stay on grapheme boundaries.
//
//   2. Surrogate-pair inputs (emoji, ZWJ family, regional indicators): parser
//      recovery and editor mutation paths must keep token/text spans from
//      slicing through the UTF-16 surrogate pair.

///|
/// BMP single-code-unit char (Japanese Hiragana). Sanity baseline.
test "insert: BMP single-code-unit char advances cursor by 1 (baseline)" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.insert("あ") catch {
    _ => ()
  }
  inspect(editor.get_text(), content="あ")
  inspect(editor.get_cursor(), content="1")
}

///|
/// #216: backspace after a combining acute accent (NFD form of "é")
/// removes the whole grapheme cluster.
test "#216: backspace removes combining grapheme" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.insert("e") catch {
    _ => ()
  }
  editor.insert("\u{0301}") catch {
    _ => ()
  } // COMBINING ACUTE
  let _ = editor.backspace()
  inspect(editor.get_text(), content="")
  inspect(editor.get_cursor(), content="0")
}

///|
test "insert combining mark leaves cursor on grapheme boundary" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.insert("e") catch {
    _ => ()
  }
  editor.insert("\u{0301}") catch {
    _ => ()
  }
  inspect(editor.get_text(), content="é")
  inspect(editor.get_cursor(), content="2")
}

///|
test "move_cursor snaps interior grapheme offset backward" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.insert("e") catch {
    _ => ()
  }
  editor.insert("\u{0301}") catch {
    _ => ()
  }
  editor.move_cursor(1)
  inspect(editor.get_cursor(), content="0")
}

///|
test "move_cursor_left_grapheme skips combining mark" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.insert("e") catch {
    _ => ()
  }
  editor.insert("\u{0301}") catch {
    _ => ()
  }
  editor.move_cursor_left_grapheme()
  inspect(editor.get_cursor(), content="0")
}

///|
test "move_cursor_right_grapheme skips combining mark" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.insert("e") catch {
    _ => ()
  }
  editor.insert("\u{0301}") catch {
    _ => ()
  }
  editor.insert("b") catch {
    _ => ()
  }
  editor.move_cursor(0)
  editor.move_cursor_right_grapheme()
  inspect(editor.get_cursor(), content="2")
}

///|
test "apply_text_edit pure insert snaps mid-cluster to previous boundary" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.insert("e") catch {
    _ => ()
  }
  editor.insert("\u{0301}") catch {
    _ => ()
  }
  editor.apply_text_edit(1, 0, "X", 0)
  inspect(editor.get_text(), content="Xé")
  inspect(editor.get_cursor(), content="1")
}

///|
test "apply_text_edit_exact rejects mid-cluster start" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("e\u{0301}")
  editor.move_cursor(0)
  let accepted = editor.apply_text_edit_exact(1, 0, "X", 0)
  inspect(accepted, content="false")
  inspect(editor.get_text(), content="é")
  inspect(editor.get_cursor(), content="0")
}

///|
test "apply_text_edit_exact accepts on-boundary splice" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("e\u{0301}")
  let accepted = editor.apply_text_edit_exact(2, 0, "X", 0)
  inspect(accepted, content="true")
  inspect(editor.get_text(), content="éX")
  inspect(
    @moji.is_grapheme_boundary(editor.get_text(), editor.get_cursor()),
    content="true",
  )
}

///|
test "insert_at preserves cursor when BMP splice fuses cluster" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("a")
  editor.move_cursor(0)
  editor.insert_at(1, "\u{0301}", 0)
  inspect(editor.get_text(), content="á")
  inspect(editor.get_cursor(), content="0")
}

///|
test "RI re-pairing snaps cursor to next grapheme boundary" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("🇯🇵🇺🇸")
  editor.apply_text_edit(4, 0, "🇮", 0)
  inspect(editor.get_text(), content="🇯🇵🇮🇺🇸")
  inspect(editor.get_cursor(), content="8")
}

///|
test "ZWJ profession join snaps preserved cursor to grapheme boundary" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("👩💻")
  editor.move_cursor(2)
  editor.insert_at(2, "\u{200D}", 0)
  inspect(editor.get_text(), content="👩‍💻")
  inspect(editor.get_cursor(), content="5")
}

///|
/// #216: insert of a surrogate-pair emoji stores the full non-BMP codepoint
/// and leaves the cursor after the grapheme.
test "#216: insert non-BMP emoji stores full emoji" {
  let editor = try! @probe.new_test_editor("test-agent")
  try! editor.insert("😀")
  inspect(editor.get_text(), content="😀")
  inspect(editor.get_cursor(), content="2")
}

///|
/// #216: ZWJ-family components are non-BMP; inserting one must not produce a
/// mid-surrogate parser recovery token.
test "#216: insert ZWJ family member stores full emoji" {
  let editor = try! @probe.new_test_editor("test-agent")
  try! editor.insert("👨")
  inspect(editor.get_text(), content="👨")
  inspect(editor.get_cursor(), content="2")
}

///|
/// #216: regional indicators are non-BMP and must stay atomic through parser
/// recovery.
test "#216: insert regional indicator stores flag half" {
  let editor = try! @probe.new_test_editor("test-agent")
  try! editor.insert("🇯")
  inspect(editor.get_text(), content="🇯")
  inspect(editor.get_cursor(), content="2")
}

///|
/// #216: `set_text` of a string containing a surrogate pair routes through
/// the same bulk text mutation path used by external bridge updates.
test "#216: set_text with non-BMP content stores full emoji" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("😀")
  inspect(editor.get_text(), content="😀")
  inspect(editor.get_cursor(), content="2")
}

///|
/// Word navigation applies the policy layer (word_nav.mbt), not raw UAX
/// boundaries: whitespace is skipped, right lands at word end.
test "word navigation: policy semantics through SyncEditor" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("foo bar")
  editor.move_cursor(0)
  editor.move_cursor_right_word()
  inspect(editor.get_cursor(), content="3") // end of "foo", not raw stop at 4
  editor.move_cursor_right_word()
  inspect(editor.get_cursor(), content="7")
  editor.move_cursor_left_word()
  inspect(editor.get_cursor(), content="4")
  editor.move_cursor_left_word()
  inspect(editor.get_cursor(), content="0")
  editor.move_cursor_left_word() // at 0: stays
  inspect(editor.get_cursor(), content="0")
}

///|
/// Word navigation post-snaps to grapheme boundaries even where a raw UAX
/// word boundary falls inside a cluster (U+0600 is Prepend/Numeric).
test "word navigation: landing snapped to grapheme boundary" {
  let editor = try! @probe.new_test_editor("test-agent")
  editor.set_text("\u{600}!")
  editor.move_cursor(0)
  editor.move_cursor_right_word()
  inspect(editor.get_cursor(), content="2") // not 1 (inside the cluster)
}
