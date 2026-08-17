# EGW P3.0: Text admission characterization

## Status

This is a read-only characterization of the merged P2 EGW tree. It records the
current Text façade contract before the P3 façade cutover. It is evidence for
plan review, not implementation authorization.

- Canonical issue: <https://github.com/dowdiness/canopy/issues/1256>
- EGW PR head reviewed: `c149610970a583a401f7f2e743159a9f1324b58f`
- EGW squash merge: `91aaffc6679b2e1864b80ef6cc505d1d3b9aa548`
- PR-head and merge-tree SHA: `abf16198183df4d145086bcad9afd0f8237bc3d4`
- Retained P2 worktree: clean; no uncommitted benchmark evidence
- Canopy `deps/event-graph-walker` gitlink: unchanged

The source links below use the merged EGW main commit:
`91aaffc6679b2e1864b80ef6cc505d1d3b9aa548`.

## Executive finding

P2 provides the required deep admission seam in `Document`, but Text still
runs a second admission module around it. The current shell expands all
resident operations, builds an H-sized identity/payload view, plans against
outer pending records, then calls `Document::apply_remote` once per applicable
operation. Each P2 wrapper call already routes through one
`Document::admit_remote([op])`, one typed one-op commit, and up to one projection.
The P3 target is to keep the Text module's small wire-facing interface while
moving causal ownership, pending membership, and the one message-level
authority transition behind `Document::admit_remote`.

The three public-contract questions are not equivalent:

1. `SyncReport` needs a delivery-count mapping, not just unique ownership
   evidence.
2. `pending_sync_count` has no current public core count adapter.
3. `clear_pending_sync` is public but has no in-repository code caller, so its
   intended discard semantics must be accepted before it is delegated to core.

## Evidence locations

- [Text wire, report, planner, and apply shell](https://github.com/dowdiness/event-graph-walker/blob/91aaffc6679b2e1864b80ef6cc505d1d3b9aa548/text/sync.mbt)
  (`SyncReport` around lines 574-730; `prepare_sync` around 1126-1257;
  `apply_with_limits` around 1270-1300; pending accessors around 1312-1324).
- [TextState cache and mutation shell](https://github.com/dowdiness/event-graph-walker/blob/91aaffc6679b2e1864b80ef6cc505d1d3b9aa548/text/text_doc.mbt)
  (fields and cache helpers around lines 35-91).
- [Typed receipt](https://github.com/dowdiness/event-graph-walker/blob/91aaffc6679b2e1864b80ef6cc505d1d3b9aa548/internal/oplog/typed_admission.mbt)
  (receipt fields and accessors around lines 4-123).
- [Document typed shell](https://github.com/dowdiness/event-graph-walker/blob/91aaffc6679b2e1864b80ef6cc505d1d3b9aa548/internal/document/document_admission.mbt)
  (admission transition around lines 259-390).
- [Core planner count and lifecycle](https://github.com/dowdiness/event-graph-walker/blob/91aaffc6679b2e1864b80ef6cc505d1d3b9aa548/internal/oplog/remote_admission_planner.mbt)
  (private `pending_count` around lines 1647-1650 and generation transitions
  around the pending rejection/begin implementation).
- [Text contract tests](https://github.com/dowdiness/event-graph-walker/blob/91aaffc6679b2e1864b80ef6cc505d1d3b9aa548/text/v04_contract_test.mbt).

## 1. Current Text ingress

`TextState` stores the authoritative `Document`, receiver sync limits, an
outer `pending_sync_records` array, and a cached version. The pending array is
private to `text`, but it is a second lifecycle next to the OpLog planner's
canonical pending map.

`SyncSession::apply_with_limits` currently performs this sequence:

```text
prepare_for_admission()
→ get_all_ops()                 // expand resident history H
→ prepare_sync(message, limits, local history, outer pending)
→ invalidate version cache if applicable is non-empty
→ Document::apply_remote(op) for each applicable op
   ↳ Document::admit_remote([op]) for each one-op wrapper call
      ↳ one OpLog prepare/typed commit and up to one projection
→ replace outer pending array
→ PreparedSync::report()
```

For `A` applicable operations (`A = M` for a complete ready message), the
current path therefore performs `A` `Document::apply_remote` calls, `A`
`Document::admit_remote` calls through those wrappers, `A` successful one-op
typed commits, and up to `A` one-op projection finalizations. P3 changes this
from M one-op batches to one message batch; it does not introduce the typed
Document shell into production.

`prepare_sync` is pure with respect to the receiver. It creates an H-sized
`local_payload_map`, a candidate map containing outer pending and current
message records, a known-operation map, a canonical order, and a receiver-
specific `PreparedSync`. Its applicable array is then consumed by the
imperative per-operation loop.

P2's `Document::admit_remote` already has the desired authority shape:

```text
Document projection/recovery guard
→ validate incoming content
→ one OpLog prepare_remote
→ one typed commit_admission
→ project receipt.committed() once when non-empty
→ return DocumentAdmission(outcome, projection status)
```

The P2 `DocumentAdmission` fields are package-private to
`internal/document`; the generated interface exposes the type but no
`outcome()` or `projection()` accessor. Text therefore cannot yet consume the
typed result across the package seam.

## 2. `SyncReport` mapping

The current report has three private counters and three public accessors:

| Current field | Current source | Meaning today |
| --- | --- | --- |
| `applied_operations` | `prepared.applicable.length()` | Applicable operations selected by the outer planner and then passed to the per-operation Document shell. |
| `duplicate_operations` | `PreparedSync.duplicate_operations` | Canonical incoming operations observed as already present in admitted history or outer pending. |
| `pending_operations` | `prepared.pending.length()` | Records left in the outer pending array after this preparation. |

The natural P3 mapping is:

```text
applied_operations  = receipt.committed().length()
pending_operations  = receipt.pending_after_count()
```

The duplicate field needs a more precise characterization than the initial
P3 hypothesis suggests.

### Same-message duplicates are canonicalized before admission

`SyncMessage::SyncMessage` runs `canonical_order`. Its candidate map collapses
same-identity, same-payload operations before storing `operations` and
`structural_operations`; `decoded_operation_count` deliberately retains the
raw wire occurrence count for the decoded-operation limit. The existing test
`duplicate-heavy decoded operation limit counts wire operations` proves:

```text
wire operations:       2
message.op_count():    1
limit actual:          2
```

Conflicting same-identity payloads are rejected during this canonicalization.
Consequently, the current public Text path does **not** pass same-message equal
wire duplicates to `prepare_sync`, and the current report does not count those
raw wire occurrences as duplicate deliveries.

The current `duplicate_operations` value therefore counts canonical incoming
operations that match an already-admitted identity, an outer pending identity,
or an earlier candidate in the preparation map. On public `SyncMessage` values,
the last category is normally eliminated by canonicalization. The existing
contract tests cover admitted retransmission (`2` duplicate operations for a
replayed two-operation message) and pending retransmission, but not a raw
same-message duplicate report.

The three quantities must remain separate:

```text
decoded_operation_count = raw decoded wire occurrences; resource-limit input
message.op_count        = canonical unique operation count
canonical_redeliveries  = canonical identities already known to Authority or
                          core pending; delivery evidence
```

A pending identity can be both a canonical redelivery and part of the committed
receipt when a same-message dependency wakes it. That is delivery evidence plus
terminal-result evidence, not a second authority commit.

P2's receipt has unique `already_admitted` identities and pending provenance
arrays. It has no field that directly counts the current delivery. The
`pending_retained` array can also contain retained work affected by the
transition, so it cannot by itself identify duplicate-pending deliveries.

**P3.0 contract:** add the generic core accessor
`pub fn AdmissionReceipt::redelivery_count(self : AdmissionReceipt) -> Int`.
It counts one unique incoming `RawVersion` identity whose matching payload was
already present in Authority or live core pending when admission was prepared.
It includes already-admitted and already-pending identities, including pending
identities that later wake and commit or are later discarded. It excludes
unrelated retained pending, raw equal occurrences removed before Document
admission, and conflicting identities. It must not silently claim to count raw
wire duplicates, and `decoded_operation_count - message.op_count()` must not be
added to `SyncReport::duplicate_operations`.

## 3. Pending API characterization

### `pending_sync_count`

`@text.SyncSession::pending_sync_count` currently reads
`self.doc.pending_sync_records.length()`. The core planner already has a
private `RemoteAdmissionPlanner::pending_count`, but the public `OpLog` surface
only exposes `has_pending() : Bool`. There is no existing public count adapter
for `Document` or `OpLog`.

`moon ide find-references @text.SyncSession::pending_sync_count` found the
Text definition plus contract, recovery, convergence, and peer-integration
uses. These are observable count assertions, not payload access. The count
must continue to represent live core pending membership, including retained
records and not stale order/waiter entries. The fixed P3 adapter is
`pub fn Document::pending_count(self : Document) -> Int`; it is a planner
operation, not a projection read, and remains callable during
`ProjectionRecoveryRequired` without invoking recovery.

### `clear_pending_sync`

`@text.SyncSession::clear_pending_sync` currently assigns an empty array. A
symbol reference search found only the Text definition as a code reference;
the public documentation calls it when intentionally discarding valid queued
work. The Tree and container façades have separate `SyncSession` types and
separate pending implementations; they must not be silently changed by a
Text-only cutover.

The current public signature returns `Unit`, and pending payloads are
intentionally opaque in the migration documentation. The core planner already
has a root-based `reject_pending_dependents` operation that removes a root and
its dependent closure, increments its generation when membership changes, and
compacts stale indexes through the OpLog adapter. It does not currently expose
a clear-all operation or discarded identities.

**P3.0 contract:** preserve the `Unit` signature and define
`clear_pending_sync()` as a core-owned clear-all transition for this private
TextState Document. The producer audit below establishes that Text SyncSession
is the only producer of remote pending membership for this Document. The
transition must:

- remove every live pending identity and its dependent closure;
- remove waiter and ready-queue membership, not just the primary map entry;
- advance planner generation exactly once when live pending membership changes;
- be a no-op that does not advance generation when pending is already empty;
- make existing `PreparedAdmission` values stale after a membership-changing
  clear;
- leave Authority, causal graph, frontier, ProjectionHealth, projection tree,
  cursor, and Text version cache unchanged;
- remain callable during `ProjectionRecoveryRequired` without attempting
  recovery or reading derived projection state;
- prevent cleared operations from reviving when a dependency arrives later;
- allow a new valid admission after clear;
- return no identities, preserving the existing opaque-payload interface.

This is the accepted plan-level contract. A future selective-discard API would
be a separate capability rather than a hidden compatibility queue.

### Producer audit result

The read-only audit fixes the producer scope to case A for the private
`Document` held by `TextState`:

- `TextState.inner` is private (`text/text_doc.mbt:37`), so peer façades and
  direct dependents cannot mutate its planner through that field.
- Text production code uses `inner.insert`/`delete`/`undelete` for local
  authority operations and the current `SyncSession::apply_with_limits` uses
  `inner.apply_remote` only for outer-planner-applicable operations
  (`text/sync.mbt:1272-1300`). Local operations acknowledge admitted local
  identities and may remove/compact a matching planner node, but do not
  register remote pending membership.
- The P3 production call that can register remote pending membership for this
  private Document is Text `SyncSession::apply_with_limits`, after it switches
  to `inner.admit_remote`.
- No other production Text or `peer_sync/text` path has access to `inner`, and
  Text has no production call to `Document::discard_pending_dependents`.
  Remote pending registration is owned by the OpLog admission begin transition
  (`internal/oplog/remote_admission_planner.mbt:1266-1486`); local
  `acknowledge_admitted` is removal/compaction, not a pending producer.

Therefore the compatibility contract is fixed as:

```text
For the private Document owned by TextState,
Text SyncSession is the only producer of remote pending membership.

SyncSession::clear_pending_sync()
  → Document::clear_pending()
  → all live core pending membership for that TextState
```

This does not describe the legacy outer `TextState.pending_sync_records`;
that second owner is removed by P3.

The cross-package API names are fixed for the implementation plan:

```moonbit
pub fn AdmissionReceipt::redelivery_count(
  self : AdmissionReceipt,
) -> Int
pub fn DocumentAdmission::outcome(
  self : DocumentAdmission,
) -> @oplog.AdmissionOutcome
pub fn DocumentAdmission::projection(
  self : DocumentAdmission,
) -> ProjectionStatus
pub fn Document::pending_count(self : Document) -> Int
pub fn Document::clear_pending(self : Document) -> Unit
```

These are read-only/direct-dependent `pub` accessors; none requires `pub(all)`
or exposes mutable collections. Any OpLog adapter behind the Document methods
is package plumbing, not a second Text ownership API. Regenerated `.mbti`
files are part of implementation review.

## 4. Partial and error mapping

The current Text shell constructs a complete `PreparedSync` before the first
per-operation mutation. A current-message preparation failure therefore
leaves the Text document and outer pending array unchanged. The public Text
path does not currently expose P1/P2 `AdmissionOutcome::Partial`; a typed
partial can be exercised only through the package-local P2 failure seam or a
future core failure during the one commit.

P2's `AdmissionOutcome::Partial` retains the committed prefix and the causal
graph error. `Document::admit_remote` projects only the committed prefix when
it is non-empty. The authority is not rolled back. If projection recovery is
required, P2 gives recovery precedence over conversion of the partial result.

P3 must preserve this mapping at the Text seam:

| Typed result | Public Text result |
| --- | --- |
| Complete + `Projected`, `Recovered`, or `Skipped` | `SyncReport` from receipt evidence. |
| Partial with no recovery failure | Existing compatible `TextError` conversion for the causal error; committed prefix and core pending remain authoritative. |
| Any `ProjectionStatus::RecoveryRequired` | `TextError::ProjectionRecoveryRequired`, with recovery precedence over partial conversion. |
| Pre-commit malformed, identity, semantic, stale, consumed, or limit failure | Existing `TextError::SyncFailed`/internal compatibility mapping; no authority or pending mutation. |

The Text error converter already maps `ProjectionRecoveryRequired` to the
retryable public error and maps legacy `PartialRemoteAdmission` through the
existing causal error converter. P3 should reuse that semantic mapping rather
than introduce a Text-specific partial variant.

## 5. Version-cache characterization

`TextState::cached_version` is a cache of the causal version, not projection
health. The current shell invalidates it exactly when
`prepared.applicable` is non-empty, before the first remote mutation. A
replayed or pending-only message keeps the cache warm because the frontier is
unchanged.

The P3 rule should be receipt-based:

```text
receipt.committed().is_empty() → keep the version cache
receipt.committed().is_empty() == false → invalidate once
partial with a committed prefix → invalidate once
projection recovery without a committed operation → do not conflate it with
  causal-version invalidation
```

A recovery-required projection state still blocks ordinary derived reads and
local mutation through the P2 Document guard. That state is independent of
whether the causal version cache needs rebuilding.

## 6. Wire, format, and limit responsibilities

The Text façade must retain:

- exact JSON object fields and schema/format identifiers;
- deterministic canonical serialization and canonical byte encoding;
- RawVersion shape and non-negative identity validation;
- parent/origin structural shape;
- one UTF-16 scalar per insert operation and non-empty insert content;
- receiver policy checks for encoded bytes, decoded wire operation count, and
  parents per operation;
- the public `@sync.Limits` error classes and atomic rejection behavior.

`SyncMessage` construction may continue to canonicalize deterministic message
ordering, but that ordering must not become a second authority or pending
owner. The core admission planner decides applicability and pending replay.
The pending-operation limit must be passed to the core-owned admission
boundary, not checked against an outer pending array.

`export_all` and `export_since` still expand resident history; their H-scan is
a separate export/delta problem and is explicitly outside the P3 ingress
cutover.

## 7. Static current-path baseline

This table is the structural baseline. The pre-cutover dynamic observations
are persisted separately in the [Text ingress baseline](../performance/2026-08-17-egw-p3-text-ingress-baseline.md).
They are single observations rather than a stable benchmark summary; no
before/after improvement claim is made.

| Observation for one current Text apply | Current value |
| --- | --- |
| `get_all_ops()` calls for admission | 1; expands H operations |
| H-sized identity/payload maps | 1 payload map plus 1 known-operation map |
| outer `prepare_sync` calls | 1 |
| Text projection-recovery guard | 1 `prepare_for_mutation` call before preflight |
| Document admission entry guards | `A` through wrapper calls; M for complete ready batches |
| `Document::admit_remote` calls | `A` through `apply_remote([op])`; M for complete ready batches |
| typed `commit_admission` calls | `A` successful one-op admissions; M for complete ready batches |
| per-operation `Document::apply_remote` calls | `A`; M for complete ready batches |
| one-op projection finalizations | up to `A`; M for complete ready batches |
| outer pending owner | 1 `TextState.pending_sync_records` array |
| export H-scan | present, but excluded from P3 ingress work |

The P3.0 benchmark matrix uses the same receiver fixture and measures resident
H values `0 / 1k / 10k / 100k`, incoming M values `1 / 10 / 100`, and complete,
duplicate-only, pending-only, dependency-arrival/drain, and
conflicting-identity cases. Its raw native-release observations and [CSV](../performance/2026-08-17-egw-p3-text-ingress-baseline.csv)
are persisted with the [Text ingress baseline](../performance/2026-08-17-egw-p3-text-ingress-baseline.md).
The run is native-only and uses in-memory `encoded_size=None` messages, so the
fallback JSON serialization/UTF-8 sizing is inside the measured current path.
It does not characterize wasm-gc/JS browser runtime, editor input-to-paint,
main-thread blocking, or Loomark perceived speed. The partial lane is
explicitly unsupported by the current public Text path; P3.3 still needs an
injected-core-failure or model trace for partial.

The structural before/after target is explicit: P3 removes the outer
`prepare_sync`, the per-operation `Document::apply_remote` loop, and its M
one-op typed admissions. P3 retains one message-level `Document::admit_remote`
and one typed commit for the incoming batch.

The baseline does not attribute P2's Document M-boundary measurements to the
Text ingress path. Before/after performance claims require the same fixture,
scenario, runtime, and measurement boundary after P3 cutover.

## Characterization conclusion

The safe next seam is clear but not yet an implementation task:

```text
wire/schema/format/receiver limits
→ one Document::admit_remote(message operations, max_pending)
→ one typed outcome/projection conversion
→ SyncReport or compatible TextError
```

Before deleting the outer lifecycle, plan review must accept the canonical
duplicate count, the core clear-all contract, and the cross-package
`DocumentAdmission`/receipt accessors. No P3 branch, `ready-for-agent` label,
Text production cutover, or Canopy gitlink update is authorized by this report.
