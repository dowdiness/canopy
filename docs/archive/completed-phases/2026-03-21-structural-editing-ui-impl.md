**Status:** Complete

# Structural Editing UI — Rabbita Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the which-key overlay (desktop) and floating action sheet (mobile) for structural editing actions as Rabbita components in the ideal editor.

**Architecture:** All UI lives in MoonBit via Rabbita's TEA model. The TypeScript layer only captures keyboard/touch events and forwards them through the existing trigger button pattern. Actions execute directly via `model.editor.apply_tree_edit()` — no JS bridge roundtrip. Binding NodeIds are resolved in MoonBit via `FlatProj`, eliminating the JS-side binding ID problem entirely.

**Tech Stack:** MoonBit, Rabbita (TEA framework), ProseMirror keymap plugin (TypeScript event capture only)

**Spec:** `docs/plans/2026-03-21-structural-editing-actions-design.md`

---

## Key Architecture Decision

The existing structural edit flow goes: PM keymap → JS event → globalThis → trigger button → Rabbita msg → JS bridge → MoonBit FFI → CRDT. This plan shortcuts the last three steps: Rabbita msg → `model.editor.apply_tree_edit(op, ts)` directly. Both `Model.editor` (SyncEditor) and the action filtering (`@proj.get_actions_for_node`) are MoonBit code — no FFI needed.

**Keyboard capture:** A ProseMirror `handleKeyDown` plugin checks `globalThis.__canopy_overlay_open`. When true, all keys are forwarded to Rabbita via a trigger button instead of being processed by PM. When false, PM processes keys normally.

**Mobile touch:** TypeScript detects long-press on the PM editor and fires through a trigger button. Rabbita opens the action sheet.

---

## File Map

| File | Responsibility | Action |
|------|----------------|--------|
| `examples/ideal/main/action_model.mbt` | `OverlayState` struct, `NodeActionContext`, action execution logic | Create |
| `examples/ideal/main/view_actions.mbt` | Render which-key overlay, action sheet, name prompt | Create |
| `examples/ideal/main/model.mbt` | Add overlay state to Model | Modify |
| `examples/ideal/main/msg.mbt` | Add overlay/action Msg variants | Modify |
| `examples/ideal/main/main.mbt` | Wire overlay view + handle new msgs in update | Modify |
| `examples/ideal/main/view_editor.mbt` | Add trigger buttons for overlay keys | Modify |
| `examples/ideal/main/bridge_ffi.mbt` | Add FFI: overlay flag, node rect, action key | Modify |
| `examples/ideal/web/src/keymap.ts` | Add Space key + key forwarding plugin | Modify |
| `examples/ideal/web/src/events.ts` | Add ACTION_OVERLAY_OPEN, ACTION_KEY events | Modify |
| `examples/ideal/web/src/main.ts` | Wire new events + trigger buttons | Modify |
| `examples/ideal/web/src/canopy-editor.ts` | Add overlay/sheet styles to SHADOW_STYLES | Modify |

---

### Task 1: Model + Message Extensions

**Files:**
- Modify: `examples/ideal/main/model.mbt`
- Modify: `examples/ideal/main/msg.mbt`

- [ ] **Step 1: Add overlay state to Model**

In `model.mbt`, add after the `SyncStatus` enum:

```moonbit
///|
pub struct OverlayState {
  visible : Bool
  actions : Array[@proj.Action]
  node_context : NodeActionContext?
  submenu : @proj.Action?   // for second-level choices
  name_prompt : Bool        // showing name input
  name_value : String       // current name input value
  name_error : String       // validation error
  anchor_top : Int          // screen position (px)
  anchor_left : Int         // screen position (px)
}

///|
pub struct NodeActionContext {
  node_id : @proj.NodeId
  kind : String
  is_let_binding : Bool
  binding_node_id : @proj.NodeId?
  binding_def_index : Int?
  module_node_id : @proj.NodeId?
}
```

Add `overlay` field to the `Model` struct:

```moonbit
  overlay : OverlayState
```

Update the `Model` creation in `main.mbt` to initialize:

```moonbit
  overlay: {
    visible: false, actions: [], node_context: None,
    submenu: None, name_prompt: false, name_value: "", name_error: "",
    anchor_top: 0, anchor_left: 0,
  },
```

- [ ] **Step 2: Add Msg variants**

In `msg.mbt`, add:

```moonbit
  // Action overlay
  OpenActionOverlay
  CloseActionOverlay
  ActionKeyPressed(String)
  ActionTapped(String)           // action id from touch
  NamePromptInput(String)
  NamePromptSubmit
  NamePromptCancel
  // Mobile
  LongPressTriggered
```

- [ ] **Step 3: Run moon check**

Run: `cd examples/ideal && moon check`
Expected: Compiles (new msgs not yet handled in update — add `_ => (Cmd::none, model)` catch-all or stub handlers).

- [ ] **Step 4: Commit**

```bash
git add examples/ideal/main/model.mbt examples/ideal/main/msg.mbt
git commit -m "feat(ideal): add overlay state and action messages to Model"
```

---

### Task 2: Action Model + Execution Logic

**Files:**
- Create: `examples/ideal/main/action_model.mbt`

- [ ] **Step 1: Create action model with context detection and execution**

The `projection/` package already has `@proj.get_actions_for_node`, `@proj.Action`, `@proj.NodeContext`, and `@proj.find_binding_for_init`. This task wires them together.

```moonbit
///|
/// Detect NodeActionContext from the current editor state and selected node.
pub fn detect_action_context(
  editor : @editor.SyncEditor,
  selected_node : String?,
) -> NodeActionContext? {
  let node_id_str = match selected_node {
    Some(s) => s
    None => return None
  }
  let node_id_int = match @strconv.parse_int?(node_id_str) {
    Ok(n) => n
    Err(_) => return None
  }
  let node_id = @proj.NodeId::from_int(node_id_int)

  // Get registry and flat_proj to determine node kind and binding context
  let registry = editor.registry_memo.get()
  let node = match registry.get(node_id) {
    Some(n) => n
    None => return None
  }

  // Detect binding context
  let flat_proj = match editor.get_flat_proj() {
    Some(fp) => fp
    None => return None
  }
  let binding_info = @proj.find_binding_for_init(node_id, flat_proj)

  // Map AST kind to PM node type name (for action filtering)
  let kind = kind_name_for_term(node.kind)

  match binding_info {
    Some((binding_id, def_index)) => {
      // Find module node id
      let mut module_id : @proj.NodeId? = None
      for pid, pnode in registry {
        if pnode.kind is @ast.Term::Module(_, _) {
          module_id = Some(pid)
          break
        }
      }
      Some({
        node_id,
        kind,
        is_let_binding: true,
        binding_node_id: Some(binding_id),
        binding_def_index: Some(def_index),
        module_node_id: module_id,
      })
    }
    None =>
      Some({
        node_id,
        kind,
        is_let_binding: false,
        binding_node_id: None,
        binding_def_index: None,
        module_node_id: None,
      })
  }
}

///|
fn kind_name_for_term(kind : @ast.Term) -> String {
  match kind {
    @ast.Term::Int(_) => "int_literal"
    @ast.Term::Var(_) => "var_ref"
    @ast.Term::Lam(_, _) => "lambda"
    @ast.Term::App(_, _) => "application"
    @ast.Term::Bop(_, _, _) => "binary_op"
    @ast.Term::If(_, _, _) => "if_expr"
    @ast.Term::Module(_, _) => "module"
    @ast.Term::Unit => "unit"
    @ast.Term::Error(_) => "error_node"
    @ast.Term::Unbound(_) => "unbound_ref"
  }
}

///|
/// Convert NodeActionContext to @proj.NodeContext for action filtering.
fn to_proj_context(ctx : NodeActionContext) -> @proj.NodeContext {
  if ctx.is_let_binding {
    match (ctx.binding_node_id, ctx.binding_def_index, ctx.module_node_id) {
      (Some(bid), Some(idx), Some(mid)) =>
        @proj.NodeContext::new_binding(
          binding_node_id=bid, binding_def_index=idx, module_node_id=mid,
        )
      _ => @proj.NodeContext::new()
    }
  } else {
    @proj.NodeContext::new()
  }
}

///|
/// Execute a structural editing action. Returns the TreeEditOp to apply,
/// or None if the action needs a name prompt first.
pub fn build_tree_edit_op(
  action : @proj.Action,
  ctx : NodeActionContext,
  choice : String?,
  name : String?,
) -> Result[@proj.TreeEditOp?, String] {
  let node_id = ctx.node_id
  match action.id {
    "delete" => Ok(Some(@proj.TreeEditOp::Delete(node_id~)))
    "extract_to_let" =>
      match name {
        Some(n) => Ok(Some(@proj.TreeEditOp::ExtractToLet(node_id~, var_name=n)))
        None => Ok(None) // needs name prompt
      }
    "inline" => Ok(Some(@proj.TreeEditOp::InlineDefinition(node_id~)))
    "rename" =>
      match name {
        Some(n) => Ok(Some(@proj.TreeEditOp::Rename(node_id~, new_name=n)))
        None => Ok(None)
      }
    "unwrap" => {
      let idx = match choice {
        Some("right") | Some("arg") | Some("then") => 1
        Some("else") => 2
        _ => 0
      }
      Ok(Some(@proj.TreeEditOp::Unwrap(node_id~, keep_child_index=idx)))
    }
    "swap" => Ok(Some(@proj.TreeEditOp::SwapChildren(node_id~)))
    "change_op" =>
      match choice {
        Some("Plus") => Ok(Some(@proj.TreeEditOp::ChangeOperator(node_id~, new_op=@ast.Bop::Plus)))
        Some("Minus") => Ok(Some(@proj.TreeEditOp::ChangeOperator(node_id~, new_op=@ast.Bop::Minus)))
        _ => Err("No operator selected")
      }
    "wrap_lambda" =>
      match name {
        Some(n) => Ok(Some(@proj.TreeEditOp::WrapInLambda(node_id~, var_name=n)))
        None => Ok(None)
      }
    "wrap_if" => Ok(Some(@proj.TreeEditOp::WrapInIf(node_id~)))
    "wrap_bop" =>
      match choice {
        Some("Plus") => Ok(Some(@proj.TreeEditOp::WrapInBop(node_id~, op=@ast.Bop::Plus)))
        Some("Minus") => Ok(Some(@proj.TreeEditOp::WrapInBop(node_id~, op=@ast.Bop::Minus)))
        _ => Err("No operator selected")
      }
    "wrap_app" => Ok(Some(@proj.TreeEditOp::WrapInApp(node_id~)))
    // Binding-level ops
    "binding_rename" =>
      match name {
        Some(n) => Ok(Some(@proj.TreeEditOp::Rename(node_id~, new_name=n)))
        None => Ok(None)
      }
    "binding_duplicate" =>
      match ctx.binding_node_id {
        Some(bid) => Ok(Some(@proj.TreeEditOp::DuplicateBinding(binding_node_id=bid)))
        None => Err("No binding context")
      }
    "binding_move_up" =>
      match ctx.binding_node_id {
        Some(bid) => Ok(Some(@proj.TreeEditOp::MoveBindingUp(binding_node_id=bid)))
        None => Err("No binding context")
      }
    "binding_move_down" =>
      match ctx.binding_node_id {
        Some(bid) => Ok(Some(@proj.TreeEditOp::MoveBindingDown(binding_node_id=bid)))
        None => Err("No binding context")
      }
    "binding_inline_all" =>
      match ctx.binding_node_id {
        Some(bid) => Ok(Some(@proj.TreeEditOp::InlineAllUsages(binding_node_id=bid)))
        None => Err("No binding context")
      }
    "binding_delete" =>
      match ctx.binding_node_id {
        Some(bid) => Ok(Some(@proj.TreeEditOp::DeleteBinding(binding_node_id=bid)))
        None => Err("No binding context")
      }
    "add_binding" =>
      match ctx.module_node_id {
        Some(mid) => Ok(Some(@proj.TreeEditOp::AddBinding(module_node_id=mid)))
        None => Err("No module context")
      }
    _ => Err("Unknown action: " + action.id)
  }
}
```

- [ ] **Step 2: Run moon check**

Run: `cd examples/ideal && moon check`

- [ ] **Step 3: Commit**

```bash
git add examples/ideal/main/action_model.mbt
git commit -m "feat(ideal): add action context detection and edit op builder"
```

---

### Task 3: TypeScript Event Capture (Space Key + Key Forwarding)

**Files:**
- Modify: `examples/ideal/web/src/events.ts`
- Modify: `examples/ideal/web/src/keymap.ts`
- Modify: `examples/ideal/web/src/main.ts`

- [ ] **Step 1: Add events**

In `events.ts`:

```typescript
  ACTION_OVERLAY_OPEN: 'action-overlay-open',
  ACTION_KEY: 'action-key',
  LONG_PRESS: 'long-press',
```

- [ ] **Step 2: Add Space key handler and key forwarding plugin to keymap.ts**

```typescript
import { Plugin } from "prosemirror-state";

// Add to structuralKeymap:
    " ": (state) => {  // ProseMirror uses " " for space
      if (!(state.selection instanceof NodeSelection)) return false;
      const nodeId = state.selection.node.attrs.nodeId;
      if (nodeId == null) return false;
      host.dispatchEvent(new CustomEvent(CanopyEvents.ACTION_OVERLAY_OPEN, {
        detail: { nodeId: String(nodeId) },
        bubbles: true, composed: true,
      }));
      return true;
    },

// New: key forwarding plugin (captures keys when overlay is open)
export function actionKeyForwardPlugin(host: HTMLElement) {
  return new Plugin({
    props: {
      handleKeyDown(_view, event) {
        const g = globalThis as any;
        if (!g.__canopy_overlay_open) return false;
        // Forward key to Rabbita
        g.__canopy_pending_action_key = event.key;
        const btn = document.getElementById('canopy-action-key-trigger');
        if (btn) btn.click();
        event.preventDefault();
        return true;
      },
    },
  });
}
```

- [ ] **Step 3: Wire new events in main.ts**

In `wireEditorEvents`, add:

```typescript
  el.addEventListener(CanopyEvents.ACTION_OVERLAY_OPEN, ((event: Event) => {
    const { nodeId } = (event as CustomEvent).detail ?? {};
    canopyGlobal.__canopy_pending_action_overlay_node = nodeId ?? null;
    clickTrigger('canopy-action-overlay-trigger');
  }) as EventListener, { signal });

  el.addEventListener(CanopyEvents.LONG_PRESS, ((event: Event) => {
    const { nodeId } = (event as CustomEvent).detail ?? {};
    canopyGlobal.__canopy_pending_action_overlay_node = nodeId ?? null;
    clickTrigger('canopy-long-press-trigger');
  }) as EventListener, { signal });
```

Add the globalThis type declarations.

- [ ] **Step 4: Register the plugin in structure-runtime.ts**

Import `actionKeyForwardPlugin` and add to the PM plugins array:

```typescript
plugins: [
  structuralKeymap(host),
  actionKeyForwardPlugin(host),  // NEW
  peerCursorPlugin(),
  errorDecoPlugin(),
  evalGhostPlugin(),
],
```

- [ ] **Step 5: Add long-press detection in structure-runtime.ts**

```typescript
// After pmView creation:
let longPressTimer: ReturnType<typeof setTimeout> | null = null;

parent.addEventListener('pointerdown', (e) => {
  if (e.pointerType !== 'touch') return;
  const startX = e.clientX, startY = e.clientY;
  longPressTimer = setTimeout(() => {
    const sel = pmView.state.selection;
    if (sel instanceof NodeSelection) {
      host.dispatchEvent(new CustomEvent(CanopyEvents.LONG_PRESS, {
        detail: { nodeId: String(sel.node.attrs.nodeId) },
        bubbles: true, composed: true,
      }));
    }
  }, 500);

  const cancel = () => { if (longPressTimer) { clearTimeout(longPressTimer); longPressTimer = null; } };
  parent.addEventListener('pointerup', cancel, { once: true });
  parent.addEventListener('pointermove', (me) => {
    if (Math.abs(me.clientX - startX) > 10 || Math.abs(me.clientY - startY) > 10) cancel();
  }, { once: true });
}, { passive: true });
```

- [ ] **Step 6: Commit**

```bash
git add examples/ideal/web/src/events.ts examples/ideal/web/src/keymap.ts examples/ideal/web/src/main.ts examples/ideal/web/src/structure-runtime.ts
git commit -m "feat(ideal): add Space key, key forwarding, and long-press event capture"
```

---

### Task 4: Trigger Buttons + FFI

**Files:**
- Modify: `examples/ideal/main/view_editor.mbt`
- Modify: `examples/ideal/main/bridge_ffi.mbt`

- [ ] **Step 1: Add trigger buttons**

In `view_editor.mbt`, add two new hidden buttons alongside the existing ones:

```moonbit
// Action overlay trigger (Space key)
@html.button(
  on_click=dispatch(OpenActionOverlay),
  attrs=@html.Attrs::build()
    .id("canopy-action-overlay-trigger")
    .class_("hidden-trigger")
    .aria_hidden("true")
    .tabindex(-1),
  [@html.text("")],
),
// Action key trigger (mnemonic keys when overlay is open)
@html.button(
  on_click=dispatch(ActionKeyPressed("")),
  attrs=@html.Attrs::build()
    .id("canopy-action-key-trigger")
    .class_("hidden-trigger")
    .aria_hidden("true")
    .tabindex(-1),
  [@html.text("")],
),
// Long press trigger (mobile)
@html.button(
  on_click=dispatch(LongPressTriggered),
  attrs=@html.Attrs::build()
    .id("canopy-long-press-trigger")
    .class_("hidden-trigger")
    .aria_hidden("true")
    .tabindex(-1),
  [@html.text("")],
),
```

- [ ] **Step 2: Add FFI functions**

In `bridge_ffi.mbt`:

```moonbit
///|
extern "js" fn js_take_action_overlay_node() -> String =
  #|(function() { var v = globalThis.__canopy_pending_action_overlay_node; globalThis.__canopy_pending_action_overlay_node = null; return v || ''; })()

///|
extern "js" fn js_take_action_key() -> String =
  #|(function() { var v = globalThis.__canopy_pending_action_key; globalThis.__canopy_pending_action_key = null; return v || ''; })()

///|
extern "js" fn js_set_overlay_open(open : Bool) -> Unit =
  #|(function(open) { globalThis.__canopy_overlay_open = open; })

///|
extern "js" fn js_get_selected_node_rect() -> String =
  #|(function() {
  #|  var el = document.querySelector('canopy-editor')?.shadowRoot?.querySelector('.ProseMirror-selectednode');
  #|  if (!el) return '{}';
  #|  var r = el.getBoundingClientRect();
  #|  return JSON.stringify({ top: Math.round(r.top), left: Math.round(r.left), bottom: Math.round(r.bottom), right: Math.round(r.right) });
  #|})()
```

- [ ] **Step 3: Commit**

```bash
git add examples/ideal/main/view_editor.mbt examples/ideal/main/bridge_ffi.mbt
git commit -m "feat(ideal): add trigger buttons and FFI for action overlay"
```

---

### Task 5: Update Handler — Action Overlay Logic

**Files:**
- Modify: `examples/ideal/main/main.mbt`

- [ ] **Step 1: Handle overlay messages in the update function**

Add cases to the `update` function's match block:

```moonbit
OpenActionOverlay => {
  let node_str = js_take_action_overlay_node()
  let ctx = detect_action_context(model.editor, Some(node_str))
  match ctx {
    None => (@cmd.none, model)
    Some(action_ctx) => {
      let proj_ctx = to_proj_context(action_ctx)
      let registry = model.editor.registry_memo.get()
      let kind = match registry.get(action_ctx.node_id) {
        Some(n) => n.kind
        None => return (@cmd.none, model)
      }
      let actions = @proj.get_actions_for_node(kind, proj_ctx)
      // Get anchor position
      let rect_json = js_get_selected_node_rect()
      let rect = @json.parse?(rect_json).or(@json.JsonValue::Object({}))
      let top = match rect {
        Object(m) => match m.get("bottom") { Some(Number(n, ..)) => n.to_int(); _ => 100 }
        _ => 100
      }
      let left = match rect {
        Object(m) => match m.get("left") { Some(Number(n, ..)) => n.to_int(); _ => 100 }
        _ => 100
      }
      js_set_overlay_open(true)
      (@cmd.none, {
        ..model,
        overlay: {
          visible: true, actions, node_context: Some(action_ctx),
          submenu: None, name_prompt: false, name_value: "", name_error: "",
          anchor_top: top + 4, anchor_left: left,
        },
      })
    }
  }
}
LongPressTriggered => {
  // Same as OpenActionOverlay — reuse logic
  let node_str = js_take_action_overlay_node()
  // ... (same as OpenActionOverlay body)
}
CloseActionOverlay => {
  js_set_overlay_open(false)
  (@cmd.none, { ..model, overlay: { ..model.overlay, visible: false, submenu: None, name_prompt: false } })
}
ActionKeyPressed(_) => {
  let key = js_take_action_key()
  if key == "Escape" {
    js_set_overlay_open(false)
    return (@cmd.none, { ..model, overlay: { ..model.overlay, visible: false } })
  }
  // Handle name prompt input
  if model.overlay.name_prompt {
    if key == "Enter" {
      return (dispatch(NamePromptSubmit), model)
    }
    // Let the name prompt input handle the key naturally
    return (@cmd.none, model)
  }
  // Handle submenu choice
  match model.overlay.submenu {
    Some(action) => {
      match action.needs_choice {
        Some(choices) => {
          let idx = match @strconv.parse_int?(key) {
            Ok(n) => n - 1
            Err(_) => return (@cmd.none, { ..model, overlay: { ..model.overlay, submenu: None } })
          }
          if idx >= 0 && idx < choices.length() {
            execute_action(dispatch, model, action, Some(choices[idx]), None)
          } else {
            (@cmd.none, { ..model, overlay: { ..model.overlay, submenu: None } })
          }
        }
        None => (@cmd.none, model)
      }
    }
    None => {
      // Match mnemonic key to action
      let matched = model.overlay.actions.iter().find(fn(a) { a.mnemonic == key[0] })
      match matched {
        Some(action) => {
          if action.needs_choice is Some(_) {
            // Open submenu
            (@cmd.none, { ..model, overlay: { ..model.overlay, submenu: Some(action) } })
          } else if action.needs_input {
            // Open name prompt
            (@cmd.none, { ..model, overlay: { ..model.overlay, name_prompt: true, name_value: "", name_error: "" } })
          } else {
            execute_action(dispatch, model, action, None, None)
          }
        }
        None => (@cmd.none, model)
      }
    }
  }
}
ActionTapped(action_id) => {
  let matched = model.overlay.actions.iter().find(fn(a) { a.id == action_id })
  match matched {
    Some(action) => {
      if action.needs_input {
        (@cmd.none, { ..model, overlay: { ..model.overlay, name_prompt: true } })
      } else {
        execute_action(dispatch, model, action, None, None)
      }
    }
    None => (@cmd.none, model)
  }
}
NamePromptInput(value) =>
  (@cmd.none, { ..model, overlay: { ..model.overlay, name_value: value, name_error: "" } })
NamePromptSubmit => {
  let name = model.overlay.name_value
  if name == "" {
    return (@cmd.none, { ..model, overlay: { ..model.overlay, name_error: "Name required" } })
  }
  // Find the pending action (the one that triggered the prompt)
  let action = model.overlay.actions.iter().find(fn(a) { a.needs_input && a.mnemonic != '\x00' })
  match action {
    Some(a) => execute_action(dispatch, model, a, None, Some(name))
    None => (@cmd.none, model)
  }
}
NamePromptCancel => {
  js_set_overlay_open(false)
  (@cmd.none, { ..model, overlay: { ..model.overlay, visible: false, name_prompt: false } })
}
```

- [ ] **Step 2: Add execute_action helper**

```moonbit
///|
fn execute_action(
  _dispatch : @rabbita.Dispatch[Msg],
  model : Model,
  action : @proj.Action,
  choice : String?,
  name : String?,
) -> (@cmd.Cmd, Model) {
  let ctx = match model.overlay.node_context {
    Some(c) => c
    None => return (@cmd.none, model)
  }
  match build_tree_edit_op(action, ctx, choice, name) {
    Ok(Some(op)) => {
      let ts = model.next_timestamp
      match model.editor.apply_tree_edit(op, ts) {
        Ok(_) => ()
        Err(msg) => {
          // Show error in overlay
          return (@cmd.none, {
            ..model,
            overlay: { ..model.overlay, name_error: msg },
          })
        }
      }
      js_set_overlay_open(false)
      // Trigger reconciliation
      js_reconcile_after_tree_edit()
      (@cmd.none, {
        ..model,
        overlay: { ..model.overlay, visible: false },
        next_timestamp: ts + 1,
      })
    }
    Ok(None) => {
      // Action needs name prompt
      (@cmd.none, { ..model, overlay: { ..model.overlay, name_prompt: true } })
    }
    Err(msg) => {
      (@cmd.none, { ..model, overlay: { ..model.overlay, name_error: msg } })
    }
  }
}
```

- [ ] **Step 3: Add reconciliation FFI**

In `bridge_ffi.mbt`:

```moonbit
///|
extern "js" fn js_reconcile_after_tree_edit() -> Unit =
  #|(function() {
  #|  var el = document.querySelector('canopy-editor');
  #|  if (el && el._bridge) el._bridge.afterLocalEdit();
  #|})()
```

Expose the bridge reference on the `<canopy-editor>` element in `canopy-editor.ts` by adding `this._bridge = bridge;` in the mount method (or via a setter).

- [ ] **Step 4: Run moon check + dev server test**

Run: `cd examples/ideal && moon check`
Run: `cd examples/ideal/web && npm run dev`

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/main/main.mbt examples/ideal/main/bridge_ffi.mbt
git commit -m "feat(ideal): handle action overlay messages in update function"
```

---

### Task 6: View — Render Overlay and Action Sheet

**Files:**
- Create: `examples/ideal/main/view_actions.mbt`
- Modify: `examples/ideal/main/main.mbt` (add to main view)
- Modify: `examples/ideal/web/src/canopy-editor.ts` (add styles)

- [ ] **Step 1: Create view_actions.mbt**

```moonbit
///|
pub fn view_action_overlay(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @html.Html {
  if not(model.overlay.visible) {
    return @html.text("")
  }

  // Name prompt mode
  if model.overlay.name_prompt {
    return view_name_prompt(dispatch, model)
  }

  // Submenu mode
  match model.overlay.submenu {
    Some(action) => view_submenu(dispatch, model, action)
    None => view_main_overlay(dispatch, model)
  }
}

///|
fn view_main_overlay(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @html.Html {
  let core = model.overlay.actions.filter(fn(a) { a.group == @proj.ActionGroup::Core })
  let wrap = model.overlay.actions.filter(fn(a) { a.group == @proj.ActionGroup::Wrap })
  let binding = model.overlay.actions.filter(fn(a) { a.group == @proj.ActionGroup::Binding })
  let module_ = model.overlay.actions.filter(fn(a) { a.group == @proj.ActionGroup::Module })

  let items : Array[@html.Html] = []
  render_action_group(dispatch, core, items)
  if wrap.length() > 0 {
    items.push(@html.div(class="wk-group-label", [@html.text("wrap")]))
    render_action_group(dispatch, wrap, items)
  }
  if binding.length() > 0 {
    items.push(@html.div(class="wk-group-label", [@html.text("binding")]))
    render_action_group(dispatch, binding, items)
  }
  render_action_group(dispatch, module_, items)

  @html.div(
    attrs=@html.Attrs::build()
      .class_("which-key-overlay")
      .style("top", model.overlay.anchor_top.to_string() + "px")
      .style("left", model.overlay.anchor_left.to_string() + "px"),
    items,
  )
}

///|
fn render_action_group(
  dispatch : @rabbita.Dispatch[Msg],
  actions : Array[@proj.Action],
  items : Array[@html.Html],
) -> Unit {
  for action in actions {
    items.push(
      @html.div(
        on_click=dispatch(ActionTapped(action.id)),
        attrs=@html.Attrs::build().class_("wk-item"),
        [
          @html.span(class="wk-key", [@html.text(action.mnemonic.to_string())]),
          @html.text(" " + action.label),
        ],
      ),
    )
  }
}

///|
fn view_submenu(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
  action : @proj.Action,
) -> @html.Html {
  let choices = match action.needs_choice {
    Some(c) => c
    None => return @html.text("")
  }
  let items : Array[@html.Html] = []
  for i, choice in choices {
    items.push(
      @html.div(
        on_click=dispatch(ActionTapped(action.id + ":" + choice)),
        attrs=@html.Attrs::build().class_("wk-item"),
        [
          @html.span(class="wk-key", [@html.text((i + 1).to_string())]),
          @html.text(" " + choice),
        ],
      ),
    )
  }
  @html.div(
    attrs=@html.Attrs::build()
      .class_("which-key-overlay")
      .style("top", model.overlay.anchor_top.to_string() + "px")
      .style("left", model.overlay.anchor_left.to_string() + "px"),
    items,
  )
}

///|
fn view_name_prompt(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @html.Html {
  @html.div(
    attrs=@html.Attrs::build()
      .class_("name-prompt")
      .style("top", model.overlay.anchor_top.to_string() + "px")
      .style("left", model.overlay.anchor_left.to_string() + "px"),
    [
      @html.input(
        attrs=@html.Attrs::build()
          .class_("name-prompt-input")
          .attr("placeholder", "name…")
          .attr("value", model.overlay.name_value)
          .attr("autofocus", "true")
          .handler("input", fn(event, scheduler) {
            let value = js_get_input_value(event)
            scheduler.dispatch(NamePromptInput(value))
          })
          .handler("keydown", fn(event, scheduler) {
            let key = js_get_event_key(event)
            if key == "Enter" {
              js_prevent_default(event)
              scheduler.dispatch(NamePromptSubmit)
            } else if key == "Escape" {
              js_prevent_default(event)
              scheduler.dispatch(NamePromptCancel)
            }
          }),
      ),
      if model.overlay.name_error != "" {
        @html.div(class="name-prompt-error", [@html.text(model.overlay.name_error)])
      } else {
        @html.text("")
      },
    ],
  )
}
```

- [ ] **Step 2: Add view_action_overlay to main view**

In `main.mbt`'s `view` function, add the overlay as the last child of the main container (so it renders on top):

```moonbit
view_action_overlay(dispatch, model),
```

- [ ] **Step 3: Add overlay + prompt styles to canopy-editor.ts SHADOW_STYLES**

Add the CSS for `.which-key-overlay`, `.wk-item`, `.wk-key`, `.wk-group-label`, `.name-prompt`, `.name-prompt-input`, `.name-prompt-error`, and `.action-sheet` / `.as-item` (same styles as the original plan — see the CSS in Tasks 3-4 of the original TypeScript plan).

- [ ] **Step 4: Add missing FFI helpers**

In `bridge_ffi.mbt`, add helpers for input events:

```moonbit
///|
extern "js" fn js_get_input_value(event : @web.Event) -> String =
  #|(function(e) { return e.target ? e.target.value || '' : ''; })

///|
extern "js" fn js_get_event_key(event : @web.Event) -> String =
  #|(function(e) { return e.key || ''; })

///|
extern "js" fn js_prevent_default(event : @web.Event) -> Unit =
  #|(function(e) { if (e.preventDefault) e.preventDefault(); })
```

- [ ] **Step 5: Test manually**

Run: `cd examples/ideal/web && npm run dev`
1. Select a node → press Space → overlay appears
2. Press a mnemonic key → action executes
3. Try Extract (e) → name prompt appears → type name → Enter
4. Press Esc → overlay dismisses
5. On mobile viewport: long press → action sheet appears → tap action

- [ ] **Step 6: Commit**

```bash
git add examples/ideal/main/view_actions.mbt examples/ideal/main/main.mbt examples/ideal/main/bridge_ffi.mbt examples/ideal/web/src/canopy-editor.ts
git commit -m "feat(ideal): render action overlay and name prompt via Rabbita"
```

---

## Dependency Graph

```
Task 1 (Model+Msg) ──→ Task 2 (action model)
Task 1 (Model+Msg) ──→ Task 5 (update handler)
Task 2 (action model) ──→ Task 5 (update handler)
Task 3 (TS events)   ──→ Task 4 (trigger buttons)
Task 4 (triggers)    ──→ Task 5 (update handler)
Task 5 (update)      ──→ Task 6 (view)
```

Tasks 1-2 and 3-4 can be done in parallel.
Task 5 depends on all of 1-4.
Task 6 depends on Task 5.
