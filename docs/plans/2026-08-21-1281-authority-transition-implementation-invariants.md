# #1281 authority-transition implementation invariants

This implementation note makes the accepted issue specification executable. It
does not change the governing decisions or authorize a second admission path.

## Transition outcome precedence

Admission has one linear precedence order. Validation or recovery failure before
the first OpLog authority mutation raises immediately and returns no transition.
After authority mutation, failed projection recovery produces an `Unavailable`
transition and its recovery error wins over a coincident partial-admission error.
Successful recovery always produces `SnapshotRequired`, even when no operation
committed. Without recovery, a provably exact warm small-batch projection produces
`Exact`; cold, dirty, oversized, or otherwise unprovable projection produces
`SnapshotRequired`. Duplicate-only and pending-only outcomes produce `Exact([])`
only when no recovery occurred. `finish()` is the sole report/error settlement:
it returns the complete `SyncReport`, raises the stored partial error after the
consumer reconciles the committed prefix, or raises the recovery error for
`Unavailable`.

## Atomic detached workspace publication

Fallible projection never mutates a published index incrementally. Before
projection, Document detaches the warm visible index and its same-generation LV
locator into a private workspace. The canonical slots remain empty while the
workspace applies the committed operations, records ordered effects, and tracks
exactness. Exact success publishes the derived visible index, locator, and
effects as one Document-owned state change. The OpLog authority frontier has
already committed independently and is never rolled back with derived state.
The Text facade then
advances its existing maintained `Version` cache from the committed receipt
before returning the transition; internal Document neither owns nor duplicates
that Text cache. Losing exactness discards effects and publishes derived state
only through the coherent fallback/recovery lifecycle. Projection failure
discards the entire workspace before recovery, so no prefix index, locator, or
effect list becomes observable. Text cache readiness follows the existing
receipt-driven rules for complete, partial, recovery, and failed recovery.

## Sequential effect coordinates

Every `TextEffect` is authority-owned and scalar-indexed. Its position or range
is interpreted against the visible source produced by every preceding effect in
the same transition. Insert content is the exact projected scalar content;
delete ranges name the exact formerly-visible scalar interval. Losing LWW
operations and other visibility no-ops emit no effect, while their admission
counts and causal Version advancement remain represented. Canopy never derives
an effect from the wire operation or raw committed receipt.

## Locator generation and complexity

The LV locator and visible index form one generation. Construction, run
insertion/removal, split/merge, detach, restore, invalidation, and publication
must update or replace them together. A locator answer is usable only for the
workspace generation that owns the corresponding visible index. Warm
LV-to-visible-position resolution uses indexed prefix information and must not
scan all visible runs. Missing, stale, or failed lookup marks exactness lost and
takes `SnapshotRequired`; it never falls back to a hidden linear traversal on
the ordinary path.

## Partial admission and recovery

A partial admission may have committed authority. Its committed prefix is
projected and reconciled before the partial error is surfaced. Exact prefix
projection yields `Exact`; successful recovery yields `SnapshotRequired` and
one coherent post-admission snapshot; failed recovery yields `Unavailable`, no
snapshot, and no consumer reconciliation. Recovery precedence is independent of
committed count, so zero-commit successful recovery still seeds once. Pending
dependency drain contributes every newly committed operation to the same ordered
projection/effect sequence. The transition retains the authority outcome until
`finish()` without exposing a second report accessor.

## Canopy two-phase prepare and commit

Remote ingress does not taint identity hints before outcome classification. For
`Exact`, preparation is pure: starting from parser-held source, it applies
the scalar effects sequentially, converts affected scalar offsets to UTF-16,
and returns one candidate source plus ordered parser edits. Preparation does not
mutate authority, cursor state, peer cursors, parser, projection identity,
identity hints, observations, or stored failure state. Commit compares the
candidate to parser-held source. Source-equal commit advances the document
Version and emits the existing `ProjectionMirrorSynchronized` observation but
does no replay, cursor movement, identity work, or hint consumption. A changing
commit clamps the local cursor to candidate UTF-16 length, transforms peer
cursors with existing UTF-16 affinity rules, then taints/consumes identity hints,
replays the prepared edits, and settles projection identity from the same
candidate/edit sequence. Duplicate, pending, net source-equal, unavailable, and
pre-commit failure paths leave pending identity hints untainted and unconsumed.

For `SnapshotRequired`, Canopy performs exactly one post-admission authority
text read and passes ownership of that coherent source into settlement. Peer
cursors are transformed from parser-held old source to that supplied source
before parser seeding and the local cursor is clamped against the supplied
source's UTF-16 length. Every `SnapshotRequired` settlement follows the existing
seed invalidation policy, including a recovered zero-commit or source-equal
seed; only `Exact` duplicate, pending, and net source-equal settlement preserves
hints unchanged. Settlement itself performs no authority read. For
`Unavailable`, Canopy performs no authority read and no reconciliation, then
calls `finish()` to surface the recovery error. If replay or seed raises after
authority commit, Canopy records and propagates the existing parser failure and
does not call `finish()`; authority remains committed and later `finish()` cannot
declare the parser synchronized.

## Observation and compatibility

Authority acceptance is observed before transition settlement. Existing sync
methods delegate to transition-aware methods and immediately finish, preserving
their signatures, standalone `SyncReport`, `TextError`, wire data, and archive
data. The opaque transition exposes only versions, exhaustive availability, and
`finish()`. EGW retains authority, conflict, recovery, and effect ownership;
Canopy retains scalar-to-UTF-16 adaptation, cursor and parser mutation,
projection identity, hints, and session observation.

## Reuse check before new definitions

Candidate project APIs are `Document::admit_remote` and its typed
`DocumentAdmission`, `AdmissionOutcome`/`AdmissionReceipt`, `ProjectionStatus`,
`IndexedState` cache detach/restore and OrderTree prefix lookup, existing Fugue
visible-change projection, `TextState::advance_cached_version`, and the current
`SyncEditor` committed-transition/replay/seed/peer-cursor machinery. Core APIs
checked are `ArrayView` for zero-copy effect exposure, `StringView` scalar and
code-unit traversal, `Map`/`Set` for locator ownership, and `Array`/`Iter` for
ordered transformation. New types are limited to the accepted opaque transition,
two exhaustive effect enums, and private workspace/locator state whose boundary
is atomic projection publication. Any further helper must have one deterministic
transformation or publication responsibility and must be justified at review.
