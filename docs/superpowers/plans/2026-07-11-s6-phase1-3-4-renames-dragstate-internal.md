# S6 Phases 1, 3, and 4 Organization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Ideal app layer navigable through feature-scoped files, group outline drag state, and enforce `Model`-free rendering boundaries with internal packages.

**Architecture:** Perform move-only file splits after Phase 0, keeping all application behavior and top-level dispatch in the parent package. Fold the small `DragState` grouping into the same mechanical plan, then extract only pure history and Graphviz computation behind narrow `internal/` APIs while parent adapters continue to own `Model`, caches, and HTML panels.

**Tech Stack:** MoonBit packages, Rabbita views, Canopy history snapshots, Graphviz parser/layout/SVG packages, white-box tests.

## Global Constraints

- Phase 0 is already landed; this plan is independent of Phase 2.
- Outline drag-and-drop remains parent-owned plain state. It does not become a cell or package.
- Renames are move-only: no behavior, signature, visibility, ordering, or formatting changes in the same commit.
- `view_history.mbt` is not split merely for discoverability; its complete pure pipeline moves together to `internal/history_render` in Phase 4.
- Only functions whose signatures are `Model`-free enter `internal/` packages.
- `render_graphviz_html`, `render_incr_graph_html`, and `render_history_html` stay in `main` as adapters.
- Run `moon check && moon test` after every independently shippable grouping.

---

### Task 1: Group outline drag fields into `DragState`

**Files:**
- Modify: `examples/ideal/main/model.mbt:66-91`
- Modify: `examples/ideal/main/main.mbt:45-61`
- Modify: `examples/ideal/main/update_handlers.mbt:232-307`
- Modify: `examples/ideal/main/view_outline.mbt:94-121`
- Modify: `examples/ideal/main/main_wbtest.mbt`
- Test: `examples/ideal/main/main_wbtest.mbt`

**Interfaces:**
- Consumes: `NodeId?`, `DropPosition?`
- Produces: `DragState::{empty, start, over, clear_target, clear}` and `Model.drag : DragState`

- [ ] **Step 1: Write the failing value-semantics test**

```moonbit
///|
test "drag state groups source target and position" {
  let source = @canopy_core.NodeId::from_int(1)
  let target = @canopy_core.NodeId::from_int(2)
  let drag = DragState::empty()
    .start(source)
    .over(target, @canopy_core.DropPosition::Inside)
  inspect(drag.source, content="Some(1)")
  inspect(drag.target_id, content="Some(2)")
  inspect(drag.position is Some(@canopy_core.DropPosition::Inside), content="true")
  inspect(drag.clear().source is None, content="true")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: FAIL because `DragState` is undefined.

- [ ] **Step 3: Implement the grouped value and update every use**

```moonbit
///|
struct DragState {
  source : @canopy_core.NodeId?
  target_id : @canopy_core.NodeId?
  position : @canopy_core.DropPosition?
}

///|
fn DragState::empty() -> DragState {
  { source: None, target_id: None, position: None }
}

///|
fn DragState::start(self : DragState, source : @canopy_core.NodeId) -> DragState {
  { ..self, source: Some(source) }
}

///|
fn DragState::over(
  self : DragState,
  target_id : @canopy_core.NodeId,
  position : @canopy_core.DropPosition,
) -> DragState {
  { ..self, target_id: Some(target_id), position: Some(position) }
}

///|
fn DragState::clear_target(self : DragState) -> DragState {
  { ..self, target_id: None, position: None }
}

///|
fn DragState::clear(self : DragState) -> DragState {
  DragState::empty()
}
```

Replace the three `Model` fields with `drag : DragState`, initialize it as `drag: DragState::empty()`, and update handlers to call `start`, `over`, `clear_target`, and `clear`. In `OutlineDrop`, save `let source = model.drag.source` before clearing. In `view_outline_node`, read `model.drag.source`, `model.drag.target_id`, and `model.drag.position`.

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/main/model.mbt examples/ideal/main/main.mbt examples/ideal/main/update_handlers.mbt examples/ideal/main/view_outline.mbt examples/ideal/main/main_wbtest.mbt
git commit -m "refactor(ideal): group outline drag state"
```

### Task 2: Split update handlers by message family

**Files:**
- Create: `examples/ideal/main/update_workspace.mbt`
- Create: `examples/ideal/main/update_structural.mbt`
- Create: `examples/ideal/main/update_outline.mbt`
- Create: `examples/ideal/main/update_file_io.mbt`
- Create: `examples/ideal/main/update_structure_mode.mbt`
- Create: `examples/ideal/main/update_codemirror.mbt`
- Modify: `examples/ideal/main/update_handlers.mbt:1-455`
- Test: `examples/ideal/main/main_wbtest.mbt`

**Interfaces:**
- Consumes: existing `handle_workspace`, `handle_structural`, `handle_outline`, `handle_file_io`, `handle_structure_mode`, `handle_codemirror`
- Produces: unchanged handler signatures in feature-named files

- [ ] **Step 1: Capture the move-only baseline**

Run: `moon test -p dowdiness/ideal-editor/main`

Expected: PASS.

- [ ] **Step 2: Move complete declarations without editing their bodies**

Move lines 5-79 to `update_workspace.mbt`, 81-173 to `update_structural.mbt`, 175-306 to `update_outline.mbt`, 329-364 to `update_file_io.mbt`, 366-417 to `update_structure_mode.mbt`, and 419-455 to `update_codemirror.mbt`. If Phase 2 has not landed, keep `handle_overlay` in a thin `update_handlers.mbt`; if Phase 2 has landed, remove the now-empty file because overlay dispatch already lives in its prescribed parent file.

- [ ] **Step 3: Run the package test to prove the move is behavior-neutral**

Run: `moon check -p dowdiness/ideal-editor/main && moon test -p dowdiness/ideal-editor/main`

Expected: PASS with unchanged handler symbols.

- [ ] **Step 4: Review the move diff**

Run: `git diff --stat && git diff -- examples/ideal/main/update_*.mbt`

Expected: declaration bodies are byte-for-byte moves except for file header comments.

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/main/update_handlers.mbt examples/ideal/main/update_workspace.mbt examples/ideal/main/update_structural.mbt examples/ideal/main/update_outline.mbt examples/ideal/main/update_file_io.mbt examples/ideal/main/update_structure_mode.mbt examples/ideal/main/update_codemirror.mbt
git commit -m "refactor(ideal): split update handlers by feature"
```

### Task 3: Split `main.mbt` by application responsibility

**Files:**
- Create: `examples/ideal/main/init.mbt`
- Create: `examples/ideal/main/commands.mbt`
- Create: `examples/ideal/main/intent_log.mbt`
- Create: `examples/ideal/main/view_root.mbt`
- Create: `examples/ideal/main/update.mbt`
- Modify: `examples/ideal/main/main.mbt:1-588`
- Test: `examples/ideal/main/main_wbtest.mbt`

**Interfaces:**
- Consumes: all existing declarations in `main.mbt`
- Produces: the same package-private symbols in responsibility-named files

- [ ] **Step 1: Record the pre-move package result**

Run: `moon test -p dowdiness/ideal-editor/main`

Expected: PASS.

- [ ] **Step 2: Move init declarations**

Move `init_model`, `subscriptions`, and `main` unchanged to `init.mbt`. Keep `using @sub {type Sub}` with the declarations that require it.

- [ ] **Step 3: Move commands and selection computation**

Move `parse_node_id`, `cm_mount_cmd`, `sync_after_local_model_change`, `sync_after_external_crdt_change`, `select_text_node_cmd`, `select_editor_node_cmd`, `build_scope_map_from_editor`, `highlight_set_for`, `select_with_highlight`, `refresh`, `tree_node_is_elided`, and `can_hydrate_tree_node` unchanged to `commands.mbt`.

- [ ] **Step 4: Move intent logging**

Move `MAX_INTENT_LOG`, `MAX_PATCH_LOG`, `MAX_PATCH_INSERTED_CHARS`, `push_intent`, `push_intent_label`, and `push_patch` unchanged to `intent_log.mbt`.

- [ ] **Step 5: Move root rendering**

Move `examples`, `view_toolbar`, `view_peer_status`, `outline_panel_attrs`, `view_outline_resize_handle`, and `view` unchanged to `view_root.mbt`, including `using @html {button, div, p, span, text}` and the Rabbita `Html`/`Emit` aliases they use.

- [ ] **Step 6: Leave a thin update unit**

Move `commit_tree_edit`, `apply_text_edit`, `load_text`, `apply_structural_edit_request`, and the top-level `update` dispatcher unchanged to `update.mbt`. Delete `main.mbt` after it contains no declarations.

- [ ] **Step 7: Run test to verify the split**

Run: `moon check -p dowdiness/ideal-editor/main && moon test -p dowdiness/ideal-editor/main`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add examples/ideal/main/main.mbt examples/ideal/main/init.mbt examples/ideal/main/commands.mbt examples/ideal/main/intent_log.mbt examples/ideal/main/view_root.mbt examples/ideal/main/update.mbt
git commit -m "refactor(ideal): split app root responsibilities"
```

### Task 4: Split bottom-panel rendering by tab feature

**Files:**
- Modify: `examples/ideal/main/view_bottom.mbt:1-687`
- Create: `examples/ideal/main/view_bottom_graphviz.mbt`
- Create: `examples/ideal/main/view_bottom_incr_graph.mbt`
- Create: `examples/ideal/main/view_bottom_oplog.mbt`
- Create: `examples/ideal/main/view_bottom_patch.mbt`
- Create: `examples/ideal/main/view_bottom_problems.mbt`
- Test: `examples/ideal/main/main_wbtest.mbt`

**Interfaces:**
- Consumes: current bottom-tab functions and shared `RenderCache`
- Produces: thin `view_bottom.mbt` containing tab definitions, ARIA/tab chrome, panel dispatch, and shared cache primitives

- [ ] **Step 1: Capture the move-only baseline**

Run: `moon test -p dowdiness/ideal-editor/main`

Expected: PASS.

- [ ] **Step 2: Move complete feature declarations**

Move `render_graphviz_html` and `view_graphviz_panel` to `view_bottom_graphviz.mbt`; move `incr_legend_html`, `render_incr_graph_html`, and `view_incr_graph_panel` to `view_bottom_incr_graph.mbt`; move `view_op_log` to `view_bottom_oplog.mbt`; move `format_structured_change` and `view_patch_log` to `view_bottom_patch.mbt`; move `view_problems` to `view_bottom_problems.mbt`.

Keep `RenderCache`, its three instances, `render_cache_key`, `cache_hit`, `cache_store`, `bottom_tab_svg_config`, `render_dot_to_svg`, `render_history_html`, all `bottom_tab_*` helpers, `view_bottom_tabs`, `view_history_panel`, and `view_bottom_content` in the thin root until Task 6 extracts pure rendering.

- [ ] **Step 3: Run test to verify the move**

Run: `moon check -p dowdiness/ideal-editor/main && moon test -p dowdiness/ideal-editor/main`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add examples/ideal/main/view_bottom.mbt examples/ideal/main/view_bottom_graphviz.mbt examples/ideal/main/view_bottom_incr_graph.mbt examples/ideal/main/view_bottom_oplog.mbt examples/ideal/main/view_bottom_patch.mbt examples/ideal/main/view_bottom_problems.mbt
git commit -m "refactor(ideal): split bottom panel views"
```

### Task 5: Extract pure history rendering to `internal/history_render`

**Files:**
- Create: `examples/ideal/main/internal/history_render/moon.pkg`
- Create: `examples/ideal/main/internal/history_render/history_render.mbt`
- Create: `examples/ideal/main/internal/history_render/history_render_wbtest.mbt`
- Modify: `examples/ideal/main/view_history.mbt:1-510`
- Modify: `examples/ideal/main/view_history_wbtest.mbt:1-305`
- Modify: `examples/ideal/main/view_bottom.mbt:230-262`
- Modify: `examples/ideal/main/moon.pkg:1-32`
- Test: `examples/ideal/main/internal/history_render/history_render_wbtest.mbt`

**Interfaces:**
- Consumes: `@history.CausalSnapshot`
- Produces: `pub enum HistoryRender { Empty; Dot(String); TooLarge(Int) }`; `render_history(CausalSnapshot, String) -> HistoryRender`; `legend_html(CausalSnapshot, String) -> String`; `escape_html_string(String) -> String`; `max_ops() -> Int`

- [ ] **Step 1: Move the white-box tests to establish package ownership**

Move the complete contents of `view_history_wbtest.mbt` to `internal/history_render/history_render_wbtest.mbt` without changing test bodies. This preserves white-box access to `collect_history_data` and `escape_dot_string`.

- [ ] **Step 2: Run test to verify the package does not exist**

Run: `moon test -p dowdiness/ideal-editor/main/internal/history_render`

Expected: FAIL because the package manifest and implementation are absent.

- [ ] **Step 3: Create the internal manifest**

```moonbit
import {
  "dowdiness/event-graph-walker/history",
  "dowdiness/canopy/editor",
  "dowdiness/canopy/lang/lambda",
  "dowdiness/lambda/ast",
  "dowdiness/graphviz/lib/parser" @gv_parser,
}

supported_targets = "js"
```

- [ ] **Step 4: Move the complete pure pipeline and expose only adapter needs**

Move all declarations from `view_history.mbt` into `history_render.mbt` unchanged. Keep implementation helpers private. Add:

```moonbit
pub fn escape_html_string(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '&' => buf.write_string("&amp;")
      '"' => buf.write_string("&quot;")
      '\'' => buf.write_string("&#39;")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

pub fn max_ops() -> Int { MAX_OPS }
```

The first function replaces the moved private declaration rather than duplicating it.

- [ ] **Step 5: Wire the parent adapter**

Add `"dowdiness/ideal-editor/main/internal/history_render" @history_render` to `main/moon.pkg`. In `render_history_html`, qualify `render_history`, `HistoryRender` variants, `legend_html`, `escape_html_string`, and replace `MAX_OPS` with `@history_render.max_ops()`.

- [ ] **Step 6: Run test to verify it passes**

Run: `moon check -p dowdiness/ideal-editor/main/internal/history_render && moon test -p dowdiness/ideal-editor/main/internal/history_render && moon test -p dowdiness/ideal-editor/main`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add examples/ideal/main/internal/history_render examples/ideal/main/view_history.mbt examples/ideal/main/view_history_wbtest.mbt examples/ideal/main/view_bottom.mbt examples/ideal/main/moon.pkg
git commit -m "refactor(ideal): isolate history rendering pipeline"
```

### Task 6: Extract pure DOT-to-SVG rendering to `internal/graphviz_render`

**Files:**
- Create: `examples/ideal/main/internal/graphviz_render/moon.pkg`
- Create: `examples/ideal/main/internal/graphviz_render/graphviz_render.mbt`
- Create: `examples/ideal/main/internal/graphviz_render/graphviz_render_wbtest.mbt`
- Modify: `examples/ideal/main/view_bottom.mbt:88-131`
- Modify: `examples/ideal/main/moon.pkg:1-32`
- Test: `examples/ideal/main/internal/graphviz_render/graphviz_render_wbtest.mbt`

**Interfaces:**
- Consumes: DOT `String`
- Produces: `render_dot_to_svg(String) -> String`; `svg_config() -> @gv_svg.SvgConfig`

- [ ] **Step 1: Write the failing package test**

```moonbit
///|
test "empty dot renders the no-data placeholder" {
  inspect(
    render_dot_to_svg("digraph { }"),
    content="<span class=\"no-problems\">No graph data</span>",
  )
}

///|
test "invalid dot renders a parse error" {
  inspect(render_dot_to_svg("not dot").has_prefix(
    "<span class=\"problem-text\">Parse error at ",
  ), content="true")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/ideal-editor/main/internal/graphviz_render`

Expected: FAIL because the package does not exist.

- [ ] **Step 3: Create the package manifest**

```moonbit
import {
  "dowdiness/graphviz/lib/parser" @gv_parser,
  "dowdiness/graphviz/lib/layout" @gv_layout,
  "dowdiness/graphviz/lib/svg" @gv_svg,
}

supported_targets = "js"
```

- [ ] **Step 4: Move the complete pure renderer**

```moonbit
///|
let bottom_tab_svg_config : @gv_svg.SvgConfig = {
  ..@gv_svg.SvgConfig::dark_theme(),
  font_size: 9.0,
}

///|
pub fn svg_config() -> @gv_svg.SvgConfig { bottom_tab_svg_config }

///|
pub fn render_dot_to_svg(dot : String) -> String {
  if dot == "" || dot == "digraph { }" {
    return "<span class=\"no-problems\">No graph data</span>"
  }
  match @gv_parser.parse_dot(dot) {
    Ok(graph) => {
      let layout = @gv_layout.compute_layout_with_config(
        graph,
        @gv_layout.LayoutConfig::compact(),
      )
      @gv_svg.render_svg_with_config(layout, bottom_tab_svg_config)
    }
    Err(e) =>
      "<span class=\"problem-text\">Parse error at \{e.position}: \{e.message}</span>"
  }
}
```

- [ ] **Step 5: Wire the parent adapters**

Add `"dowdiness/ideal-editor/main/internal/graphviz_render" @graphviz_render` to `main/moon.pkg`. Replace parent calls with `@graphviz_render.render_dot_to_svg(dot)` and replace the IncrGraph call's config argument with `@graphviz_render.svg_config()`.

- [ ] **Step 6: Run test to verify it passes**

Run: `moon check -p dowdiness/ideal-editor/main/internal/graphviz_render && moon test -p dowdiness/ideal-editor/main/internal/graphviz_render && moon test -p dowdiness/ideal-editor/main`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add examples/ideal/main/internal/graphviz_render examples/ideal/main/view_bottom.mbt examples/ideal/main/view_bottom_incr_graph.mbt examples/ideal/main/view_bottom_graphviz.mbt examples/ideal/main/moon.pkg
git commit -m "refactor(ideal): isolate graphviz rendering"
```

### Task 7: Verify the complete mechanical organization phase

**Files:**
- Test: `examples/ideal/main/main_wbtest.mbt`
- Test: `examples/ideal/main/internal/history_render/history_render_wbtest.mbt`
- Test: `examples/ideal/main/internal/graphviz_render/graphviz_render_wbtest.mbt`

**Interfaces:**
- Consumes: all Phase 1/3/4 moves
- Produces: independently shippable, workspace-green organization change

- [ ] **Step 1: Format and regenerate interfaces**

Run: `moon fmt && moon info`

Expected: PASS.

- [ ] **Step 2: Review package surfaces**

Run: `git diff -- '*.mbti'`

Expected: internal packages expose only the functions listed in Tasks 5-6; no `Model` type crosses either boundary.

- [ ] **Step 3: Run workspace validation**

Run: `moon check && moon test`

Expected: PASS.

- [ ] **Step 4: Confirm the diff contains only intended paths**

Run: `git diff --stat`

Expected: `view_history.mbt` is removed only because its full pipeline moved to `internal/history_render`; `view_history.mbt` was not split into additional parent view files, and no source outside `examples/ideal/main/` changed.

- [ ] **Step 5: Commit generated interfaces if tracked**

```bash
git add examples/ideal/main
git commit -m "chore(ideal): record organized package interfaces"
```

Expected: skip this commit when validation produces no tracked changes.
