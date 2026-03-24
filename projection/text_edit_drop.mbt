///|
fn compute_drop(
  ctx : EditContext[@ast.Term],
  source : NodeId,
  target : NodeId,
  position : DropPosition,
) -> EditResult {
  let { source_text, source_map, .. } = ctx
  let source_range = match source_map.get_range(source) {
    Some(r) => r
    None => return Err("Source node not found")
  }
  let target_range = match source_map.get_range(target) {
    Some(r) => r
    None => return Err("Target node not found")
  }
  let source_slice = source_text[source_range.start:source_range.end].to_string()
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
