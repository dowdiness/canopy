///|
fn scope_test_registry(
  root : ProjNode[@ast.Term],
) -> Map[NodeId, ProjNode[@ast.Term]] {
  let registry : Map[NodeId, ProjNode[@ast.Term]] = {}
  fn register(node : ProjNode[@ast.Term]) {
    registry[node.id()] = node
    for child in node.children {
      register(child)
    }
  }
  register(root)
  registry
}

// The `module_def_references` edits-local wrapper was removed when inline/binding
// ops were taught block-local scopes (docs/TODO.md §20): references are now read
// directly via `@scope.references(g, decl.id)`, whose identity-based,
// shadowing-correct behavior is owned and tested by the `@scope` package.

///|
test "find_binding_for_init: maps init ProjNode to binding NodeId" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let fp = ModuleProjection::from_proj_node(proj)
  // First def's init is the LetDef node's child.
  let init_id = proj.children[0].children[0].id()
  match find_binding_for_init(init_id, fp) {
    Some((binding_id, def_index)) => {
      inspect(binding_id == fp.defs[0].3, content="true")
      inspect(def_index, content="0")
    }
    None => fail("expected Some")
  }
  match find_binding_for_init(proj.children[0].id(), fp) {
    Some((binding_id, def_index)) => {
      inspect(binding_id == fp.defs[0].3, content="true")
      inspect(def_index, content="0")
    }
    None => fail("expected Some for LetDef id")
  }
}

///|
test "find_binding_for_init: returns None for non-init node" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let fp = ModuleProjection::from_proj_node(proj)
  // Body node is not an init expression
  let body = proj.children.last().unwrap()
  inspect(find_binding_for_init(body.id(), fp) is None, content="true")
}

///|
test "find_binding_for_init: duplicate defs return matching binding order" {
  let text = "let x = 0\nlet x = x\nx"
  let (proj, _) = parse_to_proj_node(text)
  let fp = ModuleProjection::from_proj_node(proj)
  match find_binding_for_init(fp.defs[0].1.id(), fp) {
    Some((binding_id, def_index)) => {
      inspect(binding_id == fp.defs[0].3, content="true")
      inspect(def_index, content="0")
    }
    None => fail("expected first duplicate binding")
  }
  match find_binding_for_init(fp.defs[1].1.id(), fp) {
    Some((binding_id, def_index)) => {
      inspect(binding_id == fp.defs[1].3, content="true")
      inspect(def_index, content="1")
    }
    None => fail("expected second duplicate binding")
  }
}
