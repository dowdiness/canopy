///|
test "free_vars: Var free when not in env" {
  let result = free_vars(@ast.Term::Var("x"), @immut/hashset.new())
  inspect(result.contains("x"), content="true")
}

///|
test "free_vars: Var bound when in env" {
  let env = @immut/hashset.new().add("x")
  let result = free_vars(@ast.Term::Var("x"), env)
  inspect(result.contains("x"), content="false")
}

///|
test "free_vars: Lam binds param" {
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.length(), content="0")
}

///|
test "free_vars: Lam body references outer" {
  let term = @ast.Term::Lam("x", @ast.Term::Var("y"))
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.contains("y"), content="true")
  inspect(result.contains("x"), content="false")
}

///|
test "free_vars: Bop collects from both sides" {
  let term = @ast.Term::Bop(
    @ast.Bop::Plus,
    @ast.Term::Var("x"),
    @ast.Term::Var("y"),
  )
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.contains("x"), content="true")
  inspect(result.contains("y"), content="true")
}

///|
test "free_vars: nested Lam shadowing" {
  let term = @ast.Term::Lam("x", @ast.Term::Lam("x", @ast.Term::Var("x")))
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.length(), content="0")
}

///|
test "free_vars: Int has no free vars" {
  let result = free_vars(@ast.Term::Int(42), @immut/hashset.new())
  inspect(result.length(), content="0")
}

///|
test "free_vars: Module sequential scoping" {
  let term = @ast.Term::Module(
    [("x", @ast.Term::Var("y")), ("z", @ast.Term::Var("x"))],
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Var("x"), @ast.Term::Var("z")),
  )
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.contains("y"), content="true")
  inspect(result.contains("x"), content="false")
  inspect(result.contains("z"), content="false")
}

///|
test "free_vars: Module def not in scope for own init" {
  let term = @ast.Term::Module([("x", @ast.Term::Var("x"))], @ast.Term::Unit)
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.contains("x"), content="true")
}

///|
test "free_vars: App collects from both" {
  let term = @ast.Term::App(@ast.Term::Var("f"), @ast.Term::Var("x"))
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.contains("f"), content="true")
  inspect(result.contains("x"), content="true")
}

///|
test "free_vars: If collects from all three" {
  let term = @ast.Term::If(
    @ast.Term::Var("a"),
    @ast.Term::Var("b"),
    @ast.Term::Var("c"),
  )
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.contains("a"), content="true")
  inspect(result.contains("b"), content="true")
  inspect(result.contains("c"), content="true")
}
