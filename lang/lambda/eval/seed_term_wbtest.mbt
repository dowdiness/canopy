// Tests for seed_term: Term → egglog fact conversion.

///|
test "seed_term: integer" {
  let db = @egglog_eval.lambda_eval_db()
  let expr = seed_term(db, @ast.Term::Int(42))
  let expected = db.call("Num", [@egglog.IntVal(42)])
  inspect(egglog_same_class(db, expr, expected), content="true")
}

///|
test "seed_term: unit" {
  let db = @egglog_eval.lambda_eval_db()
  let expr = seed_term(db, @ast.Term::Unit)
  let expected = db.call("Unit", [])
  inspect(egglog_same_class(db, expr, expected), content="true")
}

///|
test "seed_term: variable" {
  let db = @egglog_eval.lambda_eval_db()
  let expr = seed_term(db, @ast.Term::Var("x"))
  let expected = db.call("Var", [@egglog.StrVal("x")])
  inspect(egglog_same_class(db, expr, expected), content="true")
}

///|
test "seed_term: lambda" {
  let db = @egglog_eval.lambda_eval_db()
  let expr = seed_term(db, @ast.Term::Lam("x", @ast.Term::Var("x")))
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let expected = db.call("Lam", [@egglog.StrVal("x"), var_x])
  inspect(egglog_same_class(db, expr, expected), content="true")
}

///|
test "seed_term: application" {
  let db = @egglog_eval.lambda_eval_db()
  let expr = seed_term(
    db,
    @ast.Term::App(@ast.Term::Var("f"), @ast.Term::Int(5)),
  )
  let f = db.call("Var", [@egglog.StrVal("f")])
  let n = db.call("Num", [@egglog.IntVal(5)])
  let expected = db.call("App", [f, n])
  inspect(egglog_same_class(db, expr, expected), content="true")
}

///|
test "seed_term: arithmetic plus" {
  let db = @egglog_eval.lambda_eval_db()
  let expr = seed_term(
    db,
    @ast.Term::Bop(Plus, @ast.Term::Int(2), @ast.Term::Int(3)),
  )
  let a = db.call("Num", [@egglog.IntVal(2)])
  let b = db.call("Num", [@egglog.IntVal(3)])
  let expected = db.call("Add", [a, b])
  inspect(egglog_same_class(db, expr, expected), content="true")
}

///|
test "seed_term: arithmetic minus" {
  let db = @egglog_eval.lambda_eval_db()
  let expr = seed_term(
    db,
    @ast.Term::Bop(Minus, @ast.Term::Int(10), @ast.Term::Int(3)),
  )
  let a = db.call("Num", [@egglog.IntVal(10)])
  let b = db.call("Num", [@egglog.IntVal(3)])
  let expected = db.call("Minus", [a, b])
  inspect(egglog_same_class(db, expr, expected), content="true")
}

///|
test "seed_term: conditional" {
  let db = @egglog_eval.lambda_eval_db()
  let expr = seed_term(
    db,
    @ast.Term::If(@ast.Term::Int(1), @ast.Term::Int(2), @ast.Term::Int(3)),
  )
  let c = db.call("Num", [@egglog.IntVal(1)])
  let t = db.call("Num", [@egglog.IntVal(2)])
  let e = db.call("Num", [@egglog.IntVal(3)])
  let expected = db.call("If", [c, t, e])
  inspect(egglog_same_class(db, expr, expected), content="true")
}

///|
test "seed_term: hole sentinel" {
  let db = @egglog_eval.lambda_eval_db()
  let expr = seed_term(db, @ast.Term::Hole(0))
  let expected = db.call("HoleNode", [@egglog.IntVal(0)])
  inspect(egglog_same_class(db, expr, expected), content="true")
}

///|
test "seed_term: error sentinel" {
  let db = @egglog_eval.lambda_eval_db()
  let expr = seed_term(db, @ast.Term::Error("bad"))
  let expected = db.call("ErrorNode", [@egglog.StrVal("bad")])
  inspect(egglog_same_class(db, expr, expected), content="true")
}

///|
test "seed_term: unbound sentinel" {
  let db = @egglog_eval.lambda_eval_db()
  let expr = seed_term(db, @ast.Term::Unbound("x"))
  let expected = db.call("UnboundNode", [@egglog.StrVal("x")])
  inspect(egglog_same_class(db, expr, expected), content="true")
}

///|
test "seed_term: module desugars to nested let" {
  let db = @egglog_eval.lambda_eval_db()
  // Module([(x, 1), (y, 2)], x+y) → Let(x, 1, Let(y, 2, x+y))
  let expr = seed_term(
    db,
    @ast.Term::Module(
      [("x", @ast.Term::Int(1)), ("y", @ast.Term::Int(2))],
      @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Var("y")),
    ),
  )
  // Build the expected nested Let manually
  let n1 = db.call("Num", [@egglog.IntVal(1)])
  let n2 = db.call("Num", [@egglog.IntVal(2)])
  let vx = db.call("Var", [@egglog.StrVal("x")])
  let vy = db.call("Var", [@egglog.StrVal("y")])
  let add = db.call("Add", [vx, vy])
  let inner_let = db.call("Let", [@egglog.StrVal("y"), n2, add])
  let outer_let = db.call("Let", [@egglog.StrVal("x"), n1, inner_let])
  inspect(egglog_same_class(db, expr, outer_let), content="true")
}

///|
test "seed_term + run_eval: end-to-end evaluation" {
  // Seed (2 + 3) into egglog and evaluate it
  let db = @egglog_eval.lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let expr = seed_term(
    db,
    @ast.Term::Bop(Plus, @ast.Term::Int(2), @ast.Term::Int(3)),
  )
  let result = @egglog_eval.run_eval(db, env, expr, @egglog_eval.eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(5)])
  inspect(result is Some(_), content="true")
  inspect(egglog_same_class(db, result.unwrap(), expected), content="true")
}

///|
test "seed_term + run_eval: lambda application" {
  // Seed (λx. x + 1) 5 and evaluate to 6
  let db = @egglog_eval.lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let expr = seed_term(
    db,
    @ast.Term::App(
      @ast.Term::Lam(
        "x",
        @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(1)),
      ),
      @ast.Term::Int(5),
    ),
  )
  let result = @egglog_eval.run_eval(db, env, expr, @egglog_eval.eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(6)])
  inspect(result is Some(_), content="true")
  inspect(egglog_same_class(db, result.unwrap(), expected), content="true")
}

///|
test "seed_term + run_eval: module with let bindings" {
  // let x = 2; let y = x + 3; y → 5
  let db = @egglog_eval.lambda_eval_db()
  let env = db.call("EmptyEnv", [])
  let expr = seed_term(
    db,
    @ast.Term::Module(
      [
        ("x", @ast.Term::Int(2)),
        ("y", @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(3))),
      ],
      @ast.Term::Var("y"),
    ),
  )
  let result = @egglog_eval.run_eval(db, env, expr, @egglog_eval.eval_rules())
  let expected = db.call("ValInt", [@egglog.IntVal(5)])
  inspect(result is Some(_), content="true")
  inspect(egglog_same_class(db, result.unwrap(), expected), content="true")
}

///|
/// Helper: check if two egglog values are in the same equivalence class.
fn egglog_same_class(
  db : @egglog.Database,
  a : @egglog.Value,
  b : @egglog.Value,
) -> Bool {
  egglog_find(db, a) == egglog_find(db, b)
}
