///|
/// Real Markdown runtime trace contract for sentinel insertion.
test "Markdown runtime projects the exact InsertBlockAfter trace" {
  let editor = try! new_editor("internal-markdown-portable-insert")
  editor.set_text("Hello\n")
  editor.refresh()
  let before = editor.get_text()
  let before_root = editor.get_proj_node().unwrap()
  let before_map = editor.get_source_map()
  let before_hidden : Array[@loom.Range] = []
  collect_hidden_sentinel_ranges(before_root, before_map, before_hidden)
  let paragraph = before_root.children[0]
  match
    apply_edit(
      editor,
      @md_edits.MarkdownEditOp::InsertBlockAfter(node_id=paragraph.id()),
      0,
    ) {
    Ok([canonical_edit]) => {
      editor.refresh()
      let after = editor.get_text()
      let after_root = editor.get_proj_node().unwrap()
      let after_map = editor.get_source_map()
      let after_hidden : Array[@loom.Range] = []
      collect_hidden_sentinel_ranges(after_root, after_map, after_hidden)
      let projected = project_markdown_edit(
        before, before_hidden, canonical_edit, after, after_hidden,
      ).unwrap()
      assert_eq(
        apply_span_edit(
          project_source(before, before_hidden).unwrap(),
          projected,
        ),
        project_source(after, after_hidden).unwrap(),
      )
    }
    Ok(_) => fail("InsertBlockAfter must return exactly one span")
    Err(_) => fail("InsertBlockAfter should apply")
  }
}

///|
test "Markdown runtime projects the repaired empty-previous merge trace" {
  let editor = try! new_editor("internal-markdown-portable-merge")
  editor.set_text("Hello\n")
  editor.refresh()
  let initial = editor.get_proj_node().unwrap()
  let paragraph = initial.children[0]
  match
    apply_edit(
      editor,
      @md_edits.MarkdownEditOp::SplitBlock(node_id=paragraph.id(), offset=0),
      0,
    ) {
    Ok([_]) => ()
    _ => fail("setup SplitBlock should return one span")
  }
  editor.refresh()
  let with_empty_previous = editor.get_proj_node().unwrap()
  guard with_empty_previous.children is [_, current] else {
    fail("split at zero must create an empty previous block")
  }
  let before = editor.get_text()
  let before_map = editor.get_source_map()
  let before_hidden : Array[@loom.Range] = []
  collect_hidden_sentinel_ranges(with_empty_previous, before_map, before_hidden)
  match
    apply_edit(
      editor,
      @md_edits.MarkdownEditOp::MergeWithPrevious(node_id=current.id()),
      0,
    ) {
    Ok([canonical_edit]) => {
      editor.refresh()
      let after = editor.get_text()
      let after_root = editor.get_proj_node().unwrap()
      let after_map = editor.get_source_map()
      let after_hidden : Array[@loom.Range] = []
      collect_hidden_sentinel_ranges(after_root, after_map, after_hidden)
      let projected = project_markdown_edit(
        before, before_hidden, canonical_edit, after, after_hidden,
      ).unwrap()
      assert_eq(
        apply_span_edit(
          project_source(before, before_hidden).unwrap(),
          projected,
        ),
        project_source(after, after_hidden).unwrap(),
      )
    }
    Ok(_) => fail("MergeWithPrevious must return exactly one span")
    Err(_) => fail("MergeWithPrevious should apply")
  }
}
