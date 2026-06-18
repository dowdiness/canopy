# Ideal Overlay Architecture — Reference Design

**Date:** 2026-06-18  
**Scope:** `examples/ideal/main/` — action overlay refactor  
**Status:** Approved for implementation

---

## Problem

The Ideal editor's action overlay uses a Rabbita child cell for UI isolation
(the skip-dirty optimization: menu keypresses do not re-render the parent's
outline tree). This is correct. However, `NodeActionContext` — application
context derived from the parent's editor projection — is stored inside the
child cell's `OverlayState` and relayed back to the parent in the
`ExecuteAction` output payload. The context takes a round-trip:

```
parent detects ctx → stores in child OverlayState.node_context
child reads ctx.kind for submenu rendering
child embeds full ctx in OverlayOutput::ExecuteAction
parent receives ctx back → uses it in execute_action
```

This violates the responsibility boundary: the child cell owns UI navigation
state; the parent owns application context. The child was holding application
data on behalf of the parent, and the dead-code `None` arm in `context_kind()`
reveals that `node_context` was always `Some(...)` — the optional wrapping
served no purpose.

---

## Design Principle

**Child cell owns UI navigation state. Parent owns application context.
Nothing crosses the boundary twice.**

The child signals *intent* (`action + choice + name`). The parent retrieves
its own context when handling that signal. Context is detected once in the
parent, stored once in the parent, consumed once in the parent.

---

## Architecture

### `OverlayState` — pure UI state (child-owned)

Remove `node_context : NodeActionContext?`. Add `kind : @ast.Term` directly.

```
struct OverlayState {
  mode       : OverlayMode
  actions    : Array[@lambda_edits.Action]
  kind       : @ast.Term      // only what the child needs for submenu choices
  error      : String
  anchor_top : Int
  anchor_left : Int
  menu       : @menu.Model
}
```

Rationale:
- The child only reads `ctx.kind` (via `context_kind()` → `submenu_choices()`).
- `node_context` was always `Some(...)` on a live overlay; the `None` fallback
  was dead code. `kind` is unconditional — no optional wrapping needed.
- Full `NodeActionContext` is application state, not UI state.

### `ActionOverlayHost` — gains application context (parent-owned)

```
struct ActionOverlayHost {
  runtime    : ActionOverlayRuntime?
  context    : NodeActionContext?   // application context, owned here
  next_token : Int
}
```

`mount` takes `context : NodeActionContext` and stores it alongside the
runtime. `close` clears both `runtime` and `context` together (they are
always co-valid). `empty` initialises `context: None`.

### `OverlayOutput` — context drops out of the wire

```
enum OverlayOutput {
  ExecuteAction(token~ : Int, @lambda_edits.Action, choice~ : String, name~ : String)
  CloseOverlay(token~ : Int)
}
```

`context~` is removed. The parent reads `model.overlay.context` when handling
`ExecuteAction` — it always has the current context because it owns it.

### Data flow (after)

```
open_action_overlay:
  parent detects ctx
  → stores ctx in ActionOverlayHost.context
  → passes only ctx.kind into OverlayState

child execution path:
  child reads self.kind for submenu choices
  → emits OverlayOutput::ExecuteAction(token, action, choice, name)

handle_overlay_output:
  parent validates token
  → reads model.overlay.context
  → calls execute_action(model, runtime, context, action, choice, name)
```

Context takes a one-way trip. The child never holds it.

---

## What Stays the Same

### Token system

Still necessary. The child communicates back to the parent via `parent_emit`
(enqueuing into the **parent's** inbox). Rabbita's `live_map` lifecycle guard
applies only to a cell's own inbox — messages routed through `parent_emit`
bypass it. The token is the correct manual equivalent for stale-output
rejection when using the captured-parent-emit pattern.

Rule: whenever a Rabbita child cell uses `parent_emit` for child→parent
signaling, the parent must provide an independent stale-output guard. The
token in `ActionOverlayHost` is the canonical form.

### `OverlayEvent` encapsulation boundary

`OverlayKeyPressed` / `OverlayNameCancel` remain a distinct type from
`OverlayMsg`. The parent `Msg` type never exposes child-internal message
types. `OverlayEvent::to_overlay_msg()` is the explicit translation layer.

### Child cell (`Cell`)

The Rabbita skip-dirty optimisation is the reason for using a child cell:
menu keypresses mark only the child dirty, not the parent. Without the child
cell, every keystroke would trigger a full re-render of the parent's outline
tree. The cell boundary is justified.

### `parent_emit` capture

The established Rabbita pattern for child→parent signaling: the child's
update closure captures `parent_emit` at cell-creation time. The parent's
`Emit[Msg]` is stable (root cell), so the captured reference is always valid.

---

## Files and Changes

| File | Change |
|------|--------|
| `model.mbt` | `OverlayState`: remove `node_context`, add `kind : @ast.Term` |
| `action_overlay_runtime.mbt` | `ActionOverlayHost`: add `context : NodeActionContext?`; update `empty`, `mount` (new param), `close` |
| `action_overlay_flow.mbt` | `OverlayOutput::ExecuteAction`: drop `context~`; `overlay_effect_to_cmd`: remove dead `None` guard; `context_kind()`: return `self.kind` directly |
| `action_overlay_state.mbt` | `open_action_overlay`: store `ctx` in host (`mount(ctx, runtime)`), pass `ctx.kind` into child `initial_state` |
| `action_overlay_update.mbt` | `handle_overlay_output` `ExecuteAction` arm: read `model.overlay.context` instead of receiving it from output |
| `view_actions.mbt` | `view_overlay` Submenu arm: replace `match state.node_context { Some(ctx) => view_submenu_choices(…ctx.kind) … }` with direct `view_submenu_choices(…state.kind)` |
| `main_wbtest.mbt` | `test_overlay_state`: replace `node_context: Some(…)` with `kind: @ast.Term::Unit`; token tests: drop `context=` from `OverlayOutput::ExecuteAction`; `ActionOverlayHost::empty().mount(runtime)` → `mount(ctx, runtime)` |

`action_overlay_exec.mbt` — no change. `execute_action` still receives
`context` from its caller (`handle_overlay_output`).

---

## Reference Implementation Notes

This design demonstrates the canonical Rabbita child-cell pattern for an
ephemeral overlay with parent-context execution:

1. **State partitioning**: child holds navigation state, parent holds
   application context. Determined by who *owns* the data, not who *uses* it.

2. **Signal vs. data**: child output carries only intent signals
   (`action`, `choice`, `name`). Application data flows from parent context,
   not from child output.

3. **Stale-output guard**: token in `ActionOverlayHost` matches the token
   embedded in `OverlayOutput`. This is mandatory whenever `parent_emit` is
   used for child→parent communication.

4. **Lifecycle co-validity**: `runtime` and `context` in `ActionOverlayHost`
   are always `Some` or `None` together. They are set together in `mount` and
   cleared together in `close`. Co-valid fields should be co-managed.

5. **No dead optionals**: `OverlayState.kind : @ast.Term` replaces
   `node_context : NodeActionContext?` which was always `Some` on a live
   overlay. Represent invariants in types: if a field is always `Some`, it
   should not be `Option`.

---

## Non-Goals

- Changing the token mechanism or `parent_emit` pattern
- Changing `OverlayEvent` / `OverlayMsg` separation
- Eliminating the child cell or changing the skip-dirty behaviour
- Touching the action execution logic in `action_overlay_exec.mbt`
- Any UI or styling changes
