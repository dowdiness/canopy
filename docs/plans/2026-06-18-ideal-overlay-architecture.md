# Ideal Overlay Architecture Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `NodeActionContext` from child `OverlayState` into parent `ActionOverlayHost` so the child signals intent only and the parent owns application context.

**Architecture:** Remove `node_context : NodeActionContext?` from `OverlayState`; replace with `kind : @ast.Term`. Add `context : NodeActionContext?` to `ActionOverlayHost` (alongside `runtime`). Drop `context~` from `OverlayOutput::ExecuteAction` and read it from `model.overlay.context` in the parent handler. All 7 affected files change together — field removal cascades immediately.

**Tech Stack:** MoonBit, Rabbita TEA framework. Working directory: `examples/ideal/main/`. Build: `NEW_MOON_MOD=0 moon check`, `NEW_MOON_MOD=0 moon test`, `NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt`.

## Global Constraints

- Prefix all moon commands with `NEW_MOON_MOD=0` to prevent auto-migration of `moon.mod.json`
- Do not touch `action_overlay_exec.mbt` — `execute_action` receives context from its caller and needs no change
- Do not change token mechanism, `OverlayEvent`/`OverlayMsg` separation, or cell structure
- Worktree: `/home/antisatori/ghq/github.com/dowdiness/canopy-ideal-overlay`, branch `refactor/ideal-overlay-architecture`

---

### Task 1: Refactor overlay ownership boundary (all 7 files)

All changes are cascade-coupled: removing `node_context` from `OverlayState` breaks callers in all other files simultaneously. Make all edits, then verify compile and tests pass as a unit.

**Files:**
- Modify: `examples/ideal/main/model.mbt:67-78`
- Modify: `examples/ideal/main/action_overlay_runtime.mbt:1-20`
- Modify: `examples/ideal/main/action_overlay_flow.mbt:13-22, 63-69, 267-295`
- Modify: `examples/ideal/main/action_overlay_state.mbt:98-121`
- Modify: `examples/ideal/main/action_overlay_update.mbt:47-54`
- Modify: `examples/ideal/main/view_actions.mbt:186-191`
- Modify: `examples/ideal/main/main_wbtest.mbt:29-43, 165-178`

**Interfaces:**
- Produces: `ActionOverlayHost::mount(context : NodeActionContext, runtime : ActionOverlayRuntime) -> ActionOverlayHost`
- Produces: `OverlayState.kind : @ast.Term` (replaces `node_context : NodeActionContext?`)
- Produces: `OverlayOutput::ExecuteAction(token~, action, choice~, name~)` (no context~)

---

- [ ] **Step 1: Edit `model.mbt` — replace `node_context` with `kind` in `OverlayState`**

Replace lines 67–78:

```moonbit
///|
struct OverlayState {
  mode : OverlayMode
  actions : Array[@lambda_edits.Action]
  kind : @ast.Term
  // The most recent failure to act. Overlay-wide, not prompt-specific: an
  // action can fail to apply from MainMenu or Submenu just as from NamePrompt,
  // so the error is rendered in the panel for any open mode (view_actions.mbt).
  error : String
  anchor_top : Int
  anchor_left : Int
  menu : @menu.Model
}
```

---

- [ ] **Step 2: Edit `action_overlay_runtime.mbt` — add `context` to `ActionOverlayHost`**

Replace the struct definition and its three methods (`empty`, `mount`, `close`):

```moonbit
struct ActionOverlayHost {
  runtime : ActionOverlayRuntime?
  context : NodeActionContext?
  next_token : Int
}

fn ActionOverlayHost::empty() -> ActionOverlayHost {
  { runtime: None, context: None, next_token: 1 }
}

fn ActionOverlayHost::mount(
  self : ActionOverlayHost,
  context : NodeActionContext,
  runtime : ActionOverlayRuntime,
) -> ActionOverlayHost {
  { runtime: Some(runtime), context: Some(context), next_token: self.next_token + 1 }
}

fn ActionOverlayHost::close(self : ActionOverlayHost) -> ActionOverlayHost {
  { ..self, runtime: None, context: None }
}
```

---

- [ ] **Step 3: Edit `action_overlay_flow.mbt` — three changes**

**3a. `OverlayOutput::ExecuteAction` — drop `context~` (lines 13–22):**

```moonbit
///|
enum OverlayOutput {
  ExecuteAction(
    token~ : Int,
    @lambda_edits.Action,
    choice~ : String,
    name~ : String
  )
  CloseOverlay(token~ : Int)
}
```

**3b. `OverlayState::context_kind` — return `self.kind` directly (lines 64–69):**

```moonbit
///|
fn OverlayState::context_kind(self : OverlayState) -> @ast.Term {
  self.kind
}
```

**3c. `overlay_effect_to_cmd` ExecuteAction arm — remove dead `match result.state.node_context` guard (lines 276–291):**

Replace:
```moonbit
    ExecuteAction(action, choice~, name~) =>
      match result.state.node_context {
        Some(context) =>
          parent_emit(
            ActionOverlayEffect(
              OverlayOutput::ExecuteAction(
                token~,
                context~,
                action,
                choice~,
                name~,
              ),
            ),
          )
        None => none
      }
```

With:
```moonbit
    ExecuteAction(action, choice~, name~) =>
      parent_emit(
        ActionOverlayEffect(
          OverlayOutput::ExecuteAction(token~, action, choice~, name~),
        ),
      )
```

---

- [ ] **Step 4: Edit `action_overlay_state.mbt` — update `open_action_overlay` (lines 98–121)**

Two changes inside the function body:

1. `initial_state` construction: replace `node_context: Some(ctx)` with `kind: ctx.kind`
2. `model.overlay.mount(...)` call: add `ctx` as first argument

```moonbit
///|
/// Open the action overlay for the given node ID string.
fn open_action_overlay(
  parent_emit : @rabbita.Emit[Msg],
  model : Model,
  node_id_str : String,
  rect_json? : String = js_get_selected_node_rect(),
) -> (Cmd, Model) {
  if node_id_str == "" {
    return (none, model)
  }
  let ctx = match detect_action_context(model.editor, node_id_str) {
    Some(c) => c
    None => return (none, model)
  }
  let proj_ctx = to_proj_context(ctx)
  let actions = @lambda_edits.get_actions_for_node(ctx.kind, proj_ctx)
  if actions.is_empty() {
    return (none, model)
  }
  let (anchor_top, anchor_left) = parse_anchor_rect(rect_json)
  let token = model.overlay.next_token
  let initial_state = {
    mode: MainMenu,
    actions,
    kind: ctx.kind,
    error: "",
    anchor_top,
    anchor_left,
    menu: @menu.Model::new(
      id="ideal-action-overlay-menu",
      item_count=actions.length(),
    ),
  }
  let (overlay_emit, cell) = create_overlay_cell(
    parent_emit, token, initial_state,
  )
  js_set_overlay_open(true)
  (
    initial_state.menu.focus_cmd(),
    {
      ..model,
      overlay: model.overlay.mount(ctx, { cell, emit: overlay_emit, token }),
    },
  )
}
```

---

- [ ] **Step 5: Edit `action_overlay_update.mbt` — update `handle_overlay_output` (lines 47–61)**

Replace the `ExecuteAction` arm to drop `context~` from the pattern and read `model.overlay.context` instead:

```moonbit
///|
/// Apply child-cell outputs only when they come from the currently mounted
/// overlay runtime. This prevents delayed outputs from a closed/reopened
/// overlay from executing against the wrong node context.
fn handle_overlay_output(model : Model, output : OverlayOutput) -> (Cmd, Model) {
  match output {
    ExecuteAction(action, choice~, name~, ..) =>
      match model.overlay.current_runtime_for_output(output) {
        Some(runtime) =>
          match model.overlay.context {
            Some(context) =>
              execute_action(model, runtime, context, action, choice, name)
            None => (none, model)
          }
        None => (none, model)
      }
    CloseOverlay(..) =>
      match model.overlay.current_runtime_for_output(output) {
        Some(_) => close_action_overlay(model)
        None => (none, model)
      }
  }
}
```

---

- [ ] **Step 6: Edit `view_actions.mbt` — fix Submenu arm in `view_overlay` (lines 186–191)**

Replace:
```moonbit
    Submenu(sub_action) =>
      match state.node_context {
        Some(ctx) =>
          view_submenu_choices(emit, state.menu, sub_action, ctx.kind)
        None => view_action_list(emit, state.menu, state.actions)
      }
```

With:
```moonbit
    Submenu(sub_action) =>
      view_submenu_choices(emit, state.menu, sub_action, state.kind)
```

---

- [ ] **Step 7: Edit `main_wbtest.mbt` — update test helpers and token tests**

**7a. `test_overlay_state` (lines 29–43):** Replace `node_context: Some(test_overlay_context())` with `kind: @ast.Term::Unit`:

```moonbit
///|
fn test_overlay_state(mode : OverlayMode) -> OverlayState {
  let actions = test_actions()
  {
    mode,
    actions,
    kind: @ast.Term::Unit,
    error: "",
    anchor_top: 0,
    anchor_left: 0,
    menu: @menu.Model::new(
      id="ideal-action-overlay-menu-test",
      item_count=actions.length(),
    ),
  }
}
```

**7b. `test_overlay_runtime` (line 58):** Update `mount` call:

```moonbit
///|
fn test_overlay_runtime(token : Int) -> ActionOverlayRuntime {
  let state = test_overlay_state(MainMenu)
  let (emit, cell) = create_overlay_cell(test_parent_emit(), token, state)
  { cell, emit, token }
}
```

(No change needed here — `test_overlay_runtime` doesn't call `mount`.)

**7c. Both token tests (lines 163–198):** Three changes across two tests:
1. Both `ActionOverlayHost::empty().mount(runtime)` calls → add `test_overlay_context()` as first argument
2. `OverlayOutput::ExecuteAction(token=7, context=..., ...)` and `(token=8, context=..., ...)` → drop `context=`

```moonbit
///|
test "overlay outputs only match their originating runtime token" {
  let runtime = test_overlay_runtime(7)
  let host = ActionOverlayHost::empty().mount(test_overlay_context(), runtime)
  let action = test_action_by_id("delete")
  let matching = OverlayOutput::ExecuteAction(
    token=7,
    action,
    choice="",
    name="",
  )
  let stale = OverlayOutput::ExecuteAction(
    token=8,
    action,
    choice="",
    name="",
  )
  inspect(host.current_runtime_for_output(matching) is Some(_), content="true")
  inspect(host.current_runtime_for_output(stale) is None, content="true")
}

///|
test "overlay close outputs only match their originating runtime token" {
  let host = ActionOverlayHost::empty().mount(test_overlay_context(), test_overlay_runtime(7))
  inspect(
    host.current_runtime_for_output(OverlayOutput::CloseOverlay(token=7))
    is Some(_),
    content="true",
  )
  inspect(
    host.current_runtime_for_output(OverlayOutput::CloseOverlay(token=8))
    is None,
    content="true",
  )
}
```

---

- [ ] **Step 8: Run `moon check` — expect zero errors**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy-ideal-overlay
NEW_MOON_MOD=0 moon check
```

Expected: no errors. If errors appear, read the error message and trace to the exact line — the field rename cascades are fully accounted for in steps 1–7; any error points to a site the plan missed.

---

- [ ] **Step 9: Run `moon test` — expect all tests pass**

```bash
NEW_MOON_MOD=0 moon test -p examples/ideal/main
```

Expected: all existing tests pass, including the snapshot tests and overlay token tests. No new test cases are added — the refactor is behaviour-preserving by construction (the parent always had the context; we are only changing where it is stored).

---

- [ ] **Step 10: Update interfaces and format**

```bash
NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt
```

Then check for unintended API surface changes:

```bash
git -C /home/antisatori/ghq/github.com/dowdiness/canopy-ideal-overlay diff *.mbti
```

The `OverlayOutput`, `OverlayState`, and `ActionOverlayHost` types are package-internal (not exported via `.mbti`), so no `.mbti` changes are expected. If a `.mbti` file changed, inspect it — it may indicate an unintended public API exposure.

---

- [ ] **Step 11: Commit**

```bash
git -C /home/antisatori/ghq/github.com/dowdiness/canopy-ideal-overlay add \
  examples/ideal/main/model.mbt \
  examples/ideal/main/action_overlay_runtime.mbt \
  examples/ideal/main/action_overlay_flow.mbt \
  examples/ideal/main/action_overlay_state.mbt \
  examples/ideal/main/action_overlay_update.mbt \
  examples/ideal/main/view_actions.mbt \
  examples/ideal/main/main_wbtest.mbt

git -C /home/antisatori/ghq/github.com/dowdiness/canopy-ideal-overlay commit -m \
  "refactor(ideal): move NodeActionContext from child OverlayState to parent ActionOverlayHost

Child signals intent only (action + choice + name). Parent owns and retrieves
application context. Removes dead None-guard in overlay_effect_to_cmd and dead
optional wrapping in OverlayState (node_context was always Some on a live overlay).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- `OverlayState`: remove `node_context`, add `kind` — Task 1 Step 1 ✓
- `ActionOverlayHost`: add `context`, update `mount`/`close`/`empty` — Task 1 Step 2 ✓
- `OverlayOutput::ExecuteAction`: drop `context~` — Task 1 Step 3a ✓
- `overlay_effect_to_cmd`: remove dead None guard — Task 1 Step 3c ✓
- `context_kind()`: return `self.kind` directly — Task 1 Step 3b ✓
- `open_action_overlay`: store ctx in host, pass ctx.kind to child — Task 1 Step 4 ✓
- `handle_overlay_output`: read `model.overlay.context` — Task 1 Step 5 ✓
- `view_actions.mbt` Submenu arm: use `state.kind` directly — Task 1 Step 6 ✓
- `main_wbtest.mbt`: update constructor and token tests — Task 1 Step 7 ✓
- `action_overlay_exec.mbt`: no change — confirmed excluded ✓

**Placeholder scan:** No TBDs, no "similar to Task N", all code blocks complete.

**Type consistency:**
- `ActionOverlayHost::mount(context : NodeActionContext, runtime : ActionOverlayRuntime)` — Step 2 defines it; Step 4 calls `mount(ctx, { cell, emit, token })`; Step 7c calls `mount(test_overlay_context(), runtime)` in both token tests (confirmed by Codex review) — consistent ✓
- `OverlayState.kind : @ast.Term` — Step 1 defines it; Step 3b, 4, 6, 7a use it — consistent ✓
- `OverlayOutput::ExecuteAction(token~, action, choice~, name~)` — Step 3a defines it; Step 3c constructs it; Step 5 pattern-matches it; Step 7c constructs in tests — consistent ✓
