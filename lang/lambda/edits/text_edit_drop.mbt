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
  let is_let_def_drop = match
    (ctx.registry.get(source), ctx.registry.get(target)) {
    (Some(source_node), Some(target_node)) =>
      source_node.kind is @ast.Term::LetDef(_, _) &&
      target_node.kind is @ast.Term::LetDef(_, _)
    _ => false
  }
  let (delete_start, delete_len, insert_pos, inserted) = if is_let_def_drop {
    let source_row = source_text[source_range.start:source_range.end].to_owned()
    let (delete_start, delete_len) = binding_delete_range(
      source_text,
      source_range.start,
      source_range.end,
    )
    let (insert_pos, inserted) = match position {
      Before => (target_range.start, source_row + "\n")
      // Dropping “inside” a let row means move the whole row after it; the
      // initializer is a child, not the row's drop target.
      After | Inside => (target_range.end, "\n" + source_row)
    }
    (delete_start, delete_len, insert_pos, inserted)
  } else {
    let source_slice = source_text[source_range.start:source_range.end].to_owned()
    let insert_pos = match position {
      Before => target_range.start
      After => target_range.end
      Inside => target_range.start
    }
    (
      source_range.start,
      source_range.end - source_range.start,
      insert_pos,
      source_slice,
    )
  }
  Ok(
    Some(
      (
        [
          { start: delete_start, delete_len, inserted: "" },
          { start: insert_pos, delete_len: 0, inserted },
        ],
        RestoreCursor,
      ),
    ),
  )
}
