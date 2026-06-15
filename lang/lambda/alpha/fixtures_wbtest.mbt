///|
fn test_binder(id : Int, hint : String) -> Binder {
  { id: BinderId(id), hint, origin: Generated(id) }
}

///|
fn test_free(name : String, origin : FreeOrigin) -> FreeName {
  { name, origin }
}

///|
fn free_var(name : String) -> AlphaTerm {
  Var(Free(test_free(name, SourceVar)))
}

///|
fn graph_for_root(root : @core.ProjNode[@ast.Term]) -> @scope.ScopeGraph {
  let source_map = @core.SourceMap::from_ast(root)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  @scope.build(registry, source_map)
}

///|
fn alpha_parse_fixture(
  text : String,
) -> (@core.ProjNode[@ast.Term], @scope.ScopeGraph) raise {
  let (proj, errors) = @lambda_proj.parse_to_proj_node(text)
  if errors.length() > 0 {
    fail("parse diagnostics in alpha fixture")
  }
  (proj, graph_for_root(proj))
}

///|
fn find_var_node(
  root : @core.ProjNode[@ast.Term],
  name : String,
) -> @core.NodeId? {
  if root.kind is @ast.Term::Var(found) && found == name {
    Some(root.id())
  } else {
    let mut result : @core.NodeId? = None
    for child in root.children {
      if result is None {
        result = find_var_node(child, name)
      }
    }
    result
  }
}
