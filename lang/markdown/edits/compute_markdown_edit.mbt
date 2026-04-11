///| Compute SpanEdits for Markdown edit operations.

///|
pub fn compute_markdown_edit(
  op : MarkdownEditOp,
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  match op {
    CommitEdit(node_id~, new_text~) =>
      compute_commit_edit(source_map, node_id, new_text)
    ChangeHeadingLevel(node_id~, level~) =>
      compute_change_heading_level(source, source_map, node_id, level)
    ToggleListItem(node_id~) =>
      compute_toggle_list_item(source, proj, source_map, node_id)
    Delete(node_id~) => compute_delete(source_map, node_id)
    InsertBlockAfter(node_id~) =>
      compute_insert_block_after(source_map, node_id)
    SplitBlock(node_id~, offset~) =>
      compute_split_block(source, proj, source_map, node_id, offset)
    MergeWithPrevious(node_id~) =>
      compute_merge_with_previous(source, proj, source_map, node_id)
  }
}

///|
/// Replace the editable "text" span of a block with new content.
fn compute_commit_edit(
  source_map : SourceMap,
  node_id : NodeId,
  new_text : String,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  // Try "text" role first, fall back to "code" for code blocks
  let range = match source_map.get_token_span(node_id, "text") {
    Some(r) => r
    None =>
      match source_map.get_token_span(node_id, "code") {
        Some(r) => r
        None => return Err("no editable span for node " + node_id.to_string())
      }
  }
  Ok(
    Some(
      (
        [
          SpanEdit::{
            start: range.start,
            delete_len: range.end - range.start,
            inserted: new_text,
          },
        ],
        FocusHint::MoveCursor(position=range.start + new_text.length()),
      ),
    ),
  )
}

///|
/// Change heading level (1-6) or convert paragraph to/from heading.
fn compute_change_heading_level(
  source : String,
  source_map : SourceMap,
  node_id : NodeId,
  level : Int,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  let content = match source_map.get_token_span(node_id, "text") {
    Some(text_range) => source[text_range.start:text_range.end].to_string()
    None => {
      // No text span — content is the whole block minus trailing newline
      let block_text = source[range.start:range.end].to_string()
      let mut end = block_text.length()
      if end > 0 && block_text[end - 1] == '\n' {
        end = end - 1
      }
      block_text[:end].to_string()
    }
  }
  let clamped = level.max(0).min(6)
  let new_prefix = if clamped > 0 {
    "#".repeat(clamped) + " "
  } else {
    "" // level 0 = paragraph (no prefix)
  }
  let new_block = new_prefix + content + "\n"
  Ok(
    Some(
      (
        [
          SpanEdit::{
            start: range.start,
            delete_len: range.end - range.start,
            inserted: new_block,
          },
        ],
        FocusHint::MoveCursor(
          position=range.start + new_prefix.length() + content.length(),
        ),
      ),
    ),
  )
}

///|
/// Toggle paragraph to/from list item.
fn compute_toggle_list_item(
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
  node_id : NodeId,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  let content = match source_map.get_token_span(node_id, "text") {
    Some(text_range) => source[text_range.start:text_range.end].to_string()
    None => source[range.start:range.end].to_string()
  }
  let is_list_item = match @core.get_node_in_tree(proj, node_id) {
    Some(node) => node.kind is @markdown.ListItem(_)
    None => false
  }
  let (new_text, prefix_len) = if is_list_item {
    // List item -> paragraph: just content
    (content + "\n", 0)
  } else {
    // Paragraph -> list item: add "- " prefix
    ("- " + content + "\n", 2)
  }
  Ok(
    Some(
      (
        [
          SpanEdit::{
            start: range.start,
            delete_len: range.end - range.start,
            inserted: new_text,
          },
        ],
        FocusHint::MoveCursor(
          position=range.start + prefix_len + content.length(),
        ),
      ),
    ),
  )
}

///|
/// Delete a block (including trailing newline).
fn compute_delete(
  source_map : SourceMap,
  node_id : NodeId,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  Ok(
    Some(
      (
        [
          SpanEdit::{
            start: range.start,
            delete_len: range.end - range.start,
            inserted: "",
          },
        ],
        FocusHint::RestoreCursor,
      ),
    ),
  )
}

///|
/// Insert empty paragraph after a block.
fn compute_insert_block_after(
  source_map : SourceMap,
  node_id : NodeId,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  let insert_pos = range.end
  // Insert "\n\u200B\n" to create a visible empty paragraph.
  // The zero-width space gives the parser a real token to produce a ProjNode,
  // so BlockInput can render and focus the new block. ZWSP is stripped at:
  //   - markdown_export_text() (FFI export boundary — raw mode)
  //   - block-input.ts (TS display/edit/commit — 3 sites)
  //   - compute_merge_with_previous (on block merge)
  // Known minor gap: MarkdownPreview renders node.text as-is (ZWSP invisible
  // in HTML, but could leak on copy-paste from preview).
  // Long-term fix: migrate to Container per-block text (empty block = empty text).
  Ok(
    Some(
      (
        [SpanEdit::{ start: insert_pos, delete_len: 0, inserted: "\n\u200B\n" }],
        FocusHint::MoveCursor(position=insert_pos + 1),
      ),
    ),
  )
}

///|
/// Split block at cursor offset within the text span.
fn compute_split_block(
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
  node_id : NodeId,
  offset : Int,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let text_range = match source_map.get_token_span(node_id, "text") {
    Some(r) => r
    None => return Err("no text span for split")
  }
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found")
  }
  // Split at offset 0 → insert empty paragraph before this block
  if offset <= 0 {
    let insert_pos = range.start
    return Ok(
      Some(
        (
          [SpanEdit::{ start: insert_pos, delete_len: 0, inserted: "\n" }],
          FocusHint::MoveCursor(position=insert_pos),
        ),
      ),
    )
  }
  // Split at end -> insert empty paragraph after
  let text_len = text_range.end - text_range.start
  if offset >= text_len {
    return compute_insert_block_after(source_map, node_id)
  }
  // Split point in source coordinates
  let split_pos = text_range.start + offset
  let is_list_item = match @core.get_node_in_tree(proj, node_id) {
    Some(node) => node.kind is @markdown.ListItem(_)
    None => false
  }
  let separator = if is_list_item { "\n- " } else { "\n\n" }
  // Delete from split point to end of block, then insert separator + rest
  let rest = source[split_pos:range.end].to_string()
  // Trim trailing newline from rest if present
  let trimmed_rest = if rest.length() > 0 && rest[rest.length() - 1] == '\n' {
    rest[:rest.length() - 1].to_string()
  } else {
    rest
  }
  let inserted = separator + trimmed_rest + "\n"
  Ok(
    Some(
      (
        [
          SpanEdit::{
            start: split_pos,
            delete_len: range.end - split_pos,
            inserted,
          },
        ],
        FocusHint::MoveCursor(position=split_pos + separator.length()),
      ),
    ),
  )
}

///|
/// Merge block with previous block.
fn compute_merge_with_previous(
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
  node_id : NodeId,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  // Find the parent that contains this node, then find sibling index
  let (siblings, idx) = find_sibling_context(proj, node_id)
  if idx < 0 {
    return Err("node not found in projection tree: " + node_id.to_string())
  }
  // First sibling — no-op
  if idx == 0 {
    return Ok(None)
  }
  let prev_node = siblings[idx - 1]
  let curr_range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("current node not in source map")
  }
  let curr_text = match source_map.get_token_span(node_id, "text") {
    Some(r) => source[r.start:r.end].to_string()
    None => ""
  }
  // End of previous block's text content — merge point
  let prev_text_end = match source_map.get_token_span(prev_node.id(), "text") {
    Some(r) => r.end
    None =>
      // No text span — use full block range end as fallback
      match source_map.get_range(prev_node.id()) {
        Some(r) => r.end
        None => return Err("previous node not in source map")
      }
  }
  // Strip ZWSP placeholder (from InsertBlockAfter empty blocks)
  let clean_text = if curr_text == "\u200B" { "" } else { curr_text }
  // The delete span covers: previous block's trailing newline, blank-line
  // separator, current block's prefix + text + trailing newline. Always
  // append \n to restore the proper \n\n block separator with the next block.
  let inserted = clean_text + "\n"
  Ok(
    Some(
      (
        [
          SpanEdit::{
            start: prev_text_end,
            delete_len: curr_range.end - prev_text_end,
            inserted,
          },
        ],
        FocusHint::MoveCursor(position=prev_text_end),
      ),
    ),
  )
}

///|
/// Find a node's siblings and its index among them.
/// Searches the tree for the parent containing `target`, handling nested
/// structures like list items inside UnorderedList.
fn find_sibling_context(
  root : ProjNode[@markdown.Block],
  target : NodeId,
) -> (Array[ProjNode[@markdown.Block]], Int) {
  for i in 0..<root.children.length() {
    if root.children[i].id() == target {
      return (root.children, i)
    }
    // Search nested children (e.g., list items inside UnorderedList)
    let (siblings, idx) = find_sibling_context(root.children[i], target)
    if idx >= 0 {
      return (siblings, idx)
    }
  }
  ([], -1)
}
