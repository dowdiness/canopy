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
  match source_map.get_token_span(node_id, "text") {
    Some(range) =>
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
    None => Err("no text span for node " + node_id.to_string())
  }
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
  // Get block content (text span)
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
  // Build new block text
  let new_prefix = if level > 0 {
    "#".repeat(level) + " "
  } else {
    "" // level 0 means convert to paragraph (no prefix)
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
  // Get block content (text span)
  let content = match source_map.get_token_span(node_id, "text") {
    Some(text_range) => source[text_range.start:text_range.end].to_string()
    None => source[range.start:range.end].to_string()
  }
  // Check if this node is already a list item
  let is_list_item = match find_node(proj, node_id) {
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
  Ok(
    Some(
      (
        [SpanEdit::{ start: insert_pos, delete_len: 0, inserted: "\n" }],
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
  // Split at offset 0 -> insert empty paragraph before
  if offset <= 0 {
    return compute_insert_block_after(source_map, node_id)
  }
  // Split at end -> insert empty paragraph after
  let text_len = text_range.end - text_range.start
  if offset >= text_len {
    return compute_insert_block_after(source_map, node_id)
  }
  // Split point in source coordinates
  let split_pos = text_range.start + offset
  // Check if this is a list item — second half gets "- " prefix
  let is_list_item = match find_node(proj, node_id) {
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
  // Find this node's index among siblings
  let siblings = proj.children
  let mut idx = -1
  for i in 0..<siblings.length() {
    if siblings[i].id() == node_id {
      idx = i
      break
    }
  }
  // First block — no-op
  if idx <= 0 {
    return Ok(None)
  }
  let prev_node = siblings[idx - 1]
  let prev_range = match source_map.get_range(prev_node.id()) {
    Some(r) => r
    None => return Err("previous node not in source map")
  }
  let curr_range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("current node not in source map")
  }
  // Get current block's text content
  let curr_text = match source_map.get_token_span(node_id, "text") {
    Some(r) => source[r.start:r.end].to_string()
    None => ""
  }
  // Merge: delete from end of previous block's text to end of current block,
  // then insert the current block's text
  let prev_text_end = match source_map.get_token_span(prev_node.id(), "text") {
    Some(r) => r.end
    None => prev_range.end
  }
  let cursor_pos = prev_text_end
  ignore(prev_range)
  Ok(
    Some(
      (
        [
          SpanEdit::{
            start: prev_text_end,
            delete_len: curr_range.end - prev_text_end,
            inserted: curr_text,
          },
        ],
        FocusHint::MoveCursor(position=cursor_pos),
      ),
    ),
  )
}

///|
/// Find a ProjNode by NodeId in the tree.
fn find_node(
  root : ProjNode[@markdown.Block],
  target : NodeId,
) -> ProjNode[@markdown.Block]? {
  if root.id() == target {
    return Some(root)
  }
  for child in root.children {
    match find_node(child, target) {
      Some(found) => return Some(found)
      None => continue
    }
  }
  None
}
