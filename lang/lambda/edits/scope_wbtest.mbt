///|
fn scope_test_registry(
  root : ProjNode[@ast.Term],
) -> Map[NodeId, ProjNode[@ast.Term]] {
  let registry : Map[NodeId, ProjNode[@ast.Term]] = Map([])
  @core.collect_registry(root, registry)
  registry
}

///|
fn module_def_references_for_test(
  g : @scope.ScopeGraph,
  def_index : Int,
) -> Result[Array[NodeId], String] {
  for decl in g.decls {
    match decl.kind {
      @scope.DeclKind::ModuleDef(def_index=i) if i == def_index =>
        return Ok(@scope.references(g, decl.id))
      _ => ()
    }
  }
  Err("No scope declaration for module def index " + def_index.to_string())
}

///|
fn def_cutoff_at_node_for_test(
  definition_index : DefinitionIndex,
  source_map : SourceMap,
  node_id : NodeId,
) -> Int {
  definition_index.cutoff_at_node(source_map, node_id)
}

///|
test "module_def_references: finds Var references in Module body" {
  let text = "let x = 0\nx + x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(registry, source_map)
  match module_def_references_for_test(g, 0) {
    Ok(refs) => inspect(refs.length(), content="2")
    Err(e) => fail(e)
  }
}

///|
test "module_def_references: respects shadowing by inner Lam" {
  let text = "let x = 0\n(x) => x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(registry, source_map)
  match module_def_references_for_test(g, 0) {
    Ok(refs) => inspect(refs.length(), content="0")
    Err(e) => fail(e)
  }
}

///|
test "module_def_references: later duplicate shadows body only" {
  let text = "let x = 0\nlet x = x\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(registry, source_map)
  match
    (module_def_references_for_test(g, 0), module_def_references_for_test(g, 1)) {
    (Ok(first_refs), Ok(second_refs)) => {
      // The first def is referenced by the second def's init; the body resolves
      // to the second def. This is the identity-based case the old name scan
      // could not distinguish when callers started at def_index + 1.
      inspect(first_refs.length(), content="1")
      inspect(second_refs.length(), content="1")
    }
    (Err(e), _) | (_, Err(e)) => fail(e)
  }
}

///|
test "def_cutoff_at_node: duplicate defs use init-range cutoff" {
  let text = "let x = 0\nlet x = x\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let body = proj.children.last().unwrap()
  let index = DefinitionIndex::from_proj_node(proj)
  inspect(
    def_cutoff_at_node_for_test(
      index,
      source_map,
      proj.children[0].children[0].id(),
    ),
    content="0",
  )
  inspect(
    def_cutoff_at_node_for_test(
      index,
      source_map,
      proj.children[1].children[0].id(),
    ),
    content="1",
  )
  inspect(
    def_cutoff_at_node_for_test(index, source_map, body.id()),
    content="2",
  )
  inspect(
    def_cutoff_at_node_for_test(index, source_map, NodeId::from_int(999_999)),
    content="2",
  )
}
