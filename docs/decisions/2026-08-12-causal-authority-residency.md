# Causal Authority residency for warm and cold document access

**Date:** 2026-08-12

**Status:** Accepted target architecture; implementation is not complete.

**Related:**

- [Indexed projection lifecycle](2026-07-22-indexed-projection-lifecycle.md)
- [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)
- [Loomark startup history corpus](../performance/2026-08-10-loomark-startup-history-corpus.md)
- [Eg-walker paper](https://arxiv.org/abs/2409.14252)

**Decision:** Keep the EventGraph, OpLog, and Frontier as the Causal Authority,
but choose its residency according to the access path. A live Persistence
Coordinator retains the authority needed for warm reconnects; a cold reopen
loads the plain-text projection and exact frontier first, while keeping the
canonical event graph disk-backed and reading only the required portion for
merge or replay.

## Context

Loomark has two different startup problems. A new Writing instance may attach
while a Persistence Coordinator is still alive, or the application may have to
reopen a Detached Editing Document after the coordinator has disappeared.
Treating both paths as full CRDT restoration makes the warm path unnecessarily
expensive and makes the cold path depend on replaying history before the editor
can become useful.

The Eg-walker design separates the canonical event graph from the current plain
text and from the temporary CRDT structure used during concurrent merge. The
canonical history must remain authoritative, but it does not follow that every
mounted editor must retain per-character causal metadata.

## Decision details

### Warm reconnect

The Persistence Coordinator owns one Aggregate Markdown runtime and the causal
authority needed to admit fresh Writing instances. A reconnecting page receives
the current plain-text projection and attaches a fresh writer identity; it does
not load another event graph, retain another FugueTree, or become a second
causal authority.

The Coordinator remains the sole application shell for that Editing Document.
Coordinator replacement creates a new epoch and requires causal handoff or
cold recovery; a page cannot infer authority from a text snapshot alone.

### Cold reopen

The durable archive retains, at minimum, the portable text, exact RawVersion
frontier, and canonical event history. Reopen initially admits the text and
frontier and creates a fresh Writing instance. It does not construct Fugue or
other per-character CRDT state, and it does not promise to complete arbitrary
history replay on the main thread within one frame.

The event history remains disk-backed. Concurrent merge, historical replay, or
recovery reads the required causal suffix from the latest usable critical
version. If the accelerator or partial-read path is unavailable or rejected,
canonical-history replay remains the correctness fallback.

### Normal and transient memory

The normal mounted projection contains the portable text and only the position
structure required for editing and lookup. It does not retain one causal
identity or tombstone record per Unicode scalar, and it does not retain Fugue
metadata. Run- or piece-level causal-span metadata may exist only when needed
to generate or validate position-based events; the projection's position query
capability must not be implemented as a resident per-scalar CRDT map.

A metadata-rich merge materializer is created only for concurrent merge or
replay, preferably outside the UI main thread, and is discarded after producing
the next plain-text projection. It is disposable acceleration state, never a
replacement for Causal Authority.

## Consequences

- Warm reconnect can reuse retained causal authority without duplicating it per
  page or rebuilding a CRDT.
- Cold reopen can make the plain text useful before any merge materialization,
  while preserving exact causal recovery.
- The durable event-graph format needs indexed or bounded access to causal
  suffixes; storing only a text snapshot is insufficient for future concurrent
  edits.
- Coordinator lifetime, handoff, crash recovery, and stale-writer rejection
  become explicit parts of the implementation.
- The 16ms goal applies to measured main-thread responsiveness, especially warm
  reconnect. It does not promise arbitrary cold replay or network startup
  completion within 16ms.
- Performance claims must be measured separately for load, sequential update,
  concurrent merge, memory, and storage, using traces comparable to the paper.

## Non-goals

- Replacing the event graph with a checkpoint or text snapshot.
- Adding a public checkpoint/restore API at this stage.
- Persisting FugueTree or other per-character CRDT metadata as the normal
  document representation.
- Claiming that every cold reopen completes fully within 16ms.
