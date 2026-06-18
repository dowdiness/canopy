# SDEG Phase 0 Markdown Heading Spike

## Why

Canopy needs a stable editing-entity layer, but the repository already has
projection identity, source maps, edit lowering, and incremental projection
memos. Before introducing a new Stable Document Entity Graph (SDEG) core or a
new `EntityId`, validate whether the existing identity pipeline can support the
first SDEG use case as a side-table layer.

This spike tests Markdown headings as stable editing entities. The goal is to
learn where existing `NodeId`/projection identity is sufficient, where it fails,
and what evidence would make failures explainable.

## Scope

In:
- `docs/design/stable-document-entity-graph.md`
- `core/` projection identity helpers, only if a small test-only observation hook
  is needed
- `lang/markdown/proj/` heading projection and token span behavior
- `lang/markdown/edits/` existing edit path, if needed for rename/move tests
- Markdown-focused tests under the owning Markdown packages

Out:
- creating a public `sdeg-*` package family
- introducing a distinct public `EntityId`
- changing event-graph-walker APIs
- persisting semantic entities into CRDT state
- adding a general graph store or ECS layer
- changing frontend protocol types

## Current State

- `core/` owns `NodeId`, `ProjNode`, `SourceMap`, generic reconciliation, and
  structural identity hints.
- `SourceMap` maps projection nodes to UTF-16 source ranges and token spans.
- `build_projection_memos` builds the projection tree, registry, and source map
  as `incr` derived values.
- `IdentityTransform` records editor-owned structural hints for reconciliation.
- Loom's `ProjectionIdentityTracker` preserves stable projection leaves across
  malformed intermediate input using source ranges and domain keys.
- `LanguageSpec::apply_edit` lowers language edit operations to `SpanEdit`s and
  applies them through the editor path.
- The design direction is recorded in
  `docs/design/stable-document-entity-graph.md`: Phase 0 should treat existing
  projection identity as the first stable entity substrate.

Constraints:
- Public source ranges are UTF-16 code-unit offsets. Do not introduce byte-range
  anchors in this spike.
- Do not bypass existing Markdown edit lowering or `SyncEditor` text mutation.
- Treat code and generated `.mbti` files as authoritative when docs drift.

## Desired State

A narrow Markdown heading experiment answers these questions:

1. Can a Markdown heading be treated as a session-local stable entity using the
   existing `NodeId`?
2. Do heading rename, reorder, deletion/restoration, duplicates, malformed input,
   and paste/formatter-like rewrites preserve or explain identity well enough?
3. Can `SourceMap` provide the current heading anchor and relevant token spans
   without new range primitives?
4. Can identity outcomes be reported as evidence side tables without changing the
   document source of truth?
5. Is a distinct SDEG core justified, or should the next step extend existing
   projection identity and side-table APIs?

## Proposed Observation Model

Keep this spike internal or test-only. Do not publish the model as stable API.

A minimal observation record may contain:

- heading `NodeId`
- heading level and normalized heading text/key
- current UTF-16 source range from `SourceMap`
- optional token span for the marker/text if already available or easy to record
- parent/section context if already derivable from the projection tree
- identity outcome: preserved, fresh, missing, ambiguous, or retired
- evidence: same range, overlapping range, same level, same text/key, same
  relative order, same parent context, or fallback/fresh allocation

This can begin as assertions in tests rather than a reusable library type.

## Steps

1. **Inventory Markdown heading projection**
   - Locate the Markdown projection shape for headings.
   - Confirm which `ProjNode` corresponds to a heading-level editing entity.
   - Confirm whether token spans are currently populated for heading marker/text.

2. **Add test-only heading observation helpers**
   - Walk a Markdown `ProjNode` tree and collect heading observations keyed by
     `NodeId`.
   - Read current anchors from `SourceMap`.
   - Keep helpers package-private or white-box-test-local unless reuse is proven.

3. **Pin baseline identity behavior**
   - Write tests for:
     - rename: `# A` → `# A2`
     - reorder: `# A\n# B` → `# B\n# A`
     - duplicate headings: `# A\n# A`
     - delete and restore
     - malformed/intermediate input followed by recovery
     - large paste or formatter-like rewrite
   - For each case, assert either preservation or an explicit, documented fresh /
     ambiguous outcome.

4. **Record evidence for failures**
   - For cases where `NodeId` is not preserved but preservation seems desirable,
     record the evidence that would have allowed a better match.
   - Classify whether the fix belongs in:
     - Markdown edit hints,
     - projection reconciliation,
     - `ProjectionIdentityTracker`-style item realignment,
     - a side-table mapping from semantic entity IDs to current `NodeId`s,
     - or a future SDEG core.

5. **Validate edit-path compatibility**
   - If a rename/edit operation is included, route it through existing Markdown
     edit lowering and editor application.
   - Confirm the spike does not mutate the observation side tables as the source
     of truth.

6. **Write the spike conclusion**
   - Update this plan or add a short result note summarizing:
     - what existing identity already covers,
     - which cases fail,
     - which extension point should be tried next,
     - whether a distinct `EntityId` is justified yet.

## Spike Results

Initial white-box tests in `lang/markdown/proj/` show that existing projection
identity is a viable Phase 0 substrate for Markdown headings, with clear limits.

Observed:
- `SourceMap` can anchor heading entity observations with the full heading range,
  the marker token span, and the text token span.
- A heading rename preserves the session-local `NodeId`.
- Duplicate headings remain distinguishable by `NodeId` and source range.
- Inline malformed-to-recovered heading content preserves the heading `NodeId`.
- Whitespace-only / formatter-like rewrites around headings preserve heading
  `NodeId`s.

Limitations:
- Reordering sibling headings is currently position-stable, not
  semantic-stable: identity stays with the projection position instead of
  following the heading text/key.
- Delete followed by restore does not recover the retired heading identity;
  there is no tombstone or last-good semantic side table yet.

Decision:
- Continue with `NodeId` side tables for the next slice.
- Do not introduce a public `EntityId` or `sdeg-*` package yet.
- Test-only matching evidence can already detect semantic reorder mismatches and
  delete/restore recovery candidates without changing document behavior.
- Next target: decide whether that evidence should feed improved Markdown edit
  hints, `ProjectionIdentityTracker`-style item realignment, or a semantic
  side-table mapping.

## Acceptance Criteria

- [x] Markdown heading observations can be collected from existing projection and
      source-map data.
- [x] Tests cover rename, reorder, duplicate headings, delete/restore,
      malformed recovery, and paste/formatter-like rewrites.
- [x] Each test has an explicit identity expectation: preserve, fresh,
      ambiguous, or known limitation.
- [x] Any identity failure includes recorded evidence and a proposed owner for a
      future fix.
- [x] No public `EntityId` or `sdeg-*` package is introduced.
- [x] Existing Markdown edit application remains on the language/edit/editor path.
- [x] The result is summarized against the decision gates in
      `docs/design/stable-document-entity-graph.md`.

## Validation

From the workspace root:

```bash
moon check
moon test
moon fmt && moon info
```

For the Markdown slice, also run the relevant Markdown packages once the touched
files are known. Prefer package-local validation first, then the workspace root
commands above.

After `moon info`, inspect generated interface drift:

```bash
git diff -- '*.mbti'
```

Expected result for a test-only/internal spike: no unintended public interface
expansion.

## Risks

- Existing `NodeId` may be stable enough for simple edits but not for reorder or
  duplicate headings. That is useful evidence, not failure of the spike.
- Adding reusable abstractions too early could create a second identity system.
  Keep the first slice observational.
- Markdown projection shape may not expose heading entities at exactly the level
  desired by SDEG. If so, record whether the projection shape or the stable
  entity layer should adapt.
- Range unit mistakes are easy because positions are plain integers in several
  APIs. Keep all spike anchors in UTF-16 source coordinates.
- Malformed-input recovery may belong in Loom's projection identity tracker, not
  Canopy core. Do not duplicate that mechanism without a concrete gap.

## Notes

Related docs:

- `docs/design/stable-document-entity-graph.md`
- `docs/architecture/responsibility-map.md`
- `docs/decisions/2026-06-01-identity-and-reuse-mechanisms.md`
- `docs/decisions/2026-06-13-range-span-unit-boundaries.md`

Recommended next decision after the spike:

- If existing projection identity is sufficient, continue with side tables over
  `NodeId`.
- If specific matching cases fail, extend hints or item realignment first.
- If reload/peer durability or graph relations become mandatory, plan a separate
  SDEG core with explicit stability scope and adapters.
