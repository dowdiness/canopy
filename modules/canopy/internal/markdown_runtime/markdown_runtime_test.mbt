///| The module-private Markdown edit application seam.

///|
test "Markdown edit application applies once and returns exact source transforms" {
  let editor = try! new_editor("internal-markdown-runtime")
  editor.set_text("# Title\n")
  editor.refresh()
  guard editor.get_proj_node() is Some(proj) && proj.children is [heading] else {
    fail("expected one projected heading")
  }

  let result = apply_edit(
    editor,
    @md_edits.MarkdownEditOp::ChangeHeadingLevel(node_id=heading.id(), level=3),
    0,
  )
  match result {
    Ok([edit]) => {
      assert_eq(edit.start, 0)
      assert_eq(edit.delete_len, 8)
      assert_eq(edit.inserted, "### Title\n")
    }
    _ => fail("expected one exact applied source transform")
  }
  assert_eq(editor.get_text(), "### Title\n")
}

///|
test "Markdown edit application returns an empty trace for a no-op" {
  let editor = try! new_editor("internal-markdown-no-op")
  editor.set_text("First\n")
  editor.refresh()
  guard editor.get_proj_node() is Some(proj) && proj.children is [paragraph] else {
    fail("expected one projected paragraph")
  }

  match
    apply_edit(
      editor,
      @md_edits.MarkdownEditOp::MergeWithPrevious(node_id=paragraph.id()),
      0,
    ) {
    Ok([]) => ()
    _ => fail("expected an empty source-transform trace")
  }
  assert_eq(editor.get_text(), "First\n")
}

///|
test "Markdown edit application preserves typed lowering errors" {
  let editor = try! new_editor("internal-markdown-error")
  editor.set_text("# Present\n")
  editor.refresh()
  let missing = @core.NodeId::from_int(999999)

  match
    apply_edit(
      editor,
      @md_edits.MarkdownEditOp::ChangeHeadingLevel(node_id=missing, level=2),
      0,
    ) {
    Err(@core.EditError::NodeNotFound(action~, node_id~)) => {
      assert_eq(action, "compute_markdown_edit")
      assert_eq(node_id, missing)
    }
    _ => fail("expected the typed missing-node lowering error")
  }
  assert_eq(editor.get_text(), "# Present\n")
}

///|
test "Markdown edit application preserves moved identity across renumbering" {
  let editor = try! new_editor("internal-markdown-move")
  editor.set_text("1. A\n2. B\n3. C\n")
  editor.refresh()
  guard editor.get_proj_node() is Some(before) &&
    before.children is [list] &&
    list.children is [first, _, third] else {
    fail("expected one three-item ordered list")
  }

  match
    apply_edit(
      editor,
      @md_edits.MarkdownEditOp::MoveBlock(
        source=third.id(),
        target=first.id(),
        position=@core.DropPosition::Before,
      ),
      0,
    ) {
    Ok([_]) => ()
    _ => fail("expected one exact move transform")
  }
  editor.refresh()
  guard editor.get_proj_node() is Some(after) &&
    after.children is [moved_list] &&
    moved_list.children is [moved, ..] else {
    fail("expected the moved ordered list")
  }
  assert_eq(moved.id(), third.id())
  assert_eq(editor.get_text(), "1. C\n2. A\n3. B\n")
}
