# Switch Editor to source_file_grammar Implementation Plan

**Status:** Complete

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch the CRDT editor from right-recursive `lambda_grammar` to flat `source_file_grammar` for O(1) incremental parsing per edit instead of O(n).

**Architecture:** Replace grammar reference, AST conversion function, and projection root handler. Add `source_file_to_proj_node` that right-folds flat LetDef children into nested Let ProjNodes. Update benchmarks and tests to use newline-delimited format. `parse_to_proj_node` stays on `lambda_grammar` (sub-expression parsing).

**Tech Stack:** MoonBit, loom parser framework, seam CST

**Breaking change:** Document text format changes from `let x = 0 in let y = 0 in body` to `let x = 0\nlet y = 0\nbody`.

**Dual-format note:** `source_file_grammar` accepts both formats. `let x = 0 in body` parses as `LetExpr` (right-recursive, same as `lambda_grammar`); `let x = 0\nbody` parses as `LetDef` (flat, incremental-friendly). This means `print_term`'s `let...in` output is still valid — it just produces `LetExpr` nodes, handled by existing `LetExprView` paths. The incremental benefit only manifests when text uses newline-delimited format.

**Dual-grammar note:** `parse_to_proj_node` stays on `lambda_grammar` deliberately — it's only used for sub-expression parsing within the tree lens (never whole documents).

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `projection/proj_node.mbt` | Modify (lines 105-323) | Add `source_file_to_proj_node`, keep `parse_to_proj_node` on `lambda_grammar` |
| `editor/sync_editor.mbt` | Modify (lines 25, 198) | Switch grammar + AST conversion |
| `editor/projection_memo.mbt` | Modify (lines 30-32) | Use `source_file_to_proj_node` |
| `editor/performance_benchmark.mbt` | Modify (lines 10-17) | Newline-delimited test input |
| `projection/proj_node_test.mbt` | Create | Test `source_file_to_proj_node` |

---

### Task 1: Add `source_file_to_proj_node` to projection

**Files:**
- Modify: `projection/proj_node.mbt` (after line 226, before `unwrap_expression_root`)
- Create: `projection/proj_node_test.mbt`

- [ ] **Step 1: Write tests for `source_file_to_proj_node`**

Create `projection/proj_node_test.mbt`:

```moonbit
///|
test "source_file_to_proj_node: single expression" {
  let ip = @loom.new_imperative_parser("42", @parser.source_file_grammar)
  let syntax = ip.parse()
  let proj = source_file_to_proj_node(syntax, Ref::new(0))
  inspect(proj.kind, content="Int(42)")
}

///|
test "source_file_to_proj_node: single let def + expression" {
  let ip = @loom.new_imperative_parser(
    "let x = 1\nx",
    @parser.source_file_grammar,
  )
  let syntax = ip.parse()
  let proj = source_file_to_proj_node(syntax, Ref::new(0))
  inspect(proj.kind, content="Let(\"x\", Int(1), Var(\"x\"))")
  inspect(proj.children.length(), content="2")
}

///|
test "source_file_to_proj_node: multiple let defs" {
  let ip = @loom.new_imperative_parser(
    "let x = 1\nlet y = 2\nx + y",
    @parser.source_file_grammar,
  )
  let syntax = ip.parse()
  let proj = source_file_to_proj_node(syntax, Ref::new(0))
  inspect(
    proj.kind,
    content="Let(\"x\", Int(1), Let(\"y\", Int(2), Bop(Plus, Var(\"x\"), Var(\"y\"))))",
  )
}

///|
test "source_file_to_proj_node: no final expression defaults to Unit" {
  let ip = @loom.new_imperative_parser(
    "let x = 1\n",
    @parser.source_file_grammar,
  )
  let syntax = ip.parse()
  let proj = source_file_to_proj_node(syntax, Ref::new(0))
  inspect(proj.kind, content="Let(\"x\", Int(1), Unit)")
}
```

- [ ] **Step 2: Run tests — expect compile error**

Run: `moon test -p dowdiness/crdt/projection -f proj_node_test.mbt`
Expected: FAIL — `source_file_to_proj_node` not found

- [ ] **Step 3: Implement `source_file_to_proj_node`**

Add to `projection/proj_node.mbt` after line 226 (after the `syntax_to_proj_node` function, before `is_term_expression_node`):

```moonbit
///|
/// Convert a SourceFile SyntaxNode (LetDef* Expression?) to a ProjNode tree.
/// Right-folds LetDef children into nested Let(name, init, body) ProjNodes,
/// mirroring `syntax_node_to_source_file_term` but preserving spans and IDs.
pub fn source_file_to_proj_node(
  root : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode {
  let defs : Array[(String, ProjNode, @seam.SyntaxNode)] = []
  let mut final_proj : ProjNode? = None
  for child in root.children() {
    if @parser.LetDefView::cast(child) is Some(v) {
      let init = match v.init() {
        Some(n) => syntax_to_proj_node(n, counter)
        None => error_node_for_syntax("missing let binding value", child, counter)
      }
      defs.push((v.name(), init, child))
    } else if final_proj is None {
      final_proj = Some(syntax_to_proj_node(child, counter))
    }
  }
  let mut result = match final_proj {
    Some(p) => p
    None =>
      ProjNode::new(
        Unit,
        root.end(),
        root.end(),
        next_proj_node_id(counter),
        [],
      )
  }
  for i = defs.length() - 1; i >= 0; i = i - 1 {
    let (name, init, def_node) = defs[i]
    result = ProjNode::new(
      Let(name, init.kind, result.kind),
      def_node.start(),
      result.end,
      next_proj_node_id(counter),
      [init, result],
    )
  }
  result
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `moon test -p dowdiness/crdt/projection -f proj_node_test.mbt`
Expected: PASS (may need `moon test --update` for snapshot content)

- [ ] **Step 5: Run all projection tests**

Run: `moon test -p dowdiness/crdt/projection`
Expected: All existing tests still pass (they use `parse_to_proj_node` which stays on `lambda_grammar`)

- [ ] **Step 6: Update interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 7: Commit**

```bash
git add projection/proj_node.mbt projection/proj_node_test.mbt projection/pkg.generated.mbti
git commit -m "feat(projection): add source_file_to_proj_node for flat LetDef* structure"
```

---

### Task 2: Switch SyncEditor grammar and AST conversion

**Files:**
- Modify: `editor/sync_editor.mbt` (lines 25, 198)
- Modify: `editor/projection_memo.mbt` (lines 30-32)

- [ ] **Step 1: Switch grammar in SyncEditor::new**

In `editor/sync_editor.mbt` line 25, change:
```moonbit
// Old:
let parser = @loom.new_imperative_parser("", @parser.lambda_grammar)
// New:
let parser = @loom.new_imperative_parser("", @parser.source_file_grammar)
```

- [ ] **Step 2: Switch AST conversion in get_ast**

In `editor/sync_editor.mbt` line 198, change:
```moonbit
// Old:
@parser.syntax_node_to_term(syntax_node)
// New:
@parser.syntax_node_to_source_file_term(syntax_node)
```

- [ ] **Step 3: Switch projection_memo to source_file_to_proj_node**

In `editor/projection_memo.mbt` lines 30-32, change:
```moonbit
// Old:
let expr_root = @proj.unwrap_expression_root(syntax_root)
let counter = Ref::new(next_id_ref.val)
let new_proj = @proj.syntax_to_proj_node(expr_root, counter)

// New:
let counter = Ref::new(next_id_ref.val)
let new_proj = @proj.source_file_to_proj_node(syntax_root, counter)
```

- [ ] **Step 4: Run editor tests**

Run: `moon test -p dowdiness/crdt/editor`
Expected: All tests pass. Existing tests use simple expressions (no let chains) which parse identically under `source_file_grammar`.

- [ ] **Step 5: Run full test suite**

Run: `moon test`
Expected: All pass. The `crdt_test.mbt` also uses simple expressions.

- [ ] **Step 6: Format and update interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 7: Commit**

```bash
git add editor/sync_editor.mbt editor/projection_memo.mbt editor/pkg.generated.mbti
git commit -m "feat(editor): switch to source_file_grammar for O(1) incremental edits"
```

---

### Task 3: Update performance benchmarks

**Files:**
- Modify: `editor/performance_benchmark.mbt` (lines 10-17)

- [ ] **Step 1: Change test input to newline-delimited LetDefs**

In `editor/performance_benchmark.mbt`, replace `parser_bench_source` (lines 10-17):

```moonbit
///|
fn parser_bench_source(let_count : Int, tail_literal : String) -> String {
  let segments : Array[String] = []
  for i = 0; i < let_count - 1; i = i + 1 {
    segments.push("let x\{i} = 0")
  }
  segments.push("let x\{let_count - 1} = \{tail_literal}")
  segments.push("x\{let_count - 1}")
  segments.join("\n")
}
```

- [ ] **Step 2: Switch grammar references in benchmarks**

Replace all `@parser.lambda_grammar` with `@parser.source_file_grammar` in `performance_benchmark.mbt` (lines 36, 55, 80, 101):

```moonbit
// In each benchmark test, change:
@parser.lambda_grammar
// To:
@parser.source_file_grammar
```

- [ ] **Step 3: Run benchmarks to verify they work**

Run: `moon test -p dowdiness/crdt/editor -f performance_benchmark.mbt`
Expected: Tests compile and pass (benchmarks run as tests with no-op bench harness).

- [ ] **Step 4: Commit**

```bash
git add editor/performance_benchmark.mbt
git commit -m "perf(editor): update benchmarks to source_file_grammar format"
```

---

### Task 4: Verify end-to-end and run benchmarks

- [ ] **Step 1: Run full test suite**

Run: `moon test`
Expected: All tests pass across all packages.

- [ ] **Step 2: Run benchmarks**

Run: `moon bench --release -p dowdiness/crdt/editor -f performance_benchmark.mbt`
Expected: Benchmarks complete. With flat LetDef structure, incremental should now be competitive with or faster than full reparse.

- [ ] **Step 3: Format and final check**

Run: `moon info && moon fmt && moon check`

- [ ] **Step 4: Final commit if needed**

If any formatting changes occurred, stage specific changed files and commit:
```bash
git commit -m "chore: format after source_file_grammar switch"
```
