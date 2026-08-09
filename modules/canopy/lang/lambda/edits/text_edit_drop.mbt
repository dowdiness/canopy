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
  let source_is_let_def = source_node.kind is @ast.Term::LetDef(_, _)
  let target_is_let_def = target_node.kind is @ast.Term::LetDef(_, _)
  let is_let_def_drop = source_is_let_def && target_is_let_def
  guard source_is_let_def == target_is_let_def else {
    raise UnsupportedOperation(
      detail="Drop requires source and target to have matching node kinds",
    )
  }
  // Validate scope before the no-op fast path: nested and cross-scope rows
  // remain rejected even when their requested position is already adjacent.
  if is_let_def_drop {
    ensure_let_def_drop_scope(ctx, source, target)
  }
  let is_noop_row_drop = match position {
    Before => is_row_immediately_after(source_text, source_range, target_range)
    After | Inside =>
      is_row_immediately_after(source_text, target_range, source_range)
  }
  // LetDef rows use newline-aware movement; expression pairs use compute_move.
  if is_let_def_drop && is_noop_row_drop {
    Some(([], RestoreCursor))
  } else if is_let_def_drop {
    ensure_let_def_drop_safety(ctx, source, target, position)
    let source_row = source_text[source_range.start:source_range.end].to_owned()
    let (delete_start, delete_len) = binding_delete_range(
      source_text,
      source_range.start,
      source_range.end,
      prefer_leading=source_range.start > target_range.end,
    )
    let (insert_pos, inserted) = match position {
      Before => (target_range.start, source_row + "\n")
      // Dropping "inside" a let row means move the whole row after it; the
      // initializer is a child, not the row's drop target.
      After | Inside => (target_range.end, "\n" + source_row)
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
  } else {
    let (edits, focus_hint) = @core.compute_move(
      source_text,
      source,
      source_range,
      target,
      target_range,
      position,
      @loomcore.Renderable::placeholder(source_node.kind),
      " ",
    )
    Some((edits, focus_hint))
  }
}

///|
fn is_row_immediately_after(
  source_text : String,
  previous_range : @loomcore.Range,
  next_range : @loomcore.Range,
) -> Bool {
  guard next_range.start > previous_range.end else { return false }
  let mut i = previous_range.end
  while i < next_range.start {
    guard is_space_code(source_text[i]) else { return false }
    i = i + 1
  }
  true
}

///|
/// LetDef rows may move only within the root binding scope.
fn ensure_let_def_drop_scope(
  ctx : EditContext[@ast.Term],
  source : NodeId,
  target : NodeId,
) -> Unit raise EditError {
  let g = @scope.build(ctx.registry, ctx.source_map)
  let source_decl = module_def_decl_for_binding(g, source)
  let target_decl = module_def_decl_for_binding(g, target)
  guard source_decl.scope == target_decl.scope else {
    raise InvalidTarget(detail="Cannot drop bindings across scopes")
  }
  guard root_scope_id(g) is Some(root_scope) else {
    raise InvalidTarget(detail="Cannot drop bindings outside root module")
  }
  guard source_decl.scope == root_scope else {
    raise InvalidTarget(detail="Cannot drop bindings outside root module")
  }
}

///|
/// Check every root binding crossed by a non-no-op row move.
fn ensure_let_def_drop_safety(
  ctx : EditContext[@ast.Term],
  source : NodeId,
  target : NodeId,
  position : DropPosition,
) -> Unit raise EditError {
  let g = @scope.build(ctx.registry, ctx.source_map)
  let source_decl = module_def_decl_for_binding(g, source)
  let target_decl = module_def_decl_for_binding(g, target)
  let source_index = match source_decl.kind {
    @scope.DeclKind::ModuleDef(def_index~) => def_index
    @scope.DeclKind::LamParam(_) =>
      raise InvalidTarget(detail="Expected module binding")
  }
  let target_index = match target_decl.kind {
    @scope.DeclKind::ModuleDef(def_index~) => def_index
    @scope.DeclKind::LamParam(_) =>
      raise InvalidTarget(detail="Expected module binding")
  }
  let source_def = edit_binding_for_decl(ctx, source_decl)
  let target_def = edit_binding_for_decl(ctx, target_decl)
  guard source_def.name != target_def.name else {
    raise InvalidTarget(detail="Cannot drop bindings with the same name")
  }
  let destination_index = match position {
    Before =>
      if source_index < target_index {
        target_index - 1
      } else {
        target_index
      }
    After | Inside =>
      if source_index < target_index {
        target_index
      } else {
        target_index + 1
      }
  }
  if destination_index < source_index {
    let mut i = source_index - 1
    while i >= destination_index {
      guard sibling_module_def_decl(g, source_decl.scope, i)
        is Some(crossed_decl) else {
        raise InvalidTarget(detail="Cannot resolve binding reorder")
      }
      let crossed_def = edit_binding_for_decl(ctx, crossed_decl)
      guard source_def.name != crossed_def.name else {
        raise InvalidTarget(detail="Cannot drop bindings with the same name")
      }
      check_swap_scoping(g, source_def, crossed_def, "drop", ctx.registry)
      i = i - 1
    }
  } else if destination_index > source_index {
    let mut i = source_index + 1
    while i <= destination_index {
      guard sibling_module_def_decl(g, source_decl.scope, i)
        is Some(crossed_decl) else {
        raise InvalidTarget(detail="Cannot resolve binding reorder")
      }
      let crossed_def = edit_binding_for_decl(ctx, crossed_decl)
      guard source_def.name != crossed_def.name else {
        raise InvalidTarget(detail="Cannot drop bindings with the same name")
      }
      check_swap_scoping(g, crossed_def, source_def, "drop", ctx.registry)
      i = i + 1
    }
  }
}
