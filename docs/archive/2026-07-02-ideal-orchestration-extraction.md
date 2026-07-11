# Ideal Orchestration Extraction

**Status: SHIPPED 2026-07-03 via PR #845 (`3a14f20`); archived 2026-07-04.**

## Why

`examples/ideal/main` is no longer a thin example. It currently contains 6,008
MoonBit source lines across 29 `.mbt` files, including reusable lambda/editor
domain logic that belongs below the app layer:

- `main.mbt` is 942 lines; `update()` spans roughly lines 453-820 and mixes TEA
  message dispatch, typed tree-edit application, log maintenance, outline
  selection repair, CodeMirror sync, and Web Component event reconciliation.
- `main.mbt::structural_edit_op_to_tree_edit` and
  `apply_structural_edit_request` span roughly lines 394-450 and rebuild typed
  lambda tree-edit operations from string events before routing them through the
  editor.
- `main.mbt::push_intent`, `push_patch`, and `refresh` span roughly lines
  161-230 and mix reusable log-entry construction / editor-state refresh logic
  with app-owned `Model` mutation.
- `scope_annotation.mbt` is 206 lines of scope-graph-derived outline annotation
  logic over lambda scope/editor data.
- `action_model.mbt` is 209 lines of lambda action context detection,
  submenu-choice computation, and action-id-to-`TreeEditOp` construction.
- `action_overlay_flow.mbt` is 314 lines; its first ~260 lines are pure overlay
  state transition logic over action/menu state, while its final section creates
  Rabbita cells and commands.

This contradicts the accepted
[Library API boundary](../decisions/2026-06-11-library-api-boundary.md): Canopy's
direction is a publishable projectional-editor library, while `examples/*` is
Tier 3 app/demo code. The example should exercise the library and language SPI,
not trap reusable orchestration inside a Rabbita package.

## Scope

In:

- `examples/ideal/main/main.mbt`
- `examples/ideal/main/model.mbt`
- `examples/ideal/main/main_wbtest.mbt`
- `examples/ideal/main/scope_annotation.mbt`
- `examples/ideal/main/scope_annotation_wbtest.mbt`
- `examples/ideal/main/action_model.mbt`
- `examples/ideal/main/action_overlay_flow.mbt`
- `examples/ideal/main/action_overlay_*.mbt`
- `examples/ideal/main/view_actions.mbt`
- `examples/ideal/main/view_bottom.mbt`
- `examples/ideal/main/moon.pkg`
- `lang/lambda/companion/`
- `lang/lambda/edits/`
- `lang/lambda/scope/`

Out:

- Moving Rabbita `@html`, `@cmd`, `@sub`, `@menu`, `@tabs`, CodeMirror, DOM, or
  Web Component types into any library package.
- Changing text/CRDT/edit semantics.
- Adding one catch-all ideal library package.
- Generic `editor/` APIs for lambda-specific action or scope behavior.
- The broader architecture redesign stages in
  [2026-06-11-architecture-redesign-proposal.md](2026-06-11-architecture-redesign-proposal.md),
  except where this plan consumes its library/app boundary.
- Source-code implementation in this plan-authoring pass.

## Current State

- The accepted boundary ADR classifies `core`, `projection`, `editor`, and
  `protocol` as Tier 1 library surface; `lang/<L>/*` as Tier 2 language SPI;
  and `examples/*` as Tier 3 internal/example code.
- `docs/TODO.md` section 14 records the remaining library API audit and the
  goal of publishing Canopy as a general projectional-editor library.
- `lang/lambda/companion/lambda_editor.mbt` already owns the lambda/editor
  integration seam: `new_lambda_editor`, `LambdaCompanion`, language
  capabilities, and `apply_lambda_tree_edit`.
- `lang/lambda/edits/actions.mbt` already owns lambda action definitions and
  availability filtering via `Action`, `ActionGroup`, `NodeContext`, and
  `get_actions_for_node`.
- `lang/lambda/scope/` already owns `ScopeGraph`, declarations, references,
  `binder_span`, `go_to_definition`, and environment queries.
- `editor/sync_editor_tree_edit.mbt` is intentionally generic: it exposes
  language-agnostic node delete/commit/transform/move operations, not
  lambda-specific `TreeEditOp` reconstruction.
- Current Ideal tests already pin several extraction contracts:
  `scope_annotation_wbtest.mbt` covers highlighting and nested module scope
  behavior; `main_wbtest.mbt` covers overlay state transitions, event detail
  parsing, and the unified structural-edit label shape.

Known constraints:

- No Rabbita type may leak into `editor/`, `lang/lambda/companion`,
  `lang/lambda/edits`, or `lang/lambda/scope`.
- Each implementation step below must be independently shippable as one PR.
- Cross-package extraction changes what tests can construct because MoonBit
  `pub` fields are read-only outside the defining package. Tests must follow
  ownership: the destination package tests extracted logic; the example keeps
  only integration/UI tests.
- Any new helper/type/API introduced during implementation must satisfy the
  Existing API First rule: check project APIs and relevant MoonBit core APIs,
  report candidates, and justify any new API boundary.

## Desired State

- `examples/ideal/main` remains the Rabbita application: `Model`, `Msg`, view
  rendering, command/subscription wiring, CodeMirror sync, DOM/Web Component
  event plumbing, and UI-only state.
- `lang/lambda/companion` owns lambda editor orchestration that crosses typed
  tree edits and `SyncEditor[@ast.Term]`: structural-edit request
  reconstruction and the "apply op, return span edits" path.
- `lang/lambda/scope` owns pure scope-derived annotation/highlight data used by
  outline-like consumers.
- `lang/lambda/edits` owns lambda action domain logic: action context,
  submenu-choice data, operator/name parsing, and action-id-to-`TreeEditOp`
  construction.
- Pure overlay state transitions are separated from Rabbita cell/command
  creation as an example-local file split (the state machine embeds
  `@menu.Msg` from the Rabbita-family `rabbita-menu` package, so it cannot
  cross the library boundary as-is; see step 6).
- Intent/patch logging keeps app-owned arrays in `Model`, but label/snapshot
  construction is pure and reusable enough to test without mutating the
  example model.
- `update()` is a coordinator over per-message-family handlers after extraction;
  the final split is example-internal and byte-equivalent where possible.

## Steps

1. **Prepare the contract and test inventory.**
   Record the current package imports, `.mbti` surfaces, and test ownership for
   the candidate files. Add or move only tests that pin existing behavior before
   extraction: structural-edit request string mapping, log-entry construction,
   scope annotation, action-context detection, action-to-tree-edit construction,
   and overlay pure state transitions.

   Test-construction decision (resolved 2026-07-02, no mid-step judgment
   needed): because each extraction moves the type definitions into the
   destination package, the pinning tests move as **whitebox tests**
   (`*_wbtest.mbt`) in that destination — same-package construction is
   unrestricted, so no `pub(all)` widening and no new public constructors are
   required for testing. Fixtures reuse the parse → `ProjNode`/`SourceMap`/
   `ScopeGraph` helpers already used by `lang/lambda/edits/text_edit_wbtest.mbt`
   and the `lang/lambda/scope` wbtests. The example keeps only integration
   tests that exercise the extracted public APIs. If an implementation step
   nonetheless appears to require visibility widening, that is a stop-and-report
   event, not a call to make inline.

2. **Extract structural-edit request reconstruction to `lang/lambda/companion`.**
   Move the `structural_edit_op_to_tree_edit` responsibility from
   `examples/ideal/main/main.mbt` into a lambda companion API, because the logic
   maps app/FFI string events onto lambda `TreeEditOp` values and must stay near
   `apply_lambda_tree_edit`. Do not put this in generic `editor/`: it knows
   `"WrapInLambda"`, `"Delete"`, lambda default variable names, and
   `@lambda_edits.TreeEditOp`. Keep unrebuildable operations such as `"Drop"` as
   an explicit `None`/unsupported result so app callers can retain their raw
   fallback labels. Migrate the direct request path and the
   `StructureStructuralEdit` FFI arm to import the companion helper.

3. **Extract pure log-entry construction, not app-owned log mutation.**
   Introduce a pure logging helper in the narrowest fitting package after the
   reuse check. Prefer `lang/lambda/companion` if the API consumes
   `TreeEditOp`/`SpanEdit` pairs produced by `apply_lambda_tree_edit`; keep it
   example-local if no downstream library consumer exists. The helper may build
   the op label and a detached/truncated `SpanEdit` snapshot. It must not accept
   or mutate `Model`, `intent_log`, or `patch_log`; cap enforcement and array
   ownership stay in the example. Preserve these invariants: empty patch arrays
   produce no patch-log row; `inserted` text truncates by codepoint rather than
   UTF-16 index; op labels remain `TreeEditOp.to_generic().to_string()`.

4. **Extract scope annotation to `lang/lambda/scope`.**
   Move `ScopeAnnotation`, binder UI-key selection, nested module graph overlay,
   usage-list rebuild, scope-map construction, and highlight-set computation
   into `lang/lambda/scope` (for example `outline_annotation.mbt`). This is
   lambda scope behavior, not companion/editor orchestration: the code depends
   on `ScopeGraph`, `DeclKind`, `@ast.Term::Module`, and core projection/source
   data, but not on Rabbita or app `Model`. Prefer a lower-level constructor
   that accepts `ProjNode[@ast.Term]`, registry, and `SourceMap`; keep an
   optional convenience wrapper for `SyncEditor[@ast.Term]` only if it does not
   create an unwanted `scope -> editor` dependency or cycle. Move
   `scope_annotation_wbtest.mbt` ownership into `lang/lambda/scope` and leave
   example tests only for rendering/highlight integration.

5. **Extract lambda action domain logic to `lang/lambda/edits`.**
   Move `NodeActionContext` or a renamed equivalent, conversion to
   `NodeContext`, submenu-choice computation, `parse_bop`, and
   `build_tree_edit_op` into the existing lambda edits package, adjacent to
   `actions.mbt`. This package already owns `Action`, `NodeContext`, and
   `get_actions_for_node`, so it is the responsibility match. Context-detection
   boundary (resolved 2026-07-02 by inspection): `detect_action_context` uses
   `SyncEditor` only for `get_node(nid)` and `get_proj_node()` — registry lookup
   plus the root `ProjNode` — and `lang/lambda/edits/moon.pkg` does not import
   `editor` today. Therefore expose a **pure builder** in `edits` over the root
   `ProjNode[@ast.Term]`, the looked-up node, `DefinitionIndex`, and the
   selected `NodeId`; place the thin `SyncEditor[@ast.Term]`-taking wrapper in
   `lang/lambda/companion` (which already imports `editor`). Do not add an
   `edits -> editor` import. Migrate action-construction tests from
   `main_wbtest.mbt` to `lang/lambda/edits`.

6. **Separate pure overlay flow from Rabbita runtime wiring (example-local).**
   Destination (resolved 2026-07-02 by inspection): the overlay state machine
   **stays in `examples/ideal/main`**. `OverlayMsg` embeds `@menu.Msg` and
   `OverlayState::handle_menu_msg` pattern-matches it, where `@menu` is
   `dowdiness/rabbita-menu/menu` — a Rabbita-family package — so moving the
   state machine to any `lang/*` package would violate the hard no-Rabbita
   constraint. The step is therefore a file split inside the example: pure
   `OverlayMsg`/`OverlayOutput`/`OverlayEffect`/`OverlayUpdate` and all
   `OverlayState::*` transitions (`action_overlay_flow.mbt` up to
   `overlay_effect_to_cmd`) in one file with no `@rabbita` import; cell
   creation, focus commands, parent emits, and view callbacks
   (`overlay_effect_to_cmd`, `overlay_cell_update`, `create_overlay_cell`) in a
   runtime file. Re-modeling `OverlayMsg` on a UI-neutral menu-message enum is
   an explicit non-goal here; note it as a follow-up only if a second consumer
   for the overlay flow appears. Preserve token-guard behavior for delayed
   child outputs.

7. **Centralize Ideal refresh orchestration around extracted pure data.**
   After scope/log/action extraction, reduce `refresh(model)` to app-owned
   state assembly: read `editor.get_proj_node()` and `get_source_map()`, refresh
   `TreeEditorState`, call the extracted scope annotation builder, and recompute
   the selected-node highlight set. Keep `js_perf_*` measurements and
   `Model` updates in the example. This step should not alter projection,
   parser, or editor memo semantics.

8. **Split `update()` into example-internal message-family handlers last.**
   Only after reusable logic has moved, reorganize the remaining reducer into
   small files such as mode/workspace, outline navigation, structural edits,
   overlay, CodeMirror, file I/O, and external structure-mode events. This is a
   secondary refactor and should be move-only / byte-equivalent where possible:
   no new library APIs, no behavior changes, and no Rabbita code moved outside
   the example.

Each step lands as its own PR with imports updated, example call sites migrated,
and tests green before the next extraction starts.

## Acceptance Criteria

Ticked post-merge 2026-07-04 against main after PR #845 (`3a14f20`): direct
greps verified the no-UI-imports and update-split criteria; the ownership
criteria are grounded in #845's diff (extracted files + moved tests); the two
process criteria (`.mbti` review, reuse check) rode PR #845's normal review.

- [x] No `@rabbita`, `@html`, `@cmd`, `@sub`, `@menu`, CodeMirror, DOM, or Web
      Component type appears in `editor/`, `lang/lambda/companion`,
      `lang/lambda/edits`, or `lang/lambda/scope`.
- [x] `examples/ideal/main` imports extracted APIs instead of defining
      structural-edit reconstruction, scope annotation, and action-to-edit
      construction locally.
- [x] `lang/lambda/companion` owns lambda structural-edit request reconstruction
      and keeps unsupported/unrebuildable app events explicit.
- [x] `lang/lambda/scope` owns `ScopeAnnotation`-style scope annotation and
      highlight computation, with nested module and shadowing tests moved there.
- [x] `lang/lambda/edits` owns action context / submenu / action-id-to-edit
      construction, with tests moved there.
- [x] Intent/patch log arrays remain app-owned, while any extracted helper is
      pure and preserves label/truncation invariants.
- [x] `update()` is split only after extraction and remains example-internal.
- [x] `.mbti` diffs for Tier 1/Tier 2 packages are reviewed as API changes;
      no visibility widening is accepted only to make old example tests compile.
- [x] Each PR reports the Existing API First reuse check for any new API.

## Validation

Run after every extraction PR:

```bash
moon check
moon test
```

Run when Ideal or JS-facing behavior changes:

```bash
moon build --target js
cd examples/ideal/web && npm run test
```

Also run targeted package tests during each step:

```bash
moon test --target js
```

Before committing an extraction PR:

```bash
moon fmt
moon info
git diff --stat
git diff -- '*.mbti'
```

Inspect `.mbti` changes for unintended visibility or trait-bound drift,
especially in `editor/`, `lang/lambda/companion`, `lang/lambda/edits`, and
`lang/lambda/scope`.

## Risks

- **Dependency direction drift.** A convenience wrapper can accidentally make
  `lang/lambda/scope` depend on `editor` or action code depend on companion
  orchestration. Prefer pure inputs first; add wrappers only when dependency
  direction stays clean.
- **Visibility pressure from moved tests.** Existing example whitebox tests can
  tempt `pub(all)` widening. Follow test ownership instead: move tests to the
  package that owns the logic, and expose only named constructors/query methods
  needed by real consumers.
- **String protocol ambiguity.** `structural_edit_op_to_tree_edit` currently
  covers only rebuildable operations. Do not pretend app event strings encode
  payloads they do not carry; `"Drop"` remains a fallback label unless the event
  protocol changes in a separate PR.
- **Over-extraction of overlay flow.** Resolved at plan time: the overlay
  state machine depends on `@menu.Msg` (rabbita-menu) and stays example-local
  (step 6). The residual risk is an implementer "improving" this by moving it
  anyway — do not; re-modeling the menu dependency is out of scope.
- **Behavior changes hidden in reducer splitting.** `update()` refactoring is
  last and should be mostly move-only so behavioral diffs are attributable to
  earlier extraction PRs.

## Notes

- Related boundary record:
  [docs/decisions/2026-06-11-library-api-boundary.md](../decisions/2026-06-11-library-api-boundary.md).
- Related backlog item: [docs/TODO.md section 14](../TODO.md#14-documentation--demo-polish).
- Related umbrella proposal:
  [docs/plans/2026-06-11-architecture-redesign-proposal.md](2026-06-11-architecture-redesign-proposal.md).
- Destination rationale:
  `editor/` is not the right home for lambda action or scope behavior; it should
  remain generic over `T`. `lang/lambda/companion` is the lambda/editor
  integration seam. `lang/lambda/edits` owns edit/action vocabulary.
  `lang/lambda/scope` owns scope-graph query behavior.
