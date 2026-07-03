# Genericize SyncEditor: LanguageCapabilities[T]

**Status:** Complete (PR #146). Implementation diverges from spec — see notes below.

### Implementation divergences from spec

1. **Package location:** Spec places `LambdaCompanion`, `new_lambda_editor()`, `apply_lambda_tree_edit()`, `parse_tree_edit_op()`, and AST helpers in `lang/lambda/edits/`. Implementation uses a separate `lang/lambda/companion/` package to break a circular dependency: `projection → lambda_edits → editor → projection`. The `lambda_edits` package cannot import `editor` because `projection` (which `editor` imports) already imports `lambda_edits`.
2. **LanguageCapabilities fields:** Spec uses `pub` fields. Implementation uses `priv` fields with `new()` and `default()` constructors, plus a phantom `T?` field to satisfy the unused type variable warning under `-w @a`.
3. **`get_annotations` closure:** Spec proposes the closure takes `ProjNode[T]?` as argument. Implementation captures `cached_proj_node_ref` (a `Ref[Memo[...]]`) and reads the memo directly — no argument needed. The closure signature is `() -> Map[NodeId, Array[ViewAnnotation]]`.

---

**Goal:** Remove all lambda-specific types and imports from the `editor/` package by introducing a `LanguageCapabilities[T]` function record that carries language-specific behavior via closures.

**Architecture:** Two mechanisms — (1) a `LanguageCapabilities[T]` function record on SyncEditor for view/rendering extensions (annotation injection, pretty-print post-processing), with closures capturing language-specific memos; (2) a companion struct pattern for language-specific operations (tree editing via FlatProj), composed at the FFI layer. SyncEditor exposes `apply_span_edits()`, `get_registry()`, `get_tree()` as public API for companions.

**Tech Stack:** MoonBit, dowdiness/canopy module

**Design spec:** This document (design + implementation combined)

---

## Why

`editor/moon.pkg` imports 4 lambda-specific packages (`@parser`, `@ast`, `@eval`, `@lambda`). The `SyncEditor[T]` struct contains two lambda-typed fields (`proj_memo : Memo[VersionedFlatProj]?`, `eval_memo : Memo[Array[EvalResult]]?`). This couples the generic editor framework to one specific language, violating the design invariant that the editor should be language-agnostic.

JSON and Markdown editors already avoid this coupling by using `SyncEditor::new_generic()`, which sets both fields to `None`. The asymmetry exists because lambda was the first language and its optimizations (FlatProj incremental change detection, eval annotations) were wired directly into the struct.

## Scope

In:
- `editor/` — struct, constructors, view pipeline, projection accessors
- `lang/lambda/edits/` — new factory, companion, moved tree edit logic
- `ffi/` — handle structure, view/pretty/lambda FFI functions
- `lang/lambda/top.mbt` — facade re-exports

Out:
- Ephemeral subsystem decomposition (separate concern)
- Sync protocol unification (separate concern)
- Submodule changes (event-graph-walker, loom, etc.)

## Current State

**SyncEditor struct** (`editor/sync_editor.mbt`):
- 19 fields, 2 are lambda-typed (`proj_memo`, `eval_memo`)
- 3 constructors: `new` (lambda-specific 4-tuple), `new_lambda` (convenience), `new_generic` (3-tuple, no lambda)

**Lambda-specific methods in editor/** (must remove):
- `get_flat_proj()` — reads `proj_memo`
- `get_eval_results()` — reads `eval_memo`
- `get_eval_annotations()` — builds annotation map from eval results
- `get_view_tree_with_eval()` — view tree + eval annotations
- `compute_view_patches_with_eval()` — incremental patches with eval
- `get_ast()` — `parser.get_tree().unwrap_or(Term::Unit)`
- `get_ast_pretty()` — formatted AST string
- `get_resolution()` — name resolution
- `get_dot_resolved()` — Graphviz DOT
- `apply_tree_edit()` — structural edit via FlatProj + EditContext
- `get_pretty_view()` — pretty-printed view with eval annotations
- `compute_pretty_patches()` — incremental pretty patches

**editor/moon.pkg** imports to remove:
```
"dowdiness/lambda" @parser
"dowdiness/lambda/ast" @ast
"dowdiness/canopy/lang/lambda" @lambda
```
(`"dowdiness/lambda/eval" @eval` was already removed in the prior refactoring.)

## Desired State

1. `editor/moon.pkg` has zero lambda/language-specific imports
2. `SyncEditor[T]` struct has zero lambda-typed fields
3. Lambda editor construction happens in `lang/lambda/edits/`
4. Generic view pipeline handles annotations for any language via `LanguageCapabilities[T]`
5. `_with_eval` variant methods are eliminated
6. All 828+ tests pass
7. FFI functions produce identical output

## Design Decisions

**D1: LanguageCapabilities[T] lives in `editor/`.**
It uses types already imported by editor (`ProjNode[T]`, `NodeId`, `ViewAnnotation`, `Layout[SyntaxCategory]`). Language packages construct it and pass it to `SyncEditor::new_generic`.

**D2: View annotations use a closure callback, not a trait.**
MoonBit can't store trait objects. A closure `(ProjNode[T]?) -> Map[NodeId, Array[ViewAnnotation]]` captures language-specific state (eval_memo) internally while exposing a generic signature. This is refunctionalization — the intermediate types (EvalResult) disappear from the struct.

**D3: Structural editing uses explicit composition, not a callback.**
`apply_tree_edit` needs language-specific input types (TreeEditOp, FlatProj) and access to SyncEditor internals. Rather than a self-referential closure, the companion pattern keeps it clean: language code calls `editor.apply_span_edits()` after computing edits externally.

**D4: Lambda factory uses Ref side-channels for memo capture.**
`SyncEditor::new_generic` creates the reactive runtime and signals internally, passing them to the `build_memos` callback. The lambda factory captures `proj_memo` and `eval_memo` via `Ref` cells that the callback fills. Capability closures capture the same `Ref` cells and dereference them at call time (after the callback has run). This is a standard lazy-init pattern.

**D5: `new_lambda_editor` returns `(SyncEditor[Term], LambdaCompanion)`.**
The companion holds `proj_memo` (for FlatProj access in tree editing). The FFI stores both in a `LambdaHandle` struct. JSON/Markdown have no companion.

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `editor/capabilities.mbt` | Create | `LanguageCapabilities[T]` struct + `default()` |
| `editor/sync_editor.mbt` | Modify | Remove `proj_memo`, `eval_memo`; add `capabilities`; remove `new()`, `new_lambda()`; modify `new_generic()` to accept `capabilities?` |
| `editor/sync_editor_span_edit.mbt` | Create | `apply_span_edits()` public API |
| `editor/projection_memo.mbt` | Modify | Remove `get_flat_proj()`; add `get_registry()`, `get_tree()` |
| `editor/view_updater.mbt` | Modify | `get_view_tree` uses capabilities; remove `_with_eval` variants |
| `editor/sync_editor_pretty.mbt` | Modify | Generic `get_pretty_view[T : Pretty]` using `pretty_post_process` callback |
| `editor/eval_memo.mbt` | Delete | All methods removed (eval logic already in `lang/lambda/eval/`) |
| `editor/sync_editor_parser.mbt` | Modify | Remove `get_ast`, `get_ast_pretty`, `get_resolution`, `get_dot_resolved` |
| `editor/tree_edit_bridge.mbt` | Delete | `apply_tree_edit` moves to lang/lambda |
| `editor/tree_edit_json.mbt` | Delete | `parse_tree_edit_op` moves to lang/lambda |
| `editor/moon.pkg` | Modify | Remove `@parser`, `@ast`, `@lambda` imports |
| `lang/lambda/edits/lambda_editor.mbt` | Create | `new_lambda_editor()` factory, `LambdaCompanion` struct, `apply_lambda_tree_edit()` |
| `lang/lambda/edits/tree_edit_json.mbt` | Create | `parse_tree_edit_op()` (moved from editor) |
| `lang/lambda/edits/lambda_ast_helpers.mbt` | Create | `get_lambda_ast()`, `get_lambda_ast_pretty()`, `get_lambda_resolution()`, `get_lambda_dot_resolved()` |
| `lang/lambda/edits/moon.pkg` | Modify | Add `@editor`, `@protocol`, `@pretty` imports |
| `lang/lambda/top.mbt` | Modify | Re-export new factory and companion |
| `ffi/canopy_lambda.mbt` | Modify | `LambdaHandle` struct; use `new_lambda_editor()` |
| `ffi/canopy_view.mbt` | Modify | Use generic `get_view_tree` / `compute_view_patches` |
| `ffi/canopy_pretty.mbt` | Modify | Use generic `get_pretty_view` / `compute_pretty_patches` |
| `ffi/moon.pkg` | Modify | Verify imports |
| `editor/eval_memo_wbtest.mbt` | Modify | Use `@lambda_edits.new_lambda_editor()` via test import |

---

## Steps

### Task 1: Define LanguageCapabilities[T] struct

**Files:**
- Create: `editor/capabilities.mbt`

- [ ] **Step 1: Create the capabilities struct**

```moonbit
// editor/capabilities.mbt
// Language-specific extension points for SyncEditor.
// Closures capture language-specific state (eval memos, type memos)
// while exposing generic signatures — no language types leak into the struct.

///|
pub(all) struct LanguageCapabilities[T] {
  /// Provide per-node view annotations (eval results, type info, etc.)
  /// Called by the generic view pipeline during get_view_tree.
  get_annotations : ((@proj.ProjNode[T]?) -> Map[@proj.NodeId, Array[@protocol.ViewAnnotation]])?
  /// Post-process pretty-printed layout (inject eval annotations, type overlays, etc.)
  /// Called by the generic get_pretty_view after Pretty::to_layout.
  pretty_post_process : ((@pretty.Layout[@pretty.SyntaxCategory]) -> @pretty.Layout[@pretty.SyntaxCategory])?
}

///|
pub fn[T] LanguageCapabilities::default() -> LanguageCapabilities[T] {
  { get_annotations: None, pretty_post_process: None }
}
```

- [ ] **Step 2: Run `moon check`**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy-refactor-editor && moon check`
Expected: PASS (no errors)

- [ ] **Step 3: Commit**

```bash
git add editor/capabilities.mbt
git commit -m "feat(editor): add LanguageCapabilities[T] function record"
```

---

### Task 2: Add new public API methods to SyncEditor

**Files:**
- Create: `editor/sync_editor_span_edit.mbt`
- Modify: `editor/projection_memo.mbt`

These methods enable language companions to compose with SyncEditor without accessing private fields.

- [ ] **Step 1: Create apply_span_edits**

```moonbit
// editor/sync_editor_span_edit.mbt
// Public API for language extensions to apply computed span edits.

///|
/// Apply an array of span edits to the document, in reverse document order.
/// This is the public entry point for language-specific tree edit operations
/// that compute their edits externally (via a companion) and then apply them
/// through SyncEditor's text CRDT pipeline.
pub fn[T] SyncEditor::apply_span_edits(
  self : SyncEditor[T],
  edits : Array[@proj.SpanEdit],
  focus_hint : @proj.FocusHint,
  timestamp_ms : Int,
) -> Unit {
  let old_cursor = self.get_cursor()
  // Sort in reverse document order to avoid position shifts
  let sorted = edits.copy()
  sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
  for edit in sorted {
    self.apply_text_edit_internal(
      edit.start,
      edit.delete_len,
      edit.inserted,
      timestamp_ms,
      true,
      false,
    )
  }
  match focus_hint {
    @proj.FocusHint::RestoreCursor => self.move_cursor(old_cursor)
    @proj.FocusHint::MoveCursor(position~) => self.move_cursor(position)
  }
}
```

- [ ] **Step 2: Add get_registry and get_tree to projection_memo.mbt**

Add to `editor/projection_memo.mbt`:

```moonbit
///|
/// Returns the full node registry. Used by language companions for tree editing.
pub fn[T] SyncEditor::get_registry(
  self : SyncEditor[T],
) -> Map[@proj.NodeId, @proj.ProjNode[T]] {
  self.registry_memo.get()
}

///|
/// Returns the parser's current AST. Used by language companions for AST access.
pub fn[T] SyncEditor::get_tree(self : SyncEditor[T]) -> T? {
  self.parser.get_tree()
}
```

- [ ] **Step 3: Run `moon check`**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy-refactor-editor && moon check`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add editor/sync_editor_span_edit.mbt editor/projection_memo.mbt
git commit -m "feat(editor): add apply_span_edits, get_registry, get_tree public API"
```

---

### Task 3: Modify SyncEditor struct and constructors

**Files:**
- Modify: `editor/sync_editor.mbt`

This task removes lambda-typed fields and the lambda-specific constructors. **This will break compilation** — subsequent tasks fix it.

- [ ] **Step 1: Update the struct**

Remove `proj_memo` and `eval_memo` fields. Add `capabilities` field.

Replace the struct definition:

```moonbit
pub struct SyncEditor[T] {
  priv doc : @text.TextState
  priv undo : @undo.UndoManager
  priv parser : @loom.ImperativeParser[T]
  priv parser_rt : @incr.Runtime
  priv source_text : @incr.Signal[String]
  priv syntax_tree : @incr.Signal[@seam.SyntaxNode?]
  priv mut cursor : Int
  priv cached_proj_node : @incr.Memo[@proj.ProjNode[T]?]
  priv registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode[T]]]
  priv source_map_memo : @incr.Memo[@proj.SourceMap]
  priv capabilities : LanguageCapabilities[T]
  priv hub : EphemeralHub
  priv cursor_view : PeerCursorView
  priv peer_id : String
  priv mut ws : JsWebSocket?
  priv mut recovery : RecoveryContext?
  priv mut recovery_epoch : Int
  priv mut projection_dirty : Bool
}
```

- [ ] **Step 2: Remove `SyncEditor::new` (lambda-specific 4-tuple constructor)**

Delete the entire `fn[T] SyncEditor::new(...)` function (lines 28-77 approximately).

- [ ] **Step 3: Remove `SyncEditor::new_lambda`**

Delete the entire `pub fn SyncEditor::new_lambda(...)` function.

- [ ] **Step 4: Modify `SyncEditor::new_generic` to accept capabilities**

```moonbit
///|
/// Generic constructor for any language.
/// The build_memos callback returns 3 memos (ProjNode, registry, SourceMap).
/// Optional capabilities provide language-specific view extensions.
pub fn[T] SyncEditor::new_generic(
  agent_id : String,
  make_parser : (String) -> @loom.ImperativeParser[T],
  build_memos : (
    @incr.Runtime,
    @incr.Signal[String],
    @incr.Signal[@seam.SyntaxNode?],
    @loom.ImperativeParser[T],
  ) -> (
    @incr.Memo[@proj.ProjNode[T]?],
    @incr.Memo[Map[@proj.NodeId, @proj.ProjNode[T]]],
    @incr.Memo[@proj.SourceMap],
  ),
  capabilities? : LanguageCapabilities[T] = LanguageCapabilities::default(),
  capture_timeout_ms? : Int = 500,
) -> SyncEditor[T] {
  let parser = make_parser("")
  let parser_rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(parser_rt, "", label="editor_source_text")
  let syntax_tree = @incr.Signal::new(
    parser_rt,
    None,
    label="editor_syntax_tree",
  )
  let (cached_proj_node, registry_memo, source_map_memo) = build_memos(
    parser_rt, source_text, syntax_tree, parser,
  )
  let (hub, cursor_view) = setup_hub_and_cursor(agent_id)
  {
    doc: @text.TextState::new(agent_id),
    undo: @undo.UndoManager::new(agent_id, capture_timeout_ms~),
    parser,
    parser_rt,
    source_text,
    syntax_tree,
    cursor: 0,
    cached_proj_node,
    registry_memo,
    source_map_memo,
    capabilities,
    hub,
    cursor_view,
    peer_id: agent_id,
    ws: None,
    recovery: None,
    recovery_epoch: 0,
    projection_dirty: false,
  }
}
```

- [ ] **Step 5: Do NOT run moon check yet** — compilation is broken until Tasks 4-5 complete.

---

### Task 4: Update view pipeline and pretty printer to use capabilities

**Files:**
- Modify: `editor/view_updater.mbt`
- Modify: `editor/sync_editor_pretty.mbt`

- [ ] **Step 1: Modify `get_view_tree` to use annotation capability**

Replace the existing `get_view_tree` and remove `get_view_tree_with_eval`:

```moonbit
///|
pub fn[T : @proj.Renderable] SyncEditor::get_view_tree(
  self : SyncEditor[T],
) -> @protocol.ViewNode? {
  match self.get_proj_node() {
    Some(proj_node) => {
      let source_map = self.get_source_map()
      let source_text = Some(self.get_text())
      let annotations = match self.capabilities.get_annotations {
        Some(f) => f(Some(proj_node))
        None => {}
      }
      Some(
        @protocol.proj_to_view_node(
          proj_node,
          source_map,
          source_text~,
          annotations~,
        ),
      )
    }
    None => None
  }
}
```

- [ ] **Step 2: Remove `get_view_tree_with_eval` and `compute_view_patches_with_eval`**

Delete both functions entirely. The generic `compute_view_patches` now handles all languages (annotations come from capabilities).

- [ ] **Step 3: Make `get_pretty_view` generic**

Replace the lambda-specific version with a generic one:

```moonbit
///|
/// Returns the pretty-printed ViewNode tree.
/// Uses capabilities.pretty_post_process for language-specific annotation injection.
pub fn[T : @pretty.Pretty] SyncEditor::get_pretty_view(
  self : SyncEditor[T],
) -> @protocol.ViewNode {
  match self.get_tree() {
    Some(ast) => {
      let layout = @pretty.Pretty::to_layout(ast)
      let post_processed = match self.capabilities.pretty_post_process {
        Some(f) => f(layout)
        None => layout
      }
      @protocol.layout_to_view_tree(post_processed, width=80)
    }
    None => @protocol.layout_to_view_tree(@pretty.text(""), width=80)
  }
}

///|
/// Compute incremental pretty-view patches.
pub fn[T : @pretty.Pretty] compute_pretty_patches(
  state : ViewUpdateState,
  editor : SyncEditor[T],
) -> Array[@protocol.ViewPatch] {
  let patches : Array[@protocol.ViewPatch] = []
  let current = editor.get_pretty_view()
  match state.previous {
    None => patches.push(@protocol.ViewPatch::FullTree(root=Some(current)))
    Some(prev) => diff_view_nodes(prev, current, patches)
  }
  state.previous = Some(current)
  patches
}
```

---

### Task 5: Remove lambda-specific methods and imports from editor

**Files:**
- Modify: `editor/projection_memo.mbt` — remove `get_flat_proj`
- Delete: `editor/eval_memo.mbt`
- Modify: `editor/sync_editor_parser.mbt` — remove lambda-specific methods
- Delete: `editor/tree_edit_bridge.mbt`
- Delete: `editor/tree_edit_json.mbt`
- Modify: `editor/moon.pkg` — remove lambda imports

- [ ] **Step 1: Remove `get_flat_proj` from `projection_memo.mbt`**

Delete the `SyncEditor::get_flat_proj` method. The remaining methods (`get_proj_node`, `get_source_map`, `get_node`, `node_at_position`, `get_node_range`, `get_registry`, `get_tree`) are all generic.

- [ ] **Step 2: Delete `editor/eval_memo.mbt`**

All eval methods (`get_eval_results`, `get_eval_annotations`) are no longer needed — annotations come through capabilities.

- [ ] **Step 3: Remove lambda methods from `sync_editor_parser.mbt`**

Delete these methods (they move to `lang/lambda/edits/`):
- `SyncEditor::get_ast`
- `SyncEditor::get_ast_pretty`
- `SyncEditor::get_resolution`
- `SyncEditor::get_dot_resolved`

Keep generic methods: `set_parser_signals`, `sync_parser_after_text_change`, `adjust_peer_cursors_after_text_change`, `resolve_applied_edit`, `apply_local_text_change`, `force_parser_reset`, `current_syntax_tree`, `mark_dirty`, `get_errors`, `is_parse_valid`.

- [ ] **Step 4: Delete `editor/tree_edit_bridge.mbt`**

The `apply_tree_edit` method moves to `lang/lambda/edits/`.

- [ ] **Step 5: Delete `editor/tree_edit_json.mbt`**

The `parse_tree_edit_op` function and helpers move to `lang/lambda/edits/`.

- [ ] **Step 6: Remove lambda imports from `editor/moon.pkg`**

Remove these lines:
```
"dowdiness/lambda" @parser,
"dowdiness/lambda/ast" @ast,
"dowdiness/canopy/lang/lambda" @lambda,
```

The `@parser.Edit` type used in `sync_editor_parser.mbt` and `text_diff.mbt` needs to be replaced with `@loom_core.Edit` or the equivalent from loom. **Verify** that `@parser.Edit` is the same type as `@loom_core.Edit` (lambda re-exports it). If so, replace all `@parser.Edit` references with the loom equivalent. If not, determine the correct import.

- [ ] **Step 7: Run `moon check` to verify editor compiles standalone**

The editor should now compile without any lambda references. Lambda editor functionality is broken (no factory), but the package itself is clean.

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy-refactor-editor && moon check --package dowdiness/canopy/editor`

Fix any remaining references. Common issues:
- `@parser.Edit` needs replacement (check `text_diff.mbt`, `sync_editor_parser.mbt`, `sync_editor_text.mbt`, `sync_editor_undo.mbt`)
- Test files referencing deleted methods (fix in Task 8)
- `@pretty.Pretty` trait bound may need explicit import

- [ ] **Step 8: Commit**

```bash
git add -A editor/
git commit -m "refactor(editor): remove all lambda-specific types and imports"
```

---

### Task 6: Create lambda editor factory and companion

**Files:**
- Create: `lang/lambda/edits/lambda_editor.mbt`
- Create: `lang/lambda/edits/lambda_ast_helpers.mbt`
- Create: `lang/lambda/edits/tree_edit_json.mbt` (moved from editor)
- Modify: `lang/lambda/edits/moon.pkg`
- Modify: `lang/lambda/top.mbt`

- [ ] **Step 1: Add editor and protocol imports to `lang/lambda/edits/moon.pkg`**

Add to the import block:
```
"dowdiness/canopy/editor" @editor,
"dowdiness/canopy/protocol" @protocol,
"dowdiness/pretty" @pretty,
"dowdiness/loom" @loom,
"dowdiness/canopy/lang/lambda/flat" @lambda_flat,
"dowdiness/canopy/lang/lambda/eval" @lambda_eval,
"dowdiness/incr" @incr,
```

Verify no circular dependency: editor no longer imports `lang/lambda`, so `lang/lambda/edits` -> `editor` is safe.

- [ ] **Step 2: Create `LambdaCompanion` and factory**

```moonbit
// lang/lambda/edits/lambda_editor.mbt
// Lambda editor factory and companion.

///|
pub struct LambdaCompanion {
  priv proj_memo : @incr.Memo[@lambda_flat.VersionedFlatProj]
  priv eval_memo : @incr.Memo[Array[@lambda_eval.EvalResult]]
}

///|
pub fn LambdaCompanion::get_flat_proj(
  self : LambdaCompanion,
) -> @lambda_proj.FlatProj? {
  self.proj_memo.get().proj
}

///|
pub fn LambdaCompanion::get_eval_results(
  self : LambdaCompanion,
) -> Array[@lambda_eval.EvalResult] {
  self.eval_memo.get()
}

///|
/// Create a lambda editor with its companion.
/// The companion holds lambda-specific memos (FlatProj, eval).
/// Capabilities closures capture the eval memo via Ref for lazy init.
pub fn new_lambda_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> (@editor.SyncEditor[@ast.Term], LambdaCompanion) {
  let proj_memo_ref : Ref[@incr.Memo[@lambda_flat.VersionedFlatProj]?] = Ref::new(
    None,
  )
  let eval_memo_ref : Ref[@incr.Memo[Array[@lambda_eval.EvalResult]]?] = Ref::new(
    None,
  )

  // Build capabilities — closures capture Ref cells, dereference at call time
  let capabilities : @editor.LanguageCapabilities[@ast.Term] = {
    get_annotations: Some(
      fn(proj_node : @core.ProjNode[@ast.Term]?) {
        match eval_memo_ref.val {
          Some(memo) =>
            build_eval_annotations(memo.get(), proj_node)
          None => {}
        }
      },
    ),
    pretty_post_process: Some(
      fn(layout : @pretty.Layout[@pretty.SyntaxCategory]) {
        match eval_memo_ref.val {
          Some(memo) =>
            @lambda_eval.inject_eval_annotations(layout, memo.get())
          None => layout
        }
      },
    ),
  }

  let editor = @editor.SyncEditor::new_generic(
    agent_id,
    fn(s) { @loom.new_imperative_parser(s, @parser.lambda_grammar) },
    fn(rt, source_text, syntax_tree, parser) {
      let (proj_memo, cached_proj_node, registry_memo, source_map_memo) = @lambda_flat.build_lambda_projection_memos(
        rt, source_text, syntax_tree, parser,
      )
      let eval_memo = @lambda_eval.build_eval_memo(rt, syntax_tree, parser)
      proj_memo_ref.val = Some(proj_memo)
      eval_memo_ref.val = Some(eval_memo)
      (cached_proj_node, registry_memo, source_map_memo)
    },
    capabilities~,
    capture_timeout_ms~,
  )

  let companion = LambdaCompanion::{
    proj_memo: proj_memo_ref.val.unwrap(),
    eval_memo: eval_memo_ref.val.unwrap(),
  }
  (editor, companion)
}

///|
/// Build eval annotation map from eval results and ProjNode.
fn build_eval_annotations(
  eval_results : Array[@lambda_eval.EvalResult],
  proj_node : @core.ProjNode[@ast.Term]?,
) -> Map[@core.NodeId, Array[@protocol.ViewAnnotation]] {
  let annotations : Map[@core.NodeId, Array[@protocol.ViewAnnotation]] = {}
  if eval_results.is_empty() {
    return annotations
  }
  let pn = match proj_node {
    Some(p) => p
    None => return annotations
  }
  let children = pn.children
  for i, result in eval_results {
    match result {
      Suppressed => continue
      Value(s) => {
        let target_id = if i < children.length() {
          children[i].id()
        } else {
          pn.id()
        }
        annotations[target_id] = [
          @protocol.ViewAnnotation(kind="eval", label="\u{2192} " + s),
        ]
      }
      Stuck(s) => {
        let target_id = if i < children.length() {
          children[i].id()
        } else {
          pn.id()
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

- [ ] **Step 3: Create lambda AST helper functions**

```moonbit
// lang/lambda/edits/lambda_ast_helpers.mbt
// Lambda-specific AST access functions.
// These were previously SyncEditor[@ast.Term] methods in editor/.

///|
pub fn get_lambda_ast(
  editor : @editor.SyncEditor[@ast.Term],
) -> @ast.Term {
  editor.get_tree().unwrap_or(@ast.Term::Unit)
}

///|
pub fn get_lambda_ast_pretty(
  editor : @editor.SyncEditor[@ast.Term],
) -> String {
  let ast = get_lambda_ast(editor)
  let formatted = @pretty.pretty_print(ast, width=60)
  "Expression: " + formatted + "\n\nAST:\n" + @debug.to_string(ast)
}

///|
pub fn get_lambda_resolution(
  editor : @editor.SyncEditor[@ast.Term],
) -> @parser.Resolution {
  let (_, res) = @parser.resolve(get_lambda_ast(editor))
  res
}

///|
pub fn get_lambda_dot_resolved(
  editor : @editor.SyncEditor[@ast.Term],
) -> String {
  let ast = get_lambda_ast(editor)
  let (resolved_ast, res) = @parser.resolve(ast)
  @parser.term_to_dot_resolved(resolved_ast, res)
}

///|
/// Apply a lambda tree edit via the companion's FlatProj.
pub fn apply_lambda_tree_edit(
  editor : @editor.SyncEditor[@ast.Term],
  companion : LambdaCompanion,
  op : TreeEditOp,
  timestamp_ms : Int,
) -> Result[Unit, @editor.TreeEditError] {
  let source_text = editor.get_text()
  let source_map = editor.get_source_map()
  let registry = editor.get_registry()
  let flat_proj = match companion.get_flat_proj() {
    Some(fp) => fp
    None =>
      return Err(@editor.TreeEditError::FlatProjUnavailable)
  }
  let ctx : EditContext[@ast.Term] = {
    source_text,
    source_map,
    registry,
    flat_proj,
  }
  match compute_text_edit(op, ctx) {
    Ok(Some((edits, focus_hint))) => {
      if edits.is_empty() {
        return Ok(())
      }
      editor.apply_span_edits(edits, focus_hint, timestamp_ms)
      Ok(())
    }
    Ok(None) =>
      Err(
        @editor.TreeEditError::UnhandledOperation(detail=op.to_string()),
      )
    Err(msg) => Err(@editor.TreeEditError::ProjectionEdit(detail=msg))
  }
}
```

- [ ] **Step 4: Move `parse_tree_edit_op` to `lang/lambda/edits/tree_edit_json.mbt`**

Copy the content from the deleted `editor/tree_edit_json.mbt`. Update type references:
- `@proj.NodeId` → `@core.NodeId`
- `@ast.Bop` → stays the same (already imported)
- `TreeEditError` → `@editor.TreeEditError`
- The helpers (`require_node_id`, `parse_bop_string`, `require_bop`, `require_string`) and `parse_tree_edit_op` all move.

Make `parse_tree_edit_op` public:
```moonbit
pub fn parse_tree_edit_op(json : Json) -> Result[TreeEditOp, @editor.TreeEditError]
```

- [ ] **Step 5: Update `lang/lambda/top.mbt` facade**

Add re-exports:
```moonbit
///|
pub using @lambda_edits {
  // ... existing re-exports ...
  type LambdaCompanion,
  new_lambda_editor,
  apply_lambda_tree_edit,
  get_lambda_ast,
  get_lambda_ast_pretty,
  get_lambda_resolution,
  get_lambda_dot_resolved,
  parse_tree_edit_op,
}
```

- [ ] **Step 6: Run `moon check`**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy-refactor-editor && moon check`

Fix compilation errors. Common issues:
- Missing imports in `lang/lambda/edits/moon.pkg`
- Type mismatches between `@core.NodeId` and `@proj.NodeId` (they're the same type, re-exported)
- `FocusHint` in `apply_span_edits` — verify it's from `@core` or `@proj`
- `SpanEdit` in `apply_span_edits` — verify the type path

- [ ] **Step 7: Commit**

```bash
git add lang/lambda/edits/ lang/lambda/top.mbt lang/lambda/moon.pkg
git commit -m "feat(lambda): add LambdaCompanion and new_lambda_editor factory"
```

---

### Task 7: Update FFI layer

**Files:**
- Modify: `ffi/canopy_lambda.mbt`
- Modify: `ffi/canopy_view.mbt`
- Modify: `ffi/canopy_pretty.mbt`
- Modify: `ffi/moon.pkg` (if needed)

- [ ] **Step 1: Create `LambdaHandle` and update editor registry**

In `ffi/canopy_lambda.mbt`, replace the editor registry:

```moonbit
///|
struct LambdaHandle {
  editor : @editor.SyncEditor[@ast.Term]
  companion : @lambda.LambdaCompanion
}

///|
let lambda_handles : Map[Int, LambdaHandle] = {}
```

- [ ] **Step 2: Update `create_editor`**

```moonbit
pub fn create_editor(agent_id : String) -> Int {
  let (editor, companion) = @lambda.new_lambda_editor(agent_id)
  let handle = next_handle.val
  next_handle.val = handle + 1
  last_created_handle.val = Some(handle)
  lambda_handles[handle] = LambdaHandle::{ editor, companion }
  handle
}
```

- [ ] **Step 3: Update all FFI functions to use LambdaHandle**

Every function that calls `editors.get(handle)` must change to `lambda_handles.get(handle)` and destructure the handle:

```moonbit
// Pattern for most functions:
match lambda_handles.get(handle) {
  Some(h) => h.editor.get_text()  // generic editor methods
  None => ""
}

// For lambda-specific operations:
match lambda_handles.get(handle) {
  Some(h) => @lambda.get_lambda_ast_pretty(h.editor)
  None => ""
}

// For tree editing:
match lambda_handles.get(handle) {
  Some(h) => {
    match @lambda.apply_lambda_tree_edit(h.editor, h.companion, op, timestamp_ms) {
      Ok(_) => "ok"
      Err(e) => "error: " + e.message()
    }
  }
  None => "error: invalid handle"
}
```

Update every function: `get_text`, `set_text`, `get_ast_dot_resolved`, `get_ast_pretty`, `get_errors_json`, `export_all_json`, `export_since_json`, `apply_sync_json`, `get_version_json`, `create_editor_with_undo`, `insert_and_record`, `delete_and_record`, `backspace_and_record`, `set_text_and_record`, `undo_manager_undo/redo/can_undo/can_redo/set_tracking/clear`, `ephemeral_*`, `get_proj_node_json`, `get_source_map_json`, `apply_tree_edit_json`, `insert_at`, `delete_at`, `undo_and_export_json`, `redo_and_export_json`, `ws_on_open/message/close`, `ws_broadcast_edit/cursor`, `handle_text_intent`, `handle_undo`, `handle_redo`, `handle_structural_intent`.

- [ ] **Step 4: Update `canopy_view.mbt` — use generic view pipeline**

```moonbit
pub fn get_view_tree_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) =>
      match h.editor.get_view_tree() {  // generic — capabilities provide annotations
        Some(view) => view.to_json().stringify()
        None => "null"
      }
    None => "null"
  }
}

pub fn compute_view_patches_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => {
      let state = match view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::new()
          view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_view_patches(state, h.editor)  // generic
      patches.to_json().stringify()
    }
    None => "[]"
  }
}
```

- [ ] **Step 5: Update `canopy_pretty.mbt` — use generic pretty pipeline**

```moonbit
pub fn get_pretty_view_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.get_pretty_view().to_json().stringify()  // generic
    None => "null"
  }
}

pub fn compute_pretty_patches_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => {
      let state = match pretty_view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::new()
          pretty_view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_pretty_patches(state, h.editor)  // generic
      patches.to_json().stringify()
    }
    None => "[]"
  }
}
```

- [ ] **Step 6: Update `destroy_editor`**

```moonbit
pub fn destroy_editor(handle : Int) -> Unit {
  lambda_handles.remove(handle)
  view_states.remove(handle)
  pretty_view_states.remove(handle)
}
```

- [ ] **Step 7: Run `moon check`**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy-refactor-editor && moon check`
Fix any remaining type errors.

- [ ] **Step 8: Commit**

```bash
git add ffi/
git commit -m "refactor(ffi): use LambdaHandle with generic view pipeline"
```

---

### Task 8: Update tests and verify

**Files:**
- Modify: `editor/eval_memo_wbtest.mbt` (or delete — tests may need restructuring)
- Modify: various test files
- Run full validation

- [ ] **Step 1: Update editor whitebox tests**

Tests in `editor/eval_memo_wbtest.mbt` use `SyncEditor::new_lambda` which no longer exists. Options:
- Add `"dowdiness/canopy/lang/lambda/edits" @lambda_edits` to `editor/moon.pkg` `for "wbtest"` section
- Replace `SyncEditor::new_lambda("id")` with `@lambda_edits.new_lambda_editor("id")` and destructure the tuple

Similarly update any other test files that reference removed methods.

- [ ] **Step 2: Update `editor/pretty_view_test.mbt` if it exists**

Check for tests calling `get_pretty_view`, `compute_pretty_patches`, `get_view_tree_with_eval`, `compute_view_patches_with_eval`. Update to use the generic versions.

- [ ] **Step 3: Update `editor/tree_edit_bridge_test.mbt`**

Tests for `apply_tree_edit` need to use the new `apply_lambda_tree_edit` from lang/lambda.

- [ ] **Step 4: Run full test suite**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy-refactor-editor
moon check
moon test
```

Expected: 0 errors, all tests pass. Test count may change slightly if some tests were restructured.

- [ ] **Step 5: Update interfaces and format**

```bash
moon info
moon fmt
```

- [ ] **Step 6: Verify API changes are intentional**

```bash
git diff -- '*.mbti'
```

Expected changes:
- `editor/pkg.generated.mbti`: Removed all lambda-specific methods and types. Added `LanguageCapabilities[T]`, `apply_span_edits`, `get_registry`, `get_tree`. No more `@lambda` or `@ast` in import list.
- `lang/lambda/edits/pkg.generated.mbti`: Added `LambdaCompanion`, `new_lambda_editor`, `apply_lambda_tree_edit`, `get_lambda_ast`, etc.
- `lang/lambda/pkg.generated.mbti`: Added re-exports for new functions.

- [ ] **Step 7: Run JS build if possible**

```bash
moon build --target js
```

Verify the JS build produces the same exports (check ffi/moon.pkg link exports list).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "test: update tests for LanguageCapabilities refactoring"
```

---

## Acceptance Criteria

- [ ] `editor/moon.pkg` has zero lambda-specific imports (`@parser`, `@ast`, `@lambda` all removed)
- [ ] `SyncEditor[T]` struct has zero lambda-typed fields
- [ ] `get_view_tree_with_eval` and `compute_view_patches_with_eval` are eliminated
- [ ] `new_lambda_editor` lives in `lang/lambda/edits/`, not `editor/`
- [ ] `moon check` passes with 0 errors
- [ ] `moon test` passes all tests (count >= 828)
- [ ] `moon build --target js` produces same link exports
- [ ] `git diff -- '*.mbti'` shows no unintended API removals

## Validation

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy-refactor-editor
moon check
moon test
moon info && moon fmt
moon build --target js
git diff -- '*.mbti'
```

## Risks

- **`@parser.Edit` type identity**: `text_diff.mbt` and `sync_editor_parser.mbt` reference `@parser.Edit` from `dowdiness/lambda`. After removing the `@parser` import, this type needs replacement. It's likely a re-export of `@loom_core.Edit` or `@loom.Edit`. Verify with `moon ide peek-def Edit` before replacing.
- **Ref lazy-init timing**: The capability closures capture `Ref` cells and dereference at call time. If any capability is called BEFORE `build_memos` runs (during construction), it will see `None`. This should not happen in practice — capabilities are called by view methods, which are called after construction.
- **Pretty trait bound**: Making `get_pretty_view` generic with `T : @pretty.Pretty` requires that JSON and Markdown AST types also implement `Pretty` if they want pretty view support. Currently only lambda uses pretty view, so this is fine. If JSON/Markdown need it later, they implement the trait.
- **Test file restructuring**: Tests that used `SyncEditor::new_lambda` need migration. The `for "wbtest"` import mechanism avoids production dependency cycles.

## Notes

- This plan builds on the prior refactoring (PR branch `refactor/extract-lambda-from-editor`) which already moved `build_lambda_projection_memos` to `lang/lambda/flat/` and eval logic to `lang/lambda/eval/`.
- The `LanguageCapabilities[T]` approach was chosen over: trait + type parameter (viral), wrapper struct (delegation boilerplate), ECS (runtime machinery MoonBit lacks), pure explicit composition (would need `_with_annotations` variants in FFI).
- Future languages (Haskell, etc.) follow the same pattern: provide `LanguageCapabilities[T]` closures + optional companion for structural editing.
