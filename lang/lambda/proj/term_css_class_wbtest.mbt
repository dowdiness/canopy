// Enumerate all 11 Term variants. Drift between this function and the
// CSS classes in examples/ideal/web/styles/editor.css is a regression.
// See docs/plans/2026-05-16-show-unification.md (Task 1, PR 2).

///|
test "term_css_class — Int" {
  inspect(term_css_class(@ast.Term::Int(42)), content="int")
}

///|
test "term_css_class — Var" {
  inspect(term_css_class(@ast.Term::Var("x")), content="var")
}

///|
test "term_css_class — Lam" {
  inspect(
    term_css_class(@ast.Term::Lam("x", @ast.Term::Var("x"))),
    content="lambda",
  )
}

///|
test "term_css_class — App" {
  inspect(
    term_css_class(@ast.Term::App(@ast.Term::Var("f"), @ast.Term::Var("x"))),
    content="app",
  )
}

///|
test "term_css_class — Bop" {
  inspect(
    term_css_class(
      @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Int(1), @ast.Term::Int(2)),
    ),
    content="binop",
  )
}

///|
test "term_css_class — If" {
  inspect(
    term_css_class(
      @ast.Term::If(@ast.Term::Int(1), @ast.Term::Int(2), @ast.Term::Int(3)),
    ),
    content="if",
  )
}

///|
test "term_css_class — Module" {
  inspect(
    term_css_class(@ast.Term::Module([], @ast.Term::Unit)),
    content="module",
  )
}

///|
test "term_css_class — Unit" {
  inspect(term_css_class(@ast.Term::Unit), content="unit")
}

///|
test "term_css_class — Unbound" {
  inspect(term_css_class(@ast.Term::Unbound("x")), content="unbound")
}

///|
test "term_css_class — Error" {
  inspect(term_css_class(@ast.Term::Error("boom")), content="error")
}

///|
test "term_css_class — Hole" {
  inspect(term_css_class(@ast.Term::Hole(0)), content="hole")
}
