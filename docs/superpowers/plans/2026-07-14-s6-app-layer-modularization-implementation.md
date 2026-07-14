# S6 — App-Layer Modularization Implementation Plan

**Date:** 2026-07-14
**Design:** `docs/superpowers/specs/2026-07-11-s6-app-layer-modularization-design.md`
**Scope:** `examples/ideal/main/`, plus the minimal supporting package manifests
and boundary adapters required to compile, target, and test the extracted
package (`js_ffi`, `lib/dom-boundary`, `lib/menu/menu`)
**Status:** Executed; supporting boundary scope amendment requires review

## Scope amendment

The extracted action-overlay package depends on shared JavaScript/DOM/menu
boundaries. The implementation therefore updated only their target manifests,
boundary adapters, generated interfaces, and focused tests. These edits are
dependency-boundary support for S6, not unrelated feature behavior.

## Goal

Remove Ideal's legacy root and overlay `Cell` usage without changing editor,
CRDT, selection, overlay, or browser behavior. The root app becomes a
`create_state_with_init` application. Overlay state becomes a pure state slice
of that root graph and is extracted with its view into the
`examples/ideal/main/action_overlay/` package. No `Cell`, nested
`Cell::view()`, runtime-held `Emit`, or runtime-held `Cmd` remains in Ideal.

## Invariants

- `cm_mount_cmd` still runs once after the root is mounted and receives the
  root `Emit` through `create_state_with_init`'s init callback.
- Every root message still reaches exactly one existing feature handler, or the
  existing explicit unhandled-message error path.
- Overlay transitions are deterministic: `(OverlayMsg, OverlayState)` produces
  `(OverlayEffect, OverlayState)` without editor, DOM, network, or command I/O.
- Overlay effects that reach the parent are stamped with the active token at
  the parent boundary. A stale token is rejected exactly as before.
- Editor/CRDT commits remain in the parent because they require the full
  `Model` and action context.
- `Model` remains the existing session/application state boundary. It may
  continue to contain the mutable editor, FFI handles, and runtime-owned
  observers already required by Ideal, but it must not contain Rabbita
  `Cell`, `Val`, `Emit`, or `Cmd` handles.

## Functional core / imperative shell boundary

This migration must not claim that the entire existing `Model` is a pure
functional-core value. The current `Model` contains `SyncEditor`, FFI handles,
and an incremental runtime tap, so it is part of the application shell.

### Functional core

- Overlay transition: `(OverlayMsg, OverlayState) -> (OverlayEffect,
  OverlayState)`.
- Overlay mode invariants and error-state transitions.
- Overlay placement calculation when given parsed anchor and viewport values.
- A pure overlay-state constructor from explicit action/context/anchor/menu
  values gathered by the shell.

The existing `open_action_overlay`, `commit_tree_edit`, `load_text`,
`refresh`, and `sync_after_*` helpers are **not** functional-core helpers:
they read or mutate `Model.editor`, call FFI, schedule commands, or perform
CRDT/intent-log work. Keep them in the shell and do not move them into the
new package under the pretext of "pure computation".

Core functions receive all inputs explicitly and return state, effects, or
decisions. They must not call `@rabbita`, `@cm`, `@ffi`, `js_*`, clocks,
network APIs, or mutate `Model.editor`.

Token capture, storage, stamping, comparison, and stale-message rejection
remain in the imperative shell. Token equality is lifecycle plumbing, not a
domain transition, so no token predicate is extracted into the core.

### Imperative shell

- Rabbita `create_state_with_init`, `Emit`, `Cmd`, subscriptions, and root
  rendering.
- Browser/DOM FFI: viewport, anchor rectangles, focus, overlay visibility.
- CodeMirror mount/synchronization and file I/O.
- CRDT/editor mutation, refresh, intent/patch logging, and incremental taps.
- Overlay token lifecycle: next-token allocation, active-token storage, parent
  stamping, comparison, and stale-message rejection.
- Interpreting `OverlayEffect` and executing its commands.

The shell may keep the existing `Model` façade during S6. The required
improvement is a narrow, explicit core/shell seam around overlay behavior; a
full `Model`/`SyncEditor` decomposition is a separate redesign and is not a
hidden acceptance criterion.

## Execution order

### 1. Characterize the current root and overlay contracts

Files: `examples/ideal/main/main_wbtest.mbt`,
`examples/ideal/main/action_overlay_*.mbt`.

First inventory the existing whitebox tests as a variant-by-responsibility
gap matrix. The current `main_wbtest.mbt` already covers `SetError` with both
existing `OverlayError` payload cases, `NoOverlayEffect`, error clearing, and
core mode transitions; do not add duplicate tests for those cases. Add or
tighten tests only for uncovered contracts:

- **Root initialization:** init model/command ordering, one-time CodeMirror
  mount command, subscriptions, and root view mapping.
- **Parent effect interpretation audit set:** inspect every `OverlayEffect`
  variant — `NoOverlayEffect`, `FocusMenu`, `FocusNamePrompt`,
  `ExecuteAction`, and `CloseOverlay` — and add tests only for variants
  lacking observable interpreter coverage.
- **Parent lifecycle:** close/reopen behavior and stale-token rejection.

Tests must assert observable state/effect values, not source shape, and remain
deterministic and independent of browser timing.

Validation: run the focused Ideal whitebox tests. Record the existing Rabbita
pin failures separately; do not modify `rabbita/` or unrelated examples.

### 2. Migrate the root application lifecycle

Files: `examples/ideal/main/main.mbt` and the root-init/view files after any
Phase 3 rename is chosen.

- Replace the root `cell_with_emit` construction with
  `create_state_with_init`.
- Put `init_model()` and the existing CodeMirror mount command in the init
  callback, preserving command ordering and subscriptions.
- Return `model.map(model => view(emit, model))` from the root component.
- Rabbita's `create_state_with_init` callbacks use `(Model, Cmd)`, while the
  current Ideal dispatcher uses `(Cmd, Model)`. Introduce one explicit adapter
  at the root boundary (or update the dispatcher consistently) and test that
  command/model ordering is preserved; never rely on tuple inference.
- Keep DOM/CodeMirror commands in the imperative shell and return them from
  update/init; do not introduce a command field in `Model`.
- Preserve the existing message dispatcher and view output byte-for-byte where
  behavior does not require a change.

Validation after this edit: `moon check` for the affected package, then its
focused tests. The current baseline has unrelated `action_overlay_runtime`
`Cell::view` and detached-Rabbita `diff_subs` errors; the migration must make
its own package compile independently of those baseline failures.

### 3. Replace the overlay runtime with pure state transitions

Files: `action_overlay_flow.mbt`, `action_overlay_state.mbt`,
`action_overlay_update.mbt`, `action_overlay_exec.mbt`,
`action_overlay_runtime.mbt`, `action_overlay_flow_wiring.mbt`.

- Fold the active overlay state/context/token representation into `Model`.
- Remove child-cell creation and runtime-held `Cell`/`Emit` values.
- Define the smallest `OverlayEffect` enum needed by current behavior:
  focus/menu updates, name-prompt requests, close, and execute-action output.
- Make overlay update return the effect and next state; keep effect execution
  in the parent update path.
- Keep `execute_action` in `main`; preserve its current error policy: action
  failures become overlay errors, while unrelated tree-edit callers retain
  their existing no-op/error behavior.
- Remove token fields from child-created output. Define the parent-only
  `ActionOverlayEffect(token, output)` wrapper carried by
  `Msg::ActionOverlayEffect`; stamp the active token when the parent schedules
  the effect command, and validate that wrapper token in the stale-output
  guard.
- Delete obsolete flow-wiring/runtime code once no call site remains.

Validation after every file edit (one file per edit call): run `moon check`
and the focused whitebox tests before editing the next file.
Use `moon ide find-references` before removing exported or package-visible
symbols.

### 4. Extract the overlay package with separate core and view layers

Create `examples/ideal/main/action_overlay/moon.pkg`. Move the overlay's
functional-core modules separately from its framework-facing view adapter:

- **Core:** flow types, state types, constructors, transition functions, and
  placement calculations. The core must not directly call or construct
  `@rabbita`, `@html`, `Emit`, `Cmd`, DOM, FFI, or parent `Msg` values.
  `OverlayState` currently reuses `@menu.Model`/`@menu.Msg`; that package has
  a transitive Rabbita/cmd/html dependency. S6 therefore guarantees
  effect-free, deterministic transitions and native-testable behavior, not a
  framework-independent dependency graph. Splitting `@menu` into a pure state
  layer is a separate follow-up design.
- **View adapter:** `view_overlay` and its rendering helpers. This layer may
  depend on `@rabbita`, `@html`, `Emit[OverlayMsg]`, `@menu.Model` rendering
  APIs, and HTML attributes. It translates core state into HTML and user
  events into overlay messages; it does not execute effects.
- Keep `action_overlay_exec.mbt` and parent dispatch in `main`.

Use package-private declarations by default. Add narrow public
constructors/accessors only where parent code or blackbox tests require them;
avoid blanket `pub(all)`. Keep the package independent of the parent `Msg`
type and wrap child effects into parent messages at the parent dispatch
boundary.

Core transition tests must not invoke the Rabbita view/runtime or any effect
executor. They may compile against the existing transitive `@menu` dependency.
View adapter tests may use the JS target and should cover event
wiring/rendered state; effect execution and token validation remain
parent-shell tests. Update package imports and generated `.mbti` interfaces.

Validation: run `moon check` and the appropriate focused tests from the
package root; inspect `git diff '*.mbti'` for unintended API exposure.

### 5. Apply feature-scoped file renames and package moves

After the behavioral migration is green, perform the design's mechanical
renames: split `update_handlers.mbt` by feature, split the bottom views, split
`main.mbt` into init/commands/intent-log/root-view/update, and move only
Model-free history/Graphviz computation into `internal/` packages. Do not mix
these moves with behavior changes. Preserve file content during moves except
for required package qualification.

Validation: run `moon check` after every edit, then focused tests. Run the two
Ideal Playwright specs after JS artifacts are rebuilt.

## Verification gate

Run, from the repository root:

1. `moon check`.
2. `moon test -p dowdiness/ideal-editor/main` (or the package's current
   equivalent discovered from its manifest).
3. `moon build --target js`.
4. `cd examples/ideal/web && npm install` only if dependencies are absent.
5. `cd examples/ideal/web && npx playwright test e2e/structure-mode-switch.spec.ts e2e/structural-editing.spec.ts`.
6. `moon info && moon fmt`; inspect generated interface diffs.

The detached-Rabbita `tea_wbtest.mbt` `diff_subs` error and any unrelated
workspace warnings must be reported as baseline blockers, not silently called
passing. Ideal's own target must compile and its focused tests must pass before
claiming completion.

## Reuse check

- Reuse project APIs: existing `init_model`, `cm_mount_cmd`, message
  dispatcher, feature handlers, `execute_action`, and overlay token checks.
- Reuse Rabbita APIs: `create_state_with_init`, `Val::map`, `Emit`, `Cmd`, and
  existing subscription/command helpers. Do not introduce a second runtime or
  custom reactive abstraction.
- Checked but not reused: legacy `cell_with_emit`/`Cell::view` because the
  current Rabbita API deprecates/removes nested Cell composition; independent
  child `create_state` was rejected because it requires late-bound imperative
  Emit wiring and duplicates state ownership.
- New helper boundary: `OverlayEffect` is the only new pure data boundary; it
  describes overlay intent and contains no side effects.
- Remaining imperative code: CodeMirror/DOM commands, scheduling, and CRDT
  mutation remain in the parent shell because they are integration effects.
