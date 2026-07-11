///|
test "DefinitionIndex::binding_for_node: maps LetDef id to binding index" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let index = DefinitionIndex::from_proj_node(proj)
  let binding_node_id = proj.children[0].id()
  match index.binding_for_node(binding_node_id) {
    Some((binding_id, def_index)) => {
      inspect(binding_id == binding_node_id, content="true")
      inspect(def_index, content="0")
    }
    None => fail("expected first binding")
  }
}

///|
test "DefinitionIndex::binding_for_node: init id is not a binding id" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let index = DefinitionIndex::from_proj_node(proj)
  let init_id = proj.children[0].children[0].id()
  inspect(index.binding_for_node(init_id) is None, content="true")
}

///|
test "DefinitionIndex::binding_for_node: duplicate defs return binding order" {
  let text = "let x = 0\nlet x = x\nx"
  let (proj, _) = parse_to_proj_node(text)
  let index = DefinitionIndex::from_proj_node(proj)
  match index.binding_for_node(proj.children[0].id()) {
    Some((binding_id, def_index)) => {
      inspect(binding_id == proj.children[0].id(), content="true")
      inspect(def_index, content="0")
    }
    None => fail("expected first duplicate binding")
  }
  match index.binding_for_node(proj.children[1].id()) {
    Some((binding_id, def_index)) => {
      inspect(binding_id == proj.children[1].id(), content="true")
      inspect(def_index, content="1")
    }
    None => fail("expected second duplicate binding")
  }
}
