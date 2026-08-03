///|
test "beta pilot: root reduction reifies without capture" {
  let (proj, graph) = alpha_parse_fixture("((x) => (y) => x) y")
  guard beta_reduce_root(lower_root(proj, graph)) is Some(reduced) else {
    fail("expected root beta reduction")
  }
  let expected_binder = test_binder(99, "y1")
  assert_true(alpha_eq(reduced, Lam(expected_binder, free_var("y"))))
  guard reify(reduced, Source) is @ast.Term::Lam(param, @ast.Term::Var(body)) else {
    fail("expected reified lambda")
  }
  inspect(param, content="y1")
  inspect(body, content="y")
}
