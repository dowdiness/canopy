///|
test "alpha_key: lambda binder identities do not matter" {
  assert_true(
    alpha_key(identity_lam(0, "x")) == alpha_key(identity_lam(1, "y")),
  )
}

///|
test "alpha_key: free and bound references differ" {
  let bound = identity_lam(0, "x")
  let free = Lam(test_binder(1, "x"), free_var("x"))
  assert_false(alpha_key(bound) == alpha_key(free))
}

///|
test "alpha_key: free origin does not affect free-name key" {
  let source_var = Var(Free(test_free("x", SourceVar)))
  let source_unbound = Var(Free(test_free("x", SourceUnbound)))
  assert_true(alpha_key(source_var) == alpha_key(source_unbound))
}

///|
fn assert_alpha_eq_key_agree(left : AlphaTerm, right : AlphaTerm) -> Unit raise {
  assert_true(alpha_eq(left, right) == (alpha_key(left) == alpha_key(right)))
}

///|
test "alpha_key: agrees with alpha_eq across constructors" {
  let x = test_binder(10, "x")
  let y = test_binder(11, "y")
  let z = test_binder(12, "z")
  let cases : Array[(AlphaTerm, AlphaTerm)] = [
    (Int(1), Int(1)),
    (Int(1), Int(2)),
    (Unit, Unit),
    (
      Var(Free(test_free("x", SourceVar))),
      Var(Free(test_free("x", GeneratedFree))),
    ),
    (identity_lam(1, "a"), identity_lam(2, "b")),
    (identity_lam(1, "a"), Lam(test_binder(2, "b"), free_var("b"))),
    (App(identity_lam(1, "a"), Int(1)), App(identity_lam(2, "b"), Int(1))),
    (Bop(@ast.Bop::Plus, Int(1), Int(2)), Bop(@ast.Bop::Plus, Int(1), Int(2))),
    (Bop(@ast.Bop::Plus, Int(1), Int(2)), Bop(@ast.Bop::Minus, Int(1), Int(2))),
    (
      If(Var(Free(test_free("c", SourceVar))), Int(1), Int(2)),
      If(free_var("c"), Int(1), Int(2)),
    ),
    (LetDef(x, Int(1)), LetDef(y, Int(1))),
    (
      Module([(x, Int(1))], Var(Bound(x.id))),
      Module([(y, Int(1))], Var(Bound(y.id))),
    ),
    (Error("bad"), Error("bad")),
    (Hole(3), Hole(3)),
    (Var(Bound(x.id)), Var(Bound(x.id))),
    (Var(Bound(x.id)), Var(Bound(z.id))),
  ]
  cases
  .iter()
  .each(fn(pair) raise {
    let (left, right) = pair
    assert_alpha_eq_key_agree(left, right)
  })
}

///|
test "alpha_key: module definitions scope sequentially" {
  let first_left = test_binder(1, "a")
  let second_left = test_binder(2, "b")
  let first_right = test_binder(10, "x")
  let second_right = test_binder(20, "y")
  let left = Module(
    [(first_left, Int(1)), (second_left, Var(Bound(first_left.id)))],
    Var(Bound(second_left.id)),
  )
  let right = Module(
    [(first_right, Int(1)), (second_right, Var(Bound(first_right.id)))],
    Var(Bound(second_right.id)),
  )
  assert_true(alpha_eq(left, right))
  assert_true(alpha_key(left) == alpha_key(right))
}

///|
test "alpha_key: module shape and body references affect key" {
  let first = test_binder(1, "a")
  let second = test_binder(2, "b")
  let one_def = Module([(first, Int(1))], Var(Bound(first.id)))
  let two_defs = Module(
    [(first, Int(1)), (second, Int(2))],
    Var(Bound(second.id)),
  )
  let different_body = Module([(first, Int(1))], free_var("a"))
  assert_false(alpha_eq(one_def, two_defs))
  assert_false(alpha_key(one_def) == alpha_key(two_defs))
  assert_false(alpha_eq(one_def, different_body))
  assert_false(alpha_key(one_def) == alpha_key(different_body))
}

///|
test "alpha_key: nested lambdas distinguish referenced binder" {
  let x = test_binder(1, "x")
  let y = test_binder(2, "y")
  let left = Lam(x, Lam(y, Var(Bound(x.id))))
  let x2 = test_binder(10, "x")
  let y2 = test_binder(20, "y")
  let right = Lam(x2, Lam(y2, Var(Bound(y2.id))))
  assert_false(alpha_eq(left, right))
  assert_false(alpha_key(left) == alpha_key(right))
}

///|
test "alpha_key: error and hole payloads are preserved" {
  assert_true(alpha_key(Error("bad")) == alpha_key(Error("bad")))
  assert_false(alpha_key(Error("bad")) == alpha_key(Error("worse")))
  assert_true(alpha_key(Hole(3)) == alpha_key(Hole(3)))
  assert_false(alpha_key(Hole(3)) == alpha_key(Hole(4)))
}

///|
test "alpha_key: standalone let definition drops binder" {
  assert_true(
    alpha_key(LetDef(test_binder(1, "x"), Int(1))) ==
    alpha_key(LetDef(test_binder(2, "y"), Int(1))),
  )
  assert_false(
    alpha_key(LetDef(test_binder(1, "x"), Int(1))) ==
    alpha_key(LetDef(test_binder(1, "x"), Int(2))),
  )
}
