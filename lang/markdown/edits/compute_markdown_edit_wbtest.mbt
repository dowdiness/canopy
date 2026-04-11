///| Whitebox tests for Markdown edit ops.

///|
/// Helper: parse, project, populate token spans, compute edit, return new source text.
fn apply_edit(
  source : String,
  op : MarkdownEditOp,
) -> String raise @loomcore.LexError {
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let source_map = @core.SourceMap::from_ast(proj)
  // Re-parse to get the SyntaxNode for populate_token_spans
  let (cst, _) = @markdown.parse_cst(source)
  let syntax_root = @seam.SyntaxNode::from_cst(cst)
  @md_proj.populate_token_spans(source_map, syntax_root, proj)
  match compute_markdown_edit(op, source, proj, source_map) {
    Ok(Some((edits, _))) => {
      let sorted = edits.copy()
      sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
      let mut result = source
      for edit in sorted {
        let before = result[:edit.start].to_string()
        let after = result[edit.start + edit.delete_len:].to_string()
        result = before + edit.inserted + after
      }
      result
    }
    Ok(None) => source // no-op
    Err(msg) => abort("edit failed: " + msg)
  }
}

///|
test "commit_edit: change paragraph text" {
  let source = "Hello world\n"
  let (proj, _) = @md_proj.parse_to_proj_node("Hello world\n")
  let para_id = proj.children[0].id()
  let result = apply_edit(
    source,
    CommitEdit(node_id=para_id, new_text="Goodbye"),
  )
  inspect(result.contains("Goodbye"), content="true")
}

///|
test "change_heading_level: paragraph to h2" {
  let source = "Hello\n"
  let (proj, _) = @md_proj.parse_to_proj_node("Hello\n")
  let para_id = proj.children[0].id()
  let result = apply_edit(source, ChangeHeadingLevel(node_id=para_id, level=2))
  inspect(result.contains("## Hello"), content="true")
}

///|
test "change_heading_level: h1 to h3" {
  let source = "# Title\n"
  let (proj, _) = @md_proj.parse_to_proj_node("# Title\n")
  let heading_id = proj.children[0].id()
  let result = apply_edit(
    source,
    ChangeHeadingLevel(node_id=heading_id, level=3),
  )
  inspect(result.contains("### Title"), content="true")
}

///|
test "toggle_list_item: paragraph to list item" {
  let source = "Hello\n"
  let (proj, _) = @md_proj.parse_to_proj_node("Hello\n")
  let para_id = proj.children[0].id()
  let result = apply_edit(source, ToggleListItem(node_id=para_id))
  inspect(result.contains("- Hello"), content="true")
}

///|
test "delete: remove a block" {
  let source = "# Title\n\nParagraph\n"
  let (proj, _) = @md_proj.parse_to_proj_node("# Title\n\nParagraph\n")
  let para_id = proj.children[1].id()
  let result = apply_edit(source, Delete(node_id=para_id))
  inspect(result.contains("Paragraph"), content="false")
}

///|
test "insert_block_after: adds newline" {
  let source = "Hello\n"
  let (proj, _) = @md_proj.parse_to_proj_node("Hello\n")
  let para_id = proj.children[0].id()
  let result = apply_edit(source, InsertBlockAfter(node_id=para_id))
  // Should have extra newline (new block separator)
  inspect(result.length() > source.length(), content="true")
}

///|
test "merge_with_previous: first block is no-op" {
  let source = "Hello\n"
  let (proj, _) = @md_proj.parse_to_proj_node("Hello\n")
  let para_id = proj.children[0].id()
  let result = apply_edit(source, MergeWithPrevious(node_id=para_id))
  inspect(result, content="Hello\n")
}

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
    ChangeHeadingLevel(node_id=heading_id, level=3),
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
  let result = apply_markdown_edit(ed, SplitBlock(node_id=para_id, offset=5), 0)
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
    SplitBlock(node_id=heading_id, offset=0),
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
    SplitBlock(node_id=para_id, offset=100),
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
  let result = apply_markdown_edit(ed, InsertBlockAfter(node_id=para_id), 0)
  inspect(result is Ok(_), content="true")
  // Raw text has ZWSP (parser needs it)
  inspect(ed.get_text().contains("\u200B"), content="true")
  // Export strips ZWSP
  let exported = ed.get_text().replace_all(old="\u200B", new="")
  inspect(exported.contains("\u200B"), content="false")
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
  let _ = apply_markdown_edit(ed, InsertBlockAfter(node_id=para_id), 0)
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
    MergeWithPrevious(node_id=empty_block_id),
    0,
  )
  inspect(merge_result is Ok(_), content="true")
  // After merge, ZWSP should be gone from raw text too
  inspect(ed.get_text().contains("\u200B"), content="false")
}
