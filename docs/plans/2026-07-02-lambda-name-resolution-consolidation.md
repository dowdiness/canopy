# Lambda Name Resolution Consolidation

## Why

Lambda name resolution is mostly centralized in `lang/lambda/scope`, but several
call sites still compute name visibility or free-name sets with local walks.
Those local walks can silently drift from the scope graph when binding rules
change, especially around nested modules, sequential `let` visibility, lambda
parameter shadowing, and unresolved names.

GitHub issue #129 is the canonical tracker for this consolidation. Its original
inventory is partly stale: `resolve_binder` has already been retired, and
`examples/ideal/main/scope_annotation.mbt` now consumes `@scope`. The remaining
work is narrower but still real: retire the edit-layer free-variable resolver
and the edit-layer module-end resolver, and keep alpha lowering and diagnostics
explicitly pinned to `@scope`.

## Scope

In:

- `lang/lambda/scope/builder.mbt`
- `lang/lambda/scope/query.mbt`
- `lang/lambda/scope/failures.mbt`
- `lang/lambda/scope/*_wbtest.mbt`
- `lang/lambda/edits/free_vars.mbt`
- `lang/lambda/edits/scope.mbt`
- `lang/lambda/edits/text_edit_binding.mbt`
- `lang/lambda/edits/text_edit_refactor.mbt`
- `lang/lambda/edits/text_edit_rename.mbt`
- `lang/lambda/edits/*_wbtest.mbt`
- `lang/lambda/alpha/lower.mbt`
- `lang/lambda/alpha/*_wbtest.mbt`
- `lang/lambda/semantic/semantic_projection.mbt`
- `lang/lambda/semantic/*_test.mbt`

Out:

- Language-agnostic scope graph extraction (#568).
- Sharing alpha substitution with the egraph adapter (#712).
- Typecheck/eval/semantic environment rewrites beyond documenting follow-ups.
- Changing Lambda binding semantics.
- Replacing user-visible rename behavior with automatic alpha-renaming.
- Implementing source changes in this plan-authoring pass.

## Current State

- `lang/lambda/scope/builder.mbt:90-188` records scope membership and per-module
  sequential cutoffs for root and nested modules. `builder.mbt:223-276` resolves
  `Var` and `Unbound` references once into `Ref.resolution`, including
  `visited_scopes` witnesses.
- `lang/lambda/scope/query.mbt:3-47` exposes `declaration` and
  `declaration_for_name_at`; `query.mbt:69-75` exposes identity-based
  `references`; `query.mbt:90-145` exposes `binder_span` and
  `go_to_definition`; `query.mbt:153-170` exposes `enclosing_env`.
- `lang/lambda/scope/failures.mbt:44-56` already derives unresolved/free-name
  failures from `ScopeGraph` refs. This is the direction requested by #617 and
  its umbrella #616.
- `lang/lambda/semantic/semantic_projection.mbt:58-76` already builds a
  `ScopeGraph` and uses `@lambda_scope.failures` for diagnostics, but
  `semantic_projection.mbt:80-215` still performs a separate env walk for
  semantic binder/ref annotations. That walk is diagnostic-adjacent metadata,
  not the edit-capture resolver targeted by this plan.
- `lang/lambda/alpha/lower.mbt:2-7` already takes a `@scope.ScopeGraph`;
  `lower.mbt:45-61` lowers references through `@scope.declaration`. The old
  hypothesis that alpha might need a separate low-level resolver is stale.
- `lang/lambda/edits/free_vars.mbt:4-31` is still a duplicate name-set resolver.
  It walks `@ast.Term`, tracks bound names, and implements sequential module
  scoping locally. Its callers guard extract/inline/move/rename behavior in
  `text_edit_refactor.mbt`, `text_edit_binding.mbt`, and
  `text_edit_rename.mbt`.
- `lang/lambda/edits/scope.mbt:208-262` still contains a local name resolver:
  `declaration_id_for_name_from_scope` and
  `declaration_id_for_name_at_module_end`. The per-node path at
  `scope.mbt:241-247` delegates to `@scope.declaration_for_name_at`, but the
  module-root-end path recomputes visibility from a root scope and
  `DefinitionIndex.length()`. This is the concrete drift class described by
  #652, even though #652's symbol name is stale in the current tree.
- `lang/lambda/edits/scope.mbt:79-97` contains `collect_var_usages`, a subtree
  traversal used to locate matching references inside candidate edit regions.
  It is not itself a resolver, but migrations should either keep it as a
  structural collector or replace it with a scope query that preserves the same
  subtree filtering.
- `examples/ideal/main/scope_annotation.mbt:1-12` now documents `@scope` as the
  single source of truth, and `scope_annotation.mbt:65-146` builds annotations
  from `@scope.references` rather than reimplementing `walk_scope`. This site is
  verified out of scope for the consolidation.
- Dependency direction is already favorable: `lang/lambda/edits/moon.pkg`,
  `lang/lambda/alpha/moon.pkg`, `lang/lambda/semantic/moon.pkg`, and
  `examples/ideal/main/moon.pkg` all import `lang/lambda/scope`. No new
  `scope -> edits`, `scope -> alpha`, or `scope -> semantic` dependency should
  be introduced.
- Incremental projection prior art exists in
  `lang/lambda/edits/scope_memo_stack_differential_wbtest.mbt`, which compares
  scope resolution from a live memo stack with a fresh rebuild. Use this pattern
  for behavior pinning before replacing duplicate resolvers.

Verified resolution-site classification:

| Site | Current behavior | Scope |
|---|---|---|
| `lang/lambda/scope/builder.mbt:223-276` | Canonical resolver that produces `Ref.resolution`. | In, source of truth. |
| `lang/lambda/scope/query.mbt:17-47` | Public per-node name query over graph cutoffs. | In, reuse/extend. |
| `lang/lambda/scope/failures.mbt:44-56` | Free/unresolved refs derived from graph facts. | In, reuse for tests and docs. |
| `lang/lambda/edits/free_vars.mbt:4-31` | Duplicate free-name resolver over `Term`. | In, replace or wrap with graph-backed API. |
| `lang/lambda/edits/scope.mbt:208-262` | Duplicate module-end name resolver. | In, replace with graph-owned module-end query. |
| `lang/lambda/alpha/lower.mbt:45-61` | Already queries `@scope.declaration`. | In only for regression tests/documentation. |
| `lang/lambda/semantic/semantic_projection.mbt:58-76` | Diagnostics already use `@scope.failures`. | Out for this plan, keep as proof of direction. |
| `lang/lambda/semantic/semantic_projection.mbt:80-215` | Separate env walk for annotations/decorations. | Follow-up only unless it starts changing resolution semantics. |
| `examples/ideal/main/scope_annotation.mbt:65-146` | Scope-map overlay consumes `@scope.references`. | Out, already migrated. |
| `lang/lambda/alpha_egraph_adapter/optimize.mbt:41-53` | Receives `ScopeGraph` and delegates lowering to alpha. | Out, already uses the alpha/scope boundary. |

Known constraints and invariants:

- Pin behavior before replacement. Differential tests must prove the old
  duplicate computations and the graph-backed replacement agree for shadowing,
  nested blocks/modules, lambda params versus let bindings, sequential let
  initializers, and unbound names.
- Edit capture guards are deliberately conservative. Over-rejection is
  acceptable; mis-rename, mis-inline, or semantics-changing movement is not.
  Consolidation must not weaken this soundness invariant.
- Scope graph construction must come from an already-current projection context
  whenever one exists. Edit call sites already build from `EditContext.registry`
  and `EditContext.source_map`; semantic diagnostics currently rebuild from the
  root with a documented benchmark-gated incremental follow-up.
- `DeclId`, `ScopeId`, and `RefId` are graph-local. Tests that compare fresh and
  memoized graphs must normalize by source range/name or binder span, following
  `scope_resolution_compare_wbtest.mbt`.

## Desired State

- `lang/lambda/scope` is the single authority for Lambda binding resolution:
  reference-to-declaration, name-at-node, name-at-module-end, free/unresolved
  references, binder spans, and reference lists.
- Edit guards still operate conservatively, but their free-name and target-site
  resolution inputs come from `ScopeGraph` facts instead of local name walks.
- Alpha lowering remains explicitly graph-backed and has regression coverage
  that blocks accidental reintroduction of string-only resolution.
- The semantic diagnostic path remains graph-backed through `failures`.
- Any remaining local tree traversals in `edits/` are structural collectors or
  subtree filters, not independent binding-resolution algorithms.
- The consolidation is staged so each PR can land independently with clear
  validation and without broad source churn.

## Steps

1. **Pin current agreement before changing behavior.**
   Add differential tests in `lang/lambda/edits/` that build one projection,
   one `ScopeGraph`, and compare current edit-layer `free_vars` /
   module-end resolution with graph-backed oracle helpers. Cover:
   shadowed module defs, nested block defs, lambda params shadowing module defs,
   module init sequential visibility, block-body visibility, free names,
   `Unbound`, inline/extract/move guard fixtures, and same-name root/block
   bindings. Reuse the source-range normalization pattern from
   `scope_resolution_compare_wbtest.mbt` and the memo/fresh pattern from
   `scope_memo_stack_differential_wbtest.mbt`. Expected break point: the graph
   may intentionally classify `Unbound` as an unresolved ref while `free_vars`
   currently returns empty for `Unbound`; record that as explicit behavior
   before choosing whether edit guards should keep or change it.

2. **Add graph-owned query surface for edit guard needs.**
   Extend `lang/lambda/scope/query.mbt` with the smallest reusable queries
   needed by edits, rather than exposing more graph internals. Candidate
   responsibilities:
   - free/unresolved names inside a subtree, optionally excluding refs whose
     resolved declaration is also inside that subtree;
   - declaration id/name lookup at a module's trailing body point, backed by
     builder-owned cutoff state rather than a root-scope recomputation;
   - reference lookup by name within a subtree when current guards need to know
     whether a same-name use would be captured.

   Preserve `DeclId` graph-local semantics and return `Decl`/`DeclId` only for
   the same graph instance. Do not move edit-specific policy such as "allow a
   move if a free ref would become bound" into `scope`; keep policy in edits and
   expose facts from scope. This is the natural place to close #652.

3. **Replace `free_vars` consumers in extract and inline.**
   Migrate `text_edit_refactor.mbt` first because it already builds a graph and
   already routes target-site lookup through `declaration_id_for_name_at_node`
   or module-end lookup. Replace local `free_vars` calls with graph-backed
   free-name queries over the selected expression or binding init. Keep
   `free_names_would_rebind` and `free_name_would_rebind_to` policy local unless
   a reusable fact boundary is obvious. Compilation break point: graph-backed
   queries need a `ProjNode` subtree and the same graph that was built from
   `ctx.registry`; update helper signatures before removing the old calls.
   Validation for this step: targeted edit wbtests for extract/inline plus the
   new differential tests from step 1.

4. **Replace `free_vars` consumers in binding moves.**
   Migrate `text_edit_binding.mbt` move-up/down guards after extract/inline.
   These guards intentionally distinguish "reference becomes free" from
   "currently free reference becomes bound". Preserve that policy by combining
   graph-backed free-name facts with the existing `init_ref_resolves` behavior,
   or by replacing `init_ref_resolves` with a graph-backed equivalent that still
   treats same-subtree declarations as non-capturing. Compilation break point:
   both move directions share mirrored logic; update one reusable helper first,
   then both callers. Validation: existing binding move tests, block-local move
   adversarial tests, and any new cases from step 1.

5. **Resolve the module-end drift path.**
   Replace `lang/lambda/edits/scope.mbt:208-262` with the graph-owned
   module-end query from step 2. If scope currently lacks an explicit root-end
   cutoff, add the builder field or module-end pseudo-node described by #652,
   then have both `scope/query` and edit guards read that field. Avoid
   recomputing the module-end cutoff from `DefinitionIndex.length()` or by
   folding declarations. Validation: scope tests for root binder visible,
   block-local binder not visible at root end, total over synthetic `Unit`, plus
   extract-to-let root/body fixtures.

6. **Delete or demote the duplicate edit resolver APIs.**
   Once all production callers are gone, remove `free_vars` from the public
   `lang/lambda/edits` surface or keep only a test-local compatibility oracle
   behind wbtests until the differential tests have served their migration
   purpose. Remove `declaration_id_for_name_from_scope` entirely if the
   module-end query has moved to `scope`. Run `moon info` and review
   `lang/lambda/edits/pkg.generated.mbti` so the public API shrink is
   intentional.

7. **Re-assert alpha and semantic boundaries.**
   Keep `alpha/lower.mbt` as-is unless the new scope query names make a small
   cleanup useful. Add or update tests that say lowering uses
   `@scope.declaration` for nested module and shadowing cases. Keep semantic
   free-variable diagnostics grounded on `@scope.failures`; do not expand this
   PR series into semantic annotation/decorations unless a test shows they
   materially diverge from `ScopeGraph`.

8. **Document remaining follow-ups without expanding scope.**
   In the closing PR, link #129, #616/#617, #652, and this plan. Note #712 as
   adjacent alpha substitution sharing, and #568 as explicitly gated on a second
   language consumer. If the semantic annotation env walk or type/eval layers
   are found to duplicate resolution in a user-visible way during migration,
   file a follow-up rather than adding it to this consolidation.

## Acceptance Criteria

- [ ] Differential tests pin agreement between old duplicate edit computations
      and graph-backed facts before production migration.
- [ ] `lang/lambda/edits/free_vars.mbt` is no longer used by production edit
      guards, or it is removed entirely from the package surface.
- [ ] `declaration_id_for_name_from_scope` and
      `declaration_id_for_name_at_module_end` no longer recompute binding
      visibility outside `lang/lambda/scope`.
- [ ] Module-end lookup reads builder-owned scope/cutoff state, closing the
      drift class in #652.
- [ ] Extract, inline, rename, and binding move guards remain conservative:
      every previously rejected unsafe capture/rebind fixture is still rejected.
- [ ] `alpha/lower` continues to lower references through `@scope.declaration`,
      with shadowing and sequential module fixtures.
- [ ] Semantic free-variable diagnostics continue to source unresolved refs
      from `@scope.failures`.
- [ ] `moon info` public API diffs are reviewed, especially
      `lang/lambda/edits/pkg.generated.mbti` and `lang/lambda/scope/pkg.generated.mbti`.

## Validation

Per PR:

```bash
moon check
moon test lang/lambda/scope
moon test lang/lambda/edits
moon test lang/lambda/alpha
moon test lang/lambda/semantic
```

Before the final consolidation PR:

```bash
moon test
moon info
git diff -- lang/lambda/edits/pkg.generated.mbti lang/lambda/scope/pkg.generated.mbti
```

If a step touches JS-facing editor behavior or examples:

```bash
moon build --target js
cd examples/web && npm run test:browser
```

## Risks

- **Conservative guard regression:** graph-backed free-name sets can be more
  precise than the old name-only walk. Precision is good only if it does not
  permit a semantics-changing edit. When in doubt, preserve over-rejection.
- **Performance regression:** rebuilding a scope graph per guard would be wrong
  in hot paths. Reuse the graph already built from `EditContext.registry` and
  `EditContext.source_map`; do not introduce fresh graph builds inside inner
  helpers.
- **Graph-local identity leakage:** `DeclId` and `ScopeId` are valid only within
  one graph. Cross-pipeline tests must normalize by source range/name/binder
  span, not raw graph ids.
- **Issue drift:** #129 and #652 name symbols or locations that have changed.
  Treat their problem statements as architectural intent, but verify current
  code before each PR.

## Notes

- Canonical issue: #129 "Unify scope resolution: walk_scope, resolve_binder,
  free_vars into single compiler phase".
- Related: #616 and #617 for witnessed free-variable diagnostics on the scope
  graph; #652 for module-end cutoff drift; #712 for alpha substitution sharing
  follow-up; #568 for deferred language-agnostic scope graph extraction.
- Prior implementation context:
  `docs/superpowers/plans/2026-05-30-retire-resolve-binder.md` records the
  already-shipped `resolve_binder` retirement, and
  `docs/decisions/2026-06-15-lambda-alpha-safe-core-boundary.md` records the
  `ScopeGraph` to alpha-safe core boundary.
- Suggested `docs/TODO.md` location: section 21, "Analysis Query Layer", because
  the work is about consolidating Lambda analysis facts and query consumers.

Ready-to-paste TODO item:

```md
- [ ] Consolidate Lambda name resolution on `lang/lambda/scope` (#129).
  Why: edit free-variable guards and module-end lookup still carry local name-resolution walks that can drift from the canonical scope graph.
  Plan: `docs/plans/2026-07-02-lambda-name-resolution-consolidation.md`
  Exit: production edit guards, alpha lowering, and free-variable diagnostics all read scope-graph facts; duplicate edit-layer resolvers are removed or test-only; #652's module-end cutoff drift is closed.
```
