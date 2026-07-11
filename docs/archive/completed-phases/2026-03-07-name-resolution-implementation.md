# Name Resolution Implementation Plan

**Status:** Complete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add name resolution (bound/free variable analysis) for lambda calculus Terms, completing boundary ③ of the incremental hylomorphism pipeline as a prototype.

**Architecture:** Walk the `Term` AST with a scope environment, recording each `Var` node as bound or free. Output is a `Resolution` map keyed by pre-order traversal index (matching `TermDotNode` IDs). Visualization colors bound vars green, free vars red in the DOT output.

**Tech Stack:** MoonBit, loom/examples/lambda, editor module

---

### Task 1: Define Resolution types

**Files:**
- Create: `loom/examples/lambda/src/resolve.mbt`

**Step 1: Write the types and a stub `resolve` function**

```moonbit
// resolve.mbt — Name resolution for lambda calculus Terms.
// Maps each Var node to Bound(depth) or Free, keyed by pre-order traversal index.

///|
pub(all) enum VarStatus {
  Bound(depth~ : Int)
  Free
} derive(Show, Eq)

///|
pub(all) struct Resolution {
  vars : Map[Int, VarStatus]
} derive(Show, Eq)

///|
pub fn resolve(term : @ast.Term) -> Resolution {
  let res : Map[Int, VarStatus] = {}
  let env : Map[String, Int] = {}
  let counter = Ref::new(0)
  resolve_walk(term, env, 0, counter, res)
  { vars: res }
}

///|
fn resolve_walk(
  term : @ast.Term,
  env : Map[String, Int],
  depth : Int,
  counter : Ref[Int],
  res : Map[Int, VarStatus],
) -> Unit {
  let node_id = counter.val
  counter.val = counter.val + 1
  match term {
    @ast.Term::Var(x) =>
      match env.get(x) {
        Some(bind_depth) => res[node_id] = Bound(depth=depth - bind_depth)
        None => res[node_id] = Free
      }
    @ast.Term::Lam(x, body) => {
      let new_env = env.set(x, depth + 1)
      resolve_walk(body, new_env, depth + 1, counter, res)
    }
    @ast.Term::Let(x, val, body) => {
      resolve_walk(val, env, depth, counter, res)
      let new_env = env.set(x, depth + 1)
      resolve_walk(body, new_env, depth + 1, counter, res)
    }
    @ast.Term::App(f, a) => {
      resolve_walk(f, env, depth, counter, res)
      resolve_walk(a, env, depth, counter, res)
    }
    @ast.Term::Bop(_, l, r) => {
      resolve_walk(l, env, depth, counter, res)
      resolve_walk(r, env, depth, counter, res)
    }
    @ast.Term::If(c, t, e) => {
      resolve_walk(c, env, depth, counter, res)
      resolve_walk(t, env, depth, counter, res)
      resolve_walk(e, env, depth, counter, res)
    }
    _ => () // Int, Unit, Error — no children, no vars
  }
}
```

**Step 2: Verify it compiles**

Run: `cd loom/examples/lambda && moon check`
Expected: no errors

**Step 3: Commit**

```bash
git add loom/examples/lambda/src/resolve.mbt
git commit -m "feat(lambda): add name resolution types and resolve function"
```

---

### Task 2: Write tests for resolve

**Files:**
- Create: `loom/examples/lambda/src/resolve_wbtest.mbt`

**Step 1: Write tests covering key cases**

```moonbit
///|
test "resolve: free variable" {
  // x — free
  let term = @ast.Term::Var("x")
  let res = resolve(term)
  inspect(res.vars.get(0), content="Some(Free)")
}

///|
test "resolve: bound variable in lambda" {
  // λx. x — x is bound at depth 1
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let res = resolve(term)
  // node 0 = Lam (no var entry), node 1 = Var("x")
  inspect(res.vars.get(1), content="Some(Bound(depth=1))")
}

///|
test "resolve: free and bound in lambda" {
  // λx. (x + y) — x bound, y free
  // Pre-order: 0=Lam, 1=Bop, 2=Var(x), 3=Var(y)
  let term = @ast.Term::Lam(
    "x",
    @ast.Term::Bop(
      @ast.Bop::Plus,
      @ast.Term::Var("x"),
      @ast.Term::Var("y"),
    ),
  )
  let res = resolve(term)
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
  inspect(res.vars.get(3), content="Some(Free)")
}

///|
test "resolve: nested lambda shadows outer binding" {
  // λx. λx. x — inner x shadows outer, depth=1
  // Pre-order: 0=Lam(x), 1=Lam(x), 2=Var(x)
  let term = @ast.Term::Lam(
    "x",
    @ast.Term::Lam("x", @ast.Term::Var("x")),
  )
  let res = resolve(term)
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
}

///|
test "resolve: let binding" {
  // let x = 1 in x — x bound in body, not in initializer
  // Pre-order: 0=Let, 1=Int(1), 2=Var(x)
  let term = @ast.Term::Let(
    "x",
    @ast.Term::Int(1),
    @ast.Term::Var("x"),
  )
  let res = resolve(term)
  inspect(res.vars.get(1), content="None") // Int node, no var entry
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
}

///|
test "resolve: var in let initializer is free" {
  // let x = x in x — first x (in init) is free, second x (in body) is bound
  // Pre-order: 0=Let, 1=Var(x) init, 2=Var(x) body
  let term = @ast.Term::Let(
    "x",
    @ast.Term::Var("x"),
    @ast.Term::Var("x"),
  )
  let res = resolve(term)
  inspect(res.vars.get(1), content="Some(Free)")
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
}
```

**Step 2: Run tests**

Run: `cd loom/examples/lambda && moon test -f resolve_wbtest.mbt`
Expected: all tests pass. If snapshot mismatches, run `moon test --update` and verify the output is correct.

**Step 3: Commit**

```bash
git add loom/examples/lambda/src/resolve_wbtest.mbt
git commit -m "test(lambda): add name resolution tests"
```

---

### Task 3: Add colored DOT visualization

**Files:**
- Modify: `loom/examples/lambda/src/dot_node.mbt`

**Step 1: Write a test for colored output**

Add to `resolve_wbtest.mbt`:

```moonbit
///|
test "term_to_dot_resolved: colors bound green, free red" {
  // λx. (x + y)
  let term = @ast.Term::Lam(
    "x",
    @ast.Term::Bop(
      @ast.Bop::Plus,
      @ast.Term::Var("x"),
      @ast.Term::Var("y"),
    ),
  )
  let res = resolve(term)
  let dot = term_to_dot_resolved(term, res)
  // Bound var node should have green color
  inspect(dot.contains("#6a9955"), content="true")
  // Free var node should have red color
  inspect(dot.contains("#f44747"), content="true")
}
```

**Step 2: Run the test to verify it fails**

Run: `cd loom/examples/lambda && moon test -f resolve_wbtest.mbt`
Expected: FAIL — `term_to_dot_resolved` not defined

**Step 3: Implement `term_to_dot_resolved` in `dot_node.mbt`**

Add a new struct and function. The key change: `node_attrs` returns color attributes when a `Resolution` is present and the node is a `Var`.

Add to the bottom of `dot_node.mbt`:

```moonbit
///|
priv struct ResolvedTermDotNode {
  id : Int
  term : @ast.Term
  child_nodes : Array[ResolvedTermDotNode]
  resolution : Resolution
}

///|
impl @viz.DotNode for ResolvedTermDotNode with node_id(self) {
  self.id
}

///|
impl @viz.DotNode for ResolvedTermDotNode with label(self) {
  match self.term {
    @ast.Term::Int(n) => "Int(" + n.to_string() + ")"
    @ast.Term::Var(s) => "Var(" + s + ")"
    @ast.Term::Lam(s, _) => "Lam(" + s + ")"
    @ast.Term::App(_, _) => "App"
    @ast.Term::Bop(op, _, _) => "Bop(" + op.to_string() + ")"
    @ast.Term::If(_, _, _) => "If"
    @ast.Term::Let(s, _, _) => "Let(" + s + ")"
    @ast.Term::Unit => "Unit"
    @ast.Term::Error(msg) => "Error(" + msg + ")"
  }
}

///|
impl @viz.DotNode for ResolvedTermDotNode with node_attrs(self) {
  match self.resolution.vars.get(self.id) {
    Some(Bound(_)) =>
      "color=\"#6a9955\", fontcolor=\"#6a9955\""
    Some(Free) =>
      "color=\"#f44747\", fontcolor=\"#f44747\""
    None => ""
  }
}

///|
impl @viz.DotNode for ResolvedTermDotNode with children(self) {
  self.child_nodes
}

///|
impl @viz.DotNode for ResolvedTermDotNode with edge_label(_self, _i) {
  ""
}

///|
fn build_resolved_term_tree(
  term : @ast.Term,
  counter : Ref[Int],
  resolution : Resolution,
) -> ResolvedTermDotNode {
  let id = counter.val
  counter.val = counter.val + 1
  let child_nodes = match term {
    @ast.Term::Lam(_, body) =>
      [build_resolved_term_tree(body, counter, resolution)]
    @ast.Term::App(f, a) =>
      [
        build_resolved_term_tree(f, counter, resolution),
        build_resolved_term_tree(a, counter, resolution),
      ]
    @ast.Term::Bop(_, l, r) =>
      [
        build_resolved_term_tree(l, counter, resolution),
        build_resolved_term_tree(r, counter, resolution),
      ]
    @ast.Term::If(c, t, e) =>
      [
        build_resolved_term_tree(c, counter, resolution),
        build_resolved_term_tree(t, counter, resolution),
        build_resolved_term_tree(e, counter, resolution),
      ]
    @ast.Term::Let(_, v, body) =>
      [
        build_resolved_term_tree(v, counter, resolution),
        build_resolved_term_tree(body, counter, resolution),
      ]
    _ => []
  }
  { id, term, child_nodes, resolution }
}

///|
pub fn term_to_dot_resolved(
  term : @ast.Term,
  resolution : Resolution,
) -> String {
  let counter = Ref::new(0)
  let dot_tree = build_resolved_term_tree(term, counter, resolution)
  @viz.to_dot(dot_tree)
}
```

**Step 4: Run the test**

Run: `cd loom/examples/lambda && moon test -f resolve_wbtest.mbt`
Expected: all tests pass

**Step 5: Update interfaces and format**

Run: `cd loom/examples/lambda && moon info && moon fmt`

**Step 6: Commit**

```bash
git add loom/examples/lambda/src/dot_node.mbt loom/examples/lambda/src/resolve_wbtest.mbt
git add loom/examples/lambda/src/pkg.generated.mbti
git commit -m "feat(lambda): add colored DOT visualization for name resolution"
```

---

### Task 4: Wire into SyncEditor

**Files:**
- Modify: `editor/sync_editor.mbt`
- Modify: `editor/sync_editor_test.mbt`

**Step 1: Write a test**

Add to `editor/sync_editor_test.mbt`:

```moonbit
///|
test "SyncEditor: get_resolution returns bound/free info" {
  let se = SyncEditor::new("agent1")
  // λx. (x + y) — x is bound, y is free
  try! insert_each(se, "\\x. x + y")
  let res = se.get_resolution()
  // Pre-order: 0=Lam, 1=Bop, 2=Var(x), 3=Var(y)
  inspect(res.vars.get(2), content="Some(Bound(depth=1))")
  inspect(res.vars.get(3), content="Some(Free)")
}
```

**Step 2: Run the test to verify it fails**

Run: `moon test -f sync_editor_test.mbt -p dowdiness/canopy/editor`
Expected: FAIL — `get_resolution` not defined

**Step 3: Add `get_resolution` to `SyncEditor`**

Add to `editor/sync_editor.mbt` after `get_ast`:

```moonbit
///|
pub fn SyncEditor::get_resolution(self : SyncEditor) -> @parser.Resolution {
  @parser.resolve(self.get_ast())
}
```

**Step 4: Run the test**

Run: `moon test -f sync_editor_test.mbt -p dowdiness/canopy/editor`
Expected: all tests pass. If snapshot mismatches, run `moon test --update` and verify.

**Step 5: Also add `get_dot_resolved`**

Add to `editor/sync_editor.mbt`:

```moonbit
///|
pub fn SyncEditor::get_dot_resolved(self : SyncEditor) -> String {
  let ast = self.get_ast()
  let res = @parser.resolve(ast)
  @parser.term_to_dot_resolved(ast, res)
}
```

**Step 6: Update interfaces and format**

Run: `moon info && moon fmt`

**Step 7: Commit**

```bash
git add editor/sync_editor.mbt editor/sync_editor_test.mbt editor/pkg.generated.mbti
git commit -m "feat(editor): add get_resolution and get_dot_resolved to SyncEditor"
```

---

### Task 5: Run full test suite and finalize

**Step 1: Run all tests across the monorepo**

Run: `moon test`
Expected: all tests pass

Run: `cd loom/examples/lambda && moon test`
Expected: all tests pass (including new resolve tests)

**Step 2: Verify interfaces are clean**

Run: `moon info && moon fmt && git diff *.mbti`
Expected: no unexpected API changes

**Step 3: Final commit if any formatting changes**

```bash
git add -u && git commit -m "chore: format and update interfaces"
```
