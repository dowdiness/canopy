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
