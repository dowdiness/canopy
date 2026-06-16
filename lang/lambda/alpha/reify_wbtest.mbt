///|
test "reify: freshens binders against free names" {
  let binder = test_binder(0, "y")
  let term = Lam(binder, free_var("y"))
  guard reify(term, Source) is @ast.Term::Lam(name, @ast.Term::Var(body)) else {
    fail("expected reified lambda")
  }
  inspect(name, content="y1")
  inspect(body, content="y")
}

///|
test "reify: Display preserves SourceUnbound and Source normalizes it" {
  let term = Var(Free(test_free("missing", SourceUnbound)))
  inspect(@ast.print_term(reify(term, Display)), content="<unbound: missing>")
  inspect(@ast.print_term(reify(term, Source)), content="missing")
}

///|
test "reify: Error and Hole survive" {
  inspect(
    reify(Error("bad"), Source) is @ast.Term::Error("bad"),
    content="true",
  )
  inspect(reify(Hole(3), Source) is @ast.Term::Hole(3), content="true")
}

///|
test "reify: nested binders avoid capturing outer references" {
  let outer = test_binder(0, "x")
  let inner = test_binder(1, "x")
  let term = Lam(outer, Lam(inner, Var(Bound(outer.id))))
  guard reify(term, Source)
    is @ast.Term::Lam(
      outer_name,
      @ast.Term::Lam(inner_name, @ast.Term::Var(body_name))
    ) else {
    fail("expected nested lambdas")
  }
  inspect(outer_name, content="x")
  inspect(inner_name, content="x1")
  inspect(body_name, content="x")
}

///|
test "reify: module binders avoid suffix free names" {
  let first = test_binder(0, "y")
  let second = test_binder(1, "z")
  let term = Module(
    [(first, Unit), (second, free_var("y"))],
    Var(Bound(first.id)),
  )
  guard reify(term, Source)
    is @ast.Term::Module(
      [(first_name, @ast.Term::Unit), (second_name, @ast.Term::Var(later_free))],
      @ast.Term::Var(body_name)
    ) else {
    fail("expected reified module")
  }
  inspect(first_name, content="y1")
  inspect(second_name, content="z")
  inspect(later_free, content="y")
  inspect(body_name, content="y1")
}

///|
test "reify: invalid binder hints fall back to lexable names" {
  let invalid = test_binder(0, "x_copy")
  let keyword = test_binder(1, "if")
  let digit = test_binder(2, "1x")
  let term = Lam(invalid, Lam(keyword, Lam(digit, Unit)))
  guard reify(term, Source)
    is @ast.Term::Lam(
      invalid_name,
      @ast.Term::Lam(keyword_name, @ast.Term::Lam(digit_name, @ast.Term::Unit))
    ) else {
    fail("expected nested lambdas")
  }
  inspect(invalid_name, content="x")
  inspect(keyword_name, content="x1")
  inspect(digit_name, content="x2")
}
