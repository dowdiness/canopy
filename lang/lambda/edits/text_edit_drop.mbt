///|
fn compute_drop(
  ctx : EditContext[@ast.Term],
  source : NodeId,
  target : NodeId,
  position : DropPosition,
) -> EditResult {
  // Legality: self-drop
  guard source != target else { return Err("Cannot drop onto self") }
  let { source_text, source_map, .. } = ctx
  guard source_map.get_range(source) is Some(source_range) else {
    return Err("Source node not found")
  }
  guard source_map.get_range(target) is Some(target_range) else {
    return Err("Target node not found")
  }
  // Legality: descendant-drop (target is inside source)
  guard !(target_range.start >= source_range.start &&
    target_range.end <= source_range.end) else {
    return Err("Cannot drop into own descendant")
  }
  let source_slice = source_text[source_range.start:source_range.end].to_owned()
  let insert_pos = match position {
    Before => target_range.start
    After => target_range.end
    Inside => target_range.start
  }
  Ok(
    Some(
      (
        [
          {
            start: source_range.start,
            delete_len: source_range.end - source_range.start,
            inserted: "",
          },
          { start: insert_pos, delete_len: 0, inserted: source_slice },
        ],
        RestoreCursor,
      ),
    ),
  )
}
