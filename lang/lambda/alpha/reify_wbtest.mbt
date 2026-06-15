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
