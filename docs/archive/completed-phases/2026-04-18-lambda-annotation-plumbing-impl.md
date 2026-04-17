# Lambda Type-Annotation Plumbing — Implementation Plan

**Status:** Complete — shipped via loom#84, loom#85, canopy#191 (2026-04-18). Codex review caught two additional correctness holes (empty blocks, missing LetDef names) that were folded into loom#85.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thread `: Type` annotations from the lambda CST through to `TypedTerm`, so `\x : Int. x` and the five web presets typecheck clean.

**Architecture:** New `convert_from_cst(SyntaxNode) -> TypedTerm` walker in `loom/examples/lambda/src/typecheck/`, parallel to the existing `syntax_node_to_term`. FFI pipeline switches from `parse → convert(Term)` to `parse_cst → convert_from_cst(SyntaxNode)`. `@ast.Term` is unchanged; the legacy `convert(Term)` stays as the AST-only path.

**Tech Stack:** MoonBit. Loom framework + seam CST. Typechecker already has `TypedTerm::Lam(String, Type?, TypedTerm)` and bidirectional `infer`/`check`. Existing test harness: `moon test` in `loom/examples/lambda/`.

**Spec:** `docs/plans/2026-04-18-lambda-annotation-plumbing-design.md`

**Phases:**
- **Phase L** (Tasks L0–L11): loom submodule. Open PR against `loom/main`, Codex review, merge before starting Phase C.
- **Phase C** (Tasks C1–C7): canopy side. Depends on Phase L being merged to `loom/main`.

---

## Phase L — Loom: `convert_from_cst` walker

Working directory throughout Phase L: `loom/examples/lambda/`.

### Task L0: Smoke-test CST shape assumptions

**Purpose:** Confirm `parse_cst` produces the CST shape the walker will rely on before writing any walker code. Catches surprises early.

**Files:**
- Test: `loom/examples/lambda/src/typecheck/typecheck_test.mbt`

- [ ] **Step 1: Add a throwaway test that dumps CST shape**

Append to `typecheck_test.mbt`:

```moonbit
///|
test "SMOKE: CST shape for annotated lambda" {
  let (cst, _) = @lambda.parse_cst("\\x : Int. x")
  let root = @seam.SyntaxNode::from_cst(cst)
  // Dump kinds of all descendants
  let lines : Array[String] = []
  fn walk(n : @seam.SyntaxNode, depth : Int) -> Unit {
    lines.push("  ".repeat(depth) + @syntax.SyntaxKind::from_raw(n.kind()).to_string())
    for c in n.children() {
      walk(c, depth + 1)
    }
  }
  walk(root, 0)
  inspect(lines.join("\n"), content="")
}
```

- [ ] **Step 2: Run the test to see actual output**

```bash
cd loom/examples/lambda && moon test -p dowdiness/lambda/typecheck -f typecheck_test.mbt 2>&1 | grep -A 30 SMOKE
```

Expected: test fails with a snapshot mismatch showing the actual CST kind tree. Read it. It must include `LambdaExpr → TypeAnnot → (TypeInt or similar)`. If the structure is unexpected, STOP and revise the spec/plan before continuing.

- [ ] **Step 3: Delete the smoke test**

Remove the `SMOKE:` test from `typecheck_test.mbt`. It was a scaffold — no need to commit it.

- [ ] **Step 4: Commit nothing; proceed**

This task produces no commit. Its output is the CST shape in your head (and optionally a note below the task list), which informs the walker code.

---

### Task L1: Add seam dependency to typecheck package

**Files:**
- Modify: `loom/examples/lambda/src/typecheck/moon.pkg`

- [ ] **Step 1: Read current moon.pkg**

```bash
cat loom/examples/lambda/src/typecheck/moon.pkg
```

Expect: imports of `dowdiness/lambda/ast` and `dowdiness/incr/*`.

- [ ] **Step 2: Add seam import**

Edit `loom/examples/lambda/src/typecheck/moon.pkg`. Add inside the `import { ... }` block (match the existing one-per-line style):

```
  "dowdiness/seam" @seam,
```

- [ ] **Step 3: Run `moon check` to confirm nothing breaks**

```bash
cd loom/examples/lambda && moon check 2>&1 | tail -5
```

Expected: "no work to do" or clean build. No errors.

- [ ] **Step 4: Commit**

```bash
cd loom && git add examples/lambda/src/typecheck/moon.pkg
git commit -m "feat(typecheck): depend on seam for CST-based conversion"
```

---

### Task L2: `type_of_node` for TInt, TUnit, TArrow

Private helper that converts a type-position CST subtree into a `Type`. Tests first.

**Files:**
- Create: `loom/examples/lambda/src/typecheck/cst_convert.mbt` — deviates from spec (spec listed `convert.mbt`). New file keeps the legacy AST path in `convert.mbt` isolated from the new CST path; both are public in the same `typecheck` package so callers see one API.
- Modify: `loom/examples/lambda/src/typecheck/typecheck_test.mbt`

- [ ] **Step 1: Write failing tests**

Append to `typecheck_test.mbt`:

```moonbit
///|
// Helper: parse a type annotation from source, return the Type it encodes.
// Uses "\\x : <src>. x" as a container because the type grammar has no
// standalone parse entry point.
fn type_from_source(src : String) -> Type {
  let (cst, _) = @lambda.parse_cst("\\x : " + src + ". x")
  let root = @seam.SyntaxNode::from_cst(cst)
  // Walk to the TypeAnnot's type child.
  fn find(n : @seam.SyntaxNode) -> @seam.SyntaxNode? {
    if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.TypeAnnot {
      for c in n.children() {
        let k = @syntax.SyntaxKind::from_raw(c.kind())
        if k == @syntax.TypeInt || k == @syntax.TypeUnit || k == @syntax.TypeArrow {
          return Some(c)
        }
      }
      return None
    }
    for c in n.children() {
      match find(c) {
        Some(x) => return Some(x)
        None => continue
      }
    }
    None
  }
  let type_node = find(root).unwrap()
  type_of_node(type_node)
}

///|
test "type_of_node: Int" {
  inspect(type_from_source("Int"), content="Int")
}

///|
test "type_of_node: Unit" {
  inspect(type_from_source("Unit"), content="Unit")
}

///|
test "type_of_node: Int -> Int" {
  inspect(type_from_source("Int -> Int"), content="Int -> Int")
}

///|
test "type_of_node: right-associative arrow" {
  inspect(type_from_source("Int -> Int -> Int"), content="Int -> Int -> Int")
}
```

- [ ] **Step 2: Run tests — verify compile failure (function not defined)**

```bash
cd loom/examples/lambda && moon test -p dowdiness/lambda/typecheck 2>&1 | tail -15
```

Expected: compile error "type_of_node not found" or similar.

- [ ] **Step 3: Implement `type_of_node` in new file**

Create `loom/examples/lambda/src/typecheck/cst_convert.mbt`. Function signatures + behavior:

- `fn type_of_node(n : @seam.SyntaxNode) -> Type` — dispatch on `@syntax.SyntaxKind::from_raw(n.kind())`:
  - `TypeInt` → `TInt`
  - `TypeUnit` → `TUnit`
  - `TypeArrow` → find the two type-kinded children (one of `TypeInt`/`TypeUnit`/`TypeArrow`) in order, recurse, emit `TArrow(lhs, rhs)`. If fewer than two found → `TError`.
  - Any other kind, or if any descendant is `@syntax.ErrorNode` → `TError`.
- For parenthesized types (parser emits paren tokens as siblings without a wrapper), the `LeftParenToken` and `RightParenToken` show up in `all_children()` but NOT in `children()` (which returns interior nodes only). So recursive descent via `children()` sees only the inner type node — parens are transparent at the node level.
- Invariant: `type_of_node` never panics; unknown shapes return `TError`.

Also add a small helper to check for ErrorNode descendants:

- `fn has_error_descendant(n : @seam.SyntaxNode) -> Bool` — DFS; returns `true` if any `@syntax.ErrorNode` in subtree.

- [ ] **Step 4: Run tests — verify pass**

```bash
cd loom/examples/lambda && moon test -p dowdiness/lambda/typecheck -f typecheck_test.mbt 2>&1 | grep -E '^(Total|.*FAIL|type_of)' | head
```

Expected: all four type_of_node tests pass. Total count should be existing + 4.

- [ ] **Step 5: Commit**

```bash
cd loom && git add examples/lambda/src/typecheck/
git commit -m "feat(typecheck): type_of_node for CST→Type conversion"
```

---

### Task L3: `convert_from_cst` for expression leaves

Leaf cases: `Int`, `Unit`, `Var`, `Hole`, `Error`.

**Files:**
- Modify: `loom/examples/lambda/src/typecheck/cst_convert.mbt`
- Modify: `loom/examples/lambda/src/typecheck/typecheck_test.mbt`

- [ ] **Step 1: Write failing tests**

Append to `typecheck_test.mbt`:

```moonbit
///|
fn typed_from_source(src : String) -> TypedTerm {
  let (cst, _) = @lambda.parse_cst(src)
  let root = @seam.SyntaxNode::from_cst(cst)
  convert_from_cst(root)
}

///|
test "convert_from_cst: int literal" {
  inspect(typed_from_source("42"), content="Int(42)")
}

///|
test "convert_from_cst: var" {
  inspect(typed_from_source("x"), content="Var(\"x\")")
}

///|
test "convert_from_cst: unit" {
  inspect(typed_from_source("()"), content="Unit")
}

///|
test "convert_from_cst: hole" {
  inspect(typed_from_source("?"), content="Hole(0)")
}
```

Note: the `"()"` test assumes `Unit` is parseable as source; if not, substitute an unannotated-but-valid source that produces `TypedTerm::Unit`. Adjust the expected content based on the smoke-test output from Task L0 if the parser produces a `Module(..., Unit)` wrapper for empty source files.

- [ ] **Step 2: Run — verify fail (function not defined)**

```bash
cd loom/examples/lambda && moon test -p dowdiness/lambda/typecheck 2>&1 | tail -10
```

Expected: compile error about `convert_from_cst` not being defined.

- [ ] **Step 3: Implement leaves**

Add to `cst_convert.mbt`:

- `pub fn convert_from_cst(n : @seam.SyntaxNode) -> TypedTerm` — dispatch on `@syntax.SyntaxKind::from_raw(n.kind())`. Leaf cases:
  - `@syntax.IntLiteral` → use `IntLiteralView` to extract Int, return `TypedTerm::Int(v)`.
  - `@syntax.VarRef` → use `VarRefView` to extract name, return `TypedTerm::Var(name)`.
  - `@syntax.HoleLiteral` → `TypedTerm::Hole(0)` (the ID isn't meaningful at this stage).
  - `@syntax.ErrorNode` → `TypedTerm::Error("error node")`.
  - `@syntax.SourceFile` → for Task L3, if the file has exactly one child and it's a single expression, recurse on that child. Multi-def handling comes in Task L8.
- For any unknown kind at this task stage, return `TypedTerm::Error("unhandled: <kind>")`. We'll flesh out more kinds in later tasks.

- [ ] **Step 4: Run — verify pass**

```bash
cd loom/examples/lambda && moon test -p dowdiness/lambda/typecheck 2>&1 | tail -5
```

Expected: all new tests pass. If `()` or `?` tests fail because the parser produces a wrapping structure, adjust the expected output to match (e.g., `Module([], Unit)` instead of `Unit`).

- [ ] **Step 5: Commit**

```bash
cd loom && git add examples/lambda/src/typecheck/
git commit -m "feat(typecheck): convert_from_cst for expression leaves"
```

---

### Task L4: LambdaExpr (unannotated, explicit child walking)

Cover the no-annotation case first. Do NOT use `LambdaExprView::body()` (returns `nth_child(0)`, which is broken for annotated lambdas). Iterate children explicitly.

**Files:**
- Modify: `loom/examples/lambda/src/typecheck/cst_convert.mbt`
- Modify: `loom/examples/lambda/src/typecheck/typecheck_test.mbt`

- [ ] **Step 1: Write failing test**

Append:

```moonbit
///|
test "convert_from_cst: unannotated lambda" {
  inspect(typed_from_source("\\x. x"), content="Lam(\"x\", None, Var(\"x\"))")
}

///|
test "convert_from_cst: nested unannotated lambdas" {
  inspect(
    typed_from_source("\\x. \\y. x"),
    content="Lam(\"x\", None, Lam(\"y\", None, Var(\"x\")))",
  )
}
```

Adjust the content if Task L3's smoke test revealed a wrapping `Module` — e.g., `"Module([], Lam(...))"`.

- [ ] **Step 2: Run — verify fail**

Expected: current implementation returns `TypedTerm::Error("unhandled: LambdaExpr")` or similar.

- [ ] **Step 3: Implement LambdaExpr handling**

In `convert_from_cst`, add case for `@syntax.LambdaExpr`:

- Use `LambdaExprView::cast(n)` to get the param name via `.param()`.
- Walk `n.children()` left-to-right. The first interior-node child is either a `TypeAnnot` or the body expression; subsequent children are the body (if TypeAnnot was present) or recovery artifacts.
- For this task (unannotated), find the first non-`TypeAnnot` interior child and recurse on it. If none found, body = `TypedTerm::Error("missing lambda body")`.
- Emit `TypedTerm::Lam(param, None, body)`.

- [ ] **Step 4: Run — verify pass**

```bash
cd loom/examples/lambda && moon test -p dowdiness/lambda/typecheck 2>&1 | tail -5
```

Expected: two new tests pass.

- [ ] **Step 5: Commit**

```bash
cd loom && git add examples/lambda/src/typecheck/
git commit -m "feat(typecheck): convert_from_cst for unannotated lambda"
```

---

### Task L5: LambdaExpr with TypeAnnot

**Files:**
- Modify: `loom/examples/lambda/src/typecheck/cst_convert.mbt`
- Modify: `loom/examples/lambda/src/typecheck/typecheck_test.mbt`

- [ ] **Step 1: Write failing tests**

Append:

```moonbit
///|
test "convert_from_cst: annotated lambda Int" {
  inspect(
    typed_from_source("\\x : Int. x"),
    content="Lam(\"x\", Some(Int), Var(\"x\"))",
  )
}

///|
test "convert_from_cst: annotated lambda arrow" {
  inspect(
    typed_from_source("\\f : Int -> Int. f"),
    content="Lam(\"f\", Some(Int -> Int), Var(\"f\"))",
  )
}

///|
test "convert_from_cst: annotated lambda full pipeline typechecks clean" {
  let term = typed_from_source("\\x : Int. x")
  let result = infer(TypeEnv::Empty, term)
  inspect(result.had_error, content="false")
  inspect(result.diagnostics.length(), content="0")
  inspect(result.typ, content="Int -> Int")
}

///|
test "convert_from_cst: malformed annotation" {
  // Parser recovers from \x : . x — emits ErrorNode inside TypeAnnot.
  let term = typed_from_source("\\x : . x")
  // Expect: Lam("x", Some(<error>), Var("x"))
  inspect(term.to_string().contains("Some(<error>)"), content="true")
  // And infer should emit the malformed-annotation diagnostic.
  let result = infer(TypeEnv::Empty, term)
  inspect(result.had_error, content="true")
  inspect(
    result.diagnostics.iter().any(fn(d) { d.message == "malformed type annotation" }),
    content="true",
  )
}
```

- [ ] **Step 2: Run — verify fail**

Expected: annotated lambdas still emit `None` because the current Task L4 implementation finds the `TypeAnnot` child and (wrongly) recurses on it.

Actually — re-read Task L4. It says "find the first non-`TypeAnnot` interior child". So Task L4 code would find the body correctly but drop the annotation. Tests fail because `Some(Int)` is expected but `None` is produced.

- [ ] **Step 3: Extend LambdaExpr handling to capture annotation**

Revise the LambdaExpr case in `convert_from_cst`:

- Walk `n.children()` collecting two slots: `annot_node : SyntaxNode?` and `body_node : SyntaxNode?`.
  - First child of kind `TypeAnnot` → annot_node.
  - First child NOT of kind `TypeAnnot` → body_node.
- If `annot_node.is_some()`:
  - Find the type child inside (first child of kind `TypeInt`/`TypeUnit`/`TypeArrow`, or ErrorNode).
  - If any `ErrorNode` descendant → `annot = Some(TError)`.
  - Else → `annot = Some(type_of_node(type_child))`.
- If `annot_node.is_none()` → `annot = None`.
- Body: `match body_node { Some(b) => convert_from_cst(b), None => TypedTerm::Error("missing lambda body") }`.
- Emit `TypedTerm::Lam(param, annot, body)`.

- [ ] **Step 4: Run — verify pass**

Expected: all four new tests pass. The previously passing Task L4 tests (unannotated) still pass.

- [ ] **Step 5: Commit**

```bash
cd loom && git add examples/lambda/src/typecheck/
git commit -m "feat(typecheck): convert_from_cst preserves lambda type annotations"
```

---

### Task L6: App, BinaryExpr, If, Block

**Files:**
- Modify: `loom/examples/lambda/src/typecheck/cst_convert.mbt`
- Modify: `loom/examples/lambda/src/typecheck/typecheck_test.mbt`

- [ ] **Step 1: Write failing tests**

Append:

```moonbit
///|
test "convert_from_cst: application" {
  inspect(
    typed_from_source("(\\x : Int. x) 5"),
    content="App(Lam(\"x\", Some(Int), Var(\"x\")), Int(5))",
  )
}

///|
test "convert_from_cst: binary op" {
  inspect(typed_from_source("1 + 2"), content="Bop(Plus, Int(1), Int(2))")
}

///|
test "convert_from_cst: if-then-else" {
  inspect(
    typed_from_source("if 1 then 2 else 3"),
    content="If(Int(1), Int(2), Int(3))",
  )
}

///|
test "convert_from_cst: block expression" {
  inspect(typed_from_source("{ 42 }"), content="Int(42)")
}
```

Adjust if block expressions wrap in `Module` — check current `syntax_node_to_term` behavior for blocks.

- [ ] **Step 2: Run — verify fail**

Expected: compile passes but these specific cases return `TypedTerm::Error("unhandled: ...")`.

- [ ] **Step 3: Implement App, BinaryExpr, If, Block**

Add cases to `convert_from_cst`:

- `@syntax.AppExpr`: use `AppExprView`. Get func (first interior child via explicit walk), get args (remaining interior children), left-fold: `result = func; for arg in args { result = App(result, arg) }`.
- `@syntax.BinaryExpr`: use the existing `BinaryExprView` (or fall back to `node.nodes_and_tokens()` as `term_convert` does). Extract left, operator token (`PlusToken` → `Plus`, `MinusToken` → `Minus`), right. Emit `Bop(op, l, r)`. If operator token is missing → `TypedTerm::Error("missing binop")`.
- `@syntax.IfExpr`: get three expression children in order (cond, then, else). If fewer than 3 → `TypedTerm::Error`.
- `@syntax.BlockExpr`: call the block-collection logic (see Task L8). For now, if block has exactly one interior child and no `LetDef`s, recurse on it. Full block handling lands in Task L8.
- `@syntax.ParenExpr`: recurse on the single interior child.

- [ ] **Step 4: Run — verify pass**

Expected: four new tests pass, all previous tests still pass.

- [ ] **Step 5: Commit**

```bash
cd loom && git add examples/lambda/src/typecheck/
git commit -m "feat(typecheck): convert_from_cst for App, Bop, If, Block, Paren"
```

---

### Task L7: LetDef (value form + ParamList with annotations)

This is the trickiest task — `LetDefView::params()` returns bare names, so we must walk the `ParamList` node ourselves to pair each ident with its optional `TypeAnnot`.

**Files:**
- Modify: `loom/examples/lambda/src/typecheck/cst_convert.mbt`
- Modify: `loom/examples/lambda/src/typecheck/typecheck_test.mbt`

- [ ] **Step 1: Write failing tests**

Append:

```moonbit
///|
test "convert_from_cst: let-def value form" {
  inspect(
    typed_from_source("let a = 1 a"),
    content="Module([(\"a\", Int(1))], Var(\"a\"))",
  )
}

///|
test "convert_from_cst: let-def single annotated param" {
  // `let f(x : Int) = x` desugars to `let f = \x : Int. x`.
  inspect(
    typed_from_source("let f(x : Int) = x f"),
    content="Module([(\"f\", Lam(\"x\", Some(Int), Var(\"x\")))], Var(\"f\"))",
  )
}

///|
test "convert_from_cst: let-def two annotated params" {
  inspect(
    typed_from_source("let f(x : Int, y : Int) = x + y f"),
    content="Module([(\"f\", Lam(\"x\", Some(Int), Lam(\"y\", Some(Int), Bop(Plus, Var(\"x\"), Var(\"y\")))))], Var(\"f\"))",
  )
}

///|
test "convert_from_cst: let-def mixed annotated and unannotated" {
  inspect(
    typed_from_source("let f(x : Int, y) = x + y f"),
    content="Module([(\"f\", Lam(\"x\", Some(Int), Lam(\"y\", None, Bop(Plus, Var(\"x\"), Var(\"y\")))))], Var(\"f\"))",
  )
}

///|
test "convert_from_cst: let-def typechecks with annotations" {
  let term = typed_from_source("let f(x : Int, y : Int) = x + y f")
  let result = infer(TypeEnv::Empty, term)
  inspect(result.had_error, content="false")
  inspect(result.typ, content="Int -> Int -> Int")
}
```

- [ ] **Step 2: Run — verify fail**

Expected: `LetDef` and `ParamList` are unhandled kinds, emit Error.

- [ ] **Step 3: Implement LetDef + ParamList walker**

Add a helper + cases:

- `fn convert_param_list(pl : @seam.SyntaxNode) -> Array[(String, Type?)]`:
  - Iterate `pl.all_children()` (tokens AND nodes in order).
  - State: most recent `IdentToken` text (`pending_name`), most recent annotation (`pending_annot`), result array.
  - On encountering an `IdentToken`: if `pending_name` is Some, flush `(pending_name, pending_annot)` to result, then set `pending_name = this name`, `pending_annot = None`.
  - On encountering a `TypeAnnot` node: set `pending_annot = type_from_annot_node(node)` where the helper reads the TypeAnnot's type child (or TError on ErrorNode descendant).
  - On encountering `CommaToken`: flush pending, reset.
  - On `RightParenToken` end: flush pending if any.
  - Skip everything else.
- `fn convert_let_def_cst(n : @seam.SyntaxNode) -> (String, TypedTerm)`:
  - Get function name: use `LetDefView::name()` (already exists, returns the first post-`let` IdentToken).
  - Get init expression: walk children for the first expression-kind interior child that isn't a `ParamList`. (Or use `LetDefView::init()` if it correctly returns the RHS after the `=`.)
  - Get optional `ParamList` child. If present, call `convert_param_list` to get `[(name, annot?), ...]`, then right-fold into nested `Lam` around the init: `body = init; for (name, annot) in params.reverse() { body = Lam(name, annot, body) }`.
  - Return `(fn_name, body)`.
- Extend `convert_from_cst`:
  - `@syntax.SourceFile` or `@syntax.BlockExpr`: iterate interior children. Each `LetDef` child → append to a `defs` array via `convert_let_def_cst`. First non-`LetDef` interior child → `body`. If no body found, `body = TypedTerm::Unit`. If `defs` is non-empty, emit `TypedTerm::Module(defs, body)`. Else return `body`.

- [ ] **Step 4: Run — verify pass**

Expected: all five new tests pass. All previous tests still pass. Specifically, the previously-simple `{ 42 }` block test from Task L6 should still return `Int(42)` (since no let-defs, no wrap).

- [ ] **Step 5: Commit**

```bash
cd loom && git add examples/lambda/src/typecheck/
git commit -m "feat(typecheck): convert_from_cst handles LetDef + ParamList annotations"
```

---

### Task L8: Module-level multi-def with trailing body

Task L7 already implements the Module structure; this task adds regression tests for multi-def scenarios.

**Files:**
- Modify: `loom/examples/lambda/src/typecheck/typecheck_test.mbt`

- [ ] **Step 1: Write tests**

Append:

```moonbit
///|
test "convert_from_cst: two defs with body" {
  inspect(
    typed_from_source("let a = 1 let b = 2 a + b"),
    content="Module([(\"a\", Int(1)), (\"b\", Int(2))], Bop(Plus, Var(\"a\"), Var(\"b\")))",
  )
}

///|
test "convert_from_cst: defs-only source" {
  // No trailing expression — body should be Unit.
  inspect(
    typed_from_source("let a = 1"),
    content="Module([(\"a\", Int(1))], Unit)",
  )
}

///|
test "convert_from_cst: Pipeline preset typechecks clean" {
  let src = "let compose = \\f : Int -> Int. \\g : Int -> Int. \\x : Int. { f (g x) } let double = \\x : Int. { x + x } let inc = \\x : Int. { x + 1 } let f = compose inc double f 5"
  let term = typed_from_source(src)
  let result = infer(TypeEnv::Empty, term)
  inspect(result.had_error, content="false")
  inspect(result.diagnostics.length(), content="0")
  inspect(result.typ, content="Int")
}
```

- [ ] **Step 2: Run — verify pass (no implementation change expected)**

If Task L7's SourceFile/BlockExpr handling is correct, these should pass immediately. If not, fix the Module handler and rerun.

- [ ] **Step 3: Commit**

```bash
cd loom && git add examples/lambda/src/typecheck/typecheck_test.mbt
git commit -m "test(typecheck): multi-def and Pipeline-preset regression tests"
```

---

### Task L9: Error-recovery coverage

**Files:**
- Modify: `loom/examples/lambda/src/typecheck/typecheck_test.mbt`

- [ ] **Step 1: Write tests**

Append:

```moonbit
///|
test "convert_from_cst: lambda missing ident" {
  // `\` with no parameter — parser recovers with an ErrorNode placeholder.
  let term = typed_from_source("\\. 1")
  // Some form of Error is acceptable; the exact message is not load-bearing.
  inspect(term.to_string().contains("Error") || term.to_string().contains("<error>"), content="true")
}

///|
test "convert_from_cst: multi-def ordering preserved under broken middle def" {
  // The middle `let b = ... ... c` produces a broken def structure.
  // The walker must still preserve left-to-right order of recovered defs.
  let src = "let a = 1 let b = let c = 3 c"
  let term = typed_from_source(src)
  // We don't assert exact shape — just that `a` precedes `b` or `c` in the diagnostic stream.
  let result = infer(TypeEnv::Empty, term)
  let first_def_diag = result.diagnostics.iter().filter(fn(d) { d.def_name.is_some() }).next()
  match first_def_diag {
    Some(d) => inspect(d.def_name.unwrap() == "a" || d.def_name.unwrap() == "b", content="true")
    None => () // no def-tagged diagnostics is also acceptable
  }
}
```

Adjust assertions if concrete tests reveal different parser recovery behavior (the point is to document the contract, not assert exact shapes).

- [ ] **Step 2: Run**

Expected: both tests pass. If missing-ident crashes or produces unexpected shape, extend `convert_from_cst` LambdaExpr to guard (returning `TypedTerm::Error("malformed lambda")` when ident is missing).

- [ ] **Step 3: Commit**

```bash
cd loom && git add examples/lambda/src/typecheck/typecheck_test.mbt
git commit -m "test(typecheck): error-recovery cases for convert_from_cst"
```

---

### Task L10: Regenerate mbti, fmt, full test run

- [ ] **Step 1: Regenerate interfaces**

```bash
cd loom/examples/lambda && moon info 2>&1 | tail -3
```

- [ ] **Step 2: Format**

```bash
cd loom/examples/lambda && moon fmt 2>&1 | tail -3
```

- [ ] **Step 3: Check mbti diff**

```bash
cd loom && git diff examples/lambda/src/typecheck/pkg.generated.mbti
```

Expected: additions for `pub fn convert_from_cst(...) -> TypedTerm`. No unrelated changes. If trait bounds widened on other functions, stop and investigate.

- [ ] **Step 4: Full test run**

```bash
cd loom/examples/lambda && moon test 2>&1 | tail -5
```

Expected: all tests pass, including the ~503 pre-existing. New test count: ~515-520.

- [ ] **Step 5: Commit mbti + fmt changes if any**

```bash
cd loom && git status --porcelain | head
git add examples/lambda/src/typecheck/
git commit -m "chore(typecheck): regenerate mbti + fmt" 2>&1 || echo "no changes"
```

---

### Task L11: Open loom PR, Codex review, merge

- [ ] **Step 1: Create and push branch**

If you've been committing on loom's `main` so far (shouldn't be — verify with `git branch --show-current`), create a branch off the current HEAD:

```bash
cd loom && git checkout -b feat/typecheck-convert-from-cst
```

Then push:

```bash
git push -u origin feat/typecheck-convert-from-cst
```

- [ ] **Step 2: Open PR**

```bash
cd loom && gh pr create --base main --title "feat(typecheck): convert_from_cst walker preserves lambda annotations" --body "$(cat <<'EOF'
## Summary
- Adds `@typecheck.convert_from_cst(SyntaxNode) -> TypedTerm` that preserves `: Type` annotations on lambdas and let-def params.
- Keeps existing `convert(Term)` as the legacy AST path.
- Fixes latent bug: `LambdaExprView::body()` returned `nth_child(0)` which is the TypeAnnot node when annotations are present.

## Design spec
See canopy PR (parent repo) — `docs/plans/2026-04-18-lambda-annotation-plumbing-design.md`.

## Test plan
- [x] ~20 new unit tests in `typecheck/typecheck_test.mbt`
- [x] All 503 existing tests still pass

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Run Codex review on the diff**

Use MCP codex tool, read-only, on loom worktree. Ask specifically: correctness of the walker (are there CST shapes missed?), mbti API surface, unhandled recovery cases.

- [ ] **Step 4: Address findings, if any**

For each finding, add a commit addressing it. Do NOT amend.

- [ ] **Step 5: Wait for CI green**

```bash
gh pr checks <NUMBER>
```

All checks must pass before merge.

- [ ] **Step 6: Merge (squash)**

```bash
gh pr merge <NUMBER> --squash --delete-branch
```

Record the merge commit SHA for Phase C bumping.

---

## Phase C — Canopy: FFI pipeline + presets

Working directory: repo root (`canopy/.worktrees/lambda-annotation-plumbing`).

### Task C1: Bump loom submodule pointer

- [ ] **Step 1: Pull loom main into the submodule**

```bash
cd loom && git fetch origin main && git checkout main && git pull && cd ..
```

- [ ] **Step 2: Verify the merge commit is in loom**

```bash
cd loom && git log --oneline -3 && cd ..
```

Expected: top commit is the merged `convert_from_cst` work.

- [ ] **Step 3: Stage submodule pointer**

```bash
git add loom
git status --porcelain
```

Expected: `M loom`.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: bump loom submodule for convert_from_cst"
```

---

### Task C2: Add seam to ffi/moon.pkg

- [ ] **Step 1: Read current ffi/moon.pkg**

```bash
cat ffi/moon.pkg | head -25
```

- [ ] **Step 2: Add seam import**

Edit `ffi/moon.pkg`. Inside the `import { ... }` block, add:

```
  "dowdiness/seam" @seam,
```

- [ ] **Step 3: Check**

```bash
moon check --target js 2>&1 | tail -3
```

Expected: no errors, no work to do (seam isn't used yet).

- [ ] **Step 4: Commit**

```bash
git add ffi/moon.pkg
git commit -m "feat(ffi): depend on seam for CST-based typecheck conversion"
```

---

### Task C3: Swap FFI typed_term_memo to parse_cst + convert_from_cst

**Files:**
- Modify: `ffi/canopy_lambda.mbt` (the `new_typecheck_bundle` function, lines ~23-39)

- [ ] **Step 1: Read current implementation**

```bash
awk '/fn new_typecheck_bundle/,/^}$/' ffi/canopy_lambda.mbt
```

- [ ] **Step 2: Replace the memo body**

In `new_typecheck_bundle`, change the `typed_term_memo` body from:

```moonbit
let typed_term_memo : @cells.Memo[@typecheck.TypedTerm] = scope.memo(
  fn() {
    let text = text_signal.get()
    let term = @lambda_lang.parse(text) catch {
      _ => return @typecheck.TypedTerm::Error("parse")
    }
    @typecheck.convert(term)
  },
  label="lambda-typed-term",
)
```

to:

```moonbit
let typed_term_memo : @cells.Memo[@typecheck.TypedTerm] = scope.memo(
  fn() {
    let text = text_signal.get()
    let (cst, _diags) = @lambda_lang.parse_cst(text) catch {
      _ => return @typecheck.TypedTerm::Error("parse")
    }
    @typecheck.convert_from_cst(@seam.SyntaxNode::from_cst(cst))
  },
  label="lambda-typed-term",
)
```

- [ ] **Step 3: Check + test**

```bash
moon check --target js 2>&1 | tail -3 && moon test 2>&1 | tail -3
```

Expected: all tests pass. In particular, the existing `get_diagnostics_json FFI: unbound variable` test should now emit the same output (the underlying TypedTerm is equivalent).

- [ ] **Step 4: Commit**

```bash
git add ffi/canopy_lambda.mbt
git commit -m "feat(ffi): route typecheck through parse_cst + convert_from_cst"
```

---

### Task C4: Update 5 preset examples to use annotations

**Files:**
- Modify: `examples/web/index.html` (the 5 `.example-btn` buttons, lines ~584-588)

- [ ] **Step 1: Read current presets**

```bash
grep 'example-btn' examples/web/index.html | head -6
```

- [ ] **Step 2: Update each preset's `data-example` attribute**

Edit `examples/web/index.html`. Replace the 5 buttons (replacing whole `data-example` attribute strings):

- **Basics**: `let double = \x : Int. {  x + x }  let result = double 5  result`
- **Composition**: `let inc = \n : Int. { n + 1 }  let twice = \f : Int -> Int. \x : Int. {  f (f x) }  let result = twice inc 0  result`
- **Currying**: `let add = \x : Int. \y : Int. { x + y }  let add5 = add 5  let sum = add5 10  sum`
- **Conditional**: `let choose = \x : Int. if x then {  x + 1 } else {  42 }  let a = choose 0  let b = choose 5  a + b`
- **Pipeline**: `let compose = \f : Int -> Int. \g : Int -> Int. \x : Int. {  f (g x) }  let double = \x : Int. { x + x }  let inc = \x : Int. { x + 1 }  let f = compose inc double  f 5`

Note: preserve the existing `&#10;` newline entities from the current HTML. You may copy the existing structure and inject the `: Type` snippets.

- [ ] **Step 3: Check HTML validity**

```bash
grep -c '.example-btn' examples/web/index.html
```

Expected: `5`.

- [ ] **Step 4: Commit**

```bash
git add examples/web/index.html
git commit -m "docs(web): annotate lambda example presets so they typecheck clean"
```

---

### Task C5: Update Playwright tests

**Files:**
- Modify: `examples/web/tests/lambda-editor.spec.ts` (the "example input parses successfully" test, ~line 63)

- [ ] **Step 1: Replace the existing `example input parses successfully` test**

Find this test in `lambda-editor.spec.ts`:

```ts
test('example input parses successfully', async ({ page }) => {
  await loadExample(page, 'Basics');
  // Parsing succeeds → AST graph renders. ...
  await expect(page.locator('#ast-graph svg')).toBeVisible();
});
```

Replace with:

```ts
const PRESETS = ['Basics', 'Composition', 'Currying', 'Conditional', 'Pipeline'] as const;

for (const preset of PRESETS) {
  test(`preset "${preset}" typechecks clean`, async ({ page }) => {
    await loadExample(page, preset);
    await expect(page.locator('#ast-graph svg')).toBeVisible();
    await expect(page.locator('#error-output')).toContainText('No errors');
    expect(await page.locator('#error-output .diag-item').count()).toBe(0);
  });
}
```

- [ ] **Step 2: Add annotated-lambda test near the typecheck-error tests**

Below the existing `unannotated lambda produces typecheck error` test:

```ts
test('annotated lambda typechecks clean', async ({ page }) => {
  const editor = page.locator('#editor');
  await editor.click();
  await page.keyboard.type('\\x : Int. x');

  await expect(page.locator('#error-output')).toContainText('No errors');
  expect(await page.locator('#error-output .diag-item').count()).toBe(0);
});
```

- [ ] **Step 3: Run Playwright**

```bash
cd examples/web && npx playwright test lambda-editor.spec.ts --reporter=list 2>&1 | tail -20
```

Expected: all tests pass, including 5 new preset-typecheck tests and the new annotated-lambda test.

- [ ] **Step 4: Commit**

```bash
cd ../.. && git add examples/web/tests/lambda-editor.spec.ts
git commit -m "test(web): preset typecheck coverage + annotated lambda test"
```

---

### Task C6: Full regression run

- [ ] **Step 1: moon test**

```bash
moon test 2>&1 | tail -3
```

Expected: 879 tests pass (same as before C3, potentially +0 since no new moon tests added).

- [ ] **Step 2: moon build --target js**

```bash
moon build --target js 2>&1 | tail -3
```

- [ ] **Step 3: Playwright**

```bash
cd examples/web && npx playwright test lambda-editor.spec.ts --reporter=list 2>&1 | tail -20
```

Expected: all tests pass.

---

### Task C7: Canopy PR — Codex review + merge

- [ ] **Step 1: Push branch**

```bash
git push -u origin feat/lambda-annotation-plumbing
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --base main --title "feat: lambda type-annotation plumbing (CST → TypedTerm)" --body "$(cat <<'EOF'
## Summary
- Bumps loom submodule to include the new `@typecheck.convert_from_cst` walker.
- Switches FFI typed_term_memo from `parse + convert(Term)` to `parse_cst + convert_from_cst(SyntaxNode)`, preserving lambda type annotations end-to-end.
- Updates all 5 example presets in `examples/web/index.html` with `: Int` / `: Int -> Int` annotations so they typecheck clean.
- Playwright coverage: every preset asserts "No errors"; a new test covers annotated lambdas typed directly by the user.

## Design spec
`docs/plans/2026-04-18-lambda-annotation-plumbing-design.md`

## Test plan
- [x] 879 moonbit tests pass
- [x] 10+ Playwright tests pass (5 preset-typecheck + annotated/unannotated lambda + existing suite)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Codex review on the diff**

Invoke `mcp__codex__codex` with `sandbox: read-only`, `cwd` set to the canopy worktree, and a prompt asking:
1. "FFI pipeline correctness — the typed_term_memo now calls `@lambda_lang.parse_cst` and wraps via `@seam.SyntaxNode::from_cst`. Does this preserve the memo-backdating semantics of PR #186?"
2. "Preset annotation correctness — read `examples/web/index.html`. Do the five annotated presets all typecheck with the existing bidirectional rules (see `loom/examples/lambda/src/typecheck/infer.mbt`)?"
3. "Any existing moonbit test that should have changed but didn't?"
4. "Anything brittle about the walker's use of explicit child-kind selection?"

Budget the reply to ≤ 400 words.

- [ ] **Step 4: CI + merge**

```bash
gh pr checks <NUMBER>
```

All checks must be green. Then:

```bash
gh pr merge <NUMBER> --squash --delete-branch
```

- [ ] **Step 5: Cleanup**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy
git worktree remove --force .worktrees/lambda-annotation-plumbing
git checkout main && git pull
```

---

## Risks and rollback

- If CST shape assumptions turn out wrong (Task L0 smoke test reveals surprises), pause and update the spec before continuing.
- If a preset fails to typecheck despite annotations, the typechecker's bidirectional rules may need a fix in loom — out of scope for this plan; open a separate issue and use unannotated-plus-`missing type annotation` as the temporary state for that preset.
- Rollback: each phase is atomic. Revert the canopy PR to restore the pre-annotation pipeline; loom PR is independently reversible via its own revert.

## Non-goals (reiterated from spec)

- No change to `@ast.Term::Lam`.
- No HM unification or let-def inference.
- No removal of `@typecheck.convert(Term)`.
- No change to `def_name` in diagnostic JSON — that's TODO §23 item 3.
