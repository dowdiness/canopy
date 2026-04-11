///| Integration tests for Markdown editor (round-trip through SyncEditor).

///|
using @md_edits {type MarkdownEditOp}

///|
test "round-trip: new_markdown_editor + apply_markdown_edit" {
  let ed = new_markdown_editor("test")
  ed.set_text("# Hello\n\nWorld\n")
  // Force a reparse/projection cycle
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, ed)
  // Apply heading level change
  let proj = ed.get_proj_node().unwrap()
  let heading_id = proj.children[0].id()
  let result = apply_markdown_edit(
    ed,
    MarkdownEditOp::ChangeHeadingLevel(node_id=heading_id, level=3),
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(ed.get_text().contains("### Hello"), content="true")
}

///|
test "split_block: middle of paragraph" {
  let ed = new_markdown_editor("test")
  ed.set_text("Hello World\n")
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, ed)
  let proj = ed.get_proj_node().unwrap()
  let para_id = proj.children[0].id()
  let result = apply_markdown_edit(
    ed,
    MarkdownEditOp::SplitBlock(node_id=para_id, offset=5),
    0,
  )
  inspect(result is Ok(_), content="true")
  // "Hello" and "World" should be in separate blocks
  let text = ed.get_text()
  inspect(text.contains("Hello"), content="true")
  inspect(text.contains("World"), content="true")
}

///|
test "split_block: offset 0 inserts before" {
  let ed = new_markdown_editor("test")
  ed.set_text("# Title\n")
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, ed)
  let proj = ed.get_proj_node().unwrap()
  let heading_id = proj.children[0].id()
  let result = apply_markdown_edit(
    ed,
    MarkdownEditOp::SplitBlock(node_id=heading_id, offset=0),
    0,
  )
  inspect(result is Ok(_), content="true")
  // Heading should still exist after the inserted blank
  inspect(ed.get_text().contains("# Title"), content="true")
}

///|
test "split_block: end of block inserts after" {
  let ed = new_markdown_editor("test")
  ed.set_text("Hello\n")
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, ed)
  let proj = ed.get_proj_node().unwrap()
  let para_id = proj.children[0].id()
  let result = apply_markdown_edit(
    ed,
    MarkdownEditOp::SplitBlock(node_id=para_id, offset=100),
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(ed.get_text().length() > 6, content="true")
}

///|
test "insert_block_after: ZWSP present in raw text, absent in export" {
  let ed = new_markdown_editor("test")
  ed.set_text("Hello\n")
  // Force projection cycle
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, ed)
  let proj = ed.get_proj_node().unwrap()
  let para_id = proj.children[0].id()
  let result = apply_markdown_edit(
    ed,
    MarkdownEditOp::InsertBlockAfter(node_id=para_id),
    0,
  )
  inspect(result is Ok(_), content="true")
  // Raw text has ZWSP (parser needs it)
  inspect(ed.get_text().contains("\u200B"), content="true")
  // Export strips placeholder ZWSP (the "\n\u200B\n" pattern)
  let exported = ed.get_text().replace_all(old="\n\u200B\n", new="\n\n")
  inspect(exported.contains("\u200B"), content="false")
}

///|
test "export preserves legitimate ZWSP in user content" {
  let ed = new_markdown_editor("test")
  // Simulate user content with ZWSP inside text (e.g., pasted from another tool)
  ed.set_text("Hello\u200Bworld\n")
  let exported = ed.get_text().replace_all(old="\n\u200B\n", new="\n\n")
  // Legitimate ZWSP inside text is preserved
  inspect(exported.contains("\u200B"), content="true")
}

///|
test "merge cleans up ZWSP from empty block" {
  let ed = new_markdown_editor("test")
  ed.set_text("Hello\n")
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, ed)
  // Insert an empty block after "Hello"
  let proj = ed.get_proj_node().unwrap()
  let para_id = proj.children[0].id()
  let _ = apply_markdown_edit(
    ed,
    MarkdownEditOp::InsertBlockAfter(node_id=para_id),
    0,
  )
  // Force re-projection to get new block's ID
  let _ = @editor.compute_view_patches(state, ed)
  let proj2 = ed.get_proj_node().unwrap()
  // The new empty block should be at index 1
  assert_true(
    proj2.children.length() >= 2,
    msg="InsertBlockAfter should produce at least 2 children",
  )
  let empty_block_id = proj2.children[1].id()
  // Merge the empty block back into previous
  let merge_result = apply_markdown_edit(
    ed,
    MarkdownEditOp::MergeWithPrevious(node_id=empty_block_id),
    0,
  )
  inspect(merge_result is Ok(_), content="true")
  // After merge, ZWSP should be gone from raw text too
  inspect(ed.get_text().contains("\u200B"), content="false")
}
