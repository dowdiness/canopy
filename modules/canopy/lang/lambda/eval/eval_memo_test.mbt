///|
test "eval_term: simple module with arithmetic" {
  let results = eval_term(
    @ast.Term::Module(
      [
        ("x", @ast.Term::Int(5)),
        ("y", @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(3))),
      ],
      @ast.Term::Var("y"),
    ),
  )
  inspect(results.length(), content="3")
  inspect(results[0], content="Value(\"5\")")
  inspect(results[1], content="Value(\"8\")")
  inspect(results[2], content="Value(\"8\")")
}

///|
test "eval_term: unbound variable is Stuck" {
  let results = eval_term(@ast.Term::Var("missing"))
  inspect(results.length(), content="1")
  inspect(
    results[0],
    content=(
      #|Stuck("‹unbound: missing›")
    ),
  )
}

///|
test "eval_term: hole is Suppressed" {
  let results = eval_term(@ast.Term::Hole(0))
  inspect(results.length(), content="1")
  inspect(results[0], content="Suppressed")
}

///|
test "eval_term: parse error is Suppressed" {
  let results = eval_term(@ast.Term::Error("bad"))
  inspect(results.length(), content="1")
  inspect(results[0], content="Suppressed")
}

///|
test "eval_term: closure renders correctly" {
  let results = eval_term(
    @ast.Term::Module(
      [("f", @ast.Term::Lam("x", @ast.Term::Var("x")))],
      @ast.Term::Var("f"),
    ),
  )
  inspect(
    results[0],
    content=(
      #|Value("‹closure›")
    ),
  )
}

///|
test "eval_term: divergence is Stuck" {
  let omega = @ast.Term::App(
    @ast.Term::Lam(
      "x",
      @ast.Term::App(@ast.Term::Var("x"), @ast.Term::Var("x")),
    ),
    @ast.Term::Lam(
      "x",
      @ast.Term::App(@ast.Term::Var("x"), @ast.Term::Var("x")),
    ),
  )
  let results = eval_term(omega)
  inspect(
    results[0],
    content=(
      #|Stuck("‹diverges›")
    ),
  )
}

///|
test "eval_term: first def fails, rest suppressed" {
  let results = eval_term(
    @ast.Term::Module(
      [
        ("a", @ast.Term::Var("missing")),
        ("b", @ast.Term::Int(1)),
        ("c", @ast.Term::Int(2)),
      ],
      @ast.Term::Int(0),
    ),
  )
  inspect(results.length(), content="4")
  inspect(
    results[0],
    content=(
      #|Stuck("‹unbound: missing›")
    ),
  )
  inspect(results[1], content="Suppressed")
  inspect(results[2], content="Suppressed")
  inspect(results[3], content="Suppressed")
}

///|
test "eval_term: unit value" {
  let results = eval_term(@ast.Term::Unit)
  inspect(results[0], content="Value(\"()\")")
}
