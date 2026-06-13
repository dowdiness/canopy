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
) -> Result[Unit, String] {
  match node.kind {
    @ast.Term::Lam(_, _) =>
      if is_source_arrow_lambda_range(ctx, node_id, range) {
        Ok(())
      } else {
        Err(
          "Cannot edit synthetic lambda parameter directly; edit the enclosing expression or function body",
        )
      }
    _ => Ok(())
  }
}

///|
fn binding_starts_with_fn(source_text : String, start : Int) -> Bool {
  start + 2 <= source_text.length() &&
  source_text[start] == 'f' &&
  source_text[start + 1] == 'n' &&
  (
    start + 2 == source_text.length() ||
    !is_identifier_code(source_text[start + 2])
  )
}

///|
/// Find a module binding's index in module_projection.defs by its NodeId.
fn find_def_index(
  module_projection : ModuleProjection,
  binding_node_id : NodeId,
) -> Result[Int, String] {
  for i, def in module_projection.defs {
    if def.3 == binding_node_id {
      return Ok(i)
    }
  }
  Err("Binding not found: " + binding_node_id.to_string())
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
  def : (String, ProjNode[@ast.Term], Int, NodeId),
) -> Result[(Int, Int), String] {
  let init_node = def.1
  guard source_map.get_range(init_node.id()) is Some(init_range) else {
    return Err("Init node not in source map")
  }
  let binding_end = match source_map.get_range(def.3) {
    Some(binding_range) => binding_range.end
    None => init_range.end
  }
  if def.2 < 0 || def.2 > source_text.length() || def.2 > binding_end {
    return Err("Binding start out of source range")
  }
  Ok((def.2, binding_end))
}

///|
fn binding_name_range(
  source_text : String,
  source_map : SourceMap,
  def : (String, ProjNode[@ast.Term], Int, NodeId),
  binding_start : Int,
  binding_end : Int,
) -> Result[(Int, Int), String] {
  match source_map.get_token_span(def.3, @lambda_proj.LET_DEF_NAME_ROLE) {
    Some(r) => Ok((r.start, r.end))
    None =>
      tight_name_range(
        source_text,
        @loomcore.Range::new(binding_start, binding_end),
        def.0,
      )
  }
}

///|
fn renamed_binding_text(
  source_text : String,
  source_map : SourceMap,
  def : (String, ProjNode[@ast.Term], Int, NodeId),
  binding_start : Int,
  binding_end : Int,
  new_name : String,
) -> Result[String, String] {
  let (name_start, name_end) = match
    binding_name_range(source_text, source_map, def, binding_start, binding_end) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  Ok(
    source_text[binding_start:name_start].to_owned() +
    new_name +
    source_text[name_end:binding_end].to_owned(),
  )
}

///|
fn trimmed_source_text(source_text : String, range : @loomcore.Range) -> String {
  let start = match first_non_space_in_range(source_text, range) {
    Some(pos) => pos
    None => range.start
  }
  // Mutable end walks backward over trivia without allocating an intermediate slice.
  let mut end = range.end
  // Stateful backward scan is bounded to the source range and stops at content.
  while end > start && is_space_code(source_text[end - 1]) {
    end = end - 1
  }
  source_text[start:end].to_owned()
}

///|
fn binding_inline_text(
  source_text : String,
  source_map : SourceMap,
  def : (String, ProjNode[@ast.Term], Int, NodeId),
) -> Result[String, String] {
  if binding_starts_with_fn(source_text, def.2) {
    Err("Cannot inline fn binding while preserving parameter annotations")
  } else {
    match source_map.get_range(def.1.id()) {
      Some(r) => Ok(trimmed_source_text(source_text, r))
      None => Ok(@ast.print_term(def.1.kind))
    }
  }
}
