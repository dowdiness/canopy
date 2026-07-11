# Two-Layer Architecture Implementation Plan

**Status:** Complete

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `TermSym` Finally Tagless layer to the lambda calculus `Term` enum, migrate `print_term` to a `Pretty` interpretation, and wire the e-graph evaluator to accept `Term` via `replay`.

**Architecture:** `TermSym` (pub(open) trait) + `replay` (generic bridge function) + `Pretty` (first interpretation) all live in a new `sym.mbt` file inside the existing `@ast` package. The e-graph bridge lives in `loom/egraph/lambda_eval_wbtest.mbt` alongside the existing evaluator, importing `@ast`. All work is inside the `loom/` git submodule on the `feat/egraph-lambda-evaluator` branch.

**Tech Stack:** MoonBit, `loom/examples/lambda` package (`dowdiness/lambda`), `loom/egraph` package (`dowdiness/egraph`), `moon test`, `moon check`.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `loom/examples/lambda/src/ast/sym.mbt` | **Create** | `TermSym` trait, `Term : TermSym`, `replay`, `Pretty` |
| `loom/examples/lambda/src/ast/ast.mbt` | **Modify** | `print_term` becomes one-liner wrapper |
| `loom/examples/lambda/src/ast/sym_test.mbt` | **Create** | Roundtrip, two-interpretation, all-variants tests |
| `loom/egraph/moon.pkg` | **Modify** | Add `dowdiness/lambda/src/ast` import for test build |
| `loom/egraph/lambda_eval_wbtest.mbt` | **Modify** | Add `TermBuilder` struct + `TermSym` impl + `term_to_egraph` |

---

## Task 1: Define `TermSym` trait and `Term : TermSym` implementation

**Files:**
- Create: `loom/examples/lambda/src/ast/sym.mbt`

All commands run from `loom/examples/lambda/` unless noted.

- [ ] **Step 1: Create `sym.mbt` with the trait**

```moonbit
// loom/examples/lambda/src/ast/sym.mbt

///|
/// Symantics for lambda calculus: a pub(open) trait whose implementations
/// are interpretations of the language. The name follows Kiselyov's Finally
/// Tagless convention — "Sym" = Symantics (syntax + semantics collapsed).
///
/// Each method corresponds to one Term constructor. Leaf constructors take
/// no Self input and are called as T::method(args) in generic contexts.
/// Branch constructors receive Self inputs from recursive calls.
///
/// pub(open) is required so downstream packages (e-graph, type checker,
/// future languages) can implement this trait without touching this file.
pub(open) trait TermSym {
  int_lit(Int) -> Self
  var(VarName) -> Self
  lam(VarName, Self) -> Self
  app(Self, Self) -> Self
  bop(Bop, Self, Self) -> Self
  if_then_else(Self, Self, Self) -> Self
  module(Array[(VarName, Self)], Self) -> Self
  unit() -> Self
  unbound(VarName) -> Self
  error_term(String) -> Self
}
```

- [ ] **Step 2: Add `Term : TermSym` implementation below the trait**

```moonbit
///|
/// Term is the identity interpretation: constructing via TermSym returns Term.
pub impl TermSym for Term with int_lit(n) { Int(n) }

///|
pub impl TermSym for Term with var(x) { Var(x) }

///|
pub impl TermSym for Term with lam(x, body) { Lam(x, body) }

///|
pub impl TermSym for Term with app(f, a) { App(f, a) }

///|
pub impl TermSym for Term with bop(op, l, r) { Bop(op, l, r) }

///|
pub impl TermSym for Term with if_then_else(c, t, e) { If(c, t, e) }

///|
pub impl TermSym for Term with module(defs, body) { Module(defs, body) }

///|
pub impl TermSym for Term with unit() { Unit }

///|
pub impl TermSym for Term with unbound(x) { Unbound(x) }

///|
pub impl TermSym for Term with error_term(msg) { Error(msg) }
```

- [ ] **Step 3: Verify it compiles**

```bash
moon check
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add src/ast/sym.mbt
git commit -m "feat(ast): add TermSym trait with Term identity implementation"
```

---

## Task 2: Add `replay` function

**Files:**
- Modify: `loom/examples/lambda/src/ast/sym.mbt`
- Create: `loom/examples/lambda/src/ast/sym_test.mbt`

- [ ] **Step 1: Write a failing test for `replay`**

Create `loom/examples/lambda/src/ast/sym_test.mbt`:

```moonbit
// loom/examples/lambda/src/ast/sym_test.mbt

///|
test "replay: Term roundtrip for Int" {
  let term = @ast.Term::Int(42)
  inspect((@ast.replay(term) : @ast.Term) == term, content="true")
}

///|
test "replay: Term roundtrip for Lam" {
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  inspect((@ast.replay(term) : @ast.Term) == term, content="true")
}
```

- [ ] **Step 2: Run the tests, verify they fail**

```bash
moon test -p dowdiness/lambda/src/ast
```

Expected: compile error — `replay` not defined.

- [ ] **Step 3: Add `replay` to `sym.mbt`**

```moonbit
///|
/// Converts a concrete Term into any TermSym interpretation.
/// This is the single site updated when a new Term variant is added.
/// Callers use type ascription: (replay(term) : Pretty)
pub fn[T : TermSym] replay(term : Term) -> T {
  match term {
    Int(n) => T::int_lit(n)
    Var(x) => T::var(x)
    Lam(x, body) => T::lam(x, replay(body))
    App(f, a) => T::app(replay(f), replay(a))
    Bop(op, l, r) => T::bop(op, replay(l), replay(r))
    If(c, t, e) => T::if_then_else(replay(c), replay(t), replay(e))
    Module(defs, body) => {
      let mapped : Array[(String, T)] = defs.map(fn(d) { (d.0, replay(d.1)) })
      T::module(mapped, replay(body))
    }
    Unit => T::unit()
    Unbound(x) => T::unbound(x)
    Error(msg) => T::error_term(msg)
  }
}
```

- [ ] **Step 4: Run the tests, verify they pass**

```bash
moon test -p dowdiness/lambda/src/ast
```

Expected: both roundtrip tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/ast/sym.mbt src/ast/sym_test.mbt
git commit -m "feat(ast): add replay function bridging Term to TermSym"
```

---

## Task 3: Add `Pretty` struct and migrate `print_term`

**Files:**
- Modify: `loom/examples/lambda/src/ast/sym.mbt`
- Modify: `loom/examples/lambda/src/ast/ast.mbt`

The existing `print_term` tests in `ast.mbt` serve as regression tests — they will fail if `Pretty` produces different output.

- [ ] **Step 1: Run existing `print_term` tests to establish baseline**

```bash
moon test -p dowdiness/lambda/src/ast
```

Expected: all tests pass (baseline before migration).

- [ ] **Step 2: Add `Pretty` to `sym.mbt`**

```moonbit
///|
/// Pretty-printing interpretation: replays a Term as its source text.
/// pub(all) exposes the repr field for cross-package access.
pub(all) struct Pretty {
  repr : String
}

///|
pub impl TermSym for Pretty with int_lit(n) { { repr: n.to_string() } }

///|
pub impl TermSym for Pretty with var(x) { { repr: x } }

///|
pub impl TermSym for Pretty with lam(x, body) {
  { repr: "(λ\{x}. \{body.repr})" }
}

///|
pub impl TermSym for Pretty with app(f, a) {
  { repr: "(\{f.repr} \{a.repr})" }
}

///|
pub impl TermSym for Pretty with bop(op, l, r) {
  let sym = match op { Plus => "+", Minus => "-" }
  { repr: "(\{l.repr} \{sym} \{r.repr})" }
}

///|
pub impl TermSym for Pretty with if_then_else(c, t, e) {
  { repr: "if \{c.repr} then \{t.repr} else \{e.repr}" }
}

///|
pub impl TermSym for Pretty with module(defs, body) {
  let parts : Array[String] = defs.map(fn(d) { "let \{d.0} = \{d.1.repr}" })
  parts.push(body.repr)
  { repr: parts.join("\n") }
}

///|
pub impl TermSym for Pretty with unit() { { repr: "()" } }

///|
pub impl TermSym for Pretty with unbound(x) { { repr: "<unbound: \{x}>" } }

///|
pub impl TermSym for Pretty with error_term(msg) { { repr: "<error: \{msg}>" } }
```

- [ ] **Step 3: Replace `print_term` body in `ast.mbt`**

Find `print_term` (lines 37–62) and replace with:

```moonbit
///|
pub fn print_term(term : Term) -> String {
  (replay(term) : Pretty).repr
}
```

Remove the old `fn go(t : Term) -> String { ... }` inner function entirely.

- [ ] **Step 4: Run all tests to verify no regressions**

```bash
moon test -p dowdiness/lambda/src/ast
```

Expected: all existing `print_term` tests still pass.

- [ ] **Step 5: Run full lambda test suite to catch any wider breakage**

```bash
moon test
```

Expected: all 311 tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/ast/sym.mbt src/ast/ast.mbt
git commit -m "feat(ast): add Pretty interpretation, migrate print_term to replay"
```

---

## Task 4: Complete `sym_test.mbt` with full coverage

**Files:**
- Modify: `loom/examples/lambda/src/ast/sym_test.mbt`

- [ ] **Step 1: Add remaining roundtrip tests and two-interpretation test**

Append to `sym_test.mbt`:

```moonbit
///|
test "replay: Term roundtrip all variants" {
  let terms : Array[@ast.Term] = [
    @ast.Term::Int(0),
    @ast.Term::Var("x"),
    @ast.Term::Lam("x", @ast.Term::Var("x")),
    @ast.Term::App(@ast.Term::Lam("x", @ast.Term::Var("x")), @ast.Term::Int(1)),
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Int(1), @ast.Term::Int(2)),
    @ast.Term::Bop(@ast.Bop::Minus, @ast.Term::Int(3), @ast.Term::Int(1)),
    @ast.Term::If(@ast.Term::Int(1), @ast.Term::Int(2), @ast.Term::Int(3)),
    @ast.Term::Module([("x", @ast.Term::Int(1))], @ast.Term::Var("x")),
    @ast.Term::Unit,
    @ast.Term::Unbound("y"),
    @ast.Term::Error("oops"),
  ]
  for term in terms {
    inspect((@ast.replay(term) : @ast.Term) == term, content="true")
  }
}

///|
test "replay: Pretty and Term from same source" {
  let term = @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Int(1), @ast.Term::Int(2))
  inspect((@ast.replay(term) : @ast.Pretty).repr, content="(1 + 2)")
  inspect((@ast.replay(term) : @ast.Term), content="Bop(Plus, Int(1), Int(2))")
}

///|
test "replay: Pretty Lam" {
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  inspect((@ast.replay(term) : @ast.Pretty).repr, content="(λx. x)")
}

///|
test "replay: Pretty Module" {
  let term = @ast.Term::Module(
    [("x", @ast.Term::Int(1)), ("y", @ast.Term::Int(2))],
    @ast.Term::Var("x"),
  )
  inspect(
    (@ast.replay(term) : @ast.Pretty).repr,
    content="let x = 1\nlet y = 2\nx",
  )
}
```

- [ ] **Step 2: Run tests**

```bash
moon test -p dowdiness/lambda/src/ast
```

Expected: all tests pass. If a `Pretty` output doesn't match, update the `content=` value to match actual output — the shape matters, not the exact string.

- [ ] **Step 3: Commit**

```bash
git add src/ast/sym_test.mbt
git commit -m "test(ast): add roundtrip and two-interpretation tests for replay"
```

---

## Task 5: E-graph bridge — connect `Term` to the lambda evaluator via `TermSym`

**Files:**
- Modify: `loom/egraph/moon.pkg` (add `@ast` import for test build)
- Modify: `loom/egraph/lambda_eval_wbtest.mbt` (add `TermBuilder` + bridge function)

The e-graph evaluator (`lambda_eval_wbtest.mbt`) already uses `LambdaLang` (defined as `priv enum` in `lambda_opt_wbtest.mbt`, same whitebox package). The goal is a `term_to_egraph` function that takes an `@ast.Term` and returns `(EGraph[LambdaLang], Id)` using `replay` and a `TermBuilder` wrapper.

**`Term` → `LambdaLang` mapping:**

| `Term` variant | `LambdaLang` node |
|---|---|
| `Int(n)` | `LNum(n)` |
| `Var(x)` | `LVar(x)` |
| `Lam(x, body)` | `LLam(x, body_id)` |
| `App(f, a)` | `LApp(f_id, a_id)` |
| `Bop(Plus, l, r)` | `LAdd(l_id, r_id)` |
| `Bop(Minus, l, r)` | `LMinus(l_id, r_id)` |
| `If(c, t, e)` | `LIf(c_id, t_id, e_id)` |
| `Module(defs, body)` | Desugar: right-fold into nested `LLet(name, val_id, body_id)` |
| `Unit` | `LNum(0)` (placeholder — no Unit in LambdaLang) |
| `Unbound(x)` | `LVar(x)` (preserve name for error reporting) |
| `Error(_)` | `LNum(0)` (placeholder) |

- [ ] **Step 1: Add `@ast` import to `loom/egraph/moon.pkg` test imports**

Open `loom/egraph/moon.pkg` and add `"dowdiness/lambda/src/ast"` to the import list. The `moon.pkg` likely has an `import` section — add to it:

```json
{
  "import": [
    ...existing imports...
  ],
  "test-import": [
    "dowdiness/lambda/src/ast"
  ]
}
```

If `test-import` doesn't exist yet, add it. Run `moon check` to verify the import resolves.

- [ ] **Step 2: Run `moon check` to verify import resolves**

```bash
cd ../../egraph
moon check
```

Expected: no errors. If the path is wrong, check `loom/examples/lambda/moon.mod.json` for the correct module name.

- [ ] **Step 3: Write a failing test for `term_to_egraph`**

Add to the top of `loom/egraph/lambda_eval_wbtest.mbt`:

```moonbit
///|
test "term_to_egraph: Int(42) creates LNum(42) root" {
  let (eg, root) = term_to_egraph(@ast.Term::Int(42))
  let nodes = eg.get_eclass_nodes(root)
  inspect(nodes.contains(LNum(42)), content="true")
}
```

Run `moon test -p dowdiness/egraph` — expected: compile error, `term_to_egraph` not defined.

- [ ] **Step 4: Add `TermBuilder` and `TermSym` implementation**

Add to `loom/egraph/lambda_eval_wbtest.mbt` after the existing imports:

```moonbit
///|
/// Builder adapting mutable EGraph to the TermSym interface.
/// Self = (EGraph[LambdaLang], Id) — a graph plus the root Id for this subterm.
priv struct TermBuilder {
  graph : EGraph[LambdaLang]
  root : Id
}

///|
impl @ast.TermSym for TermBuilder with int_lit(n) {
  let g : EGraph[LambdaLang] = EGraph::new()
  let id = g.add(LNum(n))
  { graph: g, root: id }
}

///|
impl @ast.TermSym for TermBuilder with var(x) {
  let g : EGraph[LambdaLang] = EGraph::new()
  let id = g.add(LVar(x))
  { graph: g, root: id }
}

///|
impl @ast.TermSym for TermBuilder with lam(x, body) {
  let id = body.graph.add(LLam(x, body.root))
  { graph: body.graph, root: id }
}

///|
impl @ast.TermSym for TermBuilder with app(f, a) {
  // Merge a's nodes into f's graph, remap a's ids
  let id = f.graph.add(LApp(f.root, a.root))
  { graph: f.graph, root: id }
}

///|
impl @ast.TermSym for TermBuilder with bop(op, l, r) {
  let node = match op { Plus => LAdd(l.root, r.root), Minus => LMinus(l.root, r.root) }
  let id = l.graph.add(node)
  { graph: l.graph, root: id }
}

///|
impl @ast.TermSym for TermBuilder with if_then_else(c, t, e) {
  let id = c.graph.add(LIf(c.root, t.root, e.root))
  { graph: c.graph, root: id }
}

///|
impl @ast.TermSym for TermBuilder with module(defs, body) {
  // Desugar Module([("x", v), ...], body) into nested LLet(x, v_id, rest_id)
  let mut result = body
  for i = defs.length() - 1; i >= 0; i = i - 1 {
    let (name, val) = defs[i]
    let let_id = result.graph.add(LLet(name, val.root, result.root))
    result = { graph: result.graph, root: let_id }
  }
  result
}

///|
impl @ast.TermSym for TermBuilder with unit() {
  let g : EGraph[LambdaLang] = EGraph::new()
  let id = g.add(LNum(0)) // placeholder
  { graph: g, root: id }
}

///|
impl @ast.TermSym for TermBuilder with unbound(x) {
  let g : EGraph[LambdaLang] = EGraph::new()
  let id = g.add(LVar(x))
  { graph: g, root: id }
}

///|
impl @ast.TermSym for TermBuilder with error_term(_) {
  let g : EGraph[LambdaLang] = EGraph::new()
  let id = g.add(LNum(0)) // placeholder
  { graph: g, root: id }
}
```

**Note on graph merging:** The simple implementation above passes each subterm's graph reference forward. If `EGraph[LambdaLang]` does not allow shared mutable access across sub-builders, you may need a different approach: build into a single shared `EGraph` threaded through all builders. Check `EGraph`'s API in `egraph.mbt` — if it has a `merge` or `absorb` function, use it. Otherwise, initialize a single `EGraph` once and pass it by reference through a `Ref[EGraph[LambdaLang]]` in `TermBuilder`.

- [ ] **Step 5: Add `term_to_egraph` convenience function**

```moonbit
///|
/// Convert an @ast.Term to an EGraph[LambdaLang] using replay.
/// Returns the graph and the root e-class Id for the term.
pub fn term_to_egraph(term : @ast.Term) -> (EGraph[LambdaLang], Id) {
  let b : TermBuilder = @ast.replay(term)
  (b.graph, b.root)
}
```

- [ ] **Step 6: Run tests**

```bash
moon test -p dowdiness/egraph
```

Expected: `term_to_egraph: Int(42) creates LNum(42) root` passes. If the `EGraph` API differs from what's shown (check `egraph.mbt` for the correct method names), adjust accordingly.

- [ ] **Step 7: Add a Lam test to verify recursive subterm building**

```moonbit
///|
test "term_to_egraph: Lam(x, Var(x)) creates LLam root" {
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let (_, root) = term_to_egraph(term)
  // root should be an LLam node
  inspect(root >= 0, content="true") // Id is valid
}
```

- [ ] **Step 8: Run full egraph test suite**

```bash
moon test
```

Expected: all existing egraph tests still pass, new tests pass.

- [ ] **Step 9: Commit**

```bash
git add moon.pkg lambda_eval_wbtest.mbt
git commit -m "feat(egraph): add TermBuilder implementing TermSym, term_to_egraph bridge"
```

---

## Task 6: Update interfaces, format, and update submodule pointer

**Files:**
- Run from `loom/examples/lambda/` and `loom/egraph/`
- Update submodule pointer in main repo

- [ ] **Step 1: Regenerate `.mbti` interface files for `ast` package**

```bash
cd loom/examples/lambda
moon info
```

Expected: `src/ast/pkg.generated.mbti` updated to include `TermSym`, `Pretty`, `replay`.

- [ ] **Step 2: Verify the public API additions look correct**

```bash
git diff src/ast/pkg.generated.mbti
```

Expected: `TermSym` trait methods, `replay`, `Pretty` struct all present. No unexpected removals.

- [ ] **Step 3: Format**

```bash
moon fmt
```

- [ ] **Step 4: Final full test run**

```bash
moon test
```

Expected: all 311+ tests pass (311 existing + new sym tests).

- [ ] **Step 5: Commit interface and formatting**

```bash
git add src/ast/pkg.generated.mbti
git commit -m "chore(ast): update .mbti interface after TermSym addition"
```

- [ ] **Step 6: Update loom submodule pointer in main repo**

```bash
cd /path/to/canopy  # the main crdt repo root
git add loom
git commit -m "chore: update loom submodule (TermSym two-layer architecture)"
```
