# SDEG Reorder Provenance Investigation

**Status:** done — concluded that Markdown reorder recovery is future block-move
work, not SDEG Phase 1 side-table work.

## Why

SDEG Phase 0 showed that pure Markdown sibling reorder is position-stable rather
than semantic-stable: the old projection `NodeId`s remain present, but they are
attached by position. Phase 1 side-table matching gives same-node evidence
priority, so a side-table-only semantic matcher cannot reassign old A to current
A while the previous node is still present.

This investigation determines whether semantic reorder identity should be solved
with edit provenance hints, projection reconciliation changes, or left out of the
current SDEG slice.

## Scope

In:
- Markdown heading reorder scenarios from the Phase 0 spike.
- Existing Markdown edit/editor path, if a reorder can be represented there.
- Existing projection reconciliation and identity hint mechanisms.
- Diagnostic tests that record what evidence is available.

Out:
- public `EntityId` or `sdeg-*` packages.
- durable reload/peer-stable identities.
- CRDT schema changes.
- UI behavior changes.

## Questions

1. Can a user-level Markdown reorder produce explicit edit provenance that says
   heading A moved rather than heading contents were replaced positionally?
2. Can existing projection reconciliation consume that provenance without
   weakening same-node priority for ordinary edits?
3. If no provenance exists, should SDEG continue to classify pure reorder as a
   known same-node-priority limitation?
4. Is the right owner Markdown edit lowering, generic projection reconciliation,
   `ProjectionIdentityTracker`-style realignment, or a later durable entity
   layer?

## Investigation steps

1. Reproduce the Phase 0 reorder observation from the archived spike and record
   which previous `NodeId`s remain present after the swap.
2. Inspect existing edit provenance / identity hint APIs before adding anything
   new.
3. Try the smallest Markdown-edit-path reorder, if one exists; otherwise record
   that reorder is currently represented only as source replacement.
4. Prototype one constrained evidence path:
   - either an edit provenance hint that identifies moved heading observations;
   - or a projection reconciliation rule that can override positional same-node
     evidence only for explicit reorder edits.
5. Add white-box tests that compare:
   - pure source reorder without provenance => same-node-priority limitation;
   - provenance-backed reorder, if implemented => semantic identity follows the
     heading text/key.
6. Update the Phase 1 side-table plan with the resulting owner and acceptance
   scope.

## Investigation log

### 2026-06-20 — Phase 0 pure source reorder reproduction

Reproduced with:

```bash
NEW_MOON_MOD=0 moon test -p dowdiness/canopy/lang/markdown/proj --filter 'sdeg phase0: heading reorder is currently position-stable, not semantic-stable'
```

The diagnostic test in `lang/markdown/proj/sdeg_heading_spike_wbtest.mbt`
records that after `# A\n# B\n` is reconciled to `# B\n# A\n`, both previous
heading `NodeId`s remain present: previous A's `NodeId` is now attached to B,
and previous B's `NodeId` is now attached to A. This confirms the Phase 0
observation: pure source reorder without provenance is position-stable, not
semantic-stable.

### 2026-06-20 — Markdown edit-path reorder check

Existing Markdown edit operations are `CommitEdit`, `ChangeHeadingLevel`,
`ToggleListItem`, `Delete`, `InsertBlockAfter`, `SplitBlock`, and
`MergeWithPrevious`; there is no explicit move/reorder operation. The generic
Markdown companion bridge computes span edits and calls
`SyncEditor::apply_span_edits` without an identity hint, so it does not produce
move provenance for reorder-like outcomes.

Added a companion white-box diagnostic covering the smallest existing edit-path
way to reach the swapped text: two `CommitEdit` operations, A→B at the first
heading and B→A at the second heading. The final source is `# B\n# A\n`, but
identity stays by position: the first heading keeps previous A's `NodeId`, and
the second heading keeps previous B's `NodeId`. This is replacement provenance,
not reorder provenance.

Reproduced with:

```bash
NEW_MOON_MOD=0 moon test -p dowdiness/canopy/lang/markdown/companion --filter 'sdeg phase0: markdown edit path swap is replacement, not reorder provenance'
```

### 2026-06-20 — Scope decision

Markdown reorder recovery is needed for the future block-based editor UI, where a
user-visible block move should carry identity with the moved block. It is not a
Phase 1 side-table deliverable: the current Markdown edit path has no reorder
operation or move provenance, and building that language-owned block move path
is a larger structural-edit feature. Until that exists, pure source reorder
remains a documented same-node-priority limitation rather than a side-table-only
semantic override.

Existing APIs checked before making that call:

- `core/reconcile.mbt`: `reconcile` / `reconcile_hinted` preserve same-kind
  siblings by LCS/position unless explicit structural hints exclude old nodes.
- `core/identity_transform.mbt`: `IdentityTransform::Move` exists as vocabulary,
  but the generic reconciler currently freshens move-targeted positions; there is
  no Markdown producer for it.
- `lang/runtime/language_spec.mbt` and `lang/markdown/companion/`: Markdown
  structural edits are lowered to span edits without identity hints.
- `lang/lambda/proj/projection_memo.mbt`: Lambda has custom hinted projection
  reconciliation, but Markdown does not.
- Loom `ProjectionIdentityTracker` / `realign_projection_items`: useful for edit
  windows and failed-input recovery, but the Phase 0 diagnostic records that it
  does not recover pure sibling reorder.

## Conclusion

Reorder recovery is **not in scope for SDEG Phase 1**. The Phase 1 side table
should keep same-node priority for ordinary edits and report pure source reorder
as a known limitation when no explicit provenance is present.

The future owner is **Markdown/block edit lowering plus hinted projection
reconciliation**: a block-based editor move command should produce an explicit
move/reorder operation, lower it to text/CRDT edits, and pass identity provenance
through the existing hint channel or a future equivalent. Projection
reconciliation should only override positional same-node evidence for that
explicit move provenance, not for arbitrary source reorder inferred from text.

No prototype fix was added because the current Markdown edit path cannot express
the required user intent. Adding that path is a larger block-editor structural
edit feature, not a side-table-only change.

Follow-up spike opened: `docs/plans/2026-06-20-markdown-block-move-provenance-spike.md`.

## Acceptance criteria

- [x] The investigation names whether reorder recovery is in scope for Phase 1.
- [x] Tests record pure source reorder as position-stable unless explicit
      provenance is present.
- [x] If a fix is prototyped, same-node priority still wins for ordinary
      non-reorder edits. Not applicable: no fix was prototyped because no
      explicit Markdown reorder provenance exists today.
- [x] No public API or `.mbti` surface changes unless explicitly justified.
- [x] Documentation states the owner: Markdown edit lowering plus hinted
      projection reconciliation for a future block move/reorder edit path.

## Validation

```bash
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test -p dowdiness/canopy/lang/markdown/proj
NEW_MOON_MOD=0 moon test -p dowdiness/canopy/lang/markdown/companion
NEW_MOON_MOD=0 moon fmt && NEW_MOON_MOD=0 moon info
git diff -- '*.mbti'
```

If the prototype changes Canopy-owned reconciliation or identity-hint code (for
example `core/`, `editor/`, or Markdown edit/companion plumbing), also run the
owning root-module validation:

```bash
NEW_MOON_MOD=0 moon test
```

If the prototype lands in standalone Loom, run the same submodule command as the
CI `Test Submodules (loom, loom/loom, ci-lenient)` matrix, then check generated
interfaces inside the submodule as well:

```bash
./scripts/run-moon-module.sh ci-lenient loom/loom
(cd loom/loom && NEW_MOON_MOD=0 moon info)
git -C loom/loom diff -- '*.mbti'
```

The parent checkout's `git diff -- '*.mbti'` does not inspect generated
interfaces inside submodules; review and commit any intended Loom `.mbti` drift
before updating the parent submodule pointer.
