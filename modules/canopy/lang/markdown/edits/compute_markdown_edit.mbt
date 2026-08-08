///| Compute SpanEdits for Markdown edit operations.

///|
pub fn compute_markdown_edit(
  op : MarkdownEditOp,
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
) -> (Array[SpanEdit], FocusHint)? raise @core.EditError {
  match op {
    CommitEdit(node_id~, new_text~) =>
      compute_commit_edit(source, source_map, node_id, new_text)
    ChangeHeadingLevel(node_id~, level~) =>
      compute_change_heading_level(source, proj, source_map, node_id, level)
    ToggleListItem(node_id~) =>
      compute_toggle_list_item(source, proj, source_map, node_id)
    Delete(node_id~) => compute_delete(source_map, node_id)
    InsertBlockAfter(node_id~) =>
      compute_insert_block_after(source_map, node_id)
    SplitBlock(node_id~, offset~) =>
      compute_split_block(source, proj, source_map, node_id, offset)
    MergeWithPrevious(node_id~) =>
      compute_merge_with_previous(source, proj, source_map, node_id)
    MoveBlock(source=source_id, target=target_id, position~) =>
      compute_move_block(
        source, proj, source_map, source_id, target_id, position,
      )
  }
}

///|
/// Replace the editable "text" span of a block with new content.
fn compute_commit_edit(
  source : String,
  source_map : SourceMap,
  node_id : NodeId,
  new_text : String,
) -> (Array[SpanEdit], FocusHint)? raise @core.EditError {
  ensure_editable_target(source_map, node_id)
  // Try "text" role first, fall back to "code" for code blocks.
  let (range, is_code) = match source_map.get_token_span(node_id, "text") {
    Some(r) => (r, false)
    None =>
      match source_map.get_token_span(node_id, "code") {
        Some(r) => (r, true)
        None =>
          raise @core.EditError::SourceSpanMissing(
            detail="no editable span for node " + node_id.to_string(),
          )
      }
  }
  let inserted = if is_code {
    code_payload_for_commit(source, range.start, range.end, new_text)
  } else {
    new_text
  }
  Some(
    (
      [
        SpanEdit::{
          start: range.start,
          delete_len: range.end - range.start,
          inserted,
        },
      ],
      FocusHint::MoveCursor(position=range.start + inserted.length()),
    ),
  )
}

///|
/// Add the opening fence's line terminator when filling an empty code span.
fn code_payload_for_commit(
  source : String,
  range_start : Int,
  range_end : Int,
  new_text : String,
) -> String {
  if range_start != range_end || new_text.is_empty() || range_start == 0 {
    return new_text
  }
  let terminator = if range_start >= 2 &&
    source[range_start - 2] == '\r' &&
    source[range_start - 1] == '\n' {
    "\r\n"
  } else if source[range_start - 1] == '\r' {
    "\r"
  } else {
    "\n"
  }
  new_text + terminator
}

///|
/// Require the existing editable payload contract without classifying syntax
/// nodes through a cross-package SourceMap role. Code and list payloads stay
/// available to their lower-level edit contracts.
fn ensure_editable_target(
  source_map : SourceMap,
  node_id : NodeId,
) -> Unit raise @core.EditError {
  guard source_map.get_range(node_id) is Some(_) else {
    raise @core.EditError::NodeNotFound(
      action="compute_markdown_edit",
      node_id~,
    )
  }
  if source_map.get_token_span(node_id, "text") is None &&
    source_map.get_token_span(node_id, "code") is None {
    raise @core.EditError::SourceSpanMissing(
      detail="no editable span for node " + node_id.to_string(),
    )
  }
}

///|
fn normalize_atx_heading_content(content : String) -> String {
  let buf = StringBuilder::StringBuilder()
  let mut previous_was_cr = false
  for ch in content {
    if ch == '\r' {
      buf.write_char(' ')
      previous_was_cr = true
    } else if ch == '\n' {
      if !previous_was_cr {
        buf.write_char(' ')
      }
      previous_was_cr = false
    } else {
      buf.write_char(ch)
      previous_was_cr = false
    }
  }
  buf.to_string()
}

///|
fn block_replacement_terminator(
  source : String,
  range_start : Int,
  range_end : Int,
) -> String {
  if range_end > range_start && source[range_end - 1] == '\n' {
    if range_end - range_start > 1 && source[range_end - 2] == '\r' {
      "\r\n"
    } else {
      "\n"
    }
  } else if range_end > range_start && source[range_end - 1] == '\r' {
    "\r"
  } else if range_end < source.length() &&
    (source[range_end] == '\n' || source[range_end] == '\r') {
    ""
  } else {
    "\n"
  }
}

///|
/// Preserve an existing block terminator without adding one at EOF.
fn block_replacement_terminator_preserving_eof(
  source : String,
  range_start : Int,
  range_end : Int,
) -> String {
  if range_end == source.length() &&
    range_end > range_start &&
    source[range_end - 1] != '\n' &&
    source[range_end - 1] != '\r' {
    ""
  } else {
    block_replacement_terminator(source, range_start, range_end)
  }
}

///|
/// Change heading level (1-6) or convert paragraph to/from heading.
fn compute_change_heading_level(
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
  node_id : NodeId,
  level : Int,
) -> (Array[SpanEdit], FocusHint)? raise @core.EditError {
  ensure_change_heading_target(proj, node_id)
  ensure_editable_target(source_map, node_id)
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None =>
      raise @core.EditError::NodeNotInSourceMap(
        action="compute_markdown_edit",
        node_id~,
      )
  }
  let content = match source_map.get_token_span(node_id, "text") {
    Some(text_range) => source[text_range.start:text_range.end].to_owned()
    None => {
      // No text span — content is the whole block minus trailing newline
      let block_text = source[range.start:range.end].to_owned()
      let mut end = block_text.length()
      if end > 0 && block_text[end - 1] == '\n' {
        end = end - 1
      }
      block_text[:end].to_owned()
    }
  }
  let clamped = level.max(0).min(6)
  let new_prefix = if clamped > 0 {
    "#".repeat(clamped) + " "
  } else {
    "" // level 0 = paragraph (no prefix)
  }
  let rendered_content = if clamped > 0 {
    normalize_atx_heading_content(content)
  } else {
    content
  }
  let new_block = new_prefix +
    rendered_content +
    block_replacement_terminator(source, range.start, range.end)
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
        position=range.start + new_prefix.length() + rendered_content.length(),
      ),
    ),
  )
}

///|
fn ensure_change_heading_target(
  proj : ProjNode[@markdown.Block],
  node_id : NodeId,
) -> Unit raise @core.EditError {
  match @core.get_node_in_tree(proj, node_id) {
    Some(node) =>
      if node.kind is @markdown.Block::Paragraph(_) ||
        node.kind is @markdown.Block::Heading(_, _) {
        ()
      } else {
        raise @core.EditError::UnsupportedOperation(
          detail="change heading level requires a paragraph or heading block",
        )
      }
    None =>
      raise @core.EditError::NodeNotFound(
        action="compute_markdown_edit",
        node_id~,
      )
  }
}

///|
/// Toggle paragraph to/from list item.
fn compute_toggle_list_item(
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
  node_id : NodeId,
) -> (Array[SpanEdit], FocusHint)? raise @core.EditError {
  ensure_toggle_list_item_target(proj, node_id)
  ensure_editable_target(source_map, node_id)
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None =>
      raise @core.EditError::NodeNotInSourceMap(
        action="compute_markdown_edit",
        node_id~,
      )
  }
  let content = match source_map.get_token_span(node_id, "text") {
    Some(text_range) => source[text_range.start:text_range.end].to_owned()
    None => source[range.start:range.end].to_owned()
  }
  let is_list_item = match @core.get_node_in_tree(proj, node_id) {
    Some(node) => is_markdown_list_item(node.kind)
    None => false
  }
  let terminator = block_replacement_terminator(source, range.start, range.end)
  let (new_text, prefix_len) = if is_list_item {
    // List item -> paragraph: just content
    (content + terminator, 0)
  } else {
    // Paragraph -> list item: add "- " prefix
    ("- " + content + terminator, 2)
  }
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
  )
}

///|
fn ensure_toggle_list_item_target(
  proj : ProjNode[@markdown.Block],
  node_id : NodeId,
) -> Unit raise @core.EditError {
  match @core.get_node_in_tree(proj, node_id) {
    Some(node) =>
      if node.kind is @markdown.Block::Paragraph(_) ||
        is_markdown_list_item(node.kind) {
        ()
      } else {
        raise @core.EditError::UnsupportedOperation(
          detail="toggle list item requires a paragraph or list item block",
        )
      }
    None =>
      raise @core.EditError::NodeNotFound(
        action="compute_markdown_edit",
        node_id~,
      )
  }
}

///|
/// Delete a block (including trailing newline).
fn compute_delete(
  source_map : SourceMap,
  node_id : NodeId,
) -> (Array[SpanEdit], FocusHint)? raise @core.EditError {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None =>
      raise @core.EditError::NodeNotInSourceMap(
        action="compute_markdown_edit",
        node_id~,
      )
  }
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
  )
}

///|
/// Insert empty paragraph after a block.
fn compute_insert_block_after(
  source_map : SourceMap,
  node_id : NodeId,
) -> (Array[SpanEdit], FocusHint)? raise @core.EditError {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None =>
      raise @core.EditError::NodeNotInSourceMap(
        action="compute_markdown_edit",
        node_id~,
      )
  }
  let insert_pos = range.end
  // Insert "\n<sentinel>\n" to create a visible empty paragraph.
  // The zero-width space gives the parser a real token to produce a ProjNode,
  // so BlockInput can render and focus the new block. The sentinel is stripped at:
  //   - markdown_export_text() (FFI export boundary — raw mode)
  //   - BlockInput.stripParagraphSentinels (TS display/edit/commit, sourced
  //     from this FFI's markdown_empty_paragraph_sentinel accessor)
  //   - compute_merge_with_previous (on block merge)
  // Known minor gap: MarkdownPreview renders node.text as-is (sentinel invisible
  // in HTML, but could leak on copy-paste from preview).
  // Long-term fix: migrate to Container per-block text (empty block = empty text).
  Some(
    (
      [
        SpanEdit::{
          start: insert_pos,
          delete_len: 0,
          inserted: "\n" + @md_sentinel.EMPTY_PARAGRAPH_SENTINEL + "\n",
        },
      ],
      FocusHint::MoveCursor(position=insert_pos + 1),
    ),
  )
}

///|
/// Split block at cursor offset within the text span.
///
/// `offset` is a UTF-16 code-unit offset inside the block's text span
/// (i.e. relative to `text_range.start`, not the document root). The
/// offset is snapped forward to a grapheme boundary within the block text
/// before computing the split point.
fn compute_split_block(
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
  node_id : NodeId,
  offset : Int,
) -> (Array[SpanEdit], FocusHint)? raise @core.EditError {
  ensure_editable_target(source_map, node_id)
  let text_range = match source_map.get_token_span(node_id, "text") {
    Some(r) => r
    None =>
      raise @core.EditError::SourceSpanMissing(detail="no text span for split")
  }
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None =>
      raise @core.EditError::NodeNotInSourceMap(
        action="compute_markdown_edit",
        node_id~,
      )
  }
  let text_slice = source[text_range.start:text_range.end].to_owned()
  let split_offset = @moji.next_grapheme_boundary(text_slice, offset)
  // Split at offset 0 → insert empty paragraph before this block
  if split_offset <= 0 {
    let insert_pos = range.start
    return Some(
      (
        [
          SpanEdit::{
            start: insert_pos,
            delete_len: 0,
            inserted: @md_sentinel.EMPTY_PARAGRAPH_SENTINEL + "\n\n",
          },
        ],
        FocusHint::MoveCursor(position=insert_pos),
      ),
    )
  }
  // Split at end -> insert empty paragraph after
  let text_len = text_range.end - text_range.start
  if split_offset >= text_len {
    return compute_insert_block_after(source_map, node_id)
  }
  // Split point in source coordinates
  let split_pos = text_range.start + split_offset
  let is_list_item = match @core.get_node_in_tree(proj, node_id) {
    Some(node) => is_markdown_list_item(node.kind)
    None => false
  }
  let separator = if is_list_item {
    let marker = source[range.start:text_range.start].to_owned()
    split_list_item_separator(marker)
  } else {
    "\n\n"
  }
  // Delete from split point to end of block, then insert separator + rest.
  // List item source ranges can exclude the following line break; include it
  // so the inserted marker does not create a blank line between list items.
  let delete_end = if is_list_item &&
    range.end < source.length() &&
    source[range.end] == '\n' {
    range.end + 1
  } else {
    range.end
  }
  let rest = source[split_pos:delete_end].to_owned()
  // Trim trailing newline from rest if present
  let trimmed_rest = if rest.length() > 0 && rest[rest.length() - 1] == '\n' {
    rest[:rest.length() - 1].to_owned()
  } else {
    rest
  }
  let inserted = separator + trimmed_rest + "\n"
  Some(
    (
      [
        SpanEdit::{
          start: split_pos,
          delete_len: delete_end - split_pos,
          inserted,
        },
      ],
      FocusHint::MoveCursor(position=split_pos + separator.length()),
    ),
  )
}

///|
fn is_markdown_list_item(block : @markdown.Block) -> Bool {
  block is @markdown.Block::UnorderedListItem(_) ||
  block is @markdown.Block::OrderedListItem(_, _)
}

///|
/// Keep merge lowering limited to block kinds with text-merge semantics.
fn is_mergeable_text_block(block : @markdown.Block) -> Bool {
  block is @markdown.Block::Paragraph(_) ||
  block is @markdown.Block::Heading(_, _) ||
  is_markdown_list_item(block)
}

///|
/// Return the marker prefix to use when splitting a Markdown list item.
///
/// Preserve the concrete source marker instead of synthesizing an unordered
/// `- ` bullet for every split.
fn split_list_item_separator(marker : String) -> String {
  match next_ordered_marker(marker) {
    Some(next) => "\n" + next
    None => "\n" + marker
  }
}

///|
fn next_ordered_marker(marker : String) -> String? {
  guard marker.find_by(fn(ch) { ch != ' ' && ch != '\t' }) is Some(marker_start) else {
    return None
  }
  let marker_body = marker.view(start_offset=marker_start)
  let digit_start = if marker_body.length() > 0 && marker_body[0] == '-' {
    1
  } else {
    0
  }
  guard marker_body
    .view(start_offset=digit_start)
    .find_by(fn(ch) { !(ch is ('0'..='9')) })
    is Some(delimiter_offset_from_digit_start) else {
    return None
  }
  let delimiter_offset = digit_start + delimiter_offset_from_digit_start
  if delimiter_offset == digit_start {
    return None
  }
  match marker_body[delimiter_offset] {
    '.' | ')' => {
      let value = @string.parse_int(marker_body[:delimiter_offset], base=10) catch {
        _ => return None
      }
      Some(
        marker.view(end_offset=marker_start).to_owned() +
        (value + 1).to_string() +
        marker_body[delimiter_offset:delimiter_offset + 1].to_owned() +
        marker_body[delimiter_offset + 1:].to_owned(),
      )
    }
    _ => None
  }
}

///|
/// Merge block with previous block.
fn compute_merge_with_previous(
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
  node_id : NodeId,
) -> (Array[SpanEdit], FocusHint)? raise @core.EditError {
  ensure_editable_target(source_map, node_id)
  // Find the parent that contains this node, then find sibling index
  let (siblings, idx) = find_sibling_context(proj, node_id)
  if idx < 0 {
    raise @core.EditError::NodeNotFound(
      action="compute_markdown_edit",
      node_id~,
    )
  }
  // First sibling — no-op
  if idx == 0 {
    return None
  }
  let curr_text_range = match source_map.get_token_span(node_id, "text") {
    Some(range) => range
    None =>
      raise @core.EditError::SourceSpanMissing(
        detail="no editable text span for merge target " + node_id.to_string(),
      )
  }
  let prev_node = siblings[idx - 1]
  let curr_node = siblings[idx]
  guard is_mergeable_text_block(prev_node.kind) &&
    is_mergeable_text_block(curr_node.kind) else {
    raise @core.EditError::UnsupportedOperation(
      detail="merge requires a mergeable current and previous block",
    )
  }
  let curr_range = match source_map.get_range(node_id) {
    Some(r) => r
    None =>
      raise @core.EditError::NodeNotInSourceMap(
        action="compute_markdown_edit",
        node_id~,
      )
  }
  let curr_text = source[curr_text_range.start:curr_text_range.end].to_owned()
  let prev_text_range = match
    source_map.get_token_span(prev_node.id(), "text") {
    Some(range) => range
    None =>
      raise @core.EditError::SourceSpanMissing(
        detail="no editable text span for previous block " +
          prev_node.id().to_string(),
      )
  }
  let prev_text = source[prev_text_range.start:prev_text_range.end].to_owned()
  let prev_is_empty = @md_sentinel.is_empty_paragraph_text(prev_text)
  let curr_is_empty = @md_sentinel.is_empty_paragraph_text(curr_text)
  // A sentinel in the previous block must be inside the replacement span;
  // otherwise merging real text after it turns the private placeholder into
  // visible content that portable Markdown can no longer strip. If both
  // blocks are empty, keep one sentinel so the surviving paragraph remains
  // projectable.
  let edit_start = if prev_is_empty {
    prev_text_range.start
  } else {
    prev_text_range.end
  }
  let clean_text = match (prev_is_empty, curr_is_empty) {
    (true, true) => @md_sentinel.EMPTY_PARAGRAPH_SENTINEL
    (_, true) => ""
    (_, false) => curr_text
  }
  // The delete span covers: the private previous sentinel when present,
  // separators, and the current block through its terminator. Preserve that
  // exact terminator, including CRLF, CR, and EOF-without-terminator.
  let terminator = block_replacement_terminator_preserving_eof(
    source,
    curr_range.start,
    curr_range.end,
  )
  let inserted = clean_text + terminator
  Some(
    (
      [
        SpanEdit::{
          start: edit_start,
          delete_len: curr_range.end - edit_start,
          inserted,
        },
      ],
      FocusHint::MoveCursor(position=edit_start),
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

///|
/// Find a node's parent, siblings, and index among them.
fn find_sibling_context_and_parent(
  root : ProjNode[@markdown.Block],
  target : NodeId,
) -> (ProjNode[@markdown.Block]?, Array[ProjNode[@markdown.Block]], Int) {
  for i in 0..<root.children.length() {
    if root.children[i].id() == target {
      return (Some(root), root.children, i)
    }
    let (parent, siblings, idx) = find_sibling_context_and_parent(
      root.children[i],
      target,
    )
    if idx >= 0 {
      return (parent, siblings, idx)
    }
  }
  (None, [], -1)
}
