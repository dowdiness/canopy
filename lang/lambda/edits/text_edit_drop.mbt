///|
fn compute_drop(
  ctx : EditContext[@ast.Term],
  source : NodeId,
  target : NodeId,
  position : DropPosition,
) -> EditResult raise EditError {
  // Legality: self-drop
  guard source != target else {
    raise InvalidTarget(detail="Cannot drop onto self")
  }
  let { source_text, .. } = ctx
  let (source_node, source_range) = ctx.resolve(source)
  let (target_node, target_range) = ctx.resolve(target)
  ensure_replaceable_node_range(ctx, source, source_node, source_range)
  ensure_replaceable_node_range(ctx, target, target_node, target_range)
  // Legality: descendant-drop (target is inside source)
  guard !(target_range.start >= source_range.start &&
    target_range.end <= source_range.end) else {
    raise InvalidTarget(detail="Cannot drop into own descendant")
  }
  let is_let_def_drop = source_node.kind is @ast.Term::LetDef(_, _) &&
    target_node.kind is @ast.Term::LetDef(_, _)
  let (delete_start, delete_len, insert_pos, inserted) = if is_let_def_drop {
    let source_row = source_text[source_range.start:source_range.end].to_owned()
    let (delete_start, delete_len) = binding_delete_range(
      source_text,
      source_range.start,
      source_range.end,
    )
    let (insert_pos, inserted) = match position {
      Before => (target_range.start, source_row + "\n")
      // Dropping "inside" a let row means move the whole row after it; the
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
  Some(
    (
      [
        { start: delete_start, delete_len, inserted: "" },
        { start: insert_pos, delete_len: 0, inserted },
      ],
      RestoreCursor,
    ),
  )
}
