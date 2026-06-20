///| Whitebox tests for Markdown edit ops (pure compute, no SyncEditor).

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
        let before = result[:edit.start].to_owned()
        let after = result[edit.start + edit.delete_len:].to_owned()
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
test "split_block: mid-cluster offset snaps to next grapheme boundary" {
  let source = "e\u{0301}x\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let para_id = proj.children[0].id()
  let result = apply_edit(source, SplitBlock(node_id=para_id, offset=1))
  inspect(result, content="é\n\nx\n")
}

///|
test "split_block: ordered list item keeps ordered marker" {
  let source = "1. first\n2. second\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let item_id = proj.children[0].children[0].id()
  let result = apply_edit(source, SplitBlock(node_id=item_id, offset=2))
  inspect(result, content="1. fi\n2. rst\n2. second\n")
}

///|
test "merge_with_previous: first block is no-op" {
  let source = "Hello\n"
  let (proj, _) = @md_proj.parse_to_proj_node("Hello\n")
  let para_id = proj.children[0].id()
  let result = apply_edit(source, MergeWithPrevious(node_id=para_id))
  inspect(result, content="Hello\n")
}
