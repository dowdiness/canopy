// Enumerate all 11 Term variants — pins the return strings. CSS-selector
// coverage in editor.css is a manually maintained contract (not test-enforced).
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

///|
/// Pin the contract that `term_kind_tag` forwards `Renderable::kind_tag`
/// verbatim — `"Lam"`, `"App"`, etc. (capitalized variant tag), not the
/// lowercased CSS fragment. If loom's `kind_tag` impl ever changes its
/// output shape this test catches it.
test "term_kind_tag — forwards Renderable::kind_tag verbatim" {
  inspect(term_kind_tag(@ast.Term::Int(42)), content="Int")
  inspect(
    term_kind_tag(@ast.Term::Lam("x", @ast.Term::Var("x"))),
    content="Lam",
  )
  inspect(
    term_kind_tag(@ast.Term::App(@ast.Term::Var("f"), @ast.Term::Var("x"))),
    content="App",
  )
  inspect(term_kind_tag(@ast.Term::Unit), content="Unit")
}
