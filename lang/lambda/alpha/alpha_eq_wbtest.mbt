///|
fn identity_lam(id : Int, hint : String) -> AlphaTerm {
  let binder = test_binder(id, hint)
  Lam(binder, Var(Bound(binder.id)))
}

///|
test "alpha_eq: lambda binder hints do not matter" {
  assert_true(alpha_eq(identity_lam(0, "x"), identity_lam(1, "y")))
}

///|
test "alpha_eq: free and bound references differ" {
  assert_false(
    alpha_eq(identity_lam(0, "x"), Lam(test_binder(1, "x"), free_var("x"))),
  )
}

///|
test "alpha_eq: free origin does not affect free-name equality" {
  let source_var = Var(Free(test_free("x", SourceVar)))
  let source_unbound = Var(Free(test_free("x", SourceUnbound)))
  assert_true(alpha_eq(source_var, source_unbound))
}

///|
test "alpha_eq: free names must match" {
  let x = Var(Free(test_free("x", SourceVar)))
  let y = Var(Free(test_free("y", GeneratedFree)))
  assert_false(alpha_eq(x, y))
}
