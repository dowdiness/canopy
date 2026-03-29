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
