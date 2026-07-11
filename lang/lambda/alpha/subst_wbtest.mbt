///|
test "substitute: replaces matching bound references only" {
  let x = test_binder(0, "x")
  let y = test_binder(1, "y")
  let replacement = free_var("z")
  let term = App(Var(Bound(x.id)), Var(Bound(y.id)))
  guard substitute(term, x.id, replacement)
    is App(Var(Free(free)), Var(Bound(rest))) else {
    fail("expected one replacement")
  }
  inspect(free.name, content="z")
  inspect(rest == y.id, content="true")
}

///|
test "substitute: nested unrelated binders are untouched" {
  let x = test_binder(0, "x")
  let y = test_binder(1, "y")
  let term = Lam(y, Var(Bound(y.id)))
  guard substitute(term, x.id, free_var("z")) is Lam(_, Var(Bound(ref_id))) else {
    fail("expected lambda to remain bound to y")
  }
  inspect(ref_id == y.id, content="true")
}

///|
test "substitute: Error and Hole are preserved" {
  let x = test_binder(0, "x")
  inspect(
    substitute(Error("bad"), x.id, free_var("z")) is Error("bad"),
    content="true",
  )
  inspect(substitute(Hole(4), x.id, free_var("z")) is Hole(4), content="true")
}

///|
test "substitute: module binder gates later substitutions" {
  let x = test_binder(0, "x")
  let term = Module([(x, Var(Bound(x.id)))], Var(Bound(x.id)))
  guard substitute(term, x.id, free_var("z"))
    is Module([(_, Var(Free(init_free)))], Var(Bound(body_id))) else {
    fail("expected init replacement and body shadowing")
  }
  inspect(init_free.name, content="z")
  inspect(body_id == x.id, content="true")
}

///|
test "beta_reduce_root: reduces only root lambda applications" {
  let x = test_binder(0, "x")
  let term = App(Lam(x, Var(Bound(x.id))), free_var("z"))
  guard beta_reduce_root(term) is Some(Var(Free(free))) else {
    fail("expected root beta reduction")
  }
  inspect(free.name, content="z")
  inspect(beta_reduce_root(free_var("z")) is None, content="true")
}
