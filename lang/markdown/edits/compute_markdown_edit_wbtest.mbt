///| Whitebox tests for Markdown edit ops (pure compute, no SyncEditor).

///|
fn compute_edit_result(
  source : String,
  op : MarkdownEditOp,
) -> Result[(Array[SpanEdit], FocusHint)?, String] raise @loomcore.LexError {
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let source_map = @core.SourceMap::from_ast(proj)
  // Re-parse to get the SyntaxNode for populate_token_spans
  let (cst, _) = @markdown.parse_cst(source)
  let syntax_root = @seam.SyntaxNode::from_cst(cst)
  @md_proj.populate_token_spans(source_map, syntax_root, proj)
  compute_markdown_edit(op, source, proj, source_map)
}

///|
/// Helper: parse, project, populate token spans, compute edit, return new source text.
fn apply_edit(
  source : String,
  op : MarkdownEditOp,
) -> String raise @loomcore.LexError {
  match compute_edit_result(source, op) {
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

///|
test "move_block: moves sibling before target" {
  let source = "# A\n# B\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let a_id = proj.children[0].id()
  let b_id = proj.children[1].id()
  let result = apply_edit(
    source,
    MoveBlock(source=b_id, target=a_id, position=@core.DropPosition::Before),
  )
  inspect(result, content="# B\n# A\n")
}

///|
test "move_block: adjacent after move is no-op" {
  let source = "# A\n# B\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let a_id = proj.children[0].id()
  let b_id = proj.children[1].id()
  let result = apply_edit(
    source,
    MoveBlock(source=a_id, target=b_id, position=@core.DropPosition::Before),
  )
  inspect(result, content="# A\n# B\n")
}

///|
test "move_block: adjacent duplicate before move is no-op" {
  let source = "# X\n# X\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let first_id = proj.children[0].id()
  let second_id = proj.children[1].id()
  let result = compute_edit_result(
    source,
    MoveBlock(
      source=first_id,
      target=second_id,
      position=@core.DropPosition::Before,
    ),
  )
  inspect(result is Ok(None), content="true")
}

///|
test "move_block: preserves paragraph blank-line separator before target" {
  let source = "A\n\nB\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let a_id = proj.children[0].id()
  let b_id = proj.children[1].id()
  let result = apply_edit(
    source,
    MoveBlock(source=b_id, target=a_id, position=@core.DropPosition::Before),
  )
  inspect(result, content="B\n\nA\n")
}

///|
test "move_block: preserves paragraph blank-line separator after target" {
  let source = "A\n\nB\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let a_id = proj.children[0].id()
  let b_id = proj.children[1].id()
  let result = apply_edit(
    source,
    MoveBlock(source=a_id, target=b_id, position=@core.DropPosition::After),
  )
  inspect(result, content="B\n\nA\n")
}

///|
test "move_block: preserves separator when moving final block without trailing newline" {
  let source = "# A\n# B"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let a_id = proj.children[0].id()
  let b_id = proj.children[1].id()
  let result = apply_edit(
    source,
    MoveBlock(source=b_id, target=a_id, position=@core.DropPosition::Before),
  )
  inspect(result, content="# B\n# A\n")
}

///|
test "move_block: preserves separator when moving first block after EOF block" {
  let source = "# A\n# B"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let a_id = proj.children[0].id()
  let b_id = proj.children[1].id()
  let result = apply_edit(
    source,
    MoveBlock(source=a_id, target=b_id, position=@core.DropPosition::After),
  )
  inspect(result, content="# B\n# A\n")
}

///|
test "move_block: preserves paragraph break left behind by moved heading" {
  let source = "A\n\n# B\nC\n\nD\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let heading_id = proj.children[1].id()
  let d_id = proj.children[3].id()
  let result = apply_edit(
    source,
    MoveBlock(
      source=heading_id,
      target=d_id,
      position=@core.DropPosition::After,
    ),
  )
  inspect(result, content="A\n\nC\n\nD\n# B\n")
}

///|
test "move_block: preserves paragraph break at target insertion" {
  let source = "# H\nP\n\nQ\n\nR\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let p_id = proj.children[1].id()
  let r_id = proj.children[3].id()
  let result = apply_edit(
    source,
    MoveBlock(source=p_id, target=r_id, position=@core.DropPosition::Before),
  )
  inspect(result, content="# H\nQ\n\nP\n\nR\n")
}

///|
test "move_block: preserves root paragraph after list target" {
  let source = "A\n\n- B\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let paragraph_id = proj.children[0].id()
  let list_id = proj.children[1].id()
  let result = apply_edit(
    source,
    MoveBlock(
      source=paragraph_id,
      target=list_id,
      position=@core.DropPosition::After,
    ),
  )
  inspect(result, content="- B\n\nA\n")
}

///|
test "move_block: rejects unclosed fenced code before following sibling" {
  let source = "# A\n```\ncode\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let heading_id = proj.children[0].id()
  let code_id = proj.children[1].id()
  let result = compute_edit_result(
    source,
    MoveBlock(
      source=heading_id,
      target=code_id,
      position=@core.DropPosition::After,
    ),
  )
  inspect(result is Err(_), content="true")
}

///|
test "move_block: preserves unrelated adjacent sibling separator" {
  let source = "# A\n\n\n# B\n# C\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let a_id = proj.children[0].id()
  let c_id = proj.children[2].id()
  let result = apply_edit(
    source,
    MoveBlock(source=c_id, target=a_id, position=@core.DropPosition::Before),
  )
  inspect(result, content="# C\n# A\n\n\n# B\n")
}

///|
test "move_block: rejects inside position" {
  let source = "# A\n# B\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let a_id = proj.children[0].id()
  let b_id = proj.children[1].id()
  let result = compute_edit_result(
    source,
    MoveBlock(source=a_id, target=b_id, position=@core.DropPosition::Inside),
  )
  inspect(result is Err(_), content="true")
}

///|
test "move_block: rejects nested list item moves" {
  let source = "- A\n- B\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let a_id = proj.children[0].children[0].id()
  let b_id = proj.children[0].children[1].id()
  let result = compute_edit_result(
    source,
    MoveBlock(source=b_id, target=a_id, position=@core.DropPosition::Before),
  )
  inspect(result is Err(_), content="true")
}

///|
test "move_block: rejects list container sources" {
  let source = "# A\n- B\n- C\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let heading_id = proj.children[0].id()
  let list_id = proj.children[1].id()
  let result = compute_edit_result(
    source,
    MoveBlock(
      source=list_id,
      target=heading_id,
      position=@core.DropPosition::Before,
    ),
  )
  inspect(result is Err(_), content="true")
}

///|
test "move_block: rejects duplicate source payloads" {
  let source = "# X\n# X\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let first_id = proj.children[0].id()
  let second_id = proj.children[1].id()
  let result = compute_edit_result(
    source,
    MoveBlock(
      source=second_id,
      target=first_id,
      position=@core.DropPosition::Before,
    ),
  )
  inspect(result is Err(_), content="true")
}
