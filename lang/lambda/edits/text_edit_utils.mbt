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
/// Resolve a binding (LetDef) node id to its scope-graph `ModuleDef`
/// declaration, block-locally. Unlike a root-relative `module_projection.defs`
/// scan, this matches the binder's structural node id against every decl in the
/// graph, so a block-local binder resolves to its own scope's declaration.
/// Mirrors #645's `rename_binding_by_id`.
fn decl_for_binding_node(
  g : @scope.ScopeGraph,
  binding_node_id : NodeId,
) -> @scope.Decl? {
  g.decls
  .iter()
  .find_first(fn(d) {
    d.node_id == binding_node_id && d.kind is @scope.DeclKind::ModuleDef(_)
  })
}

///|
/// Synthesize the `(name, init, start, letdef_id)` def-view tuple consumed by the
/// binding text helpers from a `ModuleDef` declaration's LetDef projection node.
/// Uniform for root and nested decls — `decl.node_id` is always the LetDef node,
/// whose first child is the init expression, mirroring
/// `ModuleProjection::from_proj_node`'s unconditional `children[0]` extraction.
/// Returns `Err` if that child is absent (rather than aborting like the indexing
/// in `from_proj_node`). The start comes from the LetDef node's source range (the
/// binding span's start).
fn def_view_from_decl(
  registry : Map[NodeId, ProjNode[@ast.Term]],
  source_map : SourceMap,
  decl : @scope.Decl,
) -> Result[(String, ProjNode[@ast.Term], Int, NodeId), String] {
  guard registry.get(decl.node_id) is Some(letdef) else {
    return Err("Binding node not in registry: " + decl.node_id.to_string())
  }
  guard source_map.get_range(decl.node_id) is Some(r) else {
    return Err("Binding node not in source map: " + decl.node_id.to_string())
  }
  guard letdef.children.get(0) is Some(init) else {
    return Err("Binding node has no init child: " + decl.node_id.to_string())
  }
  Ok((decl.name, init, r.start, decl.node_id))
}

///|
/// Resolve a binding node to the scope graph, its block-local `ModuleDef`
/// declaration, and the synthesized `(name, init, start, letdef_id)` def-view —
/// the shared preamble of every binding op (delete/duplicate/move/inline-all).
/// Block-local via `decl_for_binding_node`, so a nested binder resolves to its
/// own scope's declaration rather than a root def at the same index.
fn def_for_binding(
  ctx : EditContext[@ast.Term],
  binding_node_id : NodeId,
) -> Result[
  (@scope.ScopeGraph, @scope.Decl, (String, ProjNode[@ast.Term], Int, NodeId)),
  String,
] {
  let { source_map, registry, module_projection, .. } = ctx
  let g = @scope.build(module_projection, registry, source_map)
  guard decl_for_binding_node(g, binding_node_id) is Some(decl) else {
    return Err("Binding not found: " + binding_node_id.to_string())
  }
  match def_view_from_decl(registry, source_map, decl) {
    Ok(def) => Ok((g, decl, def))
    Err(e) => Err(e)
  }
}

///|
/// The same-scope sibling declaration at scope-relative offset `offset` from
/// `decl` (e.g. -1 = previous binding, +1 = next), or None at the boundary.
/// Keyed on `decl.scope` + scope-relative `def_index`, so move-up/down swap the
/// correct neighbour within a nested block — never a root def at the same index.
fn sibling_def_decl(
  g : @scope.ScopeGraph,
  decl : @scope.Decl,
  offset : Int,
) -> @scope.Decl? {
  guard decl.kind is @scope.DeclKind::ModuleDef(def_index~) else { return None }
  let target = def_index + offset
  g.decls
  .iter()
  .find_first(fn(d) {
    d.scope == decl.scope &&
    (match d.kind {
      @scope.DeclKind::ModuleDef(def_index=i) => i == target
      _ => false
    })
  })
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
