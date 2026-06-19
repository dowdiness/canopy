# SDEG Reorder Provenance Investigation

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

## Acceptance criteria

- [ ] The investigation names whether reorder recovery is in scope for Phase 1.
- [ ] Tests record pure source reorder as position-stable unless explicit
      provenance is present.
- [ ] If a fix is prototyped, same-node priority still wins for ordinary
      non-reorder edits.
- [ ] No public API or `.mbti` surface changes unless explicitly justified.
- [ ] Documentation states the owner: Markdown edit lowering, projection
      reconciliation, identity realignment, or future SDEG core.

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
