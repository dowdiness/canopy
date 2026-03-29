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
    _ => @ast.Term::Var("a")
  }
}

///|
/// Find the start position of the "let " keyword by scanning backwards
/// from a known position in the source text.
fn find_let_start(source_text : String, from : Int) -> Int {
  let mut pos = from
  while pos > 0 {
    pos = pos - 1
    if pos + 3 < source_text.length() &&
      source_text[pos] == 'l' &&
      source_text[pos + 1] == 'e' &&
      source_text[pos + 2] == 't' &&
      source_text[pos + 3] == ' ' {
      return pos
    }
  }
  pos
}

///|
/// Find a module binding's index in flat_proj.defs by its NodeId.
fn find_def_index(
  flat_proj : FlatProj,
  binding_node_id : NodeId,
) -> Result[Int, String] {
  for i, def in flat_proj.defs {
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
      if NodeId::from_int(child.node_id) == node_id {
        return Some((pid, pnode, i))
      }
    }
  }
  None
}

///|
/// Get the text range of a binding line: from "let " to end of init expression.
/// Returns (let_start, init_end).
fn get_binding_text_range(
  source_text : String,
  source_map : SourceMap,
  def : (String, ProjNode[@ast.Term], Int, NodeId),
) -> Result[(Int, Int), String] {
  let init_node = def.1
  let init_range = match source_map.get_range(init_node.id()) {
    Some(r) => r
    None => return Err("Init node not in source map")
  }
  let let_start = find_let_start(source_text, init_range.start)
  Ok((let_start, init_range.end))
}
