# Loomark production editing is source-first and input-budgeted

**Date:** 2026-08-24

**Status:** Accepted

**Issue:** [#1162](https://github.com/dowdiness/canopy/issues/1162)

**Implementation:** [PR #1345](https://github.com/dowdiness/canopy/pull/1345)

**Related:**

- [Loomark projection execution is asynchronous and source-stamped](2026-08-12-loomark-concurrent-projection-execution.md)
- [Causal Authority residency](2026-08-12-causal-authority-residency.md)
- [Loomark local archive repository](../plans/2026-08-06-loomark-local-archive-repository.md)
- [Loomark editable-branch restore feasibility](../plans/2026-08-19-loomark-editable-branch-restore-feasibility.md)
- [#1347 — bound Source durability without entering Raw input tasks](https://github.com/dowdiness/canopy/issues/1347)

## Context

Loomark's immediate product is a fast, comfortable, private single-user Markdown
editor. Earlier specifications made every visible edit immediately advance a
causal transaction and prepare a complete history archive. Real-browser and
archive-preparation measurements showed that this contract cannot satisfy the
interactive target: complete history work can take orders of magnitude longer
than one input task, and even ordinary parsing or CRDT work can exceed the
budget on larger documents.

The product therefore needs separate guarantees for what the browser is showing,
what the application has accepted, what can be recovered locally, and what a
future collaborative editor can replay causally. Treating all four as one
"document state" either makes typing slow or makes durability claims dishonest.

## Decision

Production Loomark uses four explicit layers:

1. **Browser draft** — the native text control's exact visible value and
   selection. The browser updates it in the input task. It may be newer than
   canonical or durable state and is never described as saved.
2. **Canonical source** — the latest source accepted by the single-user
   application after composition ends and the 250 ms quiet period expires, or
   at an explicit editing boundary. It uses the browser text control's LF line
   representation and is the authority for production editing.
3. **Source record** — an atomically replaced local record containing document
   identity and exact canonical Markdown source. Acknowledgment establishes
   source durability and nothing more.
4. **Causal archive** — optional history, frontier, and writer evidence needed
   for collaboration, cross-instance causal undo, or exact branch replay. It is
   not allocated, prepared, or persisted by the current production input path.

The Raw input task has a hard p95 and maximum target of 10 ms. Parsing, CRDT
mutation, hashing, JSON encoding, archive preparation, IndexedDB work, and
speculative Preview work must not execute in that task. Frame latency is
measured separately.

Canonical acceptance never waits for speculative Preview. Preview may consume a
browser draft early, but an artifact is displayable only when bound to the exact
requested source and current projection provenance. Preview failure, timeout,
or obsolescence cannot delay canonical source or source durability.

IME intermediate values remain browser drafts. They do not become canonical or
durable until composition finishes and the normal acceptance boundary runs.

The current minimum durability guarantee is trailing: after input becomes quiet,
the latest canonical source is atomically stored. #1347 tracks continuous-typing
max-wait and lifecycle hardening, which must remain outside the input task. Until implemented, the UI and documentation must not claim a bounded
crash-loss window during uninterrupted typing.

Causal archive work is promoted only by an explicit collaboration requirement
and its manual evidence gate. Promotion must preserve the source-first input
budget and add causal capability behind a separate preparation and persistence
boundary; it must not restore complete-history preparation to ordinary input.

## Consequences

- Visible browser text can briefly be newer than canonical and durable source.
  This is a named Browser draft, not a falsely accepted transaction.
- A crash before quiet-period acceptance may lose that draft. Once source
  durability is acknowledged, reopen restores the exact stored source and
  document identity.
- Production restart does not promise causal history, collaborative identity,
  or undo/redo continuity.
- Source-backed browser editing uses LF line terminators. Exact imported file
  terminator profiles require a separately promoted File-backed capability.
- Source-only document catalogs, switching, and session metadata may proceed
  without waiting for the future causal archive design.
- Existing causal architecture remains valid for collaboration-capable modes,
  but it no longer defines the baseline production editor contract.
- Performance regressions are product correctness failures when the measured Raw
  input task exceeds the 10 ms gate.

## Rejected alternatives

**Prepare a complete causal archive after every edit.** Rejected because its
cost is incompatible with the input objective and it couples single-user source
recovery to future collaboration metadata.

**Keep canonical source browser-owned indefinitely.** Rejected because parsing,
mode changes, recovery, and persistence need a clear acceptance boundary.

**Let Preview completion authorize canonical acceptance.** Rejected because a
derived, fallible, and potentially obsolete computation must not control source
authority.

**Claim bounded durability from trailing debounce alone.** Rejected because
continuous input can postpone a trailing callback indefinitely.
