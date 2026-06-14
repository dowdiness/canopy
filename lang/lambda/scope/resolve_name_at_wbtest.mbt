// Tests for the hypothetical-position resolvers `resolve_name_at` and
// `resolve_at_module_root_end` (the model the edits/ capture analysis reuses
// instead of a single root-relative cutoff). The fixture has a root `a` AND a
// block-local `a`, so a single root cutoff would mis-resolve the nested case.

///|
/// `let a = 99\nlet r = { let a = 1\n  let b = a\n  b }`
/// proj.children = [LetDef(a), LetDef(r), body]; r.children[0] = block;
/// block.children = [LetDef(a), LetDef(b), body Var(b)].
fn resolve_fixture() -> (
  ScopeGraph,
  @core.NodeId, // root LetDef(a) id
  @core.NodeId, // block LetDef(a) id
  @core.ProjNode[@ast.Term], // proj root (for find_var_node)
) raise {
  let text = "let a = 99\nlet r = { let a = 1\n  let b = a\n  b }"
  let (proj, module_projection, registry, source_map) = build_fixture(text)
  let g = build(module_projection, registry, source_map)
  let root_a = proj.children[0].id()
  let block = proj.children[1].children[0]
  let block_a = block.children[0].id()
  (g, root_a, block_a, proj)
}

///|
test "resolve_name_at: block body resolves a free name to the BLOCK-LOCAL binder" {
  let (g, root_a, block_a, proj) = resolve_fixture()
  // The block body `b` sees the block's own `a` (block-index 0), so `a` resolved
  // AT that position must be the block-local binder, not the root `a`.
  let body_b = find_var_node(proj, "b")
  guard resolve_name_at(g, body_b, "a") is Some(decl)
  inspect(decl.name, content="a")
  inspect(decl.node_id == block_a, content="true")
  inspect(decl.node_id == root_a, content="false")
}

///|
test "resolve_name_at: the root module node is a total query (None, not abort)" {
  let (g, _root_a, _block_a, _proj) = resolve_fixture()
  // The container module node is not a resolution site; resolving any name there
  // must return None rather than aborting on a missing root-scope cutoff.
  inspect(resolve_name_at(g, g.module_node_id, "a") is None, content="true")
  inspect(resolve_name_at(g, g.module_node_id, "nope") is None, content="true")
}

///|
test "resolve_at_module_root_end: resolves to the ROOT binder, not a block-local one" {
  let (g, root_a, block_a, _proj) = resolve_fixture()
  // At module end every ROOT def is visible; the block-local `a` is not in scope.
  guard resolve_at_module_root_end(g, "a") is Some(decl)
  inspect(decl.node_id == root_a, content="true")
  inspect(decl.node_id == block_a, content="false")
  // A block-only name is unbound at module end (so extract sees it would rebind).
  inspect(resolve_at_module_root_end(g, "b") is None, content="true")
}
