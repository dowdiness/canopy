# S6 Phase 2 Action Overlay Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the proven action-overlay child cell into a compiler-enforced package without leaking parent messages, context, or stale-output tokens into the child.

**Architecture:** First narrow both directions of the boundary while every file remains in `main`, proving the behavior before package ceremony. Then move child state, flow, wiring, errors, and rendering to `main/action_overlay`, expose narrow constructors/functions, and leave execution, host lifecycle, token validation, and context detection in the parent.

**Tech Stack:** MoonBit packages, Rabbita `cell_with_emit`, `Emit`, `Cmd`, white-box tests, generated `.mbti` review.

## Global Constraints

- Phase 0 is already landed.
- Child-to-parent output is `Emit[OverlayOutput]`, never `Emit[Msg]`.
- Parent-to-child construction uses narrow public constructors/functions; do not make invariant-bearing child state `pub(all)`.
- `OverlayOutput` contains no token. Parent adapter closures capture the current token and construct `Msg::ActionOverlayEffect(token, output)`.
- The stale-output comparison remains `ActionOverlayHost.runtime.token` versus the received token.
- Prove the narrowed boundary in-package before adding `action_overlay/moon.pkg`.
- The child owns `action_overlay_flow.mbt`, `action_overlay_flow_wiring.mbt`, `action_overlay_error.mbt`, and the complete `view_overlay` rendering subtree. The parent keeps `action_overlay_exec.mbt`, `action_overlay_update.mbt`, `action_overlay_runtime.mbt`, and `action_overlay_state.mbt`.
- Host/token tests stay in `main`; state-machine and error-formatting tests move to the child package.
- Review `git diff '*.mbti'` explicitly after the split.

---

### Task 1: Remove tokens and parent `Msg` from the child-facing output boundary in-package

**Files:**
- Modify: `examples/ideal/main/msg.mbt:32-40`
- Modify: `examples/ideal/main/action_overlay_flow.mbt:12-25`
- Modify: `examples/ideal/main/action_overlay_flow_wiring.mbt:1-52`
- Modify: `examples/ideal/main/action_overlay_state.mbt:90-132`
- Modify: `examples/ideal/main/action_overlay_update.mbt:12-45`
- Modify: `examples/ideal/main/main_wbtest.mbt:46-220`
- Test: `examples/ideal/main/main_wbtest.mbt`

**Interfaces:**
- Consumes: `@rabbita.Emit[T]`, `ActionOverlayRuntime.token : Int`
- Produces: `OverlayOutput::{ExecuteAction(Action, choice~ : String, name~ : String), CloseOverlay}`; `create_overlay_cell(Emit[OverlayOutput], OverlayState) -> (Emit[OverlayMsg], Cell)`; `Msg::ActionOverlayEffect(Int, OverlayOutput)`

- [ ] **Step 1: Rewrite the token tests to express parent-stamped identity**

Replace the two token tests with:

```moonbit
///|
test "overlay outputs only match the parent-stamped runtime token" {
  let runtime = test_overlay_runtime(7)
  let host = ActionOverlayHost::empty().mount(test_overlay_context(), runtime)
  let action = test_action_by_id("delete")
  let output = OverlayOutput::ExecuteAction(action, choice="", name="")
  inspect(host.active_for_output(7) is Some(_), content="true")
  inspect(host.active_for_output(8) is None, content="true")
  match output {
    ExecuteAction(action, choice~, name~) => {
      inspect(action.id, content="delete")
      inspect(choice, content="")
      inspect(name, content="")
    }
    _ => abort("expected ExecuteAction")
  }
}

///|
test "overlay close outputs use the parent-stamped runtime token" {
  let host = ActionOverlayHost::empty().mount(
    test_overlay_context(),
    test_overlay_runtime(7),
  )
  inspect(host.active_for_output(7) is Some(_), content="true")
  inspect(host.active_for_output(8) is None, content="true")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: FAIL because `OverlayOutput` still requires tokens and `active_for_output` still accepts an output.

- [ ] **Step 3: Narrow the in-package output types and wiring**

Use these complete boundary definitions:

```moonbit
enum OverlayOutput {
  ExecuteAction(@lambda_edits.Action, choice~ : String, name~ : String)
  CloseOverlay
}
```

```moonbit
fn overlay_effect_to_cmd(
  parent_emit : @rabbita.Emit[OverlayOutput],
  result : OverlayUpdate,
) -> Cmd {
  match result.effect {
    NoOverlayEffect => none
    FocusMenu => result.state.menu.focus_cmd()
    FocusNamePrompt => focus_selector_after_render(".name-prompt-input")
    ExecuteAction(action, choice~, name~) =>
      parent_emit(OverlayOutput::ExecuteAction(action, choice~, name~))
    CloseOverlay => parent_emit(OverlayOutput::CloseOverlay)
  }
}

fn overlay_cell_update(
  parent_emit : @rabbita.Emit[OverlayOutput],
  _emit : @rabbita.Emit[OverlayMsg],
  msg : OverlayMsg,
  state : OverlayState,
) -> (Cmd, OverlayState) {
  let result = state.update(msg)
  (overlay_effect_to_cmd(parent_emit, result), result.state)
}

fn create_overlay_cell(
  parent_emit : @rabbita.Emit[OverlayOutput],
  initial_state : OverlayState,
) -> (@rabbita.Emit[OverlayMsg], @rabbita.Cell) {
  @rabbita.cell_with_emit(
    model=initial_state,
    update=fn(emit, msg, state) {
      overlay_cell_update(parent_emit, emit, msg, state)
    },
    view=fn(emit, state) { view_overlay(emit, state) },
  )
}
```

Change the parent bridge to:

```moonbit
ActionOverlayEffect(Int, OverlayOutput)
```

At `open_action_overlay`, capture the token in the parent adapter:

```moonbit
  let overlay_output_emit : @rabbita.Emit[OverlayOutput] = output => {
    parent_emit(ActionOverlayEffect(token, output))
  }
  let (overlay_emit, cell) = create_overlay_cell(
    overlay_output_emit,
    initial_state,
  )
```

Change output validation and handling to:

```moonbit
fn ActionOverlayHost::active_for_output(
  self : ActionOverlayHost,
  token : Int,
) -> (@lambda_edits.ActionContext, ActionOverlayRuntime)? {
  match self.active {
    Some((context, runtime)) if runtime.token == token => Some((context, runtime))
    _ => None
  }
}

fn handle_overlay_output(
  model : Model,
  token : Int,
  output : OverlayOutput,
) -> (Cmd, Model) {
  match output {
    ExecuteAction(action, choice~, name~) => {
      guard model.overlay.active_for_output(token) is Some((context, runtime)) else {
        return (none, model)
      }
      execute_action(model, runtime, context, action, choice, name)
    }
    CloseOverlay =>
      match model.overlay.active_for_output(token) {
        Some(_) => close_action_overlay(model)
        None => (none, model)
      }
  }
}
```

Update the dispatcher arm to `ActionOverlayEffect(token, output) => Some(handle_overlay_output(model, token, output))`. Update `test_parent_emit` to return `Emit[OverlayOutput]`, and call `create_overlay_cell(test_parent_emit(), state)`.

- [ ] **Step 4: Run the in-package boundary proof**

Run: `moon check -p dowdiness/ideal-editor/main && moon test -p dowdiness/ideal-editor/main`

Expected: PASS while every overlay file is still in `main`.

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/main/msg.mbt examples/ideal/main/action_overlay_flow.mbt examples/ideal/main/action_overlay_flow_wiring.mbt examples/ideal/main/action_overlay_state.mbt examples/ideal/main/action_overlay_update.mbt examples/ideal/main/main_wbtest.mbt
git commit -m "refactor(ideal): invert overlay emit boundary"
```

### Task 2: Add narrow parent-to-child constructors in-package

**Files:**
- Modify: `examples/ideal/main/action_overlay_flow.mbt`
- Modify: `examples/ideal/main/action_overlay_error.mbt`
- Modify: `examples/ideal/main/action_overlay_exec.mbt`
- Modify: `examples/ideal/main/action_overlay_update.mbt`
- Modify: `examples/ideal/main/action_overlay_state.mbt`
- Modify: `examples/ideal/main/main_wbtest.mbt`
- Test: `examples/ideal/main/main_wbtest.mbt`

**Interfaces:**
- Consumes: private `OverlayMsg`, `OverlayError`, `OverlayState`, `OverlayMode`
- Produces: `overlay_key_pressed(String) -> OverlayMsg`; `overlay_name_cancel() -> OverlayMsg`; `overlay_set_build_error(String) -> OverlayMsg`; `overlay_set_apply_error(String) -> OverlayMsg`; `overlay_show_name_prompt(Action) -> OverlayMsg`; `new_overlay_state(Array[Action], Term, Int, Int) -> OverlayState`

- [ ] **Step 1: Write tests against the proposed narrow API**

```moonbit
///|
test "overlay narrow constructors preserve parent-to-child messages" {
  inspect(overlay_key_pressed("x") is KeyPressed("x"), content="true")
  inspect(overlay_name_cancel() is NameCancel, content="true")
  inspect(
    overlay_set_build_error("bad") is SetError(BuildActionFailed("bad")),
    content="true",
  )
  inspect(
    overlay_set_apply_error("bad") is SetError(ApplyActionFailed("bad")),
    content="true",
  )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/ideal-editor/main -f main_wbtest.mbt`

Expected: FAIL because the narrow constructors are undefined.

- [ ] **Step 3: Implement and adopt the narrow API**

Add these functions:

```moonbit
pub fn overlay_key_pressed(key : String) -> OverlayMsg { KeyPressed(key) }
pub fn overlay_name_cancel() -> OverlayMsg { NameCancel }
pub fn overlay_set_build_error(message : String) -> OverlayMsg {
  SetError(BuildActionFailed(message))
}
pub fn overlay_set_apply_error(message : String) -> OverlayMsg {
  SetError(ApplyActionFailed(message))
}
pub fn overlay_show_name_prompt(action : @lambda_edits.Action) -> OverlayMsg {
  ShowNamePrompt(action)
}
pub fn new_overlay_state(
  actions : Array[@lambda_edits.Action],
  kind : @ast.Term,
  anchor_top : Int,
  anchor_left : Int,
) -> OverlayState {
  {
    mode: MainMenu,
    actions,
    kind,
    error: None,
    anchor_top,
    anchor_left,
    menu: @menu.Model::new(
      id="ideal-action-overlay-menu",
      item_count=actions.length(),
    ),
  }
}
```

Make `OverlayMsg`, `OverlayOutput`, and `OverlayState` public opaque types (`pub enum`/`pub struct`, not `pub(all)`) so parent signatures may name them without constructing variants or fields. Replace `OverlayEvent::to_overlay_msg`, `execute_action`, and `open_action_overlay` construction with the functions above.

- [ ] **Step 4: Run the second in-package boundary proof**

Run: `moon check -p dowdiness/ideal-editor/main && moon test -p dowdiness/ideal-editor/main`

Expected: PASS with no parent production call site constructing a child variant or record directly.

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/main/action_overlay_flow.mbt examples/ideal/main/action_overlay_error.mbt examples/ideal/main/action_overlay_exec.mbt examples/ideal/main/action_overlay_update.mbt examples/ideal/main/action_overlay_state.mbt examples/ideal/main/main_wbtest.mbt
git commit -m "refactor(ideal): narrow overlay child constructors"
```

### Task 3: Split state-machine tests into the child package

**Files:**
- Create: `examples/ideal/main/action_overlay/action_overlay_wbtest.mbt`
- Modify: `examples/ideal/main/main_wbtest.mbt:1-220,323-401`
- Test: `examples/ideal/main/action_overlay/action_overlay_wbtest.mbt`

**Interfaces:**
- Consumes: child-private `OverlayMode`, `OverlayState::update`, error formatting
- Produces: child-owned coverage for navigation, prompt, effect, and typed-error behavior; parent retains token and `ActionOverlayHost` tests

- [ ] **Step 1: Move the complete state-machine test block**

Move `test_actions`, `test_action_by_id`, `test_overlay_state`, tests from `overlay update dispatches main menu mnemonic action` through `overlay update name cancel closes overlay`, and all `overlay error`/`format_overlay_error` tests into `action_overlay/action_overlay_wbtest.mbt`. Keep `test_overlay_context`, `test_overlay_runtime`, token guard tests, and `mount sets context on host` in `main_wbtest.mbt`.

In the child test file, keep the existing test bodies unchanged except that `test_overlay_state` remains a white-box record constructor and no test calls parent-only `OverlayEvent::to_overlay_msg`; replace that one assertion with:

```moonbit
test "overlay key constructor preserves submenu invalid-key recovery" {
  let wrap_bop_action = test_action_by_id("wrap_bop")
  let result = test_overlay_state(Submenu(wrap_bop_action)).update(
    overlay_key_pressed("z"),
  )
  inspect(result.state.mode is MainMenu, content="true")
  inspect(result.effect is FocusMenu, content="true")
}
```

- [ ] **Step 2: Run test to verify package setup is still missing**

Run: `moon test -p dowdiness/ideal-editor/main/action_overlay`

Expected: FAIL because the child package manifest and production files do not exist yet.

- [ ] **Step 3: Leave the failing test file staged for the package split**

No production implementation occurs in this task; the failure is the red step for Task 4.

- [ ] **Step 4: Commit the test ownership split**

```bash
git add examples/ideal/main/main_wbtest.mbt examples/ideal/main/action_overlay/action_overlay_wbtest.mbt
git commit -m "test(ideal): split overlay state machine coverage"
```

### Task 4: Create the child package and perform the exact file cut

**Files:**
- Create: `examples/ideal/main/action_overlay/moon.pkg`
- Create: `examples/ideal/main/action_overlay/action_overlay_flow.mbt`
- Create: `examples/ideal/main/action_overlay/action_overlay_flow_wiring.mbt`
- Create: `examples/ideal/main/action_overlay/action_overlay_error.mbt`
- Create: `examples/ideal/main/action_overlay/view_overlay.mbt`
- Create: `examples/ideal/main/action_overlay/view_overlay_classes.mbt`
- Modify: `examples/ideal/main/model.mbt:39-65`
- Modify: `examples/ideal/main/view_actions.mbt:1-215`
- Modify: `examples/ideal/main/moon.pkg:1-32`
- Test: `examples/ideal/main/action_overlay/action_overlay_wbtest.mbt`

**Interfaces:**
- Consumes: narrowed in-package API from Tasks 1-2
- Produces: package `dowdiness/ideal-editor/main/action_overlay` imported as `@action_overlay`

- [ ] **Step 1: Create the package manifest**

```moonbit
import {
  "moonbit-community/rabbita",
  "moonbit-community/rabbita/html",
  "dowdiness/rabbita-menu/menu",
  "dowdiness/ideal-editor/main/ui",
  "dowdiness/canopy/lang/lambda/edits" @lambda_edits,
  "dowdiness/lambda/ast",
}

supported_targets = "js"
```

- [ ] **Step 2: Move the child production units**

Move the complete narrowed contents of `action_overlay_flow.mbt`, `action_overlay_flow_wiring.mbt`, and `action_overlay_error.mbt` into the new directory. Move `OverlayMode` and `OverlayState` from `model.mbt` to `action_overlay_flow.mbt` because the actual source currently defines them in `model.mbt`, despite the design table attributing them to the flow file.

Move the complete contents of `view_actions.mbt` into `action_overlay/view_overlay.mbt`; every function in that file is part of the `view_overlay` rendering subtree. Move the complete contents of `view_actions_classes.mbt` into `action_overlay/view_overlay_classes.mbt`, because those package-private class bindings are required by the moved renderer. Do not move `action_overlay_exec.mbt`, `action_overlay_update.mbt`, `action_overlay_runtime.mbt`, or `action_overlay_state.mbt`.

- [ ] **Step 3: Import and qualify the child API in the parent**

Add to `main/moon.pkg`:

```moonbit
  "dowdiness/ideal-editor/main/action_overlay" @action_overlay,
```

Qualify every parent signature and call with `@action_overlay`, including `OverlayOutput`, `OverlayMsg`, `OverlayState`, `create_overlay_cell`, `new_overlay_state`, and the five message constructors. The parent `OverlayEvent` remains distinct and maps only through the narrow constructors.

- [ ] **Step 4: Run test to verify it passes**

Run: `moon check -p dowdiness/ideal-editor/main/action_overlay && moon test -p dowdiness/ideal-editor/main/action_overlay && moon check -p dowdiness/ideal-editor/main && moon test -p dowdiness/ideal-editor/main`

Expected: PASS for both child and parent packages.

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/main/action_overlay examples/ideal/main/model.mbt examples/ideal/main/view_actions.mbt examples/ideal/main/view_actions_classes.mbt examples/ideal/main/moon.pkg examples/ideal/main/action_overlay_exec.mbt examples/ideal/main/action_overlay_update.mbt examples/ideal/main/action_overlay_runtime.mbt examples/ideal/main/action_overlay_state.mbt examples/ideal/main/msg.mbt examples/ideal/main/main_wbtest.mbt
git commit -m "refactor(ideal): extract action overlay package"
```

### Task 5: Review the new public surface and verify the split

**Files:**
- Test: `examples/ideal/main/action_overlay/action_overlay_wbtest.mbt`
- Test: `examples/ideal/main/main_wbtest.mbt`

**Interfaces:**
- Consumes: extracted child package
- Produces: reviewed `.mbti` surface and workspace-green Phase 2

- [ ] **Step 1: Regenerate formatting and interfaces**

Run: `moon fmt && moon info`

Expected: PASS.

- [ ] **Step 2: Review generated API changes explicitly**

Run: `git diff -- '*.mbti'`

Expected: the new child interface exposes only opaque `OverlayMsg`, `OverlayOutput`, `OverlayState`, `create_overlay_cell`, `new_overlay_state`, output matching access, and the narrow message constructors; no parent `Msg`, token, `Model`, or `ActionOverlayHost` appears.

- [ ] **Step 3: Run workspace validation**

Run: `moon check && moon test`

Expected: PASS.

- [ ] **Step 4: Build and run the overlay browser regression suite**

Run: `moon build --target js && cd examples/ideal/web && npx playwright test e2e/structural-editing.spec.ts`

Expected: PASS; child-cell focus, keyboard navigation, prompts, errors, and close behavior are unchanged.

- [ ] **Step 5: Commit generated interfaces if they are tracked**

```bash
git add examples/ideal/main/action_overlay examples/ideal/main
git commit -m "chore(ideal): record overlay package interface"
```

Expected: skip this commit when `moon info` produces no tracked changes.
