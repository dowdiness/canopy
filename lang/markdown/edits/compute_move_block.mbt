///| Source-text lowering for explicit Markdown block moves.

///|
/// Move a sibling block before or after another block.
fn compute_move_block(
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
  source_id : NodeId,
  target_id : NodeId,
  position : DropPosition,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  if source_id == target_id {
    return Ok(None)
  }
  guard position is Before || position is After else {
    return Err("markdown block move supports only before/after positions")
  }
  let (source_parent, source_siblings, source_idx) = find_sibling_context_and_parent(
    proj, source_id,
  )
  if source_idx < 0 {
    return Err(
      "source node not found in projection tree: " + source_id.to_string(),
    )
  }
  let (target_parent, target_siblings, target_idx) = find_sibling_context_and_parent(
    proj, target_id,
  )
  if target_idx < 0 {
    return Err(
      "target node not found in projection tree: " + target_id.to_string(),
    )
  }
  guard source_parent is Some(source_parent_node) else {
    return Err(
      "source node not found in projection tree: " + source_id.to_string(),
    )
  }
  guard target_parent is Some(target_parent_node) else {
    return Err(
      "target node not found in projection tree: " + target_id.to_string(),
    )
  }
  if source_parent_node.id() != target_parent_node.id() {
    if is_markdown_list_item(source_siblings[source_idx].kind) {
      return Err(list_payload_blocker("list-item sources"))
    }
    if is_markdown_list_item(target_siblings[target_idx].kind) {
      return Err(list_payload_blocker("list-item targets"))
    }
    return Err(
      "markdown block move currently supports same-container siblings only",
    )
  }
  match position {
    Before if source_idx + 1 == target_idx => return Ok(None)
    After if target_idx + 1 == source_idx => return Ok(None)
    _ => ()
  }
  let source_kind = source_siblings[source_idx].kind
  if source_kind is @markdown.Block::UnorderedList(_) ||
    source_kind is @markdown.Block::OrderedList(_, _) {
    return Err(list_payload_blocker("list container sources"))
  }
  if source_siblings.any(sibling => {
      sibling.id() != source_id &&
      move_block_payload_equal(sibling.kind, source_kind)
    }) {
    return Err("markdown block move requires a unique source block payload")
  }
  let move_result = match source_parent_node.id() {
    parent_id if parent_id == proj.id() =>
      compute_root_move_source(
        source, source_siblings, source_idx, target_idx, position, source_map,
      )
    _ if is_markdown_list_item(source_kind) &&
      is_markdown_list_item(target_siblings[target_idx].kind) =>
      compute_list_item_move_source(
        source, source_siblings, source_idx, target_idx, position, source_map,
      )
    _ =>
      Err(
        "markdown block move currently supports root blocks and same-list items only",
      )
  }
  let (replace_start, replace_end, inserted) = match move_result {
    Ok(patch) => patch
    Err(msg) => return Err(msg)
  }
  Ok(
    Some(
      (
        [
          SpanEdit::{
            start: replace_start,
            delete_len: replace_end - replace_start,
            inserted,
          },
        ],
        FocusHint::RestoreCursor,
      ),
    ),
  )
}

///|
fn list_payload_blocker(blocked : String) -> String {
  // The sibling-level reconciler cannot preserve identity across a container
  // boundary, so cross-container / list-container moves stay rejected. This is a
  // proof-backed standing decision (#724), not a temporary gate; see
  // docs/design/sdeg-invariant-review.md "Decision: Markdown move-provenance
  // scope" and the drag-drop-foundation follow-up in docs/TODO.md.
  "markdown block move rejects " +
  blocked +
  ": cannot preserve identity across a container boundary; see docs/design/sdeg-invariant-review.md (Decision: Markdown move-provenance scope) and docs/TODO.md"
}

///|
/// Compare the stable payload used to prove a move source is unambiguous.
/// Ordered-list item markers are intentionally ignored because supported moves
/// renumber them during source-text lowering.
fn move_block_payload_equal(
  left : @markdown.Block,
  right : @markdown.Block,
) -> Bool {
  match (left, right) {
    (OrderedListItem(left_inlines, _), OrderedListItem(right_inlines, _)) =>
      left_inlines == right_inlines
    _ => left == right
  }
}

///|
/// Return siblings after moving one entry before/after another same-container
/// entry. The copy/remove/insert mutation is confined to this array transform.
fn reordered_siblings(
  siblings : Array[ProjNode[@markdown.Block]],
  source_idx : Int,
  target_idx : Int,
  position : DropPosition,
) -> Array[ProjNode[@markdown.Block]] {
  let reordered = siblings.copy()
  let source = reordered.remove(source_idx)
  let adjusted_target_idx = if source_idx < target_idx {
    target_idx - 1
  } else {
    target_idx
  }
  let insert_idx = match position {
    Before => adjusted_target_idx
    After => adjusted_target_idx + 1
    Inside => abort("unreachable: inside rejected above")
  }
  reordered.insert(insert_idx, source)
  reordered
}

///|
fn compute_root_move_source(
  source : String,
  siblings : Array[ProjNode[@markdown.Block]],
  source_idx : Int,
  target_idx : Int,
  position : DropPosition,
  source_map : SourceMap,
) -> Result[(Int, Int, String), String] {
  let reordered = reordered_siblings(siblings, source_idx, target_idx, position)
  match validate_no_unclosed_code_before_sibling(reordered, source_map) {
    Ok(_) => ()
    Err(msg) => return Err(msg)
  }
  let first_range = match source_map.get_range(siblings[0].id()) {
    Some(r) => r
    None => return Err("first sibling not in source map")
  }
  let last_range = match
    source_map.get_range(siblings[siblings.length() - 1].id()) {
    Some(r) => r
    None => return Err("last sibling not in source map")
  }
  let buffer = StringBuilder::new()
  for idx, node in reordered {
    if idx > 0 {
      match
        separator_between_nodes(
          source,
          siblings,
          reordered[idx - 1],
          node,
          source_map,
        ) {
        Ok(separator) => buffer.write_string(separator)
        Err(msg) => return Err(msg)
      }
    }
    match block_text_without_trailing_newlines(source, node, source_map) {
      Ok(text) => buffer.write_string(text)
      Err(msg) => return Err(msg)
    }
  }
  buffer.write_string("\n")
  Ok((first_range.start, last_range.end, buffer.to_string()))
}

///|
fn compute_list_item_move_source(
  source : String,
  siblings : Array[ProjNode[@markdown.Block]],
  source_idx : Int,
  target_idx : Int,
  position : DropPosition,
  source_map : SourceMap,
) -> Result[(Int, Int, String), String] {
  let reordered = reordered_siblings(siblings, source_idx, target_idx, position)
  let first_range = match source_map.get_range(siblings[0].id()) {
    Some(r) => r
    None => return Err("first list item not in source map")
  }
  let last_range = match
    source_map.get_range(siblings[siblings.length() - 1].id()) {
    Some(r) => r
    None => return Err("last list item not in source map")
  }
  match reject_loose_list_separators(source, siblings, source_map) {
    Ok(_) => ()
    Err(msg) => return Err(msg)
  }
  let ordered_seed = match siblings[0].kind {
    @markdown.Block::OrderedListItem(_, _) =>
      ordered_list_marker_seed(source, siblings[0], source_map)
    _ => None
  }
  let buffer = StringBuilder::new()
  let mut marker = ordered_seed.unwrap_or("")
  for idx, node in reordered {
    if idx > 0 {
      buffer.write_string("\n")
    }
    match ordered_seed {
      Some(_) => {
        marker = match next_ordered_marker(marker) {
          Some(next) => next
          None => return Err("ordered list item marker is not parseable")
        }
        match ordered_list_item_content(source, node, source_map, marker) {
          Ok(content) => {
            let marker = ordered_marker_for_content(marker, content)
            buffer.write_string(marker)
            buffer.write_string(content)
          }
          Err(msg) => return Err(msg)
        }
      }
      None =>
        match block_text_without_trailing_newlines(source, node, source_map) {
          Ok(text) => buffer.write_string(text)
          Err(msg) => return Err(msg)
        }
    }
  }
  buffer.write_string("\n")
  let replace_end = if last_range.end < source.length() &&
    source[last_range.end] == '\n' {
    last_range.end + 1
  } else {
    last_range.end
  }
  Ok((first_range.start, replace_end, buffer.to_string()))
}

///|
fn reject_loose_list_separators(
  source : String,
  siblings : Array[ProjNode[@markdown.Block]],
  source_map : SourceMap,
) -> Result[Unit, String] {
  for idx in 0..<(siblings.length() - 1) {
    let left_range = match source_map.get_range(siblings[idx].id()) {
      Some(r) => r
      None => return Err("left list item not in source map")
    }
    let right_range = match source_map.get_range(siblings[idx + 1].id()) {
      Some(r) => r
      None => return Err("right list item not in source map")
    }
    let left_end = block_text_end_without_trailing_newlines(
      source,
      left_range.start,
      left_range.end,
    )
    if separator_has_blank_line(source[left_end:right_range.start].to_owned()) {
      return Err("markdown list item move currently rejects loose lists")
    }
  }
  Ok(())
}

///|
fn separator_has_blank_line(separator : String) -> Bool {
  for idx in 0..<separator.length() {
    if separator[idx] == '\n' {
      let mut next = idx + 1
      while next < separator.length() &&
            (separator[next] == ' ' || separator[next] == '\t') {
        next = next + 1
      }
      if next < separator.length() && separator[next] == '\n' {
        return true
      }
    }
  }
  false
}

///|
fn ordered_list_marker_seed(
  source : String,
  node : ProjNode[@markdown.Block],
  source_map : SourceMap,
) -> String? {
  match ordered_list_marker_parts(source, node, source_map) {
    Some((seed, _)) => Some(seed)
    None => None
  }
}

///|
fn ordered_list_marker_parts(
  source : String,
  node : ProjNode[@markdown.Block],
  source_map : SourceMap,
) -> (String, Int)? {
  let range = match source_map.get_range(node.id()) {
    Some(r) => r
    None => return None
  }
  let mut marker_start = range.start
  while marker_start < range.end &&
        (source[marker_start] == ' ' || source[marker_start] == '\t') {
    marker_start = marker_start + 1
  }
  let mut delimiter = marker_start
  while delimiter < range.end && source[delimiter] is ('0'..='9') {
    delimiter = delimiter + 1
  }
  if delimiter == marker_start || delimiter >= range.end {
    return None
  }
  guard source[delimiter] is ('.' | ')') else { return None }
  let mut content_start = delimiter + 1
  while content_start < range.end &&
        (source[content_start] == ' ' || source[content_start] == '\t') {
    content_start = content_start + 1
  }
  let value = @string.parse_int(source[marker_start:delimiter], base=10) catch {
    _ => return None
  }
  Some(
    (
      source[range.start:marker_start].to_owned() +
      (value - 1).to_string() +
      source[delimiter:content_start].to_owned(),
      content_start,
    ),
  )
}

///|
fn ordered_marker_for_content(marker : String, content : String) -> String {
  guard content.length() > 0 && content[0] != '\n' else { return marker }
  if marker.length() > 0 && marker[marker.length() - 1] is (' ' | '\t') {
    marker
  } else {
    marker + " "
  }
}

///|
fn ordered_list_item_content(
  source : String,
  node : ProjNode[@markdown.Block],
  source_map : SourceMap,
  marker : String,
) -> Result[String, String] {
  let range = match source_map.get_range(node.id()) {
    Some(r) => r
    None => return Err("ordered list item not in source map")
  }
  let content_start = match
    ordered_list_marker_parts(source, node, source_map) {
    Some((_, start)) => start
    None => return Err("ordered list item marker is not parseable")
  }
  let end = block_text_end_without_trailing_newlines(
    source,
    range.start,
    range.end,
  )
  let content = source[content_start:end].to_owned()
  let marker = ordered_marker_for_content(marker, content)
  Ok(
    reindent_ordered_item_continuations(
      content,
      old_marker_width=content_start - range.start,
      new_marker_width=marker.length(),
    ),
  )
}

///|
fn reindent_ordered_item_continuations(
  content : String,
  old_marker_width~ : Int,
  new_marker_width~ : Int,
) -> String {
  if old_marker_width == new_marker_width || !content.contains("\n") {
    return content
  }
  let buffer = StringBuilder::new()
  let mut line_start = 0
  let mut idx = 0
  while idx < content.length() {
    if content[idx] == '\n' {
      buffer.write_string(content[line_start:idx + 1].to_owned())
      line_start = idx + 1
      let indent_end = leading_spaces_end(content, line_start)
      let indent_width = indent_end - line_start
      if indent_width >= old_marker_width {
        buffer.write_string(
          String::make(new_marker_width + indent_width - old_marker_width, ' '),
        )
        line_start = indent_end
      }
    }
    idx = idx + 1
  }
  buffer.write_string(content[line_start:].to_owned())
  buffer.to_string()
}

///|
fn leading_spaces_end(source : String, start : Int) -> Int {
  let mut end = start
  while end < source.length() && source[end] == ' ' {
    end = end + 1
  }
  end
}

///|
fn block_text_without_trailing_newlines(
  source : String,
  node : ProjNode[@markdown.Block],
  source_map : SourceMap,
) -> Result[String, String] {
  let range = match source_map.get_range(node.id()) {
    Some(r) => r
    None => return Err("node not in source map")
  }
  let end = block_text_end_without_trailing_newlines(
    source,
    range.start,
    range.end,
  )
  Ok(source[range.start:end].to_owned())
}

///|
fn block_text_end_without_trailing_newlines(
  source : String,
  start : Int,
  end : Int,
) -> Int {
  let mut current_end = end
  while current_end > start && source[current_end - 1] == '\n' {
    current_end = current_end - 1
  }
  current_end
}

///|
fn validate_no_unclosed_code_before_sibling(
  nodes : Array[ProjNode[@markdown.Block]],
  source_map : SourceMap,
) -> Result[Unit, String] {
  for idx in 0..<(nodes.length() - 1) {
    if is_unclosed_fenced_code(nodes[idx], source_map) {
      return Err(
        "markdown block move does not support unclosed fenced code before another block",
      )
    }
  }
  Ok(())
}

///|
fn is_unclosed_fenced_code(
  node : ProjNode[@markdown.Block],
  source_map : SourceMap,
) -> Bool {
  node.kind is CodeBlock(_, _) &&
  source_map.get_token_span(node.id(), "fence_open") is Some(_) &&
  source_map.get_token_span(node.id(), "fence_close") is None
}

///|
fn separator_between_nodes(
  source : String,
  siblings : Array[ProjNode[@markdown.Block]],
  left : ProjNode[@markdown.Block],
  right : ProjNode[@markdown.Block],
  source_map : SourceMap,
) -> Result[String, String] {
  match original_adjacent_separator(source, siblings, left, right, source_map) {
    Some(Ok(separator)) => Ok(separator)
    Some(Err(msg)) => Err(msg)
    None => Ok(separator_between(left.kind, right.kind))
  }
}

///|
fn original_adjacent_separator(
  source : String,
  siblings : Array[ProjNode[@markdown.Block]],
  left : ProjNode[@markdown.Block],
  right : ProjNode[@markdown.Block],
  source_map : SourceMap,
) -> Result[String, String]? {
  for idx in 0..<(siblings.length() - 1) {
    if siblings[idx].id() == left.id() && siblings[idx + 1].id() == right.id() {
      let left_range = match source_map.get_range(left.id()) {
        Some(r) => r
        None => return Some(Err("left sibling not in source map"))
      }
      let right_range = match source_map.get_range(right.id()) {
        Some(r) => r
        None => return Some(Err("right sibling not in source map"))
      }
      let left_end = block_text_end_without_trailing_newlines(
        source,
        left_range.start,
        left_range.end,
      )
      return Some(Ok(source[left_end:right_range.start].to_owned()))
    }
  }
  None
}

///|
fn separator_between(left : @markdown.Block, right : @markdown.Block) -> String {
  match (left, right) {
    (UnorderedListItem(_), UnorderedListItem(_))
    | (OrderedListItem(_, _), OrderedListItem(_, _)) => "\n"
    (Paragraph(_), Paragraph(_))
    | (UnorderedList(_), _)
    | (OrderedList(_, _), _) => "\n\n"
    _ =>
      // Default root siblings (heading/code/paragraph before non-paragraph)
      // use a single newline unless an original adjacent separator is reused.
      "\n"
  }
}
