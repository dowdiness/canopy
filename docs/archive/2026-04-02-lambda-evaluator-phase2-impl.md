# Lambda Direct Evaluator — Implementation Plan (Phase 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tree-walking evaluator for the lambda calculus that handles all `Term` variants with fuel-limited divergence protection.

**Architecture:** Recursive `eval` function over the `Term` enum with an immutable environment (`Map[String, Value]`). Returns `Value!StuckReason` using MoonBit's error type system. ~80-100 lines of implementation code, plus ~150 lines of tests.

**Tech Stack:** MoonBit, `dowdiness/lambda` module (`loom/examples/lambda/`)

**Design spec:** `docs/plans/2026-04-02-lambda-evaluator-design.md` (Phase 2, Tier 1)

---

## File Structure

```
loom/examples/lambda/src/eval/
├── moon.pkg              # Package config — imports ast
├── eval.mbt              # Value, StuckReason, Env, eval function
├── eval_test.mbt         # Blackbox tests: arithmetic, beta, let, if, module
└── eval_wbtest.mbt       # Whitebox tests: fuel, error nodes, edge cases
```

One new package: `dowdiness/lambda/eval`. Three files total.

---

### Task 1: Create Package and Define Types

**Files:**
- Create: `loom/examples/lambda/src/eval/moon.pkg`
- Create: `loom/examples/lambda/src/eval/eval.mbt`

- [ ] **Step 1: Create `moon.pkg`**

```json
{
  "import": [
    "dowdiness/lambda/ast"
  ]
}
```

- [ ] **Step 2: Define Value, StuckReason, and Env types in `eval.mbt`**

```moonbit
///|
pub(all) enum Value {
  VInt(Int)
  VClosure(Env, @ast.VarName, @ast.Term)
  VUnit
} derive(Show, Eq, Debug)

///|
pub(all) type! StuckReason {
  Unbound(@ast.VarName)
  TypeMismatch(String)
  Incomplete
  ParseError
  Divergence
} derive(Show)

///|
pub(all) struct Env {
  bindings : Map[String, Value]
} derive(Show, Eq)

///|
pub fn Env::empty() -> Env {
  { bindings: {} }
}

///|
pub fn Env::lookup(self : Env, name : String) -> Value? {
  self.bindings.get(name)
}

///|
pub fn Env::extend(self : Env, name : String, value : Value) -> Env {
  let new_bindings = self.bindings
  new_bindings[name] = value
  { bindings: new_bindings }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd loom/examples/lambda && moon check`
Expected: no errors

- [ ] **Step 4: Commit**

```bash
cd loom/examples/lambda && moon info && moon fmt
git add loom/examples/lambda/src/eval/
git commit -m "feat(lambda): add eval package with Value, StuckReason, Env types"
```

---

### Task 2: Implement Core Eval Function — Literals and Variables

**Files:**
- Modify: `loom/examples/lambda/src/eval/eval.mbt`
- Create: `loom/examples/lambda/src/eval/eval_test.mbt`

- [ ] **Step 1: Write failing tests for literals and variables**

Create `loom/examples/lambda/src/eval/eval_test.mbt`:

```moonbit
///|
test "eval: integer literal" {
  let term = @ast.Term::Int(42)
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(42))")
}

///|
test "eval: unit literal" {
  let term = @ast.Term::Unit
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VUnit)")
}

///|
test "eval: variable lookup" {
  let env = Env::empty().extend("x", VInt(5))
  let term = @ast.Term::Var("x")
  let result = @eval.eval(env, term)
  inspect(result, content="Ok(VInt(5))")
}

///|
test "eval: unbound variable" {
  let term = @ast.Term::Var("x")
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Err(Unbound(\"x\"))")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/eval`
Expected: FAIL — `eval` function not defined

- [ ] **Step 3: Implement eval for Int, Unit, Var, Hole, Error, Unbound**

Add to `loom/examples/lambda/src/eval/eval.mbt`:

```moonbit
///|
pub fn eval(
  env : Env,
  term : @ast.Term,
  fuel~ : Int = 1000,
) -> Value!StuckReason {
  if fuel <= 0 {
    raise Divergence
  }
  match term {
    Int(n) => VInt(n)
    Unit => VUnit
    Var(x) =>
      match env.lookup(x) {
        Some(v) => v
        None => raise Unbound(x)
      }
    Hole(_) => raise Incomplete
    Error(_) => raise ParseError
    Unbound(x) => raise Unbound(x)
    Lam(x, body) => VClosure(env, x, body)
    _ => raise TypeMismatch("not yet implemented")
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/eval`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
cd loom/examples/lambda && moon check && moon info && moon fmt
git add loom/examples/lambda/src/eval/
git commit -m "feat(lambda/eval): implement eval for literals, variables, and error nodes"
```

---

### Task 3: Implement Arithmetic (Bop)

**Files:**
- Modify: `loom/examples/lambda/src/eval/eval.mbt`
- Modify: `loom/examples/lambda/src/eval/eval_test.mbt`

- [ ] **Step 1: Write failing tests for arithmetic**

Append to `eval_test.mbt`:

```moonbit
///|
test "eval: addition" {
  let term = @ast.Term::Bop(Plus, @ast.Term::Int(2), @ast.Term::Int(3))
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(5))")
}

///|
test "eval: subtraction" {
  let term = @ast.Term::Bop(Minus, @ast.Term::Int(10), @ast.Term::Int(3))
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(7))")
}

///|
test "eval: nested arithmetic" {
  // (2 + 3) - 1
  let term = @ast.Term::Bop(
    Minus,
    @ast.Term::Bop(Plus, @ast.Term::Int(2), @ast.Term::Int(3)),
    @ast.Term::Int(1),
  )
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(4))")
}

///|
test "eval: add non-integer is type error" {
  let term = @ast.Term::Bop(Plus, @ast.Term::Lam("x", @ast.Term::Var("x")), @ast.Term::Int(1))
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Err(TypeMismatch(\"add: expected integer\"))")
}
```

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/eval`
Expected: FAIL on new arithmetic tests

- [ ] **Step 3: Add Bop case to eval**

Replace the `_ => raise TypeMismatch("not yet implemented")` arm in `eval.mbt`, adding the `Bop` case before it:

```moonbit
    Bop(op, a, b) => {
      let va = eval!(env, a, fuel=fuel - 1)
      let vb = eval!(env, b, fuel=fuel - 1)
      match (op, va, vb) {
        (Plus, VInt(na), VInt(nb)) => VInt(na + nb)
        (Minus, VInt(na), VInt(nb)) => VInt(na - nb)
        (Plus, _, _) => raise TypeMismatch("add: expected integer")
        (Minus, _, _) => raise TypeMismatch("minus: expected integer")
      }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/eval`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
cd loom/examples/lambda && moon check && moon info && moon fmt
git add loom/examples/lambda/src/eval/
git commit -m "feat(lambda/eval): implement arithmetic (Bop Plus/Minus)"
```

---

### Task 4: Implement If-Then-Else

**Files:**
- Modify: `loom/examples/lambda/src/eval/eval.mbt`
- Modify: `loom/examples/lambda/src/eval/eval_test.mbt`

- [ ] **Step 1: Write failing tests for conditionals**

Append to `eval_test.mbt`:

```moonbit
///|
test "eval: if truthy (non-zero)" {
  let term = @ast.Term::If(@ast.Term::Int(1), @ast.Term::Int(2), @ast.Term::Int(3))
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(2))")
}

///|
test "eval: if falsy (zero)" {
  let term = @ast.Term::If(@ast.Term::Int(0), @ast.Term::Int(2), @ast.Term::Int(3))
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(3))")
}

///|
test "eval: if with negative is truthy" {
  let term = @ast.Term::If(@ast.Term::Int(-1), @ast.Term::Int(10), @ast.Term::Int(20))
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(10))")
}

///|
test "eval: if non-integer condition is type error" {
  let term = @ast.Term::If(@ast.Term::Lam("x", @ast.Term::Var("x")), @ast.Term::Int(1), @ast.Term::Int(2))
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Err(TypeMismatch(\"if: expected integer condition\"))")
}
```

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/eval`
Expected: FAIL on conditional tests

- [ ] **Step 3: Add If case to eval**

Add before the catch-all arm in `eval.mbt`:

```moonbit
    If(cond, then_branch, else_branch) => {
      let vc = eval!(env, cond, fuel=fuel - 1)
      match vc {
        VInt(0) => eval!(env, else_branch, fuel=fuel - 1)
        VInt(_) => eval!(env, then_branch, fuel=fuel - 1)
        _ => raise TypeMismatch("if: expected integer condition")
      }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/eval`
Expected: PASS (12 tests)

- [ ] **Step 5: Commit**

```bash
cd loom/examples/lambda && moon check && moon info && moon fmt
git add loom/examples/lambda/src/eval/
git commit -m "feat(lambda/eval): implement if-then-else (0=falsy, nonzero=truthy)"
```

---

### Task 5: Implement Application (App) and Lambda

**Files:**
- Modify: `loom/examples/lambda/src/eval/eval.mbt`
- Modify: `loom/examples/lambda/src/eval/eval_test.mbt`

- [ ] **Step 1: Write failing tests for application**

Append to `eval_test.mbt`:

```moonbit
///|
test "eval: lambda creates closure" {
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let result = @eval.eval(Env::empty(), term)
  // Closure captures empty env
  inspect(
    result,
    content="Ok(VClosure({bindings: {}}, \"x\", Var(\"x\")))",
  )
}

///|
test "eval: simple application" {
  // (λx. x + 1) 5
  let term = @ast.Term::App(
    @ast.Term::Lam("x", @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(1))),
    @ast.Term::Int(5),
  )
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(6))")
}

///|
test "eval: curried application" {
  // (λx. λy. x + y) 2 3
  let term = @ast.Term::App(
    @ast.Term::App(
      @ast.Term::Lam(
        "x",
        @ast.Term::Lam("y", @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Var("y"))),
      ),
      @ast.Term::Int(2),
    ),
    @ast.Term::Int(3),
  )
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(5))")
}

///|
test "eval: apply non-function is type error" {
  let term = @ast.Term::App(@ast.Term::Int(5), @ast.Term::Int(3))
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Err(TypeMismatch(\"app: expected function\"))")
}

///|
test "eval: closure captures environment" {
  // let five = 5 in let add_five = λx. x + five in let five = 6 in add_five 1
  // Should evaluate to 6 (lexical scoping: add_five closes over five=5)
  let term = @ast.Term::Module(
    [
      ("five", @ast.Term::Int(5)),
      ("add_five", @ast.Term::Lam("x", @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Var("five")))),
      ("five", @ast.Term::Int(6)),
    ],
    @ast.Term::App(@ast.Term::Var("add_five"), @ast.Term::Int(1)),
  )
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(6))")
}
```

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/eval`
Expected: FAIL on application tests

- [ ] **Step 3: Add App case to eval**

Add before the catch-all arm in `eval.mbt`:

```moonbit
    App(func, arg) => {
      let vf = eval!(env, func, fuel=fuel - 1)
      let va = eval!(env, arg, fuel=fuel - 1)
      match vf {
        VClosure(closure_env, param, body) => {
          let ext = closure_env.extend(param, va)
          eval!(ext, body, fuel=fuel - 1)
        }
        _ => raise TypeMismatch("app: expected function")
      }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/eval`
Expected: PASS (17 tests). Note: the closure-captures-environment test also needs Module support (Task 6). If it fails, that's expected — it will pass after Task 6.

- [ ] **Step 5: Commit**

```bash
cd loom/examples/lambda && moon check && moon info && moon fmt
git add loom/examples/lambda/src/eval/
git commit -m "feat(lambda/eval): implement function application with lexical closures"
```

---

### Task 6: Implement Module (Let-Bindings)

**Files:**
- Modify: `loom/examples/lambda/src/eval/eval.mbt`
- Modify: `loom/examples/lambda/src/eval/eval_test.mbt`

- [ ] **Step 1: Write failing tests for let-bindings**

Append to `eval_test.mbt`:

```moonbit
///|
test "eval: simple let binding" {
  // let x = 2 in x + x
  let term = @ast.Term::Module(
    [("x", @ast.Term::Int(2))],
    @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Var("x")),
  )
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(4))")
}

///|
test "eval: nested let bindings" {
  // let x = 1 in let y = 2 in x + y
  let term = @ast.Term::Module(
    [("x", @ast.Term::Int(1)), ("y", @ast.Term::Int(2))],
    @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Var("y")),
  )
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(3))")
}

///|
test "eval: let shadowing" {
  // let x = 1 in let x = 2 in x
  let term = @ast.Term::Module(
    [("x", @ast.Term::Int(1)), ("x", @ast.Term::Int(2))],
    @ast.Term::Var("x"),
  )
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(2))")
}

///|
test "eval: let with Unit body" {
  let term = @ast.Term::Module([("x", @ast.Term::Int(1))], @ast.Term::Unit)
  let result = @eval.eval(Env::empty(), term)
  inspect(result, content="Ok(VUnit)")
}
```

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/eval`
Expected: FAIL on let-binding tests

- [ ] **Step 3: Add Module case to eval**

Add before the catch-all arm in `eval.mbt`:

```moonbit
    Module(defs, body) => {
      let mut current_env = env
      for def in defs {
        let (name, expr) = def
        let v = eval!(current_env, expr, fuel=fuel - 1)
        current_env = current_env.extend(name, v)
      }
      eval!(current_env, body, fuel=fuel - 1)
    }
```

- [ ] **Step 4: Remove the catch-all arm**

The `_ => raise TypeMismatch("not yet implemented")` arm is no longer needed — all `Term` variants are now handled. Remove it. The match should be exhaustive.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/eval`
Expected: PASS (all tests including the closure-captures-environment test from Task 5)

- [ ] **Step 6: Commit**

```bash
cd loom/examples/lambda && moon check && moon info && moon fmt
git add loom/examples/lambda/src/eval/
git commit -m "feat(lambda/eval): implement Module (sequential let-bindings)"
```

---

### Task 7: Fuel Limit and Edge Cases

**Files:**
- Create: `loom/examples/lambda/src/eval/eval_wbtest.mbt`

- [ ] **Step 1: Write tests for fuel exhaustion and edge cases**

Create `loom/examples/lambda/src/eval/eval_wbtest.mbt`:

```moonbit
///|
test "eval: fuel exhaustion on omega combinator" {
  // (λx. x x)(λx. x x) — diverges
  let omega = @ast.Term::Lam("x", @ast.Term::App(@ast.Term::Var("x"), @ast.Term::Var("x")))
  let term = @ast.Term::App(omega, omega)
  let result = eval(Env::empty(), term, fuel=50)
  inspect(result, content="Err(Divergence)")
}

///|
test "eval: fuel works for deep but terminating computation" {
  // Nested application: ((λx.x) ((λx.x) ((λx.x) 42)))
  let id = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let term = @ast.Term::App(
    id,
    @ast.Term::App(id, @ast.Term::App(id, @ast.Term::Int(42))),
  )
  let result = eval(Env::empty(), term, fuel=100)
  inspect(result, content="Ok(VInt(42))")
}

///|
test "eval: Hole returns Incomplete" {
  let term = @ast.Term::Hole(0)
  let result = eval(Env::empty(), term)
  inspect(result, content="Err(Incomplete)")
}

///|
test "eval: Error node returns ParseError" {
  let term = @ast.Term::Error("missing expression")
  let result = eval(Env::empty(), term)
  inspect(result, content="Err(ParseError)")
}

///|
test "eval: Unbound node returns Unbound" {
  let term = @ast.Term::Unbound("foo")
  let result = eval(Env::empty(), term)
  inspect(result, content="Err(Unbound(\"foo\"))")
}

///|
test "eval: empty module with Unit body" {
  let term = @ast.Term::Module([], @ast.Term::Unit)
  let result = eval(Env::empty(), term)
  inspect(result, content="Ok(VUnit)")
}

///|
test "eval: module definition uses previous binding" {
  // let x = 2 in let y = x + 1 in y
  let term = @ast.Term::Module(
    [
      ("x", @ast.Term::Int(2)),
      ("y", @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(1))),
    ],
    @ast.Term::Var("y"),
  )
  let result = eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(3))")
}

///|
test "eval: if with computed condition" {
  // if (2 - 2) then 10 else 20  →  20 (condition is 0)
  let term = @ast.Term::If(
    @ast.Term::Bop(Minus, @ast.Term::Int(2), @ast.Term::Int(2)),
    @ast.Term::Int(10),
    @ast.Term::Int(20),
  )
  let result = eval(Env::empty(), term)
  inspect(result, content="Ok(VInt(20))")
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd loom/examples/lambda && moon test -p dowdiness/lambda/eval`
Expected: PASS (all tests)

- [ ] **Step 3: Run full module test suite to check nothing is broken**

Run: `cd loom/examples/lambda && moon test`
Expected: PASS (all existing tests + new eval tests)

- [ ] **Step 4: Commit**

```bash
cd loom/examples/lambda && moon check && moon info && moon fmt
git add loom/examples/lambda/src/eval/
git commit -m "test(lambda/eval): add fuel exhaustion, error nodes, and edge case tests"
```

---

### Task 8: Format, Interface Check, Final Verification

**Files:**
- Verify: all files in `loom/examples/lambda/src/eval/`

- [ ] **Step 1: Run moon info to update .mbti interface files**

Run: `cd loom/examples/lambda && moon info`

- [ ] **Step 2: Review the generated interface**

Run: `cat loom/examples/lambda/src/eval/pkg.generated.mbti`

Verify it exports:
- `enum Value` with `VInt`, `VClosure`, `VUnit`
- `type! StuckReason` with `Unbound`, `TypeMismatch`, `Incomplete`, `ParseError`, `Divergence`
- `struct Env` with `empty`, `lookup`, `extend`
- `fn eval(Env, Term, fuel~ : Int) -> Value!StuckReason`

- [ ] **Step 3: Run moon fmt**

Run: `cd loom/examples/lambda && moon fmt`

- [ ] **Step 4: Run full test suite one more time**

Run: `cd loom/examples/lambda && moon test`
Expected: PASS

- [ ] **Step 5: Run moon check for lint**

Run: `cd loom/examples/lambda && moon check`
Expected: no errors or warnings

- [ ] **Step 6: Final commit if any formatting changes**

```bash
git add loom/examples/lambda/src/eval/
git diff --cached --stat  # verify only eval/ files
git commit -m "chore(lambda/eval): format and update interfaces"
```

---

## Summary

| Task | What | Tests |
|------|------|-------|
| 1 | Types: Value, StuckReason, Env | compile check |
| 2 | eval: Int, Unit, Var, Hole, Error, Unbound, Lam | 4 tests |
| 3 | eval: Bop (Plus, Minus) | 4 tests |
| 4 | eval: If (0=falsy, nonzero=truthy) | 4 tests |
| 5 | eval: App (closure application) | 5 tests |
| 6 | eval: Module (sequential let-bindings) | 4 tests |
| 7 | Fuel exhaustion + edge cases | 8 tests |
| 8 | Format, interface, final verification | — |

Total: ~29 tests, ~80-100 lines of implementation, 3 new files.
