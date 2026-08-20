# ADR: Private restore coordinator for Loomark cold open

**Date:** 2026-08-20

**Status:** Accepted target architecture; implementation is not complete.

**Implementation plan:** [Private Rabbita restore coordinator](../plans/2026-08-20-loomark-private-restore-coordinator.md)

**Canonical decision:** [Choose the restore lifecycle interface seam (#1320)](https://github.com/dowdiness/canopy/issues/1320)

**Related:**

- [Causal Authority residency](2026-08-12-causal-authority-residency.md)
- [Restore/readiness lifecycle interface patterns](../research/2026-08-20-restore-lifecycle-interface-patterns.md)
- [Define restore readiness and fallback states (#1296)](https://github.com/dowdiness/canopy/issues/1296)
- [Production editable-branch restore architecture (#1295)](https://github.com/dowdiness/canopy/issues/1295)

## Context

Loomark cold open currently combines browser storage completion, archive classification,
repository admission, `EditorSession` adoption, rendering, and terminal recovery in the
Rabbita bootstrap/update path. The Boolean `archive_persistence_enabled` also participates
in readiness decisions. That shape is sufficient for one all-or-nothing archive reopen,
but it cannot represent canonical Markdown becoming readable before causal editability,
a discardable accelerator attempt, canonical full-history fallback, superseding Retry, or
correlated focus/selection activation without distributing ordering rules across callbacks.

Canonical v1 full history remains the authority. A retained active-store value may
accelerate admission only after independent validation. Its rejection must not replace
canonical text, manufacture an editor, or prevent automatic reconstruction from canonical
history.

## Decision

Deepen the restore seam inside `apps/loomark/internal/rabbita` with one package-private
restore coordinator. Keep `mount_standalone(String, String) -> String` as the sole public
cold-open interface and expose no restore handle, subscription, candidate, storage value,
or mutation capability through generated interfaces.

The coordinator has three semantic entry points:

- `start` creates the initial Mount generation and commands;
- `step` owns every restore-state transition and stale-result decision;
- `view` projects loading, stable read-only, recovery, and unavailable presentation.

The coordinator owns these exhaustive readiness states:

- authority loading;
- canonical text readable while editability is being prepared;
- canonical text readable while full history is being rebuilt;
- admitted session awaiting correlated after-render activation;
- editable;
- terminal editing-recovery failure with canonical text;
- terminal unavailability without canonical text.

Every asynchronous result is correlated with a Mount generation. Retry creates a newer
generation; completions from older generations are no-ops. Page termination remains the
existing lifetime end and does not create a public cancellation interface.

Canonical text may enter the readable state only from structurally decoded canonical v1
archive material. The progressive path uses existing archive decode and
`reopen_decoded_local_archive` separately rather than the all-in-one
`classify_local_archive_record` path. Accelerator rejection discards the candidate and
commands canonical full-history admission while the same canonical text remains visible.

The existing private `EditorSession` is the mutation capability. The coordinator may install
it into the live Rabbita application only after complete constrained admission and
canonical-text equality. Input before the editable state is rejected rather than queued.

Editable activation is a correlated state transition, not an incidental render effect. It
preserves scroll, logical focus, focus endpoint, and the anchor, head, bounds, and direction
of `MarkdownDocumentUtf16Selection`. Activation must not round-trip through a conversion
that writes `NoDirection`. The editable state is entered only after the same-generation
after-render effect confirms continuity.

Reuse existing archive, repository, `archive_storage`, `EditorSession`, and DOM-effect
modules/adapters. Add only restore-specific effect functions required by the coordinator.
Do not introduce generic store or DOM ports until two real product adapters require the same
purposeful conversation.

## Rationale

The coordinator passes the deletion test: deleting it would force each callback path to
reconstruct authority ordering, generation checks, fallback precedence, terminal actions,
and the session-swap invariant. Its small private interface therefore has leverage over a
large implementation and gives restore changes locality.

The public caller remains one call. Existing archive/repository interfaces already separate
structural readability from causal admission, and `EditorSession` plus
`MarkdownDocumentUtf16Selection` already express the required capabilities. Reusing them
avoids parallel authority and selection models.

Making readiness exhaustive prevents a Boolean from conflating no-text loading,
readable-but-not-editable preparation, fallback rebuilding, activation, terminal readable
recovery, and terminal unavailability. It also makes the coordinator interface the test
surface for transition ordering instead of extracting shallow helpers that leave callback
composition untested.

## Alternatives rejected

### Generic restore ports and sink

A private coordinator was sound, but `RestorePorts` and `RestoreSink` would wrap the existing
storage and DOM adapters without a second product adapter. Deleting those wrappers would
only move forwarding code, so they fail the deletion test.

### Public restore state/event log

A public reducer could make transitions exhaustive, but it would expose candidate policy,
telemetry, multiple-consumer machinery, and retained-state values before a second caller
exists. That interface is wider than the current product seam requires.

### General Mount view and capability interface

A common-caller view preserves one-call mounting, but combining restore readiness with editor
mode, split preview, and general actions reduces locality. Loomark already has the private
`EditorSession` capability needed for activation.

### New `RestoreAuthority` adapter family

Dependency classification and narrow effects are retained, but wrapping `archive_storage`
and DOM effects in another adapter family duplicates real seams rather than deepening them.

## Consequences

- Restore ordering and failure precedence become explicit package-private data.
- Current all-in-one bootstrap classification must be split into structural decode followed
  by admission for the progressive path.
- `archive_persistence_enabled` may remain a persistence-policy fact, but it must stop driving
  rendering, subscriptions, or input readiness.
- Coordinator tests must cover readable-before-editable, automatic fallback, stale result
  suppression, terminal actions, and activation failure.
- Browser tests remain necessary for real focus, directed UTF-16 selection, scroll, stable
  surface, and assistive-technology announcements.
- The implementation adds private state/event/command types, but does not add a public
  lifecycle interface or choose a retained-state representation, storage provider,
  performance threshold, migration, or publication policy.
