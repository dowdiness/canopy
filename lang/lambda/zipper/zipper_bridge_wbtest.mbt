// Whitebox tests for the Zipper-NodeId bridge.
// Uses parse_to_proj_node to build realistic ProjNode fixtures.

///|
test "to_path_indices: root has empty trail" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  inspect(to_path_indices(z), content="[]")
}

///|
test "to_path_indices: one level down gives [0]" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let down = go_down(z).unwrap()
  inspect(to_path_indices(down), content="[0]")
}

///|
test "to_path_indices: right sibling gives [1]" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let down = go_down(z).unwrap()
  let right = go_right(down).unwrap()
  inspect(to_path_indices(right), content="[1]")
}

///|
test "walk_proj: depth 0 returns root" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let result = walk_proj(proj_root, [], 0)
  inspect(result is Some(_), content="true")
}

///|
test "walk_proj: index [0] returns first child" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let result = walk_proj(proj_root, [0], 0)
  inspect(result is Some(_), content="true")
  match result {
    Some(node) => inspect(node.kind, content="Var(\"f\")")
    None => abort("expected Some")
  }
}

///|
test "walk_proj: index [1] returns second child" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let result = walk_proj(proj_root, [1], 0)
  inspect(result is Some(_), content="true")
  match result {
    Some(node) => inspect(node.kind, content="Int(1)")
    None => abort("expected Some")
  }
}

///|
test "walk_proj: out-of-range index returns None" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let result = walk_proj(proj_root, [99], 0)
  inspect(result, content="None")
}

///|
test "find_proj_node_for_focus: root zipper gives root proj node" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let z = from_root(proj_root.kind)
  let found = find_proj_node_for_focus(z, proj_root)
  inspect(found is Some(_), content="true")
  match found {
    Some(node) => inspect(node.kind, content="App(Var(\"f\"), Int(1))")
    None => abort("expected Some")
  }
}

///|
test "find_proj_node_for_focus: child zipper gives child proj node" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let z = from_root(proj_root.kind) |> go_down() |> Option::unwrap()
  let found = find_proj_node_for_focus(z, proj_root)
  match found {
    Some(node) => inspect(node.kind, content="Var(\"f\")")
    None => abort("expected Some")
  }
}

///|
test "path_indices_to_node: root node found with empty path" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let root_id = proj_root.id()
  let path = path_indices_to_node(proj_root, root_id)
  inspect(path, content="Some([])")
}

///|
test "path_indices_to_node: child node found with [0]" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let child_id = proj_root.children[0].id()
  let path = path_indices_to_node(proj_root, child_id)
  inspect(path, content="Some([0])")
}

///|
test "path_indices_to_node: missing node returns None" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let missing_id = @core.NodeId::from_int(99999)
  let path = path_indices_to_node(proj_root, missing_id)
  inspect(path, content="None")
}

///|
test "zipper_from_node_id: root id gives root zipper" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let root_id = proj_root.id()
  let z = zipper_from_node_id(root_id, proj_root.kind, proj_root)
  inspect(z is Some(_), content="true")
  match z {
    Some(zipper) => inspect(zipper.focus, content="App(Var(\"f\"), Int(1))")
    None => abort("expected Some")
  }
}

///|
test "zipper_from_node_id: child id gives focused zipper" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let child_id = proj_root.children[0].id()
  let z = zipper_from_node_id(child_id, proj_root.kind, proj_root)
  match z {
    Some(zipper) => inspect(zipper.focus, content="Var(\"f\")")
    None => abort("expected Some")
  }
}

///|
test "zipper_from_node_id: missing id returns None" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let missing_id = @core.NodeId::from_int(99999)
  let z = zipper_from_node_id(missing_id, proj_root.kind, proj_root)
  inspect(z, content="None")
}

///|
test "navigate Down from root" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let root_id = proj_root.id()
  let result = navigate(root_id, Down, proj_root.kind, proj_root)
  inspect(result is Some(_), content="true")
  match result {
    Some(node_id) =>
      inspect(node_id == proj_root.children[0].id(), content="true")
    None => abort("expected Some")
  }
}

///|
test "navigate Up from child returns root id" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let child_id = proj_root.children[0].id()
  let result = navigate(child_id, Up, proj_root.kind, proj_root)
  inspect(result is Some(_), content="true")
  match result {
    Some(node_id) => inspect(node_id == proj_root.id(), content="true")
    None => abort("expected Some")
  }
}

///|
test "navigate Right from first child reaches second child" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let child_id = proj_root.children[0].id()
  let result = navigate(child_id, Right, proj_root.kind, proj_root)
  match result {
    Some(node_id) =>
      inspect(node_id == proj_root.children[1].id(), content="true")
    None => abort("expected Some")
  }
}

///|
test "navigate Up from root returns None" {
  let (proj_root, _) = @proj.parse_to_proj_node("f 1")
  let root_id = proj_root.id()
  let result = navigate(root_id, Up, proj_root.kind, proj_root)
  inspect(result, content="None")
}
