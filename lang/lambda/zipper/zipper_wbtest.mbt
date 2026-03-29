///|
test "go_down then go_up is identity" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let down = go_down(z).unwrap()
  let up = go_up(down).unwrap()
  inspect(to_root(up), content="App(Var(\"f\"), Int(1))")
}

///|
test "go_right then go_left is identity" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let down = go_down(z).unwrap()
  let right = go_right(down).unwrap()
  let left = go_left(right).unwrap()
  inspect(to_root(left), content="App(Var(\"f\"), Int(1))")
}

///|
test "go_down on leaf returns None" {
  let z = from_root(@ast.Int(42))
  inspect(go_down(z), content="None")
}

///|
test "go_down on Hole returns None" {
  let z = from_root(@ast.Hole(0))
  inspect(go_down(z), content="None")
}

///|
test "traverse all children of If" {
  let z = from_root(@ast.If(@ast.Int(1), @ast.Int(2), @ast.Int(3)))
  let c = go_down(z).unwrap()
  inspect(c.focus, content="Int(1)")
  let t = go_right(c).unwrap()
  inspect(t.focus, content="Int(2)")
  let e = go_right(t).unwrap()
  inspect(e.focus, content="Int(3)")
  inspect(go_right(e), content="None")
}

///|
test "Module navigation: defs then body" {
  let z = from_root(
    @ast.Module([("x", @ast.Int(1)), ("y", @ast.Int(2))], @ast.Var("x")),
  )
  let d0 = go_down(z).unwrap()
  inspect(d0.focus, content="Int(1)")
  let d1 = go_right(d0).unwrap()
  inspect(d1.focus, content="Int(2)")
  let body = go_right(d1).unwrap()
  inspect(body.focus, content="Var(\"x\")")
  inspect(go_right(body), content="None")
}

///|
test "focus_at ancestor walk" {
  let term = @ast.App(@ast.Var("f"), @ast.Int(1))
  let z = focus_at(term, [0, 0, 0])
  inspect(depth(z), content="1")
}

///|
test "focus_at exact path" {
  let term = @ast.If(@ast.Int(1), @ast.Int(2), @ast.Int(3))
  let z = focus_at(term, [2])
  inspect(z.focus, content="Int(3)")
}

///|
test "navigate_to_child child 0" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let c = navigate_to_child(z, 0).unwrap()
  inspect(c.focus, content="Var(\"f\")")
}

///|
test "navigate_to_child child 1" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let c = navigate_to_child(z, 1).unwrap()
  inspect(c.focus, content="Int(1)")
}

///|
test "go_left from Module body to last def" {
  let z = from_root(@ast.Module([("x", @ast.Int(1))], @ast.Var("x")))
  let body = go_down(z).unwrap() |> go_right() |> Option::unwrap()
  inspect(body.focus, content="Var(\"x\")")
  let def = go_left(body).unwrap()
  inspect(def.focus, content="Int(1)")
}

///|
test "root position" {
  let z = from_root(@ast.Int(42))
  inspect(position_role(z), content="Root")
}

///|
test "function position in App" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let down = go_down(z).unwrap()
  inspect(position_role(down), content="FunctionPosition")
}

///|
test "argument position in App" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let down = go_down(z).unwrap()
  let right = go_right(down).unwrap()
  inspect(position_role(right), content="ArgumentPosition")
}

///|
test "else branch in If" {
  let z = from_root(@ast.If(@ast.Int(1), @ast.Int(2), @ast.Int(3)))
  let c = go_down(z).unwrap()
  let t = go_right(c).unwrap()
  let e = go_right(t).unwrap()
  inspect(position_role(e), content="ElseBranch")
}

///|
test "let definition role carries name" {
  let z = from_root(@ast.Module([("x", @ast.Int(1))], @ast.Var("x")))
  let d = go_down(z).unwrap()
  inspect(position_role(d), content="LetDefinition(\"x\")")
}

///|
test "to_tree_edit_op maps Delete" {
  let id = @core.NodeId::from_int(5)
  let op = to_tree_edit_op(id, Delete)
  inspect(op, content="Delete(node_id=NodeId(5))")
}

///|
test "to_tree_edit_op maps WrapLam" {
  let id = @core.NodeId::from_int(5)
  let op = to_tree_edit_op(id, WrapLam("x"))
  inspect(op, content="WrapInLambda(node_id=NodeId(5), var_name=\"x\")")
}

///|
test "to_tree_edit_op maps Unwrap" {
  let id = @core.NodeId::from_int(5)
  let op = to_tree_edit_op(id, Unwrap(1))
  inspect(op, content="Unwrap(node_id=NodeId(5), keep_child_index=1)")
}

///|
test "HoleRegistry fresh_hole_id increments" {
  let reg = HoleRegistry::new()
  inspect(reg.fresh_hole_id(), content="0")
  inspect(reg.fresh_hole_id(), content="1")
  inspect(reg.fresh_hole_id(), content="2")
}

///|
test "HoleRegistry register and get" {
  let reg = HoleRegistry::new()
  let id = @core.NodeId::from_int(5)
  let info : HoleInfo = { created_by: Delete, role: Root }
  reg.register(id, info)
  inspect(reg.get(id) is None, content="false")
  inspect(reg.get(@core.NodeId::from_int(99)) is None, content="true")
}

///|
test "to_path_indices round-trip" {
  let term = @ast.If(@ast.Int(1), @ast.Int(2), @ast.Int(3))
  let z = from_root(term)
    |> go_down()
    |> Option::unwrap()
    |> go_right()
    |> Option::unwrap()
  let indices = to_path_indices(z)
  inspect(indices, content="[1]")
  let z2 = focus_at(term, indices)
  inspect(z2.focus, content="Int(2)")
}

///|
test "available_actions includes SwapChildren for Bop" {
  let z = from_root(@ast.Bop(@ast.Plus, @ast.Int(1), @ast.Int(2)))
  let actions = available_actions(z)
  let has_swap = actions
    .iter()
    .any(fn(a) {
      match a {
        SwapChildren => true
        _ => false
      }
    })
  inspect(has_swap, content="true")
}

///|
test "available_actions excludes SwapChildren for App" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let actions = available_actions(z)
  let has_swap = actions
    .iter()
    .any(fn(a) {
      match a {
        SwapChildren => true
        _ => false
      }
    })
  inspect(has_swap, content="false")
}

///|
test "available_actions includes Unwrap for non-leaf" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let actions = available_actions(z)
  let has_unwrap = actions
    .iter()
    .any(fn(a) {
      match a {
        Unwrap(_) => true
        _ => false
      }
    })
  inspect(has_unwrap, content="true")
}

///|
test "available_actions excludes Unwrap for leaf" {
  let z = from_root(@ast.Int(42))
  let actions = available_actions(z)
  let has_unwrap = actions
    .iter()
    .any(fn(a) {
      match a {
        Unwrap(_) => true
        _ => false
      }
    })
  inspect(has_unwrap, content="false")
}
