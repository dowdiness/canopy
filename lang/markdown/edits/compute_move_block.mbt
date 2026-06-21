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
  let source_siblings = proj.children
  let source_idx = match
    root_sibling_index_or_error(proj, source_siblings, source_id, "source") {
    Ok(idx) => idx
    Err(msg) => return Err(msg)
  }
  let target_idx = match
    root_sibling_index_or_error(proj, source_siblings, target_id, "target") {
    Ok(idx) => idx
    Err(msg) => return Err(msg)
  }
  match position {
    Before if source_idx + 1 == target_idx => return Ok(None)
    After if target_idx + 1 == source_idx => return Ok(None)
    _ => ()
  }
  let source_kind = source_siblings[source_idx].kind
  // Current Loom Markdown folds ordered and unordered list containers into
  // UnorderedList. When explicit ordered-list payloads land, keep every list
  // container source rejected here until #724 widens MoveBlock legality with
  // list-item scope, identity, and marker-renumbering tests.
  if source_kind is @markdown.Block::UnorderedList(_) {
    return Err(list_payload_blocker("list container sources"))
  }
  if source_siblings.any(sibling => {
      sibling.id() != source_id && sibling.kind == source_kind
    }) {
    return Err("markdown block move requires a unique source block payload")
  }
  let (replace_start, replace_end, inserted) = match
    compute_root_move_source(
      source, source_siblings, source_idx, target_idx, position, source_map,
    ) {
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
fn root_sibling_index_or_error(
  proj : ProjNode[@markdown.Block],
  root_siblings : Array[ProjNode[@markdown.Block]],
  node_id : NodeId,
  role : String,
) -> Result[Int, String] {
  match root_siblings.search_by(sibling => sibling.id() == node_id) {
    Some(idx) => Ok(idx)
    None => {
      let (nested_siblings, nested_idx) = find_sibling_context(proj, node_id)
      if nested_idx >= 0 {
        if nested_siblings[nested_idx].kind is @markdown.Block::ListItem(_) {
          return Err(list_payload_blocker("list-item " + role + "s"))
        }
        return Err(
          "markdown block move currently supports root-level blocks only",
        )
      }
      Err(role + " node not found in projection tree: " + node_id.to_string())
    }
  }
}

///|
fn list_payload_blocker(blocked : String) -> String {
  "markdown block move currently rejects " +
  blocked +
  " until issue #724 is unblocked by explicit ordered/unordered list payloads; see docs/plans/2026-06-20-markdown-list-payloads.md"
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
  let without_source = [
    for idx, sibling in siblings if idx != source_idx => sibling
  ]
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
  // Builder: construct the reordered root-block list once for rendering the
  // replacement span.
  let reordered : Array[ProjNode[@markdown.Block]] = []
  for idx in 0..<=without_source.length() {
    if idx == insert_idx {
      reordered.push(siblings[source_idx])
    } else {
      let without_source_idx = if idx < insert_idx { idx } else { idx - 1 }
      match without_source.get(without_source_idx) {
        Some(node) => reordered.push(node)
        None => ()
      }
    }
  }
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
  for current_end = end {
    if current_end > start && source[current_end - 1] == '\n' {
      continue current_end - 1
    }
    break current_end
  }
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
    (Paragraph(_), Paragraph(_)) | (UnorderedList(_), _) => "\n\n"
    _ =>
      // Default root siblings (heading/code/paragraph before non-paragraph)
      // use a single newline unless an original adjacent separator is reused.
      "\n"
  }
}
