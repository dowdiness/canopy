# Causal Authority residency for warm and cold document access

**Date:** 2026-08-12

**Status:** Accepted target architecture; implementation is not complete.

**Related:**

- [Indexed projection lifecycle](2026-07-22-indexed-projection-lifecycle.md)
- [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)
- [Loomark startup history corpus](../performance/2026-08-10-loomark-startup-history-corpus.md)
- [Eg-walker paper](https://arxiv.org/abs/2409.14252)

**Decision:** Preserve one causal authority and choose its residency according
to the access path. Warm access may retain authority across reconnects; cold
access may load a plain-text projection and exact causal frontier first, while
keeping durable history available and reading only the required portion for
merge or replay. Local edits require causal admission of that loaded base.

## Context

Loomark has two different startup problems. A new editor may attach while the
authority is still resident, or the application may have to reopen a document
after that authority has disappeared. Treating both paths as full merge-state
restoration makes the warm path unnecessarily expensive and makes the cold path
depend on replaying history before the editor can become useful.

The target design separates canonical history from current plain text and
from temporary merge state. Canonical history must remain authoritative, but it
does not follow that every mounted editor must retain merge-only causal metadata.

## Decision details

### Warm reconnect

A warm access path may retain one aggregate runtime and its causal authority.
A reconnecting editor receives the current plain-text projection and attaches a
fresh writer identity; it does not duplicate canonical history, retain another
merge materialization, or become a second authority.

The authority-owning application shell remains singular for the document.
Replacement creates a new epoch and requires causal handoff or cold recovery; an
editor cannot infer authority from a text snapshot alone.

### Cold reopen

The durable archive retains, at minimum, the portable text, exact causal
frontier, and canonical history. Archive consistency is an invariant:

```text
Replay(canonical history, exact frontier) == portable text
```

The archive loader must verify that invariant, or treat the portable text as an
untrusted display snapshot and fall back to canonical replay. A text/frontier
pair that cannot be verified against canonical history is not a causally
admitted editing base.

Cold reopen initially loads or presents the text and frontier. It does not
construct merge-only causal state, and it does not promise to complete arbitrary
history replay on the main thread within one frame. Loading text is not causal
authority admission, and local event generation remains disabled until the
loaded base has been validated against the authority.

The history remains available for concurrent merge, historical replay, or
recovery. The Causal Authority is the authoritative producer and validator of
critical-version evidence; neither the plain-text projection nor a transient
materializer may invent or promote a candidate. Detection is a deterministic
analysis of causal ancestry and descendants: a candidate is usable only when
its represented base is causally before the required replay suffix, the suffix
is causally closed, and no required event is incomparable with or missing from
that boundary's evidence. The detector identifies versions that cleanly
separate the already represented history from the history that must be replayed.
Selection chooses the maximal usable candidate under the causal order that
precedes every required event and whose associated base evidence is internally
consistent; it never chooses a newer incomparable or unverified candidate.

If detection finds no usable candidate, or a candidate is unavailable, partial,
stale, corrupt, or rejected by resource policy, recovery discards that
candidate and tries the next usable ancestor. If none remains, it falls back to
canonical-history replay from the initial state. A failed accelerator never
changes Causal Authority or becomes a reason to accept an unverified text base.
This is a target recovery contract; Gate A records no production detector or
recovery implementation.

### Normal and transient memory

The normal mounted projection contains the portable text and only the position
structure required for editing and lookup. Position queries do not require
merge-only causal metadata to remain resident in that projection.

A metadata-rich merge materializer is created only for concurrent merge or
replay, preferably outside the UI main thread, and is discarded after producing
the next plain-text projection. It is disposable acceleration state, never a
replacement for Causal Authority.

## Consequences

- Warm reconnect can reuse retained causal authority without duplicating it per
  page or rebuilding a CRDT.
- Cold reopen can make the plain text useful before any merge materialization,
  while preserving exact causal recovery.
- Durable history needs indexed or bounded access to causal suffixes; storing
  only a text snapshot is insufficient for future concurrent edits.
- Authority lifetime, handoff, crash recovery, and stale-writer rejection
  become explicit parts of the implementation.
- The 16ms goal applies to measured main-thread responsiveness, especially warm
  reconnect. It does not promise arbitrary cold replay or network startup
  completion within 16ms.
- Performance claims must be measured separately for load, sequential update,
  concurrent merge, memory, and storage, using traces comparable to the paper.

## Non-goals

- Replacing canonical history with a checkpoint or text snapshot.
- Adding a public checkpoint/restore API at this stage.
- Persisting merge-only or per-character causal metadata as the normal document
  representation.
- Claiming that every cold reopen completes fully within 16ms.
