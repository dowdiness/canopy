// Integration tests for the resolved edit passed to cursor and parser sync.
// The direct TextState mutations model a CRDT placement that differs from the
// caller's trusted position hint, while keeping the test deterministic.

///|
test "apply_local_text_change uses actual CRDT insertion for peer cursors" {
  let editor = try! @probe.new_test_editor("crdt-insert-integration")
  editor.set_text("abcd")
  editor.cursor_view.set_cursor("before", 0, "Before", "#000000")
  editor.cursor_view.set_cursor("after", 2, "After", "#000000")
  editor.cursor_view.set_cursor("end", 4, "End", "#000000")

  let old_source = editor.doc.text()
  let item_start = utf16_offset_to_item_pos(old_source, 0)
  editor.doc.insert(@text.Pos::at(item_start), "X")
  let new_source = editor.doc.text()
  inspect(new_source, content="Xabcd")

  // The caller believed the insertion landed at the end. The resolver must
  // reject that hint and use the actual CRDT transition at position 0.
  editor.apply_local_text_change(
    old_source,
    new_source,
    Some(@loom_core.Edit::insert(4, 1)),
  )
  inspect(
    editor.cursor_view.get_cursor("before").unwrap().adjusted_cursor,
    content="0",
  )
  inspect(
    editor.cursor_view.get_cursor("after").unwrap().adjusted_cursor,
    content="3",
  )
  inspect(
    editor.cursor_view.get_cursor("end").unwrap().adjusted_cursor,
    content="5",
  )
  inspect(
    @probe.get_test_ast(editor),
    content=(
      #|Branch("", [Leaf("Xabcd")])
    ),
  )
}

///|
test "apply_local_text_change adjusts cursors inside a displaced replacement" {
  let editor = try! @probe.new_test_editor("crdt-replace-integration")
  editor.set_text("abcd")
  editor.cursor_view.set_cursor("before", 0, "Before", "#000000")
  editor.cursor_view.set_cursor("inside", 2, "Inside", "#000000")
  editor.cursor_view.set_cursor("after", 4, "After", "#000000")

  let old_source = editor.doc.text()
  editor.doc.replace_range(@text.Range::from_ints(1, 3), "X") catch {
    _ => fail("test CRDT replacement failed")
  }
  let new_source = editor.doc.text()
  inspect(new_source, content="aXd")

  // Actual transition: old range 1..3 becomes one code unit. The supplied
  // hint is intentionally shifted to exercise the full-diff fallback.
  editor.apply_local_text_change(
    old_source,
    new_source,
    Some(@loom_core.Edit::new(0, 1, 1)),
  )
  inspect(
    editor.cursor_view.get_cursor("before").unwrap().adjusted_cursor,
    content="0",
  )
  inspect(
    editor.cursor_view.get_cursor("inside").unwrap().adjusted_cursor,
    content="2",
  )
  inspect(
    editor.cursor_view.get_cursor("after").unwrap().adjusted_cursor,
    content="3",
  )
  inspect(
    @probe.get_test_ast(editor),
    content=(
      #|Branch("", [Leaf("aXd")])
    ),
  )
}

///|
test "apply_local_text_change reuses a valid ASCII insertion hint" {
  let editor = try! @probe.new_test_editor("crdt-fast-path-integration")
  editor.set_text("abcd")
  editor.cursor_view.set_cursor("after", 4, "After", "#000000")

  let old_source = editor.doc.text()
  let item_start = utf16_offset_to_item_pos(old_source, 2)
  editor.doc.insert(@text.Pos::at(item_start), "X")
  let new_source = editor.doc.text()
  inspect(new_source, content="abXcd")
  let hint = @loom_core.Edit::insert(2, 1)
  assert_true(known_edit_matches_source_change(old_source, new_source, hint))

  editor.apply_local_text_change(old_source, new_source, Some(hint))
  inspect(
    editor.cursor_view.get_cursor("after").unwrap().adjusted_cursor,
    content="5",
  )
  inspect(
    @probe.get_test_ast(editor),
    content=(
      #|Branch("", [Leaf("abXcd")])
    ),
  )
}

///|
test "apply_local_text_change keeps same-character insertion ambiguity conservative" {
  let editor = try! @probe.new_test_editor("crdt-same-character-integration")
  editor.set_text("x")
  editor.cursor_view.set_cursor("peer", 1, "Peer", "#000000")

  let old_source = editor.doc.text()
  let item_start = utf16_offset_to_item_pos(old_source, 0)
  editor.doc.insert(@text.Pos::at(item_start), "x")
  let new_source = editor.doc.text()
  inspect(new_source, content="xx")

  // The trusted hint is physically plausible at offset 0, but the canonical
  // grapheme diff intentionally resolves the repeated-character ambiguity at
  // offset 1, preserving the existing cursor semantics.
  editor.apply_local_text_change(
    old_source,
    new_source,
    Some(@loom_core.Edit::insert(0, 1)),
  )
  inspect(
    editor.cursor_view.get_cursor("peer").unwrap().adjusted_cursor,
    content="1",
  )
}

///|
test "apply_local_text_change uses actual CRDT deletion" {
  let editor = try! @probe.new_test_editor("crdt-delete-integration")
  editor.set_text("abcd")
  editor.cursor_view.set_cursor("before", 0, "Before", "#000000")
  editor.cursor_view.set_cursor("inside", 2, "Inside", "#000000")
  editor.cursor_view.set_cursor("after", 4, "After", "#000000")

  let old_source = editor.doc.text()
  editor.doc.delete_range(@text.Range::from_ints(1, 3)) catch {
    _ => fail("test CRDT deletion failed")
  }
  let new_source = editor.doc.text()
  inspect(new_source, content="ad")

  editor.apply_local_text_change(
    old_source,
    new_source,
    Some(@loom_core.Edit::delete(0, 1)),
  )
  inspect(
    editor.cursor_view.get_cursor("before").unwrap().adjusted_cursor,
    content="0",
  )
  inspect(
    editor.cursor_view.get_cursor("inside").unwrap().adjusted_cursor,
    content="1",
  )
  inspect(
    editor.cursor_view.get_cursor("after").unwrap().adjusted_cursor,
    content="2",
  )
  inspect(
    @probe.get_test_ast(editor),
    content=(
      #|Branch("", [Leaf("ad")])
    ),
  )
}

///|
test "apply_local_text_change falls back for a combining grapheme" {
  let editor = try! @probe.new_test_editor("crdt-combining-integration")
  editor.set_text("e\u{0301}x")
  editor.cursor_view.set_cursor("after", 3, "After", "#000000")

  let old_source = editor.doc.text()
  editor.doc.replace_range(@text.Range::from_ints(0, 2), "e") catch {
    _ => fail("test combining replacement failed")
  }
  let new_source = editor.doc.text()
  inspect(new_source, content="ex")

  // Removing the combining mark alone is not the canonical grapheme edit.
  editor.apply_local_text_change(
    old_source,
    new_source,
    Some(@loom_core.Edit::new(1, 1, 0)),
  )
  inspect(
    editor.cursor_view.get_cursor("after").unwrap().adjusted_cursor,
    content="2",
  )
  inspect(
    @probe.get_test_ast(editor),
    content=(
      #|Branch("", [Leaf("ex")])
    ),
  )
}

///|
test "apply_local_text_change falls back for a CRLF transition" {
  let editor = try! @probe.new_test_editor("crdt-crlf-integration")
  editor.set_text("a\r\nb")
  editor.cursor_view.set_cursor("after", 4, "After", "#000000")

  let old_source = editor.doc.text()
  editor.doc.replace_range(@text.Range::from_ints(1, 3), "\n") catch {
    _ => fail("test CRLF replacement failed")
  }
  let new_source = editor.doc.text()
  inspect(new_source, content="a\nb")

  editor.apply_local_text_change(
    old_source,
    new_source,
    Some(@loom_core.Edit::new(0, 1, 1)),
  )
  inspect(
    editor.cursor_view.get_cursor("after").unwrap().adjusted_cursor,
    content="3",
  )
}
