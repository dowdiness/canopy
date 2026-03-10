// Whitebox tests for apply_edit_to_proj

///|
fn tree_edit_test_registry(root : ProjNode) -> Map[NodeId, ProjNode] {
  let registry : Map[NodeId, ProjNode] = {}
  tree_edit_test_register(root, registry)
  registry
}

///|
fn tree_edit_test_register(
  node : ProjNode,
  registry : Map[NodeId, ProjNode],
) -> Unit {
  registry[node.id()] = node
  for child in node.children {
    tree_edit_test_register(child, registry)
  }
}

///|
fn tree_edit_test_var(id : Int, name : String) -> ProjNode {
  ProjNode::new(@ast.Term::Var(name), id, id + 1, id, [])
}

///|
fn tree_edit_test_container(children : Array[ProjNode]) -> ProjNode {
  ProjNode::new(@ast.Term::Error("container"), 0, 0, 0, children)
}

///|
fn tree_edit_test_ids(nodes : Array[ProjNode]) -> Array[Int] {
  nodes.map(fn(node) { node.node_id })
}

///|
test "apply_edit_to_proj CommitEdit preserves node id" {
  let (root, _) = parse_to_proj_node("x + 1")
  let target = root.children[1]
  let result = apply_edit_to_proj(
    root,
    CommitEdit(node_id=target.id(), new_value="2"),
    tree_edit_test_registry(root),
    Ref::new(100),
  )
  match result {
    Ok(updated) => {
      inspect(updated.children[1].node_id, content=target.node_id.to_string())
      inspect(@ast.print_term(updated.kind), content="(x + 2)")
    }
    Err(msg) => abort(msg)
  }
}

///|
test "apply_edit_to_proj WrapInLambda keeps target id" {
  let (root, _) = parse_to_proj_node("42")
  let result = apply_edit_to_proj(
    root,
    WrapInLambda(node_id=root.id(), var_name="x"),
    tree_edit_test_registry(root),
    Ref::new(100),
  )
  match result {
    Ok(updated) => {
      inspect(updated.node_id, content=root.node_id.to_string())
      inspect(@ast.print_term(updated.kind), content="(λx. 42)")
    }
    Err(msg) => abort(msg)
  }
}

///|
test "apply_edit_to_proj Delete removes child from container" {
  let root = tree_edit_test_container([
    tree_edit_test_var(1, "a"),
    tree_edit_test_var(2, "b"),
    tree_edit_test_var(3, "c"),
  ])
  let result = apply_edit_to_proj(
    root,
    Delete(node_id=NodeId(2)),
    tree_edit_test_registry(root),
    Ref::new(100),
  )
  match result {
    Ok(updated) => {
      inspect(updated.children.length(), content="2")
      inspect(tree_edit_test_ids(updated.children), content="[1, 3]")
    }
    Err(msg) => abort(msg)
  }
}

///|
test "apply_edit_to_proj InsertChild inserts placeholder node" {
  let root = tree_edit_test_container([
    tree_edit_test_var(1, "a"),
    tree_edit_test_var(2, "b"),
  ])
  let result = apply_edit_to_proj(
    root,
    InsertChild(parent=root.id(), index=1, kind=@ast.Term::Var("ignored")),
    tree_edit_test_registry(root),
    Ref::new(100),
  )
  match result {
    Ok(updated) => {
      inspect(updated.children.length(), content="3")
      inspect(tree_edit_test_ids(updated.children), content="[1, 100, 2]")
      inspect(
        match updated.children[1].kind {
          @ast.Term::Var("a") => "true"
          _ => "false"
        },
        content="true",
      )
    }
    Err(msg) => abort(msg)
  }
}

///|
test "apply_edit_to_proj Drop reorders container siblings" {
  let root = tree_edit_test_container([
    tree_edit_test_var(1, "a"),
    tree_edit_test_var(2, "b"),
    tree_edit_test_var(3, "c"),
  ])
  let result = apply_edit_to_proj(
    root,
    Drop(source=NodeId(3), target=NodeId(1), position=Before),
    tree_edit_test_registry(root),
    Ref::new(100),
  )
  match result {
    Ok(updated) =>
      inspect(tree_edit_test_ids(updated.children), content="[3, 1, 2]")
    Err(msg) => abort(msg)
  }
}

///|
test "apply_edit_to_proj rejects deleting root" {
  let (root, _) = parse_to_proj_node("x")
  let result = apply_edit_to_proj(
    root,
    Delete(node_id=root.id()),
    tree_edit_test_registry(root),
    Ref::new(100),
  )
  inspect(result is Err(_), content="true")
}

///|
test "apply_edit_to_proj rejects moving node into its own subtree" {
  let nested = ProjNode::new(@ast.Term::Error("nested"), 1, 2, 1, [
    tree_edit_test_var(2, "a"),
  ])
  let root = tree_edit_test_container([nested, tree_edit_test_var(3, "b")])
  let result = apply_edit_to_proj(
    root,
    Drop(source=NodeId(1), target=NodeId(2), position=Inside),
    tree_edit_test_registry(root),
    Ref::new(100),
  )
  inspect(result is Err(_), content="true")
}
