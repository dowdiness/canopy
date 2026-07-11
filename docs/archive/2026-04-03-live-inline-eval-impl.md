# Live Inline Evaluation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show evaluation results (`→ 10`) next to definitions in both pretty-print and structural views, computed reactively as the user types.

**Architecture:** An eval memo in the editor layer evaluates the AST per keystroke. Pretty-print view post-processes the canonical Layout to inject eval annotations (no formatting duplication). Structural view attaches `ViewAnnotation` to ViewNode. Both flow through the existing ViewPatch pipeline. Annotation changes trigger `ReplaceNode` patches (no `UpdateNode` extension needed).

**Tech Stack:** MoonBit (editor/, protocol/, loom/pretty), TypeScript (lib/editor-adapter/, examples/web/), `@incr.Memo` for reactive eval.

**Design doc:** `docs/plans/2026-04-03-live-inline-eval-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `loom/pretty/ann.mbt` | Modify | Add `EvalAnnotation`, `EvalError` to `SyntaxCategory` |
| `protocol/formatted_view.mbt` | Modify | Extend `category_to_role` for new categories |
| `protocol/view_node.mbt` | Modify | Add `ViewAnnotation` struct + `annotations` field on `ViewNode` |
| `editor/eval_memo.mbt` | Create | `EvalResult` enum, `eval_term`, `build_eval_memo`, `render_value`, `split_at_hardlines`, `inject_eval_annotations` |
| `editor/eval_memo_test.mbt` | Create | Unit tests for eval memo |
| `editor/eval_memo_wbtest.mbt` | Create | Whitebox tests for layout injection + structural annotations |
| `editor/sync_editor.mbt` | Modify | Add `eval_memo` field to `SyncEditor` |
| `editor/sync_editor_pretty.mbt` | Modify | Use eval results in `get_pretty_view` |
| `editor/view_updater.mbt` | Modify | Diff annotations in `diff_view_nodes`; lambda-specific `get_view_tree` |
| `protocol/convert.mbt` | Modify | Accept optional annotations in `proj_to_view_node` |
| `editor/moon.pkg` | Modify | Add `dowdiness/lambda/eval` import |
| `lib/editor-adapter/types.ts` | Modify | Add `annotations` to `ViewNode` TS type |
| `lib/editor-adapter/html-adapter.ts` | Modify | Render annotations on structural nodes |
| `examples/web/index.html` | Modify | CSS for `.eval-annotation`, `.eval-error`, `.annotation-eval` |

---

### Task 1: Add `EvalAnnotation` and `EvalError` to `SyntaxCategory`

**Files:**
- Modify: `loom/pretty/ann.mbt`
- Modify: `protocol/formatted_view.mbt`

- [ ] **Step 1: Add variants to `SyntaxCategory`**

In `loom/pretty/ann.mbt`, add two variants at the end of the enum:

```moonbit
///|
pub(all) enum SyntaxCategory {
  Keyword
  Identifier
  Number
  StringLit
  Operator
  Punctuation
  Comment
  Error
  EvalAnnotation
  EvalError
} derive(Show, Eq)
```

- [ ] **Step 2: Extend `category_to_role` in formatted_view**

In `protocol/formatted_view.mbt`, add the new cases to the match in `category_to_role`:

```moonbit
    EvalAnnotation => "eval-annotation"
    EvalError => "eval-error"
```

- [ ] **Step 3: Run checks**

```bash
cd loom/loom && moon check && cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon check
```

Expected: both pass.

- [ ] **Step 4: Update interfaces and format**

```bash
cd loom/loom && moon info && moon fmt && cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon info && moon fmt
```

- [ ] **Step 5: Commit**

```bash
git add loom protocol/formatted_view.mbt
git commit -m "feat(pretty): add EvalAnnotation and EvalError to SyntaxCategory"
```

---

### Task 2: Add `ViewAnnotation` and `annotations` field to `ViewNode`

**Files:**
- Modify: `protocol/view_node.mbt`
- Modify: `lib/editor-adapter/types.ts`

- [ ] **Step 1: Add `ViewAnnotation` struct**

Add before the `ViewNode` struct in `protocol/view_node.mbt`:

```moonbit
///|
pub(all) struct ViewAnnotation {
  kind : String
  label : String
  severity : String

  fn new(kind~ : String, label~ : String, severity? : String) -> ViewAnnotation
} derive(Show, Eq)

///|
pub fn ViewAnnotation::new(
  kind~ : String,
  label~ : String,
  severity? : String = "info",
) -> ViewAnnotation {
  { kind, label, severity }
}

///|
pub impl ToJson for ViewAnnotation with to_json(self) {
  let m : Map[String, Json] = {}
  m["kind"] = self.kind.to_json()
  m["label"] = self.label.to_json()
  m["severity"] = self.severity.to_json()
  Json::object(m)
}
```

- [ ] **Step 2: Add `annotations` field to `ViewNode`**

Add the field to the struct, the `new` declaration inside, and the `new` implementation:

In the struct body, add after `children`:
```moonbit
  annotations : Array[ViewAnnotation]
```

In the `new` declaration inside the struct, add:
```moonbit
    annotations? : Array[ViewAnnotation],
```

In the `ViewNode::new` implementation, add parameter and default:
```moonbit
  annotations? : Array[ViewAnnotation] = [],
```

And include `annotations` in the struct literal.

- [ ] **Step 3: Add `annotations` to `ViewNode::to_json`**

In the `ToJson` impl for `ViewNode`, add after the `children` line:

```moonbit
  m["annotations"] = Json::array(self.annotations.map(fn(a) { a.to_json() }))
```

- [ ] **Step 4: Update TS types**

In `lib/editor-adapter/types.ts`, add to the `ViewNode` type:

```typescript
export type ViewNode = {
  id: number;
  kind_tag: string;
  label: string;
  text: string | null;
  text_range: [number, number];
  token_spans: { role: string; start: number; end: number }[];
  editable: boolean;
  css_class: string;
  children: ViewNode[];
  annotations: { kind: string; label: string; severity: string }[];
};
```

- [ ] **Step 5: Run `moon check`**

```bash
moon check
```

Expected: pass. Existing callers use named args — `annotations` defaults to `[]`.

- [ ] **Step 6: Update interfaces and format**

```bash
moon info && moon fmt
```

- [ ] **Step 7: Commit**

```bash
git add protocol/view_node.mbt lib/editor-adapter/types.ts
git commit -m "feat(protocol): add ViewAnnotation struct and annotations field to ViewNode"
```

---

### Task 3: Create eval memo with tests (TDD)

**Files:**
- Modify: `editor/moon.pkg` (add eval import)
- Create: `editor/eval_memo.mbt`
- Create: `editor/eval_memo_test.mbt`

- [ ] **Step 1: Add eval import to editor package**

In `editor/moon.pkg`, add to the import list:

```
  "dowdiness/lambda/eval" @eval,
```

- [ ] **Step 2: Run `moon check` to verify import resolves**

```bash
moon check
```

Expected: pass.

- [ ] **Step 3: Write the failing tests**

Create `editor/eval_memo_test.mbt`:

```moonbit
///|
test "eval_term: simple module with arithmetic" {
  let results = eval_term(
    @ast.Term::Module(
      [("x", @ast.Term::Int(5)), ("y", @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(3)))],
      @ast.Term::Var("y"),
    ),
  )
  // 3 results: def x, def y, body
  inspect!(results.length(), content="3")
  inspect!(results[0], content="Value(\"5\")")
  inspect!(results[1], content="Value(\"8\")")
  inspect!(results[2], content="Value(\"8\")")
}

///|
test "eval_term: unbound variable is Stuck" {
  let results = eval_term(@ast.Term::Var("missing"))
  inspect!(results.length(), content="1")
  inspect!(results[0], content="Stuck(\"\\u{2039}unbound: missing\\u{203a}\")")
}

///|
test "eval_term: hole is Suppressed" {
  let results = eval_term(@ast.Term::Hole(0))
  inspect!(results.length(), content="1")
  inspect!(results[0], content="Suppressed")
}

///|
test "eval_term: parse error is Suppressed" {
  let results = eval_term(@ast.Term::Error("bad"))
  inspect!(results.length(), content="1")
  inspect!(results[0], content="Suppressed")
}

///|
test "eval_term: closure renders correctly" {
  let results = eval_term(
    @ast.Term::Module(
      [("f", @ast.Term::Lam("x", @ast.Term::Var("x")))],
      @ast.Term::Var("f"),
    ),
  )
  inspect!(results[0], content="Value(\"\\u{2039}closure\\u{203a}\")")
}

///|
test "eval_term: divergence is Stuck" {
  let omega = @ast.Term::App(
    @ast.Term::Lam("x", @ast.Term::App(@ast.Term::Var("x"), @ast.Term::Var("x"))),
    @ast.Term::Lam("x", @ast.Term::App(@ast.Term::Var("x"), @ast.Term::Var("x"))),
  )
  let results = eval_term(omega)
  inspect!(results[0], content="Stuck(\"\\u{2039}diverges\\u{203a}\")")
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
  // def a = Stuck, defs b and c = Suppressed, body = Suppressed
  inspect!(results.length(), content="4")
  inspect!(results[0], content="Stuck(\"\\u{2039}unbound: missing\\u{203a}\")")
  inspect!(results[1], content="Suppressed")
  inspect!(results[2], content="Suppressed")
  inspect!(results[3], content="Suppressed")
}

///|
test "eval_term: unit value" {
  let results = eval_term(@ast.Term::Unit)
  inspect!(results[0], content="Value(\"()\")")
}
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
moon test -p dowdiness/canopy/editor -f eval_memo_test.mbt
```

Expected: FAIL — `eval_term` not defined.

- [ ] **Step 5: Implement the eval memo**

Create `editor/eval_memo.mbt`:

```moonbit
// Eval Memo: Reactive evaluation of lambda terms with result rendering.

///|
pub(all) enum EvalResult {
  Value(String)
  Stuck(String)
  Suppressed
} derive(Show, Eq)

///|
fn render_value(v : @eval.Value) -> String {
  match v {
    @eval.Value::VInt(n) => n.to_string()
    @eval.Value::VClosure(_, _, _) => "\u{2039}closure\u{203a}"
    @eval.Value::VUnit => "()"
  }
}

///|
fn render_stuck(reason : @eval.StuckReason) -> EvalResult {
  match reason {
    Incomplete => Suppressed
    ParseError => Suppressed
    Unbound(name) => Stuck("\u{2039}unbound: " + name + "\u{203a}")
    TypeMismatch(msg) => Stuck("\u{2039}type error: " + msg + "\u{203a}")
    Divergence => Stuck("\u{2039}diverges\u{203a}")
  }
}

///|
/// Evaluate a term and return per-definition results.
/// For Module(defs, body): one result per def + one for body.
/// For non-Module: one result for the whole expression.
pub fn eval_term(term : @ast.Term) -> Array[EvalResult] {
  let results : Array[EvalResult] = []
  match term {
    Module(defs, body) => {
      let mut env = @eval.Env::empty()
      for def in defs {
        let (name, expr) = def
        try {
          let v = @eval.eval(env, expr)
          results.push(Value(render_value(v)))
          env = env.extend(name, v)
        } catch {
          reason => {
            results.push(render_stuck(reason))
            // Stop evaluating — env is incomplete
            for _ in 0..<(defs.length() - results.length()) {
              results.push(Suppressed)
            }
            results.push(Suppressed) // body
            return results
          }
        }
      }
      // Evaluate body
      try {
        let v = @eval.eval(env, body)
        results.push(Value(render_value(v)))
      } catch {
        reason => results.push(render_stuck(reason))
      }
    }
    _ =>
      try {
        let v = @eval.eval(@eval.Env::empty(), term)
        results.push(Value(render_value(v)))
      } catch {
        reason => results.push(render_stuck(reason))
      }
  }
  results
}

///|
/// Build a reactive eval memo.
/// Reads `syntax_tree` signal to establish reactive dependency —
/// the memo recomputes whenever the parser produces a new tree.
pub fn build_eval_memo(
  rt : @incr.Runtime,
  syntax_tree : @incr.Signal[@seam.SyntaxNode?],
  parser : @loom.ImperativeParser[@ast.Term],
) -> @incr.Memo[Array[EvalResult]] {
  @incr.Memo::new_no_backdate(
    rt,
    fn() -> Array[EvalResult] {
      // Read syntax_tree to track reactive dependency
      let _ = syntax_tree.get()
      let ast = parser.get_tree().unwrap_or(@ast.Term::Unit)
      eval_term(ast)
    },
    label="eval_memo",
  )
}
```

- [ ] **Step 6: Run `moon check`**

```bash
moon check
```

Expected: pass.

- [ ] **Step 7: Run tests to verify they pass**

```bash
moon test -p dowdiness/canopy/editor -f eval_memo_test.mbt
```

Expected: all 8 tests pass. If snapshot content doesn't match, run `moon test --update` and verify the diffs make sense.

- [ ] **Step 8: Format and update interfaces**

```bash
moon info && moon fmt
```

- [ ] **Step 9: Commit**

```bash
git add editor/moon.pkg editor/eval_memo.mbt editor/eval_memo_test.mbt
git commit -m "feat(editor): add eval memo with per-definition evaluation and tests"
```

---

### Task 4: Wire eval memo into SyncEditor (lambda-specific)

**Files:**
- Modify: `editor/sync_editor.mbt`

The eval memo is lambda-specific — it must be built in `SyncEditor::new_lambda`, not the generic constructor. The generic constructor sets `eval_memo: None`.

- [ ] **Step 1: Add `eval_memo` field to `SyncEditor`**

In `editor/sync_editor.mbt`, add to the struct after `source_map_memo`:

```moonbit
  priv mut eval_memo : @incr.Memo[Array[EvalResult]]?
```

- [ ] **Step 2: Set `eval_memo: None` in generic `SyncEditor::new`**

In the struct literal inside `SyncEditor::new`, add:

```moonbit
    eval_memo: None,
```

- [ ] **Step 3: Build eval memo in `SyncEditor::new_lambda`**

Change `SyncEditor::new_lambda` to build the eval memo after the base constructor. Since `SyncEditor::new` is private, we can modify the approach: build the eval memo using `parser_rt` and `syntax_tree` from the returned editor.

Actually, the cleanest approach: add an optional `eval_builder` callback to `SyncEditor::new`, or build it directly in `new_lambda`. Since `new` returns the struct, modify `new_lambda` to set `eval_memo` after construction:

```moonbit
pub fn SyncEditor::new_lambda(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> SyncEditor[@ast.Term] {
  let editor = SyncEditor::new(
    agent_id,
    fn(s) { @loom.new_imperative_parser(s, @parser.lambda_grammar) },
    build_lambda_projection_memos,
    capture_timeout_ms~,
  )
  editor.eval_memo = Some(
    build_eval_memo(editor.parser_rt, editor.syntax_tree, editor.parser),
  )
  editor
}
```

- [ ] **Step 4: Set `eval_memo: None` in `SyncEditor::new_generic`**

In the struct literal inside `SyncEditor::new_generic`, add:

```moonbit
    eval_memo: None,
```

- [ ] **Step 5: Add accessor in `editor/eval_memo.mbt`**

```moonbit
///|
/// Get current eval results for a lambda editor.
pub fn SyncEditor::get_eval_results(
  self : SyncEditor[@ast.Term],
) -> Array[EvalResult] {
  match self.eval_memo {
    Some(memo) => memo.get()
    None => []
  }
}
```

- [ ] **Step 6: Run `moon check`**

```bash
moon check
```

Expected: pass.

- [ ] **Step 7: Run full tests**

```bash
moon test
```

Expected: all pass — no behavioral change yet.

- [ ] **Step 8: Commit**

```bash
git add editor/sync_editor.mbt editor/eval_memo.mbt
git commit -m "feat(editor): wire eval memo into SyncEditor (lambda-specific)"
```

---

### Task 5: Inject eval annotations into pretty-print Layout (TDD)

**Files:**
- Modify: `editor/sync_editor_pretty.mbt`
- Create: `editor/eval_memo_wbtest.mbt` (whitebox — needs access to internal `split_at_hardlines`)

This task post-processes the canonical Layout from `Pretty::to_layout` — no formatting logic duplication. We split the Layout at top-level `HardLine` boundaries, append annotations, and rejoin.

`@pretty.separate(hardline(), items)` uses left fold, producing:
```
Concat(Concat(Concat(item0, Concat(HardLine, item1)), HardLine), item2)
```

The Module layout is `defs_doc + hardline + body` where `defs_doc = separate(hardline(), def_layouts)`.

- [ ] **Step 1: Write failing tests**

Create `editor/eval_memo_wbtest.mbt`:

```moonbit
///|
test "split_at_hardlines: separates module layout into segments" {
  let layout : @pretty.Layout[@pretty.SyntaxCategory] = @pretty.separate(
    @pretty.hardline(),
    [
      @pretty.text("def0"),
      @pretty.text("def1"),
      @pretty.text("body"),
    ],
  )
  let segments = split_at_hardlines(layout)
  inspect!(segments.length(), content="3")
  inspect!(@pretty.render_string(segments[0], width=80), content="def0")
  inspect!(@pretty.render_string(segments[1], width=80), content="def1")
  inspect!(@pretty.render_string(segments[2], width=80), content="body")
}

///|
test "split_at_hardlines: single segment (no hardlines)" {
  let layout = @pretty.text("hello")
  let segments = split_at_hardlines(layout)
  inspect!(segments.length(), content="1")
}

///|
test "inject_eval_annotations: adds arrow to each segment" {
  let ast = @ast.Term::Module(
    [("x", @ast.Term::Int(5))],
    @ast.Term::Var("x"),
  )
  let layout = @pretty.Pretty::to_layout(ast)
  let results = [EvalResult::Value("5"), EvalResult::Value("5")]
  let annotated = inject_eval_annotations(layout, results)
  let text = @pretty.render_string(annotated, width=80)
  inspect!(text.contains("\u{2192} 5"), content="true")
}

///|
test "inject_eval_annotations: suppressed results add nothing" {
  let ast = @ast.Term::Module(
    [("x", @ast.Term::Hole(0))],
    @ast.Term::Hole(1),
  )
  let layout = @pretty.Pretty::to_layout(ast)
  let results = [EvalResult::Suppressed, EvalResult::Suppressed]
  let annotated = inject_eval_annotations(layout, results)
  let text = @pretty.render_string(annotated, width=80)
  inspect!(text.contains("\u{2192}"), content="false")
}

///|
test "inject_eval_annotations: error results show eval-error" {
  let ast = @ast.Term::Var("x")
  let layout = @pretty.Pretty::to_layout(ast)
  let results = [EvalResult::Stuck("\u{2039}unbound: x\u{203a}")]
  let annotated = inject_eval_annotations(layout, results)
  let rendered = @pretty.render_spans(annotated, width=80)
  // Check that there's an EvalError-annotated span
  let has_eval_error = rendered.iter().any(fn(pair) {
    pair.1 == @pretty.SyntaxCategory::EvalError
  })
  inspect!(has_eval_error, content="true")
}

///|
test "pretty_view: eval annotations appear after edit" {
  let editor = SyncEditor::new_lambda("test-eval-pretty")
  editor.set_text("let x = 5\nx")
  let view = editor.get_pretty_view()
  let lines = view.children
  // At least one line should have an eval-annotation token span
  let has_eval_span = lines.iter().any(fn(line) {
    line.token_spans.iter().any(fn(span) { span.role == "eval-annotation" })
  })
  inspect!(has_eval_span, content="true")
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
moon test -p dowdiness/canopy/editor -f eval_memo_wbtest.mbt
```

Expected: FAIL — `split_at_hardlines` and `inject_eval_annotations` not defined.

- [ ] **Step 3: Implement `split_at_hardlines` and `inject_eval_annotations`**

Add to `editor/eval_memo.mbt` (these are internal functions, whitebox tests can access them):

```moonbit
///|
/// Split a Layout at top-level HardLine boundaries.
/// Only descends into Concat nodes — Nest, Group, Annotate are opaque.
/// Returns the segments between HardLines.
fn split_at_hardlines(
  layout : @pretty.Layout[@pretty.SyntaxCategory],
) -> Array[@pretty.Layout[@pretty.SyntaxCategory]] {
  let segments : Array[@pretty.Layout[@pretty.SyntaxCategory]] = []
  let parts : Array[@pretty.Layout[@pretty.SyntaxCategory]] = []
  fn flush() -> Unit {
    if parts.is_empty() {
      return
    }
    let mut combined = parts[0]
    for i = 1; i < parts.length(); i = i + 1 {
      combined = @pretty.Layout::Concat(combined, parts[i])
    }
    segments.push(combined)
    parts.clear()
  }

  fn walk(l : @pretty.Layout[@pretty.SyntaxCategory]) -> Unit {
    match l {
      HardLine => flush()
      Concat(left, right) => {
        walk(left)
        walk(right)
      }
      Empty => ()
      other => parts.push(other)
    }
  }

  walk(layout)
  flush()
  segments
}

///|
fn eval_annotation_layout(
  result : EvalResult,
) -> @pretty.Layout[@pretty.SyntaxCategory]? {
  match result {
    Value(s) =>
      Some(
        @pretty.annotate(
          @pretty.SyntaxCategory::EvalAnnotation,
          @pretty.text("  \u{2192} " + s),
        ),
      )
    Stuck(s) =>
      Some(
        @pretty.annotate(
          @pretty.SyntaxCategory::EvalError,
          @pretty.text("  \u{2192} " + s),
        ),
      )
    Suppressed => None
  }
}

///|
/// Post-process a Layout to inject eval annotations after each segment.
/// Splits the canonical Layout at HardLine boundaries, appends annotation
/// to each segment, and rejoins. No formatting logic duplication —
/// the canonical Pretty::to_layout output is preserved exactly.
fn inject_eval_annotations(
  layout : @pretty.Layout[@pretty.SyntaxCategory],
  eval_results : Array[EvalResult],
) -> @pretty.Layout[@pretty.SyntaxCategory] {
  if eval_results.is_empty() {
    return layout
  }
  let segments = split_at_hardlines(layout)
  let annotated : Array[@pretty.Layout[@pretty.SyntaxCategory]] = []
  for i, seg in segments {
    match eval_results.get(i) {
      Some(result) =>
        match eval_annotation_layout(result) {
          Some(ann) => annotated.push(@pretty.Layout::Concat(seg, ann))
          None => annotated.push(seg)
        }
      None => annotated.push(seg)
    }
  }
  @pretty.separate(@pretty.hardline(), annotated)
}
```

- [ ] **Step 4: Update `get_pretty_view` to use eval injection**

In `editor/sync_editor_pretty.mbt`, replace the existing `get_pretty_view`:

```moonbit
///|
pub fn SyncEditor::get_pretty_view(
  self : SyncEditor[@ast.Term],
) -> @protocol.ViewNode {
  let ast = self.get_ast()
  let layout = @pretty.Pretty::to_layout(ast)
  let eval_results = self.get_eval_results()
  let annotated = inject_eval_annotations(layout, eval_results)
  @protocol.layout_to_view_tree(annotated, width=80)
}
```

- [ ] **Step 5: Run `moon check`**

```bash
moon check
```

- [ ] **Step 6: Run tests**

```bash
moon test -p dowdiness/canopy/editor -f eval_memo_wbtest.mbt
```

Expected: all pass. If snapshot content doesn't match, run `moon test --update` and verify.

- [ ] **Step 7: Run full test suite**

```bash
moon test
```

Expected: all pass.

- [ ] **Step 8: Format**

```bash
moon info && moon fmt
```

- [ ] **Step 9: Commit**

```bash
git add editor/eval_memo.mbt editor/eval_memo_wbtest.mbt editor/sync_editor_pretty.mbt
git commit -m "feat(editor): inject eval annotations into pretty-print layout via post-processing"
```

---

### Task 6: Add annotations to structural view

**Files:**
- Modify: `protocol/convert.mbt`
- Modify: `editor/view_updater.mbt`
- Modify: `editor/eval_memo.mbt` (add `get_eval_annotations`)

- [ ] **Step 1: Extend `proj_to_view_node` to accept annotations**

In `protocol/convert.mbt`, add an optional `annotations` parameter:

```moonbit
pub fn[T : @loomcore.Renderable] proj_to_view_node(
  node : @core.ProjNode[T],
  source_map : @core.SourceMap,
  annotations? : Map[@core.NodeId, Array[ViewAnnotation]] = {},
) -> ViewNode {
  let node_id = node.id()
  let kind_tag = @loomcore.Renderable::kind_tag(node.kind)
  let label = @loomcore.Renderable::label(node.kind)
  let text_range = match source_map.get_range(node_id) {
    Some(r) => (r.start, r.end)
    None => (node.start, node.end)
  }
  let token_spans : Array[TokenSpan] = []
  match source_map.token_spans.get(node_id) {
    Some(roles) =>
      for role, range in roles {
        token_spans.push(TokenSpan(role~, start=range.start, end=range.end))
      }
    None => ()
  }
  let node_annotations = match annotations.get(node_id) {
    Some(anns) => anns
    None => []
  }
  let children : Array[ViewNode] = []
  for child in node.children {
    children.push(proj_to_view_node(child, source_map, annotations~))
  }
  ViewNode(
    id=node_id,
    kind_tag~,
    label~,
    text_range~,
    token_spans~,
    css_class=kind_tag,
    children~,
    annotations=node_annotations,
  )
}
```

- [ ] **Step 2: Add `get_eval_annotations` to eval_memo.mbt**

In `editor/eval_memo.mbt`:

```moonbit
///|
/// Build a NodeId → ViewAnnotation map from eval results.
/// Maps definition indices to their ProjNode IDs via the projection.
pub fn SyncEditor::get_eval_annotations(
  self : SyncEditor[@ast.Term],
) -> Map[@proj.NodeId, Array[@protocol.ViewAnnotation]] {
  let annotations : Map[@proj.NodeId, Array[@protocol.ViewAnnotation]] = {}
  let eval_results = self.get_eval_results()
  if eval_results.is_empty() {
    return annotations
  }
  let proj_node = match self.get_proj_node() {
    Some(p) => p
    None => return annotations
  }
  // For Module: children are defs + body. Map eval results to child NodeIds.
  // For non-Module: single eval result maps to the root node itself.
  let children = proj_node.children
  for i, result in eval_results {
    match result {
      Suppressed => continue
      Value(s) => {
        let target_id = if i < children.length() {
          children[i].id()
        } else {
          proj_node.id() // non-Module or body beyond children
        }
        annotations[target_id] = [
          @protocol.ViewAnnotation(kind="eval", label="\u{2192} " + s),
        ]
      }
      Stuck(s) => {
        let target_id = if i < children.length() {
          children[i].id()
        } else {
          proj_node.id()
        }
        annotations[target_id] = [
          @protocol.ViewAnnotation(
            kind="eval",
            label="\u{2192} " + s,
            severity="warning",
          ),
        ]
      }
    }
  }
  annotations
}
```

- [ ] **Step 3: Override `get_view_tree` for lambda to pass eval annotations**

In `editor/view_updater.mbt`, replace the generic `get_view_tree` with a lambda-specific override that passes annotations. Add a new specialization that shadows the generic one for `@ast.Term`:

```moonbit
///|
/// Lambda-specific: returns ViewNode tree with eval annotations attached.
/// This overrides the generic get_view_tree for SyncEditor[@ast.Term].
pub fn SyncEditor::get_view_tree(
  self : SyncEditor[@ast.Term],
) -> @protocol.ViewNode? {
  match self.get_proj_node() {
    Some(proj_node) => {
      let source_map = self.get_source_map()
      let annotations = self.get_eval_annotations()
      Some(@protocol.proj_to_view_node(proj_node, source_map, annotations~))
    }
    None => None
  }
}
```

Note: MoonBit allows a more specific method (for `SyncEditor[@ast.Term]`) to shadow a generic one (for `SyncEditor[T]`). The existing `compute_view_patches` calls `editor.get_view_tree()` — with this override, lambda editors automatically get eval annotations in the structural view pipeline without changing `compute_view_patches`.

If MoonBit does not allow this shadowing, the fallback is to modify `compute_view_patches` to check `self.eval_memo` and call the appropriate code path. Verify with `moon check` and adjust.

- [ ] **Step 4: Add annotation diff check in `diff_view_nodes`**

In `editor/view_updater.mbt`, in the `diff_view_nodes` function, add annotation comparison right after the `token_spans` check:

```moonbit
  // Annotation changes require full node replacement
  if prev.annotations != curr.annotations {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=curr.id, node=curr))
    return
  }
```

- [ ] **Step 5: Add whitebox test for structural annotations**

Add to `editor/eval_memo_wbtest.mbt`:

```moonbit
///|
test "get_eval_annotations: module defs have annotations" {
  let editor = SyncEditor::new_lambda("test-struct-ann")
  editor.set_text("let x = 5\nx")
  let annotations = editor.get_eval_annotations()
  // Should have at least one annotation (for def x and/or body)
  inspect!(annotations.size() > 0, content="true")
}

///|
test "get_view_tree_with_eval: annotations present on nodes" {
  let editor = SyncEditor::new_lambda("test-view-ann")
  editor.set_text("let x = 5\nx")
  let view = editor.get_view_tree_with_eval()
  match view {
    Some(root) => {
      // Walk tree to find a node with annotations
      fn has_annotations(node : @protocol.ViewNode) -> Bool {
        if node.annotations.length() > 0 {
          return true
        }
        node.children.iter().any(has_annotations)
      }
      inspect!(has_annotations(root), content="true")
    }
    None => inspect!(false, content="true") // should not reach
  }
}
```

- [ ] **Step 6: Run `moon check`**

```bash
moon check
```

- [ ] **Step 7: Run tests**

```bash
moon test -p dowdiness/canopy/editor
```

Expected: all pass.

- [ ] **Step 8: Format**

```bash
moon info && moon fmt
```

- [ ] **Step 9: Commit**

```bash
git add protocol/convert.mbt editor/view_updater.mbt editor/eval_memo.mbt editor/eval_memo_wbtest.mbt
git commit -m "feat(protocol): add structural view annotations with eval results"
```

---

### Task 7: Render annotations in HTML adapter and add CSS

**Files:**
- Modify: `lib/editor-adapter/html-adapter.ts`
- Modify: `examples/web/index.html`

- [ ] **Step 1: Update HTML adapter to render annotations**

In `lib/editor-adapter/html-adapter.ts`, annotations must be rendered in **both** the leaf (`wrapper`) and non-leaf (`container`) branches of `renderNode`. Both branches have a `.node-row` with a `.node-tag` element.

Extract a helper function and call it in both branches, after the `row` is built but before appending to the parent:

```typescript
/** Append annotation badges to a node row */
function renderAnnotations(row: HTMLElement, node: ViewNode): void {
  if (!node.annotations || node.annotations.length === 0) return;
  for (const ann of node.annotations) {
    const badge = document.createElement('span');
    badge.className = `annotation-${ann.kind} severity-${ann.severity}`;
    badge.textContent = ann.label;
    row.appendChild(badge);
  }
}
```

In the **leaf branch** (around line 212, before `wrapper.appendChild(row)`):
```typescript
      renderAnnotations(row, node);
      wrapper.appendChild(row);
```

In the **non-leaf branch** (around line 250, after `row.appendChild(tagEl)` and before the row is appended):
```typescript
      renderAnnotations(row, node);
```

- [ ] **Step 2: Add CSS for eval annotations**

In `examples/web/index.html`, find the `.formatted-text` CSS section and add:

```css
    /* Eval annotation styling (pretty-print view) */
    .formatted-text .eval-annotation {
      color: #89ddff;
      opacity: 0.7;
      font-style: italic;
    }
    .formatted-text .eval-error {
      color: #ff5370;
      opacity: 0.7;
      font-style: italic;
    }

    /* Eval annotation styling (structural tree view) */
    .annotation-eval {
      color: #89ddff;
      opacity: 0.7;
      font-style: italic;
      margin-left: 0.5em;
    }
    .annotation-eval.severity-warning {
      color: #ff5370;
    }
```

- [ ] **Step 3: Verify web build**

```bash
moon build --target js
cd examples/web && npx vite build
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
git add lib/editor-adapter/html-adapter.ts examples/web/index.html
git commit -m "feat(web): render eval annotations in HTML adapter with CSS styling"
```

---

### Task 8: Integration test and final verification

**Files:** All modified files.

- [ ] **Step 1: Run the full test suite across all modules**

```bash
moon test
cd event-graph-walker && moon test
cd ../loom/loom && moon test
cd ../loom/examples/lambda && moon test
```

Expected: all pass.

- [ ] **Step 2: Run moon check and moon fmt**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
moon check && moon info && moon fmt
```

Expected: clean.

- [ ] **Step 3: Check for interface changes**

```bash
git diff -- '*.mbti'
```

Review: `SyntaxCategory` should have two new variants. `ViewNode` should have `annotations` field and `ViewAnnotation` struct. `editor/` should export `EvalResult`, `eval_term`, `build_eval_memo`.

- [ ] **Step 4: Build JS and test web editor locally**

```bash
moon build --target js
cd examples/web && npm run dev
```

Open `http://localhost:5173/` and type:

```
let x = 5
let y = x + 3
y
```

Expected: each definition line shows `→ 5`, `→ 8`, `→ 8` in italic cyan text in the pretty-print view.

Type `let bad = z` (unbound variable). Expected: shows `→ ‹unbound: z›` in italic red.

Delete partial text to create a parse error. Expected: no eval annotation shown (suppressed).

- [ ] **Step 5: Verify reactive update**

Edit `5` to `10` in the first definition. Expected: all eval results update immediately — `→ 10`, `→ 13`, `→ 13`.

- [ ] **Step 6: Final commit if any cleanup needed**

```bash
git add -A
git commit -m "chore: final cleanup for live inline eval"
```

---

## Validation Commands

```bash
# All tests
moon test && cd event-graph-walker && moon test && cd ../loom/loom && moon test

# Lint
moon check

# Interfaces
moon info && moon fmt

# Web build
moon build --target js && cd examples/web && npx vite build

# Manual: open localhost:5173, type code, see eval results
```

## Review Findings Addressed

### Round 1 (Codex review)

| Finding | Resolution |
|---------|-----------|
| 1. Task 4 type mismatch | Eval memo built in `SyncEditor::new_lambda`, not generic constructor |
| 2. Eval memo not reactive | Reads `syntax_tree.get()` inside memo closure to establish dependency |
| 3. Structural view not wired | Added `get_view_tree_with_eval`, `get_eval_annotations`, TS types, HTML adapter |
| 4. MoonBit syntax errors | Fixed enum constructors (`@ast.Term::Var`), `SyntaxCategory::EvalAnnotation`, `set_text` for tests |
| 5. Pretty-print layout duplication | Post-processes canonical Layout via `split_at_hardlines` — no formatting duplication |
| 6. Design/plan inconsistency | Chose `ReplaceNode` for annotation changes, documented in plan |

### Round 2 (Codex re-review)

| Finding | Resolution |
|---------|-----------|
| 1. `eval_memo` field immutable | Changed to `priv mut eval_memo` |
| 2. `compute_view_patches` uses old path | Lambda-specific `get_view_tree` override shadows the generic version, so `compute_view_patches` gets annotations automatically |
| 3. `get_eval_annotations` wrong for non-Module | Added fallback: when index >= children.length(), annotate root node |
| 4. HTML adapter wrong branch + selector | Extracted `renderAnnotations` helper, called in both leaf and non-leaf branches; uses `.node-tag` |
