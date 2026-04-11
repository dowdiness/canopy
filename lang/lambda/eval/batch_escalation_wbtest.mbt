// Tests for batch escalation (Tier 1 → Tier 2).
//
// The key scenario: when Tier 1 stops at a stuck definition (hole, error),
// subsequent independent definitions are Suppressed. Tier 2 (egglog) can
// evaluate around holes — it resolves what it can via partial environments.

///|
test "escalation: no suppressed → returns tier1 as-is" {
  let ast = @ast.Term::Module([("x", @ast.Term::Int(5))], @ast.Term::Var("x"))
  let tier1 = eval_term(ast)
  // All results are Value, no escalation needed
  let merged = escalate_suppressed(ast, tier1)
  inspect(merged.length(), content="2")
  inspect(merged[0], content="Value(\"5\")")
  inspect(merged[1], content="Value(\"5\")")
}

///|
test "escalation: hole in middle, independent defs resolved" {
  // let x = 2 + 3       → Value("5")
  // let y = ?            → Stuck (Incomplete → Suppressed in Tier 1)
  // let z = x + 1        → Suppressed by Tier 1 (env incomplete)
  // z                     → Suppressed by Tier 1
  //
  // After escalation: z should be Value("6") because it only depends on x.
  let ast = @ast.Term::Module(
    [
      ("x", @ast.Term::Bop(Plus, @ast.Term::Int(2), @ast.Term::Int(3))),
      ("y", @ast.Term::Hole(0)),
      ("z", @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(1))),
    ],
    @ast.Term::Var("z"),
  )
  let tier1 = eval_term(ast)
  // Verify Tier 1 behavior: stops at y
  inspect(tier1[0], content="Value(\"5\")")
  inspect(tier1[1], content="Suppressed") // Hole → Incomplete → Suppressed
  inspect(tier1[2], content="Suppressed")
  inspect(tier1[3], content="Suppressed")
  // Escalation should resolve z and body
  let merged = escalate_suppressed(ast, tier1)
  inspect(merged[0], content="Value(\"5\")") // unchanged
  inspect(merged[1], content="Suppressed") // y is still stuck (hole)
  inspect(merged[2], content="Value(\"6\")") // z = x + 1 = 6 via egglog!
  inspect(merged[3], content="Value(\"6\")") // body = z = 6 via egglog!
}

///|
test "escalation: stuck def shadows earlier binding" {
  // let x = 1
  // let x = missing     → Stuck (unbound)
  // x + 1               → Suppressed
  //
  // After escalation: body should stay unresolved because the second x
  // (stuck) shadows the first x=1. Partial env must NOT expose x=1.
  let ast = @ast.Term::Module(
    [("x", @ast.Term::Int(1)), ("x", @ast.Term::Var("missing"))],
    @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(1)),
  )
  let tier1 = eval_term(ast)
  inspect(tier1[0], content="Value(\"1\")")
  inspect(
    tier1[1],
    content=(
      #|Stuck("‹unbound: missing›")
    ),
  )
  inspect(tier1[2], content="Suppressed")
  let merged = escalate_suppressed(ast, tier1)
  inspect(merged[0], content="Value(\"1\")") // unchanged
  inspect(
    merged[1],
    content=(
      #|Stuck("‹unbound: missing›")
    ),
  ) // unchanged
  // Body: x is shadowed by stuck def → egglog can't resolve → Suppressed
  inspect(merged[2], content="Suppressed")
}

///|
test "escalation: stuck then recovered same-name binding" {
  // Codex bug: global blocked_names prevented recovery of re-bound names.
  // let x = missing      → Stuck
  // let x = 1            → Suppressed, but CAN be recovered (independent of first x)
  // x                    → Suppressed, should see x=1 from second binding
  let ast = @ast.Term::Module(
    [("x", @ast.Term::Var("missing")), ("x", @ast.Term::Int(1))],
    @ast.Term::Var("x"),
  )
  let tier1 = eval_term(ast)
  inspect(
    tier1[0],
    content=(
      #|Stuck("‹unbound: missing›")
    ),
  )
  inspect(tier1[1], content="Suppressed")
  inspect(tier1[2], content="Suppressed")
  let merged = escalate_suppressed(ast, tier1)
  inspect(
    merged[0],
    content=(
      #|Stuck("‹unbound: missing›")
    ),
  ) // stays stuck
  inspect(merged[1], content="Value(\"1\")") // second x=1 recovered
  inspect(merged[2], content="Value(\"1\")") // body sees x=1
}

///|
test "escalation: arithmetic expression resolved via egglog" {
  // let a = 10
  // let b = ?            → Suppressed (hole)
  // let c = a - 3        → Suppressed by Tier 1
  // c                     → Suppressed by Tier 1
  //
  // Escalation: c = 10 - 3 = 7
  let ast = @ast.Term::Module(
    [
      ("a", @ast.Term::Int(10)),
      ("b", @ast.Term::Hole(0)),
      ("c", @ast.Term::Bop(Minus, @ast.Term::Var("a"), @ast.Term::Int(3))),
    ],
    @ast.Term::Var("c"),
  )
  let tier1 = eval_term(ast)
  let merged = escalate_suppressed(ast, tier1)
  inspect(merged[0], content="Value(\"10\")")
  inspect(merged[1], content="Suppressed") // hole
  inspect(merged[2], content="Value(\"7\")") // c = a - 3 = 7
  inspect(merged[3], content="Value(\"7\")") // body = c = 7
}

///|
test "escalation: def depends on stuck → stays suppressed" {
  // let x = ?
  // let y = x + 1     → depends on x which is stuck
  // y
  let ast = @ast.Term::Module(
    [
      ("x", @ast.Term::Hole(0)),
      ("y", @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(1))),
    ],
    @ast.Term::Var("y"),
  )
  let tier1 = eval_term(ast)
  let merged = escalate_suppressed(ast, tier1)
  inspect(merged[0], content="Suppressed") // x = ? (hole)
  inspect(merged[1], content="Suppressed") // y needs x → unresolved
  inspect(merged[2], content="Suppressed") // body needs y → unresolved
}

///|
test "escalation: closure in partial env" {
  // let f = λx. x + 1
  // let y = ?
  // let z = f 5         → Suppressed by Tier 1
  // z
  //
  // Escalation: z = f 5 = 6. The partial env must correctly seed the
  // closure value for f.
  let ast = @ast.Term::Module(
    [
      (
        "f",
        @ast.Term::Lam(
          "x",
          @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(1)),
        ),
      ),
      ("y", @ast.Term::Hole(0)),
      ("z", @ast.Term::App(@ast.Term::Var("f"), @ast.Term::Int(5))),
    ],
    @ast.Term::Var("z"),
  )
  let tier1 = eval_term(ast)
  inspect(
    tier1[0],
    content=(
      #|Value("‹closure›")
    ),
  )
  inspect(tier1[1], content="Suppressed")
  inspect(tier1[2], content="Suppressed")
  inspect(tier1[3], content="Suppressed")
  let merged = escalate_suppressed(ast, tier1)
  inspect(
    merged[0],
    content=(
      #|Value("‹closure›")
    ),
  )
  inspect(merged[1], content="Suppressed") // hole
  inspect(merged[2], content="Value(\"6\")") // f 5 = 6
  inspect(merged[3], content="Value(\"6\")") // body = z = 6
}

///|
test "escalation: multi-round forward propagation" {
  // let a = 10
  // let b = ?            → Suppressed (hole)
  // let c = a + 1        → Suppressed, resolves in round 1 → 11
  // let d = c + 1        → Suppressed, resolves in round 2 → 12 (needs c from round 1)
  // d                    → Suppressed, resolves in round 3 → 12
  let ast = @ast.Term::Module(
    [
      ("a", @ast.Term::Int(10)),
      ("b", @ast.Term::Hole(0)),
      ("c", @ast.Term::Bop(Plus, @ast.Term::Var("a"), @ast.Term::Int(1))),
      ("d", @ast.Term::Bop(Plus, @ast.Term::Var("c"), @ast.Term::Int(1))),
    ],
    @ast.Term::Var("d"),
  )
  let tier1 = eval_term(ast)
  inspect(tier1[0], content="Value(\"10\")")
  inspect(tier1[1], content="Suppressed") // hole
  inspect(tier1[2], content="Suppressed") // c
  inspect(tier1[3], content="Suppressed") // d
  inspect(tier1[4], content="Suppressed") // body
  let merged = escalate_suppressed(ast, tier1)
  inspect(merged[0], content="Value(\"10\")")
  inspect(merged[1], content="Suppressed") // hole stays
  inspect(merged[2], content="Value(\"11\")") // c = a+1 = 11
  inspect(merged[3], content="Value(\"12\")") // d = c+1 = 12
  inspect(merged[4], content="Value(\"12\")") // body = d = 12
}

///|
test "escalation: non-module term unchanged" {
  let ast = @ast.Term::Int(42)
  let tier1 = eval_term(ast)
  let merged = escalate_suppressed(ast, tier1)
  inspect(merged[0], content="Value(\"42\")")
}
