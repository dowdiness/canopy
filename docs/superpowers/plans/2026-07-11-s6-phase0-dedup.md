# S6 Phase 0 De-duplication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove repeated selection, text-load, and CRDT tree-edit update code while preserving behavior and fixing the invalid `OutlineNavigate` crash.

**Architecture:** Keep every helper package-private in `dowdiness/ideal-editor/main`. Characterize the five selection/highlight call sites before extraction, then introduce narrow helpers whose callers retain their distinct navigation-reset and error policies.

**Tech Stack:** MoonBit, Canopy `SyncEditor`, Rabbita `Cmd`, white-box tests, Playwright.

## Global Constraints

- Phase 0 lands before Phase 2.
- `commit_tree_edit` covers all four call sites and returns `Result`; it never swallows an apply error.
- `OutlineStructuralEdit`, `OutlineDrop`, and `apply_structural_edit_request` preserve their current `Err` no-op policy; `execute_action` converts the same error to child-cell `SetError`.
- `highlight_set_for` takes an explicit `reset_nav : Bool`; `OutlineNavigate` passes `false`, while click, structural-edit selection, and structure-mode selection pass `true`.
- Fix the invalid `OutlineNavigate` branch separately from the extraction: it returns `Some((none, model))`, not `None`.
- `CmDocChanged`, `Undo`, and `Redo` remain outside the text-load helper.
- Run workspace MoonBit checks and the two selection-sensitive Playwright specs.

---

### Task 1: Characterize the five selection/highlight call sites

**Files:**
- Modify: `examples/ideal/main/main_wbtest.mbt`
- Test: `examples/ideal/main/main_wbtest.mbt`

**Interfaces:**
- Consumes: `init_model() -> Model raise`, `refresh(Model) -> Model`, `handle_outline(Emit[Msg], Msg, Model) -> (Cmd, Model)?`, `handle_structure_mode(Emit[Msg], Msg, Model) -> (Cmd, Model)?`
- Produces: five regression tests pinning `refresh`, `OutlineNodeClicked`, `OutlineNavigate`, `OutlineStructuralEdit`, and `StructureNodeSelected`

- [ ] **Step 1: Write the characterization tests before changing production code**

Append this complete test support and the five tests to `main_wbtest.mbt`:

```moonbit
///|
fn selected_test_model() -> (Model, String) raise {
  let model = init_model()
  let node_id = model.editor.get_source_map()
    .innermost_node_at(model.editor.get_cursor())
    .unwrap()
  (model, node_id_to_string(node_id))
}

///|
test "selection characterization: refresh recomputes selected highlight" {
  let (model, node_id) = try! selected_test_model()
  let refreshed = refresh({ ..model, selected_node: Some(node_id) })
  inspect(refreshed.highlight_set.is_empty(), content="false")
}

///|
test "selection characterization: outline click selects highlights and clears nav" {
  let (model, node_id) = try! selected_test_model()
  model.nav_path = Some([0])
  let Some((_, changed)) = handle_outline(
    test_parent_emit(),
    OutlineNodeClicked(node_id),
    model,
  ) else {
    abort("OutlineNodeClicked was not handled")
  }
  inspect(changed.selected_node, content="Some(\"\{node_id}\")")
  inspect(changed.highlight_set.is_empty(), content="false")
  inspect(changed.nav_path is None, content="true")
}

///|
test "selection characterization: outline navigation preserves nav cache" {
  let (model, node_id) = try! selected_test_model()
  model.nav_path = Some([0])
  let Some((_, changed)) = handle_outline(
    test_parent_emit(),
    OutlineNavigate(node_id),
    model,
  ) else {
    abort("OutlineNavigate was not handled")
  }
  inspect(changed.selected_node, content="Some(\"\{node_id}\")")
  inspect(changed.highlight_set.is_empty(), content="false")
  inspect(changed.nav_path, content="Some([0])")
}

///|
test "selection characterization: outline structural edit refreshes selection" {
  let (model, node_id) = try! selected_test_model()
  model.nav_path = Some([0])
  let nid = parse_node_id(node_id).unwrap()
  let Some((_, changed)) = handle_structural(
    test_parent_emit(),
    OutlineStructuralEdit(@lambda_edits.TreeEditOp::Select(node_id=nid)),
    model,
  ) else {
    abort("OutlineStructuralEdit was not handled")
  }
  inspect(changed.highlight_set.is_empty(), content="false")
  inspect(changed.nav_path is None, content="true")
}

///|
test "selection characterization: structure selection highlights and clears nav" {
  let (model, node_id) = try! selected_test_model()
  model.nav_path = Some([0])
  let Some((_, changed)) = handle_structure_mode(
    test_parent_emit(),
    StructureNodeSelected(node_id),
    model,
  ) else {
    abort("StructureNodeSelected was not handled")
  }
  inspect(changed.selected_node, content="Some(\"\{node_id}\")")
  inspect(changed.highlight_set.is_empty(), content="false")
  inspect(changed.nav_path is None, content="true")
}
```

- [ ] **Step 2: Run the characterization tests**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: PASS; these tests pin the pre-extraction behavior.

- [ ] **Step 3: Commit**

```bash
git add examples/ideal/main/main_wbtest.mbt
git commit -m "test(ideal): characterize selection update paths"
```

### Task 2: Fix invalid outline navigation without bundling it into extraction

**Files:**
- Modify: `examples/ideal/main/update_handlers.mbt:194-211`
- Modify: `examples/ideal/main/main_wbtest.mbt`
- Test: `examples/ideal/main/main_wbtest.mbt`

**Interfaces:**
- Consumes: `handle_outline(Emit[Msg], Msg, Model) -> (Cmd, Model)?`
- Produces: invalid `OutlineNavigate` is handled as `(none, unchanged_model)`

- [ ] **Step 1: Write the failing crash-regression test**

```moonbit
///|
test "outline navigation with an invalid id is a handled no-op" {
  let model = try! init_model()
  let Some((_, changed)) = handle_outline(
    test_parent_emit(),
    OutlineNavigate("not-a-node-id"),
    model,
  ) else {
    abort("invalid OutlineNavigate fell through to the top-level abort")
  }
  inspect(changed.selected_node, content="None")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: FAIL with `invalid OutlineNavigate fell through to the top-level abort`.

- [ ] **Step 3: Write the one-line implementation**

In the `OutlineNavigate` parse failure arm, replace only the failure return:

```moonbit
            None => return Some((none, model))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/main/update_handlers.mbt examples/ideal/main/main_wbtest.mbt
git commit -m "fix(ideal): handle invalid outline navigation ids"
```

### Task 3: Extract explicit selection/highlight helpers

**Files:**
- Modify: `examples/ideal/main/main.mbt:236-263`
- Modify: `examples/ideal/main/update_handlers.mbt:127-232,336-362`
- Test: `examples/ideal/main/main_wbtest.mbt`

**Interfaces:**
- Consumes: `parse_node_id(String) -> NodeId?`, `@scope.compute_highlight_set(NodeId, Map[NodeId, ScopeAnnotation]) -> HashSet[NodeId]`
- Produces: `highlight_set_for(String?, Map[NodeId, ScopeAnnotation]) -> HashSet[NodeId]`; `select_with_highlight(Model, String?, Bool) -> Model`

- [ ] **Step 1: Write the failing helper test**

```moonbit
///|
test "select_with_highlight obeys its explicit reset_nav policy" {
  let (model, node_id) = try! selected_test_model()
  model.nav_path = Some([0])
  let preserved = select_with_highlight(model, Some(node_id), false)
  inspect(preserved.highlight_set.is_empty(), content="false")
  inspect(preserved.nav_path, content="Some([0])")
  let reset = select_with_highlight(model, Some(node_id), true)
  inspect(reset.nav_path is None, content="true")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: FAIL because `select_with_highlight` is undefined.

- [ ] **Step 3: Write the minimal helpers and replace all five duplicated sites**

Add beside `refresh`:

```moonbit
///|
fn highlight_set_for(
  node_id : String?,
  scope_map : Map[@canopy_core.NodeId, @scope.ScopeAnnotation],
) -> @immut/hashset.HashSet[@canopy_core.NodeId] {
  match node_id {
    Some(value) =>
      match parse_node_id(value) {
        Some(nid) => @scope.compute_highlight_set(nid, scope_map)
        None => @immut/hashset.new()
      }
    None => @immut/hashset.new()
  }
}

///|
fn select_with_highlight(
  model : Model,
  selected_node : String?,
  reset_nav : Bool,
) -> Model {
  let highlight_set = highlight_set_for(selected_node, model.scope_map)
  if reset_nav {
    { ..model, selected_node, highlight_set, nav_path: None }
  } else {
    { ..model, selected_node, highlight_set }
  }
}
```

Replace `refresh`'s nested parse block with:

```moonbit
  let highlight_set = highlight_set_for(model.selected_node, scope_map)
```

At the four handler selection bundles, use these exact policies:

```moonbit
let selected = select_with_highlight(model, Some(node_id), true)
let selected = select_with_highlight(model, new_selected, false)
let selected = select_with_highlight(new_model, new_selected, true)
let selected = select_with_highlight(model, Some(node_id), true)
```

Preserve each site's existing `cmd` and `outline_state` fields by spreading the corresponding `selected` value into its returned model.

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: PASS, including all five characterization tests.

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/main/main.mbt examples/ideal/main/update_handlers.mbt examples/ideal/main/main_wbtest.mbt
git commit -m "refactor(ideal): centralize selection highlighting"
```

### Task 4: Extract the shared text-load pipeline

**Files:**
- Modify: `examples/ideal/main/main.mbt:58-85`
- Modify: `examples/ideal/main/update_handlers.mbt:307-335`
- Modify: `examples/ideal/main/main_wbtest.mbt`
- Test: `examples/ideal/main/main_wbtest.mbt`

**Interfaces:**
- Consumes: `refresh(Model) -> Model`, `sync_after_local_model_change(Model, String) -> Cmd`
- Produces: `apply_text_edit(Model, String) -> (String, Model)`; `load_text(Model, String) -> (Cmd, Model)`

- [ ] **Step 1: Write the failing helper test**

```moonbit
///|
test "load_text records text and advances the edit timestamp" {
  let model = try! init_model()
  let before = model.next_timestamp
  let (_, changed) = load_text(model, "fn loaded() { 42 }")
  inspect(changed.editor.get_text(), content="fn loaded() { 42 }")
  inspect(changed.next_timestamp, content="\{before + 1}")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: FAIL because `load_text` is undefined.

- [ ] **Step 3: Write the implementation and replace only `LoadExample` and `FileLoaded`**

Add to `main.mbt` with the other commands:

```moonbit
///|
fn apply_text_edit(model : Model, text : String) -> (String, Model) {
  model.editor.set_text_and_record(text, js_now_ms())
  let changed = refresh({
    ..model,
    next_timestamp: model.next_timestamp + 1,
  })
  (changed.editor.get_text(), changed)
}

///|
fn load_text(model : Model, text : String) -> (Cmd, Model) {
  let (actual_text, changed) = apply_text_edit(model, text)
  (sync_after_local_model_change(changed, actual_text), changed)
}
```

Replace the two handler arms with:

```moonbit
    LoadExample(example_text) => Some(load_text(model, example_text))
```

and

```moonbit
    FileLoaded(content) => Some(load_text(model, content))
```

Do not change `CmDocChanged`, `Undo`, or `Redo`.

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/main/main.mbt examples/ideal/main/update_handlers.mbt examples/ideal/main/main_wbtest.mbt
git commit -m "refactor(ideal): share text load pipeline"
```

### Task 5: Extract tree-edit commit while preserving caller error policy

**Files:**
- Modify: `examples/ideal/main/main.mbt:397-432`
- Modify: `examples/ideal/main/update_handlers.mbt:109-171,255-303`
- Modify: `examples/ideal/main/action_overlay_exec.mbt:1-40`
- Modify: `examples/ideal/main/main_wbtest.mbt`
- Test: `examples/ideal/main/main_wbtest.mbt`

**Interfaces:**
- Consumes: `@lambda.apply_lambda_tree_edit`, `push_intent`, `push_patch`, `refresh`, `sync_after_local_model_change`
- Produces: `commit_tree_edit(Model, @lambda_edits.TreeEditOp) -> Result[(Cmd, Model), @editor.TreeEditError]`

- [ ] **Step 1: Write the failing success-path test**

```moonbit
///|
test "commit_tree_edit returns the committed model" {
  let (model, node_id) = try! selected_test_model()
  let op = @lambda_edits.TreeEditOp::Select(
    node_id=parse_node_id(node_id).unwrap(),
  )
  match commit_tree_edit(model, op) {
    Ok((_, changed)) =>
      inspect(changed.next_timestamp, content="\{model.next_timestamp + 1}")
    Err(err) => abort(err.message())
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: FAIL because `commit_tree_edit` is undefined.

- [ ] **Step 3: Write the minimal result-returning implementation**

Add beside `apply_structural_edit_request`:

```moonbit
///|
fn commit_tree_edit(
  model : Model,
  tree_op : @lambda_edits.TreeEditOp,
) -> Result[(Cmd, Model), @editor.TreeEditError] {
  match @lambda.apply_lambda_tree_edit(
    model.editor,
    model.companion,
    tree_op,
    js_now_ms(),
  ) {
    Ok(edits) => {
      push_intent(model, tree_op)
      push_patch(model, tree_op, edits)
      let changed = refresh({
        ..model,
        next_timestamp: model.next_timestamp + 1,
      })
      let cmd = sync_after_local_model_change(changed, changed.editor.get_text())
      Ok((cmd, changed))
    }
    Err(err) => Err(err)
  }
}
```

Use `commit_tree_edit(model, tree_op)` in all four sites. In `OutlineStructuralEdit`, `OutlineDrop`, and `apply_structural_edit_request`, retain:

```moonbit
Err(_) => (none, model)
```

(wrap with `Some(...)` in handlers). In `execute_action`, retain the child-visible failure:

```moonbit
Err(err) =>
  (runtime.send(SetError(ApplyActionFailed(err.message()))), model)
```

For the `OutlineStructuralEdit` success tail, apply its selection-only post-processing to the `new_model` returned by `commit_tree_edit`; do not reapply the edit or resync.

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: PASS; all four call sites compile against the result-returning helper.

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/main/main.mbt examples/ideal/main/update_handlers.mbt examples/ideal/main/action_overlay_exec.mbt examples/ideal/main/main_wbtest.mbt
git commit -m "refactor(ideal): centralize tree edit commits"
```

### Task 6: Verify Phase 0 behavior across MoonBit and browser boundaries

**Files:**
- Test: `examples/ideal/main/main_wbtest.mbt`
- Test: `examples/ideal/web/e2e/structure-mode-switch.spec.ts`
- Test: `examples/ideal/web/e2e/structural-editing.spec.ts`

**Interfaces:**
- Consumes: completed Phase 0 helpers and handlers
- Produces: a shippable Phase 0 baseline for Phase 2

- [ ] **Step 1: Run the package tests**

Run: `moon test -p dowdiness/ideal-editor/main`

Expected: PASS.

- [ ] **Step 2: Run workspace validation**

Run: `moon check && moon test`

Expected: PASS.

- [ ] **Step 3: Build the JS artifacts used by Ideal E2E**

Run: `moon build --target js`

Expected: PASS and refreshed namespaced JS artifacts.

- [ ] **Step 4: Run the two selection-sensitive browser specs**

Run: `cd examples/ideal/web && npx playwright test e2e/structure-mode-switch.spec.ts e2e/structural-editing.spec.ts`

Expected: PASS with no selection/highlight regression or unhandled message crash.

- [ ] **Step 5: Commit any generated interface changes only when intentional**

```bash
git add examples/ideal/main
git commit -m "test(ideal): verify phase zero deduplication"
```

Expected: skip this commit when validation produced no tracked changes.
