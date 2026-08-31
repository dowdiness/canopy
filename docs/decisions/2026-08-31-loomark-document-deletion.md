# Loomark deletes Sources only from a quiescent document state

**Date:** 2026-08-31

**Status:** Accepted

**Issue:** [#1306](https://github.com/dowdiness/canopy/issues/1306)

**Related:**

- [Loomark Source repository](2026-08-29-loomark-source-repository.md)
- [Loomark separates current and saved text](2026-08-24-loomark-source-first-interactive-contract.md)

## Context

Deleting a Source must not publish a Catalog that disagrees with IndexedDB or
overwrite a Snapshot accepted by another repository operation. Loomark already
admits document switching and creation only while the active document is Saved,
not composing, and not creating. Only the active document can Autosave.

Allowing edits or another repository mutation during deletion would create a
Save/Delete ordering problem that the product does not otherwise need. Solving
that self-created concurrency with per-document queues, Snapshot deltas,
watchdogs, or a new persisted ordering field would make permanent deletion
substantially deeper than its product behavior.

Issue #1306 also requires a policy for the final valid Source. Replacing it with
a newly generated Source would add identity generation and a second mutation to
an operation whose purpose is deleting one Source.

## Decision

Loomark permits deletion only from the existing quiescent document boundary:
the active document is Saved, composition is inactive, and creation is idle.
Confirmation and an in-flight Delete temporarily block text mutation, document
switching, creation, and another Delete. Preview and Editor mode remain usable
because they do not mutate the Source repository.

The repository validates that the target belongs to the supplied immutable
`RepositorySnapshot` and that at least two valid Sources remain. Unknown targets
and the final Source fail before IndexedDB work.

The repository computes the next Snapshot and derived Catalog before issuing
one transaction. That transaction contains only
`Mutation::Delete(source_key)`. Only transaction completion publishes the
prepared Snapshot. Abort, unavailability, quota, or another write failure
preserves the prior Snapshot.

Delete attempts carry an app-private monotonic request ID. A completion changes
state only when it matches the single in-flight attempt.

Deleting the active Source activates `RepositorySnapshot::selected()` after
commit. Its existing lexical Document ID order is the deterministic fallback.
Deleting a non-active Source changes only the acknowledged repository Snapshot.

The final valid Source cannot be deleted. The UI disables that action and the
repository independently enforces the policy.

The `source/v1` value remains exactly `document_id` and `text`. Delete adds no
persisted Catalog, ordering field, tombstone, replacement Source, empty
repository state, or Rabbita provider behavior.

## Consequences

- Delete has one in-flight state rather than a persistence queue.
- A stalled transaction can temporarily make document mutations unavailable;
  no timeout may claim whether an unacknowledged transaction committed.
- Closing the page needs no special recovery. The next complete Source scan
  reflects whichever IndexedDB state became durable.
- Most-recently-changed fallback and deleting the final Source remain separate
  product decisions requiring their own evidence and storage contracts.

## Rejected alternatives

**Delete the final Source and open an ephemeral replacement.** Rejected because
it changes the existing non-empty repository invariant and introduces identity
reservation and first-write promotion unrelated to deleting one Source.

**Atomically replace the final Source with `# Untitled\n`.** Rejected because it
adds UUID failure and a Source put to the smallest deletion contract.

**Allow Save and Delete concurrently and merge acknowledged deltas.** Rejected
because the existing Saved-only admission boundary can prevent that race.

**Add per-document persistence lanes.** Rejected because Loomark edits and saves
only one active document, while Delete is a rare confirmed operation.

**Probe after a watchdog timeout.** Rejected because IndexedDB transaction
completion or abort already defines the operation result; page termination is
resolved by the next repository scan.
