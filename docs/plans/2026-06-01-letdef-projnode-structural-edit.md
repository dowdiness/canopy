# First-class LetDef ProjNodes for binding-level structural edits

**Status:** ready
**Date:** 2026-06-01
**GitHub:** #127
**Supersedes:** the deferred Option-B endpoint from `docs/plans/2026-05-30-scope-binder-node-id-reconciliation.md` only for structural editing of bindings. Option D remains the source-location solution.

## Why

Module and block bindings are already user-visible structural rows in Structure mode and in the binding action menu, but they are not real `ProjNode`s. The current tree shape makes every binding-level consumer borrow a nearby identity:

- Structure-mode PM `let_def` rows are synthesized from Module init children and use the init expression `nodeId`.
- Generic drag/drop over `.structure-let_def` therefore moves or swaps the init expression, not the binding as a structural object.
- MoonBit binding actions use `FlatProj.defs[i].3` as a synthetic binding handle and special-case it through edit middleware because the id does not exist in the projection registry.

This is the concrete consumer #127 was waiting for: structural editing of a binding row as an object. It does **not** reopen the already-solved binder-location problem; go-to-definition, source-range binder highlighting/location, and rename targeting should continue to use `@scope.binder_span` / `@scope.go_to_definition`.

## Scope

In:
- `loom/examples/lambda/src/ast/ast.mbt`
- `loom/examples/lambda/src/ast/sym.mbt`
- `loom/examples/lambda/src/ast/proj_traits.mbt`
- `loom/examples/lambda/src/ast/proj_traits_mechanical.mbt`
- other `loom/examples/lambda/src/**` pattern matches that must handle a `LetDef` term variant
- `lang/lambda/proj/proj_node.mbt`
- `lang/lambda/proj/flat_proj.mbt`
- `lang/lambda/proj/populate_token_spans.mbt`
- `lang/lambda/proj/term_css_class*.mbt`
- `lang/lambda/flat/projection_memo.mbt`
- `lang/lambda/scope/{builder,graph,query}.mbt`
- `lang/lambda/edits/{actions,scope,text_edit_binding,text_edit_refactor,text_edit_rename,text_edit_utils,text_edit_middleware,tree_lens}.mbt`
- `lang/lambda/semantic/semantic_projection.mbt`
- `protocol/convert.mbt` and protocol tests
- `editor/*tree_edit*` tests that assume binding rows use init ids
- `ffi/lambda/*` tree-edit / source-map JSON tests as needed
- `examples/ideal/main/{action_model,scope_annotation,view_outline}.mbt` as needed
- `examples/ideal/web/src/{convert,reconciler,schema,text-nodeview,structure-nodeview,types}.ts`
- `examples/ideal/web/e2e/drag-drop.spec.ts`
- generated `pkg.generated.mbti` files from affected packages

Out:
- Replacing `@scope.binder_span` / `@scope.go_to_definition` for locator use cases.
- Query-side scope indexing from `docs/TODO.md:447`.
- #414 public projection-walk helper work; that decision remains closed.
- Grammar changes such as interleaved let/expression source syntax.
- Canvas and audio-graph authoring packages; no concrete dependency was found there.
- A public `FlatDef` API cleanup unless needed to complete this migration. Prefer the smallest compatible `FlatProj` surface change first.

## Current State

- `lang/lambda/proj/proj_node.mbt` collects `ProjectedLetDef` entries and builds `Module(term_defs, body.kind)` with `children = [init0, init1, ..., body]`.
- `lang/lambda/proj/flat_proj.mbt` stores `defs : Array[(String, ProjNode[Term], Int, NodeId)]`; the fourth tuple field is a binding handle, synthetic on the production `to_flat_proj` path.
- `FlatProj::to_proj_node_with_prev_module_id` reconstructs a Module with init children only; `FlatProj::from_proj_node` reads Module children back as init children.
- `lang/lambda/proj/populate_token_spans.mbt` stores module-def name token spans on the Module node as roles `name:<def_index>`.
- `lang/lambda/scope/query.mbt` exposes `binder_span` and `go_to_definition`, and `lang/lambda/scope/graph.mbt` documents that module `Decl.node_id` is not a reliable tree-node pointer.
- `examples/ideal/web/src/convert.ts` synthesizes PM `let_def` nodes from Module init children and assigns `nodeId: proj.children[i].node_id`.
- `examples/ideal/web/src/reconciler.ts` has a special `diffModule` path because PM Module children are `let_def(init)` while ProjNode Module children are bare init nodes.
- `examples/ideal/web/src/structure-nodeview.ts` sends drag/drop payloads with the PM row's `nodeId`; for a `let_def` row, that is currently the init expression id.
- `editor/sync_editor_tree_edit_wbtest.mbt` describes let-definition exchange, but the expected text proves the operation swaps init values (`let x = 2`, `let y = 1`) rather than whole binding rows.
- `lang/lambda/edits/text_edit_middleware.mbt` accepts FlatProj binding ids for selected operations even when the registry does not contain them.
- `examples/ideal/main/scope_annotation.mbt` still needs UI-only synthetic keys for module binder rows because no binding row exists in the projection tree.

## Desired State

Expected projection layout:

```text
Module node
  children[0] = LetDef("x") node
    children[0] = init expression for x
  children[1] = LetDef("y") node
    children[0] = init expression for y
  children[n] = body expression
```

Observable outcomes:

- Every module/block binding has a registry-backed `LetDef` `NodeId`.
- `FlatProj.defs[i].3` is the real `LetDef` node id, not a synthetic non-registry handle.
- `Decl.node_id` for `ModuleDef` points at the real `LetDef` node.
- Binding row drag/drop and binding-level actions target the `LetDef` id.
- Structure-mode conversion no longer synthesizes `let_def` wrappers from init nodes; it maps actual `LetDef` ProjNodes to PM `let_def` nodes.
- SourceMap exposes the full LetDef range and a binder-name token span on the LetDef node. Keep Module `name:<i>` spans as a short-term compatibility fallback if it materially reduces migration risk.
- `@scope.binder_span` still returns binder-name ranges for both lambda params and module defs.
- Drag/drop on `.structure-let_def` moves/swaps whole binding rows, while expression-level drag/drop inside the init still works on the init child.

## Steps

1. **Submodule prep and AST variant.**
   - Work inside `loom/examples/lambda` on a dedicated branch if implementation starts.
   - Add `Term::LetDef(VarName, Term)` (or an equivalent name if the AST owner prefers) and update the structural source-of-truth files: `ast.mbt`, `sym.mbt`, `proj_traits*.mbt`, pretty/replay helpers, `children_of`, `rebuild_from`, and tests.
   - Define semantics for standalone `LetDef`: projection/display wrapper only. Evaluation/resolution should not treat it as a top-level program form outside a Module except as needed for total pattern matches.

2. **Projection construction.**
   - Change `project_let_def` to produce a `LetDef` `ProjNode` spanning the full `LetDef` syntax node, with the init expression as its single child.
   - Change `module_node_from_defs` and `to_proj_node` to make Module children `[let_def0, ..., body]` while keeping `Module(defs, body.kind)` as the semantic kind.
   - For block Modules, use the same layout.

3. **FlatProj migration.**
   - Keep the existing tuple shape initially if possible: `(name, init, start, binding_id)` where `binding_id` now equals the real `LetDef` node id.
   - Update `to_flat_proj`, `to_flat_proj_incremental`, and `reconcile_flat_proj` to allocate/preserve LetDef ids as first-class node ids.
   - Update `FlatProj::to_proj_node_with_prev_module_id` to wrap each init in a `LetDef` ProjNode using `defs[i].3`.
   - Update `FlatProj::from_proj_node` to read `LetDef` children and extract their init child. Treat legacy init-only Module children only if tests or migration need a compatibility fallback.

4. **SourceMap and token spans.**
   - Ensure `SourceMap::from_ast` records ranges for LetDef nodes.
   - Update `populate_token_spans` to walk SourceFile/Block syntax against LetDef children, put the binder name span on the LetDef node (role likely `"name"`), then recurse into the init child.
   - Keep or intentionally remove Module `name:<i>` spans; if removed, update all callers in the same PR.

5. **Scope graph and locator API.**
   - Update `@scope.build` so ModuleDef declarations use the LetDef node id.
   - Update `Decl` documentation: module defs once again occupy real projection nodes, but locator consumers should still prefer `binder_span`.
   - Update `binder_span` for ModuleDef to read the LetDef node's binder-name token span first, with a Module `name:<i>` fallback only if retained for compatibility.
   - Keep `references(g, decl.id)` identity-based; do not reintroduce `Decl.node_id` as the reference key.

6. **Binding edit operations.**
   - Make `find_binding_for_init` either unnecessary or explicitly return the parent LetDef id for an init child.
   - Update binding actions so a selected LetDef row directly produces `Rename`, `DeleteBinding`, `DuplicateBinding`, `MoveBindingUp`, `MoveBindingDown`, and `InlineAllUsages` with a registry-backed id.
   - Remove or shrink `ValidateNodeExists` binding-id special cases once binding ids are registry ids.
   - Update `get_binding_text_range` to prefer the LetDef node range. Keep init-range/backward-scan fallback only for compatibility tests.
   - Decide whether generic `Drop` on two LetDef nodes delegates to binding move/swap logic or remains in `SyncEditor::move_node` with LetDef-aware whole-range edits. The observable behavior must be whole-binding movement, not init swapping.

7. **Protocol and Structure-mode UI.**
   - Add `LetDef` to `examples/ideal/web/src/types.ts` and `kindToPmType` / `attrsForKind`.
   - Change `projNodeToPmNode` so `LetDef` maps directly to the PM `let_def` node.
   - Simplify or remove `diffModule`; with real LetDef ProjNodes, Module children should match PM children by index.
   - Update `LetDefView` token editing to call `handleTokenEdit(letDefNodeId, "name", changes)` instead of resolving `(moduleNodeId, defIndex)` when the new token span exists.
   - Keep compatibility fallback for `name:<defIndex>` only if the backend retains Module-level spans during migration.

8. **Scope annotation and semantic overlay cleanup.**
   - Replace module-binder UI synthetic keys with real LetDef ids for visible structural rows where possible.
   - Update `SemanticProjection` module-binder row annotations/overlay keys to attach to LetDef ids; continue deriving source ranges through `binder_span` / token spans, not `Decl.node_id`.
   - Ensure lambda binder row highlighting still attaches to the Lam node id.

9. **Tests, generated interfaces, and docs.**
   - Update all projection/FlatProj/source-map/scope/edit/protocol/TS tests covered by this scope and the acceptance criteria.
   - Run `moon fmt && moon info`; review `pkg.generated.mbti` diffs for intended API changes only.
   - For submodule changes, run the relevant `moon test` commands inside `loom/examples/lambda` and push the submodule branch before opening a parent PR.

## Acceptance Criteria

- [ ] `Module` ProjNodes expose children `[LetDef..., body]`; every LetDef has exactly one init child.
- [ ] `FlatProj.defs[i].3` is present in the projection registry and identifies the corresponding LetDef node.
- [ ] `@scope.Decl` for `ModuleDef` uses the LetDef node id, and `@scope.binder_span` still returns the binder-name range.
- [ ] Structure-mode PM conversion maps actual LetDef ProjNodes to `let_def`; no init-id synthesis remains in `convert.ts` / `reconciler.ts`.
- [ ] Drag/drop on `.structure-let_def` moves or swaps whole binding rows. Tests must reject the old `let x = 2 / let y = 1` init-swap behavior unless an explicit expression-level drop selected the init child.
- [ ] Binding actions (`DeleteBinding`, `DuplicateBinding`, `MoveBindingUp`, `MoveBindingDown`, `InlineAllUsages`, binding rename) work when passed the LetDef id.
- [ ] Module binder row annotations use real LetDef ids where a visible structural row exists; source-location highlighting still uses `@scope.binder_span`; no stale negative UI key is required for top-level/module rows.
- [ ] Go-to-definition and rename targeting remain source-span based and continue to pass existing Option-D tests.
- [ ] No canvas/audio-graph files change as part of this refactor.

## Validation

Parent canopy workspace:

```bash
moon check
moon test lang/lambda/proj lang/lambda/scope lang/lambda/edits editor protocol examples/ideal/main
moon test
moon fmt
moon info
```

Loom submodule / lambda example:

```bash
cd loom/examples/lambda && moon check && moon test && moon fmt && moon info
```

Web / Structure mode:

```bash
moon build --target js
cd examples/ideal/web && npm run build
cd examples/ideal/web && npm run test:e2e -- drag-drop.spec.ts
```

If JS export paths are affected, also run the repository's JS packaging/build script used by CI:

```bash
scripts/build-js.sh
```

Review API and generated-file impact:

```bash
git diff --stat
git diff -- '*pkg.generated.mbti'
git status --short
```

## Risks

- **Submodule workflow:** adding a Term variant touches `loom/examples/lambda`, which is in the `loom` submodule. The submodule branch/commit must be pushed before the parent PR references it.
- **Term variant blast radius:** `Term` is the lambda AST's structural source of truth. Every pattern match, `children_of`, `rebuild_from`, pretty/replay, `Renderable`, evaluator, resolver, and tests must handle `LetDef` deliberately.
- **FlatProj compatibility:** callers read tuple fields directly. Keeping the tuple shape while changing the fourth field from synthetic id to real LetDef id minimizes API churn, but the semantic change must be documented in tests and `.mbti` review.
- **Tree-shape assumptions:** `populate_token_spans`, `projection_memo` patch paths, protocol conversion, PM reconciliation, and tests currently assume the first N Module children are init expressions.
- **Drag/drop semantics ambiguity:** generic `Drop` currently works by source/target ranges. With LetDef ranges it may move whole binding text, but scoping guards from `MoveBindingUp/Down` may need to be reused to avoid invalid binding reorders.
- **SourceMap token-span migration:** inline name editing needs token spans on LetDef nodes. Keeping Module `name:<i>` spans temporarily reduces frontend compatibility risk but must not obscure the new canonical role.
- **Performance:** adding one node per binding increases tree/view node counts and may affect `TreeEditorState::refresh` and PM reconciliation benchmarks. Run the existing tree refresh/view updater benchmarks if large-binding docs regress.

## Notes

- Existing APIs inspected before planning:
  - `@scope.binder_span` and `@scope.go_to_definition` solve source-location use cases.
  - `FlatProj` is the current per-binding state carrier.
  - `ProjNode::branch` / `ProjNode::leaf` are sufficient construction primitives; no core projection helper is missing.
  - `find_binding_for_init` is a workaround for the missing binding row and should shrink or disappear.
- Do not conflate this with #129 query/scope-resolution unification; `@scope` binding-index work already shipped the relevant pieces.
- Do not reopen query-side indexing from `docs/TODO.md:447`; that is a separate performance-gated follow-up.
