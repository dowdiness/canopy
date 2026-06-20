# Markdown Block Move Provenance Spike

**Status:** backlog

## Why

Markdown reorder recovery is required for the future block-based editor UI: when a
user moves a visible block, the block's editing identity should move with it.
The SDEG reorder provenance investigation showed that current Markdown edits do
not express that intent. Pure source reorder and replacement-style `CommitEdit`
sequences are position-stable, so a Phase 1 side table must not infer semantic
move identity without explicit provenance.

This spike designs and validates the smallest explicit provenance path for a
future Markdown/block move command.

## Scope

In:
- `lang/markdown/edits/`
- `lang/markdown/companion/`
- `lang/markdown/proj/`
- `lang/runtime/` if the generic edit bridge needs a hint-bearing return shape
- `core/` only if existing `IdentityTransform::Move` / `reconcile_hinted` cannot
  express the needed invariant
- tests proving identity behavior for explicit block moves
- documentation updates that connect this spike to block-editor drag/drop plans

Out:
- polished drag-and-drop UI
- public `EntityId` or `sdeg-*` packages
- durable reload/peer-stable identities
- CRDT schema changes unless the spike proves they are unavoidable
- side-table-only semantic reorder guessing
- broad rewrite of Markdown projection reconciliation

## Current State

- `docs/plans/2026-06-19-sdeg-reorder-provenance-investigation.md` concludes
  reorder recovery is not in SDEG Phase 1 and names this as future work.
- `lang/markdown/edits/markdown_edit_op.mbt` has no move/reorder operation.
- `lang/runtime/language_spec.mbt` lowers structural edits to span edits and
  calls `SyncEditor::apply_span_edits` without identity hints.
- `editor/sync_editor.mbt` can carry a single `IdentityTransform` hint through
  `apply_span_edits`, but Markdown does not use that channel.
- `core/identity_transform.mbt` already has `IdentityTransform::Move`, while
  `core/reconcile.mbt` currently treats `Move` as editor-owned and freshens the
  node at the old position unless a language-specific reconciler consumes it.
- `docs/plans/2026-03-30-editor-drag-drop-foundation.md` tracks the broader
  block-editor drag/drop foundation; this spike is the identity-provenance slice.

## Desired State

The spike answers, with code/tests or a written rejection:

- What is the minimal Markdown/block move operation shape?
- How does that operation lower to text edits while preserving source truth,
  undo, and parser/reconcile flow?
- How is explicit move provenance delivered to projection reconciliation?
- Can moved block identity follow the moved heading/block only when explicit
  provenance is present?
- Do ordinary replacement edits and pure source reorder keep same-node priority
  / documented limitation behavior?

## Steps

1. Define candidate move operations, e.g. `MoveBlockBefore(source~, target~)` /
   `MoveBlockAfter(source~, target~)`, including legality rules for self-target,
   missing nodes, and same-position no-ops.
2. Decide how Markdown should pass identity hints through the existing generic
   companion runtime: extend the edit result shape to include an optional
   `IdentityTransform`, add a Markdown-specific bridge, or document why the
   current hint channel is insufficient.
3. Prototype the smallest source-text lowering for sibling block moves. Keep the
   source/text patch as the document mutation; do not mutate side-table metadata
   as source of truth.
4. Prototype or design the reconciliation owner. Prefer a Markdown-specific
   hinted reconciler if generic `reconcile_hinted` cannot safely preserve move
   identity without weakening ordinary same-node priority. Prefer a
   test-only/private prototype; stop before public API changes unless the
   prototype proves that a public shape is necessary.
5. Add white-box tests comparing:
   - pure source reorder without provenance remains position-stable;
   - replacement-style edit-path swap remains replacement-by-position;
   - explicit block move provenance preserves moved block identity;
   - ordinary non-reorder edits still preserve same-node identity by position.
6. Update the broader drag/drop foundation plan or TODO item with the chosen
   provenance contract and any blockers.

## Acceptance Criteria

- [ ] A concrete Markdown/block move operation shape is accepted or rejected with
      reasons.
- [ ] The provenance delivery path is named: existing `IdentityTransform::Move`,
      an extended hint channel, a Markdown-specific bridge, or a documented
      blocker.
- [ ] Tests or a written proof-of-blocker show that explicit provenance is the
      only case where reorder identity can override positional same-node
      evidence.
- [ ] Pure source reorder remains documented and tested as a limitation when no
      explicit provenance is present.
- [ ] The future block-editor drag/drop plan links to the accepted provenance
      contract.
- [ ] No public SDEG/entity ID API is introduced.

## Validation

```bash
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test -p dowdiness/canopy/lang/markdown/proj
NEW_MOON_MOD=0 moon test -p dowdiness/canopy/lang/markdown/companion
NEW_MOON_MOD=0 moon fmt && NEW_MOON_MOD=0 moon info
git diff -- '*.mbti'
```

If the spike changes `core/`, `editor/`, or `lang/runtime/`, also run:

```bash
NEW_MOON_MOD=0 moon test
```

## Risks

- The generic `IdentityTransform::Move` vocabulary may not be sufficient for a
  source-text block move without language-specific matching.
- A text patch can represent a move as delete+insert; provenance must be carried
  separately or identity will remain position-stable.
- Generic reconciliation changes could weaken same-node priority for ordinary
  edits; prefer language-owned logic unless the invariant is proven generic.
- This may overlap the broader block-editor drag/drop foundation; keep this
  spike focused on identity provenance, not UI.

## Notes

- Follow-up from `docs/plans/2026-06-19-sdeg-reorder-provenance-investigation.md`.
- Related broader foundation: `docs/plans/2026-03-30-editor-drag-drop-foundation.md`.
