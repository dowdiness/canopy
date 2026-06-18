# Analysis Query Layer Phase 2 — Projection Aggregator

## Why

Phase 1 proved that external structural-search results can enter Canopy as
snapshot-bound analysis facts and render through existing decorations. The
lambda editor now has two separate projection paths for related derived data:

- host-provided ast-grep pattern facts stored on `LambdaCompanion` refs;
- in-process semantic, evaluation, and diagnostic data assembled directly in
  language capability closures and FFI functions.

Phase 2 should introduce a small aggregation seam so these in-process analyses
are routed through one projection layer before Canopy commits to broader
provider abstractions or `moon ide` integration.

## Scope

In:

- `docs/design/analysis-query-layer.md` — source design and phase boundaries.
- `analysis/` — shared rendering/projection helpers for analysis facts.
- `lib/analysis/` — shared snapshot/fact primitives, only if a minimal new fact
  wrapper is required.
- `lang/lambda/companion/lambda_editor.mbt` — first consumer and prototype seam.
- `lang/lambda/semantic/semantic_projection.mbt` — existing semantic projection
  input, not a rewrite target unless an adapter boundary is needed.
- `ffi/lambda/{analysis,view,diagnostics}.mbt` — FFI surfaces affected by the
  lambda prototype.
- tests in `analysis/`, `lib/analysis/`, `lang/lambda/companion/`, and
  `ffi/lambda/` as needed.

Out:

- `moon ide` provider integration. That is Phase 3.
- rewrite, rename, or edit-plan previews. That is Phase 4.
- new public protocol variants or exposing raw analysis facts to TypeScript.
- broad cross-language migration beyond lambda.
- node-id anchoring as a requirement. Source ranges remain authoritative.
- persistent semantic database or workspace indexing.

## Current State

- Phase 1 host integration shipped in PR #704.
- `lib/analysis/source_snapshot.mbt` defines `SourceSnapshot` and stale-result
  matching by document id, version, hash, and UTF-16 length.
- `lib/analysis/pattern_match_fact.mbt` defines `PatternMatchFact` with
  snapshot-bound UTF-16 ranges.
- `analysis/adapter.mbt` converts ast-grep byte offsets to UTF-16 via
  `from_ast_grep_matches`; this remains the only ast-grep byte-conversion
  boundary.
- `analysis/render.mbt` projects pattern facts to existing
  `@protocol.Decoration` values and match-list entries.
- `lang/lambda/companion/lambda_editor.mbt` currently merges semantic
  decorations and ast-grep decorations in the `get_decorations` capability
  closure. It separately merges evaluation and semantic annotations in
  `get_annotations`.
- `ffi/lambda/diagnostics.mbt` assembles parse/type/eval diagnostics separately
  from the decoration/annotation path.
- `editor/capabilities.mbt` and `editor/view_updater.mbt` already provide the
  public projection seam: annotations, decorations, diagnostics, and view
  patches.

## Desired State

A narrow lambda-first aggregator owns the composition of analysis projections
without changing the public protocol:

- structural matches, semantic decorations, semantic annotations, and
  evaluation annotations have an explicit local composition boundary;
- diagnostics are either routed through that boundary or explicitly deferred
  with rationale;
- snapshot-bound external facts are stale-checked before projection;
- in-process facts remain derived from existing memo/capability inputs and do
  not require artificial provider snapshots;
- output continues through existing protocol surfaces (`SetDecorations`,
  diagnostics JSON, annotations), not a new fact protocol;
- the design leaves room for Phase 3 `moon ide` facts without prematurely
  designing a full provider abstraction.

## Steps

1. **Name the seam.** Decide whether Phase 2 needs a concrete type such as
   `AnalysisProjection` / `AnalysisStore` or a smaller set of helper functions
   under `analysis/`. Prefer the smallest type that removes ad-hoc composition
   from lambda capability closures.
2. **Model only projected outputs first.** Start with decorations and
   annotations; keep diagnostics separate unless a minimal adapter is obvious.
3. **Move pattern fact refs behind the seam.** Replace direct
   `pattern_facts_ref` / `pattern_snapshot_ref` access in capability closures
   with a small owned object or helper API.
4. **Route semantic and eval projections through the same seam.** Reuse
   existing `build_semantic_projection`, `build_eval_annotations`, and
   `facts_to_decorations`; do not rewrite semantic analysis.
5. **Add tests for composition behavior.** Pin that semantic decorations and
   ast-grep decorations are both present, stale external facts are dropped, and
   missing external patches do not clear in-process decorations.
6. **Document follow-ups.** If diagnostics need a larger representation, record
   the decision and keep them out of the first Phase 2 PR.

## Acceptance Criteria

- [ ] Lambda analysis projection composition has one named seam rather than
      duplicated ad-hoc merging in capability closures.
- [ ] Existing semantic/eval decorations and annotations behave as before.
- [ ] Existing ast-grep decorations remain snapshot-bound and stale-safe.
- [ ] No new public protocol variant is introduced.
- [ ] Tests cover combined semantic + pattern decorations and stale external
      facts.
- [ ] `docs/design/analysis-query-layer.md` reflects the implemented Phase 2
      slice and any deferred diagnostics work.

## Validation

```bash
moon fmt analysis lib/analysis lang/lambda/companion ffi/lambda
moon info analysis lib/analysis lang/lambda/companion ffi/lambda
moon check analysis lib/analysis lang/lambda/companion ffi/lambda
moon test analysis lib/analysis lang/lambda/companion ffi/lambda
cd examples/web && npx tsc --noEmit
cd examples/web && npm run build
```

If public interfaces change, inspect generated `.mbti` diffs for unintended
API widening.

## Risks

- Over-generalizing the fact model before Phase 3 provider needs are known.
- Accidentally making in-process semantic/eval data snapshot-bound in a way that
  does not match their memo lifetimes.
- Losing incremental decoration behavior by forcing full projections on every
  view patch.
- Expanding `LambdaCompanion` public API unnecessarily.

## Notes

- Keep the Existing API First rule active during implementation. Candidate APIs
  to reuse include `@analysis.facts_to_decorations`,
  `@analysis.facts_to_match_list`,
  `@lambda_semantic.build_semantic_projection`, `build_eval_annotations`,
  `@editor.LanguageCapabilities`, and `@editor.compute_view_patches`.
- Phase 2 should make Phase 3 easier by clarifying the projection boundary, not
  by designing the `moon ide` provider itself.
