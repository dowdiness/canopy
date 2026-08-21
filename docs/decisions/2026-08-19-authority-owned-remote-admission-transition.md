# ADR: Authority-owned remote admission transition

**Date:** 2026-08-19

**Status:** Accepted and implemented.

**Implementation plan:** [#1281 authority-transition implementation invariants](../archive/completed-phases/2026-08-21-1281-authority-transition-implementation-invariants.md)

**Canonical issue:** [Avoid full text snapshots during remote admission (#1281)](https://github.com/dowdiness/canopy/issues/1281)

## Context

Canopy remote admission previously asked event-graph-walker to admit a message and then materialized the complete authority text before reconciling parser, cursor, projection identity, and hint state. The full snapshot made a one-operation admission scale with resident history and obscured whether authority had committed when projection recovery failed.

Event-graph-walker now exposes one opaque admission transition whose exhaustive availability is `Exact`, `SnapshotRequired`, or `Unavailable`. The transition retains the complete report or error until `finish()` and keeps authority mutation, recovery precedence, and effect ownership inside the authority module.

## Decision

`SyncEditor` consumes the authority transition as the sole remote-admission result.

For `Exact`, Canopy prepares the ordered scalar-domain text effects without mutating editor state. Preparation derives one coherent candidate source and converts every affected scalar position to a UTF-16 parser edit. Settlement compares that candidate with parser-held source, then applies cursor, peer-cursor, hint, parser, projection-identity, and observation changes from the same prepared value.

For `SnapshotRequired`, Canopy performs exactly one post-admission authority text read and gives that coherent source to settlement. Peer cursors are reconciled on grapheme boundaries in UTF-16 coordinates before parser seeding. Precise separated edits use a longest-common-subsequence matrix capped at 65,536 cells; larger changed middles use one grapheme-aligned replacement so settlement time and memory remain bounded. The coarse path intentionally collapses cursor affinity inside that changed middle.

For `Unavailable`, Canopy performs no authority text read or parser reconciliation and calls `finish()` to surface the retained recovery error. Authority acceptance is observed before settlement. Parser replay or seed failure after authority commit remains a parser failure and does not let `finish()` declare synchronization.

The existing public Canopy interfaces, sync report, wire data, and archive data remain unchanged. The event-graph-walker transition is the authority interface; Canopy owns only editor-domain adaptation and settlement.

## Consequences

- Warm, exact remote admission no longer materializes the complete authority text.
- Admission outcome and post-commit failure precedence are explicit and testable through one transition interface.
- Scalar CRDT effects and UTF-16 editor coordinates meet at one preparation seam.
- Snapshot fallback performs one full authority read and has bounded diff memory and time.
- Large unrelated fallback changes preserve source correctness but use coarse interior peer-cursor affinity.
- Existing callers retain their current Canopy interface and compatibility behavior.

## Alternatives rejected

### Always materialize the authority text

This preserves the old implementation but keeps one-operation cost proportional to resident history and hides exact effects already known by the authority module.

### Reconstruct admission effects in Canopy

This duplicates authority ordering, pending, recovery, and partial-admission semantics across the seam. Divergent reconstruction could reconcile a source different from the committed authority outcome.

### Run an unbounded precise fallback diff

A full longest-common-subsequence matrix preserves interior equal clusters, but unrelated large snapshots require quadratic time and memory before parser recovery. Bounded coarse replacement preserves correctness and availability at the documented cursor-affinity cost.
