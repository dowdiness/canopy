///|
/// Return a placeholder Term for a given Term kind (for Delete replacement).
fn placeholder_term_for_kind(kind : @ast.Term) -> @ast.Term {
  match kind {
    @ast.Term::Int(_) => @ast.Term::Int(0)
    @ast.Term::Var(_) => @ast.Term::Var("a")
    @ast.Term::Lam(_, _) => @ast.Term::Lam("x", @ast.Term::Var("x"))
    @ast.Term::App(_, _) =>
      @ast.Term::App(@ast.Term::Var("f"), @ast.Term::Var("x"))
    @ast.Term::Bop(_, _, _) =>
      @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Int(0), @ast.Term::Int(0))
    @ast.Term::If(_, _, _) =>
      @ast.Term::If(@ast.Term::Int(0), @ast.Term::Int(0), @ast.Term::Int(0))
    @ast.Term::Hole(_) => @ast.Term::Hole(0)
    _ => @ast.Term::Var("a")
  }
}

///|
fn range_contains_arrow(source_text : String, range : @loomcore.Range) -> Bool {
  let mut found = false
  for pos = range.start; pos + 1 < range.end; pos = pos + 1 {
    if source_text[pos] == '=' && source_text[pos + 1] == '>' {
      found = true
      break
    }
  }
  found
}

///|
fn is_space_code(code : UInt16) -> Bool {
  code == ' ' || code == '\n' || code == '\t' || code == '\r'
}

///|
fn first_non_space_in_range(
  source_text : String,
  range : @loomcore.Range,
) -> Int? {
  for pos = range.start; pos < range.end; pos = pos + 1 {
    if !is_space_code(source_text[pos]) {
      return Some(pos)
    }
  }
  None
}

///|
fn is_source_arrow_lambda_range(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  range : @loomcore.Range,
) -> Bool {
  let _ = node_id
  match first_non_space_in_range(ctx.source_text, range) {
    Some(start) =>
      start < ctx.source_text.length() &&
      ctx.source_text[start] == '(' &&
      range_contains_arrow(ctx.source_text, range)
    None => false
  }
}

///|
fn ensure_replaceable_node_range(
  ctx : EditContext[@ast.Term],
  node_id : NodeId,
  node : ProjNode[@ast.Term],
  range : @loomcore.Range,
) -> Unit raise EditError {
  match node.kind {
    @ast.Term::Lam(_, _) => {
      guard is_source_arrow_lambda_range(ctx, node_id, range) else {
        raise UnsupportedOperation(
          detail="Cannot edit synthetic lambda parameter directly; edit the enclosing expression or function body",
        )
      }
    }
    _ => ()
  }
}

///|
/// Compute (start, length) for deleting a binding line, consuming
/// the adjacent newline if present (trailing preferred, else leading).
fn binding_delete_range(
  source_text : String,
  let_start : Int,
  binding_end : Int,
) -> (Int, Int) {
  if binding_end < source_text.length() && source_text[binding_end] == '\n' {
    (let_start, binding_end - let_start + 1)
  } else if let_start > 0 && source_text[let_start - 1] == '\n' {
    (let_start - 1, binding_end - let_start + 1)
  } else {
    (let_start, binding_end - let_start)
  }
}

///|
/// Find the parent of a node by scanning the registry.
/// Returns (parent_id, parent_node, child_index) or None for root nodes.
fn find_parent(
  registry : Map[NodeId, ProjNode[@ast.Term]],
  node_id : NodeId,
) -> (NodeId, ProjNode[@ast.Term], Int)? {
  for pid, pnode in registry {
    for i, child in pnode.children {
      if child.id() == node_id {
        return Some((pid, pnode, i))
      }
    }
  }
  None
}

///|
/// Get the text range of a binding line: from the stored definition start to
/// the end of the binding syntax. The stored start is syntax-derived, so it
/// covers both `let` and `fn` bindings without keyword-specific scanning.
/// Returns (binding_start, binding_end).
fn get_binding_text_range(
  source_text : String,
  source_map : SourceMap,
  def : EditModuleBinding,
) -> (Int, Int) raise EditError {
  let init_node = def.init
  guard source_map.get_range(init_node.id()) is Some(init_range) else {
    raise NodeNotInSourceMap(
      action="Get binding text range",
      node_id=init_node.id(),
    )
  }
  let binding_end = match source_map.get_range(def.binding_id) {
    Some(binding_range) => binding_range.end
    None =>
      raise NodeNotInSourceMap(
        action="Get binding text range",
        node_id=def.binding_id,
      )
  }
  guard !(def.start < 0 ||
    def.start > source_text.length() ||
    def.start > binding_end) else {
    raise Invariant(detail="Binding start out of source range")
  }
  (def.start, binding_end)
}
