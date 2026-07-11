// Tests for incremental eval caching.
//
// Verifies that editing one definition reuses cached results for unchanged
// definitions in the prefix.

///|
test "incremental: unchanged module returns cached results" {
  let ast = @ast.Term::Module(
    [("x", @ast.Term::Int(5)), ("y", @ast.Term::Int(10))],
    @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Var("y")),
  )
  let (results1, cache1) = eval_term_cached(ast, [])
  inspect(results1[0], content="Value(\"5\")")
  inspect(results1[1], content="Value(\"10\")")
  inspect(results1[2], content="Value(\"15\")")
  // Same AST → cache hit, same results
  let (results2, _) = eval_term_cached(ast, cache1)
  inspect(results2[0], content="Value(\"5\")")
  inspect(results2[1], content="Value(\"10\")")
  inspect(results2[2], content="Value(\"15\")")
}

///|
test "incremental: changing last def preserves prefix" {
  let ast1 = @ast.Term::Module(
    [("x", @ast.Term::Int(5)), ("y", @ast.Term::Int(10))],
    @ast.Term::Var("y"),
  )
  let (results1, cache1) = eval_term_cached(ast1, [])
  inspect(results1.length(), content="3")
  inspect(results1[0], content="Value(\"5\")")
  inspect(results1[1], content="Value(\"10\")")
  // Change y from 10 to 20 — x should be reused from cache
  let ast2 = @ast.Term::Module(
    [("x", @ast.Term::Int(5)), ("y", @ast.Term::Int(20))],
    @ast.Term::Var("y"),
  )
  let (results2, cache2) = eval_term_cached(ast2, cache1)
  inspect(results2[0], content="Value(\"5\")") // reused
  inspect(results2[1], content="Value(\"20\")") // re-evaluated
  inspect(results2[2], content="Value(\"20\")") // re-evaluated (body)
  // Verify cache has correct terms
  inspect(cache2[0].term == @ast.Term::Int(5), content="true")
  inspect(cache2[1].term == @ast.Term::Int(20), content="true")
}

///|
test "incremental: changing first def re-evaluates all" {
  let ast1 = @ast.Term::Module(
    [("x", @ast.Term::Int(5)), ("y", @ast.Term::Var("x"))],
    @ast.Term::Var("y"),
  )
  let (_, cache1) = eval_term_cached(ast1, [])
  // Change x from 5 to 100 — everything depends on x
  let ast2 = @ast.Term::Module(
    [("x", @ast.Term::Int(100)), ("y", @ast.Term::Var("x"))],
    @ast.Term::Var("y"),
  )
  let (results2, _) = eval_term_cached(ast2, cache1)
  inspect(results2[0], content="Value(\"100\")")
  inspect(results2[1], content="Value(\"100\")")
  inspect(results2[2], content="Value(\"100\")")
}

///|
test "incremental: stuck in prefix blocks cache reuse for dependents" {
  let ast1 = @ast.Term::Module(
    [("x", @ast.Term::Var("missing")), ("y", @ast.Term::Int(10))],
    @ast.Term::Int(0),
  )
  let (results1, cache1) = eval_term_cached(ast1, [])
  inspect(
    results1[0],
    content=(
      #|Stuck("‹unbound: missing›")
    ),
  )
  inspect(results1[1], content="Suppressed")
  inspect(results1[2], content="Suppressed")
  // Change y (which was Suppressed) — x is still stuck, so y stays Suppressed
  let ast2 = @ast.Term::Module(
    [("x", @ast.Term::Var("missing")), ("y", @ast.Term::Int(20))],
    @ast.Term::Int(0),
  )
  let (results2, _) = eval_term_cached(ast2, cache1)
  inspect(
    results2[0],
    content=(
      #|Stuck("‹unbound: missing›")
    ),
  )
  inspect(results2[1], content="Suppressed")
  inspect(results2[2], content="Suppressed")
}

///|
test "incremental: renaming a binder invalidates cache" {
  // Codex bug: cache keyed on RHS only, not binder name.
  // let x=1; let y=x → let z=1; let y=x should fail (x now unbound)
  let ast1 = @ast.Term::Module(
    [("x", @ast.Term::Int(1)), ("y", @ast.Term::Var("x"))],
    @ast.Term::Var("y"),
  )
  let (results1, cache1) = eval_term_cached(ast1, [])
  inspect(results1[0], content="Value(\"1\")")
  inspect(results1[1], content="Value(\"1\")")
  inspect(results1[2], content="Value(\"1\")")
  // Rename x → z (same RHS Int(1), different name)
  let ast2 = @ast.Term::Module(
    [("z", @ast.Term::Int(1)), ("y", @ast.Term::Var("x"))],
    @ast.Term::Var("y"),
  )
  let (results2, _) = eval_term_cached(ast2, cache1)
  inspect(results2[0], content="Value(\"1\")") // z=1 still evaluates
  inspect(
    results2[1],
    content=(
      #|Stuck("‹unbound: x›")
    ),
  ) // y=x now fails (x unbound)
  inspect(results2[2], content="Suppressed") // body suppressed
}

///|
test "incremental: module shape change invalidates cache" {
  let ast1 = @ast.Term::Module(
    [("x", @ast.Term::Int(1)), ("y", @ast.Term::Int(2))],
    @ast.Term::Var("y"),
  )
  let (_, cache1) = eval_term_cached(ast1, [])
  // Remove a definition: 2 defs → 1 def
  let ast2 = @ast.Term::Module([("x", @ast.Term::Int(1))], @ast.Term::Var("x"))
  let (results2, _) = eval_term_cached(ast2, cache1)
  inspect(results2.length(), content="2")
  inspect(results2[0], content="Value(\"1\")")
  inspect(results2[1], content="Value(\"1\")")
}

///|
test "incremental: only body changed" {
  let ast1 = @ast.Term::Module([("x", @ast.Term::Int(5))], @ast.Term::Var("x"))
  let (results1, cache1) = eval_term_cached(ast1, [])
  inspect(results1[0], content="Value(\"5\")")
  inspect(results1[1], content="Value(\"5\")")
  // Change body from Var("x") to Int(99)
  let ast2 = @ast.Term::Module([("x", @ast.Term::Int(5))], @ast.Term::Int(99))
  let (results2, _) = eval_term_cached(ast2, cache1)
  inspect(results2[0], content="Value(\"5\")") // reused
  inspect(results2[1], content="Value(\"99\")") // re-evaluated
}
