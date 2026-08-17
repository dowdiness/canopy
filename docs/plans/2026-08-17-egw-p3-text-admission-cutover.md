# EGW P3: Text façade admission cutover

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/1256>

The issue and this plan are reciprocal references. This document is a **draft
plan only**. It is not implementation authorization and must not be treated as
`ready-for-agent` work.

Related characterization: [EGW P3.0 Text admission characterization](../research/2026-08-17-egw-p3-text-admission-characterization.md).

Related accepted decision: [EGW ADR 0008 — core-owned batch remote admission over legacy operations](https://github.com/dowdiness/event-graph-walker/blob/91aaffc6679b2e1864b80ef6cc505d1d3b9aa548/docs/adr/0008-core-owned-batch-remote-admission-over-legacy-op.md).

P2 is squash-merged in EGW at
[`91aaffc6679b2e1864b80ef6cc505d1d3b9aa548`](https://github.com/dowdiness/event-graph-walker/commit/91aaffc6679b2e1864b80ef6cc505d1d3b9aa548).
The reviewed PR-head and merge commit have identical content-tree SHA
`abf16198183df4d145086bcad9afd0f8237bc3d4`. The Canopy
`deps/event-graph-walker` gitlink remains unchanged.

**Status:** P3.0 characterization complete; docs-only plan draft in review;
implementation not started. This document is not implementation authorization.

```text
P0: ACCEPTED / MERGED
P1: ACCEPTED / MERGED
P2: ACCEPTED / MERGED
P2 merge: 91aaffc6679b2e1864b80ef6cc505d1d3b9aa548
P3: PLAN IN REVIEW
P3 implementation: NOT STARTED
Canopy gitlink: unchanged
```

## Why

P2 established the Document-owned admission seam:

```text
M operations
→ one prepare
→ one typed commit
→ at most one projection finalization
```

The Text façade still owns a second admission lifecycle. Its current
`SyncSession::apply_with_limits` expands resident history, reconstructs an
H-sized identity/payload view, merges an outer pending array with the incoming
message, runs a second dependency planner, and calls `Document::apply_remote`
for each applicable operation. It then replaces the outer pending array.

This duplication is not only a performance concern. It gives two modules a
claim over causal applicability, pending membership, duplicate evidence, and
partial failure. Removing it without first freezing the public Text contract
could silently change `SyncReport`, pending visibility, receiver limits, or
retry behavior.

The P3 goal is a deep Text adapter: a small wire and compatibility interface
with the admission complexity hidden behind one Document seam. The Text
module retains format and policy compatibility; EGW core remains the sole
owner of authority, causal validation, pending membership, and pending replay.

## Scope

### In

- Text façade `SyncSession::apply_with_limits` and its compatibility wrappers.
- One call to `Document::admit_remote` for one incoming message.
- Cross-package access to the P2 typed `DocumentAdmission` result, only as
  needed to reconstruct the existing Text report and error interface.
- Core-owned pending count and an accepted clear-pending capability.
- Exact duplicate-delivery evidence required for `SyncReport` compatibility.
- Receiver wire/schema/format/limit validation that does not own admission.
- Text version-cache invalidation based on committed receipt evidence.
- Red tests, differential traces, and an H/M ingress benchmark matrix.
- Text and `peer_sync/text` compatibility validation.

### Out

- Tree and container façade cutovers. They have distinct `SyncSession`,
  `SyncReport`, wire, and pending implementations.
- `TextReplica` or another aggregate façade.
- Position-based canonical `TextEvent` payloads.
- Wire/archive migration or compatibility lifting.
- `export_all`/`export_since` H-scan optimization.
- Plain projection replacement, transient materializers, or editor changes.
- A generic planner extraction.
- Canopy submodule/gitlink changes.
- A P3 branch or `ready-for-agent` label before plan acceptance.

## Current State

The source of truth is merged EGW main at
`91aaffc6679b2e1864b80ef6cc505d1d3b9aa548`.

### Current Text module

`text/sync.mbt` defines the public `SyncReport`, private `PreparedSync`,
private `SyncCandidate`, and `SyncSession`. The current apply shell is:

```text
prepare_for_admission()
→ message limits and outer prepare_sync
→ TextState.inner.get_all_ops()
→ outer pending array copy
→ per-applicable Document::apply_remote
→ outer pending array replacement
→ SyncReport
```

`prepare_sync` is a legitimate functional core for the old adapter, but it is
the wrong ownership seam after P2. It repeats identity maps, dependency
planning, pending cleanup, and semantic checks already owned by OpLog's
`RemoteAdmissionPlanner`.

The strict `SyncMessage` constructor remains useful: it validates structure,
canonicalizes deterministic message order, and retains raw decoded operation
count for receiver limits. P3 must retain this wire work without treating its
canonical order as authority commit order or pending ownership.

### Current P2 core module

`Document::admit_remote` performs one typed OpLog prepare/commit and projects
`receipt.committed()` once when non-empty. `AdmissionReceipt` exposes committed
operations, unique already-admitted identities, pending provenance, discarded
identities, pending counts, and before/after frontiers. `ProjectionStatus`
records skipped, projected, recovered, and recovery-required derived state.

The current cross-package seam is incomplete for Text: `DocumentAdmission`'s
fields are private to `internal/document`, while the public `DocumentAdmission`
type has no accessor for its `AdmissionOutcome` or `ProjectionStatus`.
`OpLog::has_pending()` is public, but pending count and clear-all are not.
These are P3.1 API-closure candidates, not reasons to recreate a Text planner.

## Desired State

For one Text message, the imperative shell should be:

```text
wire decode / structural validation / receiver limits
→ one Document::admit_remote(message operations, max_pending)
→ one typed outcome + projection-status conversion
→ SyncReport or compatible TextError
```

Observable invariants:

- No `get_all_ops()` call occurs in the admission path.
- No outer pending array or Text-owned pending planner exists.
- No H-sized admission map is built by Text.
- `Document::admit_remote` is called once per message.
- The typed authority commit is called once per message.
- Projection finalization is attempted at most once, and only for a non-empty
  committed receipt view.
- Committed prefixes remain authoritative on partial outcomes.
- Pending suffixes remain in core and are not projected.
- Invalid current input rejects atomically before authority mutation.
- `pending_sync_count()` reports live core pending membership.
- `clear_pending_sync()` has an explicit core-owned discard contract.
- `TextError::ProjectionRecoveryRequired` retains priority over partial-error
  conversion.
- The Text version cache is invalidated once only when committed operations are
  non-empty.
- Export history scans remain unchanged and are not part of the P3 claim.

## P3.0 — Contract characterization and acceptance questions

P3.0 is complete only when plan review accepts the following contracts.

### A. `SyncReport` and the three distinct counts

Preserve the existing public accessors and use these separate quantities:

```text
decoded_operation_count
  raw decoded wire operation count before canonicalization;
  receiver resource-limit input

message.op_count
  canonicalized unique operation count delivered by SyncMessage

canonical_redeliveries
  canonical incoming identities already known to Authority or core pending;
  delivery evidence, not an ownership set
```

`decoded_operation_count` and `message.op_count` must remain distinct. For an
equal same-identity duplicate in one JSON message, the raw count is `2` while
`message.op_count()` is `1`; the raw count consumes the decoded-operation
limit, but the removed occurrence is not a duplicate delivery. If the single
canonical operation is already known locally or in core pending,
`canonical_redeliveries` is `1`.

For complete outcomes, the public report mapping is:

```text
applied_operations = receipt.committed().length()
pending_operations = receipt.pending_after_count()
duplicate_operations = canonical_redeliveries
```

`canonical_redeliveries` is independent of terminal ownership. A pending
operation may be re-delivered and become applicable after its dependency is
included in the same transition; its identity may then contribute to both
`duplicate_operations` and `applied_operations`. This is not double commit;
it is delivery evidence plus committed-result evidence.

The P3.1 option is a core-owned receipt field named
`redelivered()`/`redelivery_count()` (final name requires review), counting one
canonical incoming operation classified as an already-admitted or pending
re-delivery. It must not claim to count raw wire duplicates. Never compute
`duplicate_operations` as
`decoded_operation_count - message.op_count()`; that would change the public
meaning and mix resource-limit evidence with admission delivery evidence.
Unique identity arrays alone cannot identify duplicate-pending deliveries when
other retained pending records are present.

### B. `pending_sync_count`

Change the implementation behind the existing public method, not its meaning:

```text
SyncSession::pending_sync_count()
  → Document/OpLog live pending membership count
```

The count must exclude stale order, waiter, and ready-queue tombstones. It must
include retained pending identities after a partial or complete transition.
The existing `RemoteAdmissionPlanner::pending_count` is a source-verified
private candidate; the package needs a narrow public OpLog/Document adapter.

### C. `clear_pending_sync`

Preserve the existing `Unit` signature and opaque-payload interface. Before
adding the adapter, audit every producer of Document-local pending state and
prove that Text sync is the only producer. If another producer exists, the
capability must be scoped to the pending class required by this compatibility
method; “clear all core pending” and “clear Text sync pending” are not
interchangeable contracts.

For the Text-owned pending class, the accepted core transition must:

- remove every live pending identity in one transition, including its
  dependent closure;
- remove associated waiter and ready-queue membership, not just the primary
  map entry;
- advance planner generation;
- make every existing `PreparedAdmission` stale and reject it;
- leave Authority, causal graph, frontier, projection, and Text version cache
  unchanged;
- prevent cleared operations from reviving when a dependency arrives later;
- allow a new valid admission after the clear to succeed;
- expose no discarded payload or identity from this compatibility method.

The count after clear must be live membership, not stale index cardinality.
This is a recommendation awaiting acceptance. It must not be implemented by
retaining a hidden Text array. A future selective-discard API would be a new
capability with explicit evidence, not part of this migration.

### D. Wire and receiver limits

Retain exact schema/format fields, strict object-field checks, RawVersion
shape validation, UTF-16/single-scalar structural validation, deterministic
serialization, encoded-byte limits, decoded-wire-operation limits, and
parents-per-operation limits. Keep the existing `@sync.Failure` classes and
atomic rejection behavior.

The pending limit must be supplied to `Document::admit_remote` so that the
core prospective transition enforces it against the complete core pending
membership. Text may still perform M-sized receiver policy checks; it must not
use them to decide causal applicability or pending ownership.

### E. Partial/error mapping

Keep `SyncSession::apply` returning `SyncReport raise TextError`.
`SyncReport` is a complete-outcome result; partial outcomes remain represented
by the existing `TextError` path rather than a new partial report variant.

- Complete typed outcome with `Skipped`, `Projected`, or `Recovered` status:
  return `SyncReport` from receipt evidence.
- Partial typed outcome without recovery failure: preserve the committed
  prefix, retain the core pending suffix, invalidate the version cache once if
  the prefix is non-empty, and map the causal cause through the existing
  compatible Text error path. Do not invent report counts for the partial
  result.
- Any `RecoveryRequired` projection status: raise
  `TextError::ProjectionRecoveryRequired` before converting a partial cause.
- Pre-commit malformed, identity, semantic, stale, consumed, and limit
  failures: preserve existing `TextError` classifications and leave authority
  and pending membership unchanged.

No new public partial report variant is introduced while the existing Text
signature remains in force.

### F. Version cache

Use `receipt.committed()` as the only causal invalidation signal:

```text
empty committed view → cache may remain ready
non-empty committed view → invalidate once
partial with committed prefix → invalidate once
pending-only / duplicate-only → no causal invalidation
```

Projection recovery remains a Document derived-state concern. It must not be
mistaken for a causal version change.

## P3.1 — Core evidence/API closure

After P3.0 acceptance, add only the smallest missing interfaces:

1. Add receipt-owned canonical redelivery evidence if the accepted report
   mapping cannot be derived from existing public fields. This is delivery
   evidence and must not be an owner set or raw decoded-duplicate count.
2. Add read-only `DocumentAdmission` accessors for typed outcome and projection
   status. Do not expose mutable arrays; reuse `AdmissionReceipt`'s immutable
   views and existing outcome variants.
3. Add a read-only pending count adapter from OpLog through Document.
4. Add one core-owned clear-all pending capability with the generation,
   waiter/ready cleanup, stale-prepared rejection, no-revival, and new-admission
   behavior specified above.

Existing API First checks before adding each symbol:

- `NEW_MOON_MOD=0 moon ide outline internal/document`
- `NEW_MOON_MOD=0 moon ide outline internal/oplog`
- `NEW_MOON_MOD=0 moon ide doc "AdmissionReceipt"`
- `NEW_MOON_MOD=0 moon ide find-references "@text.SyncSession::clear_pending_sync"`
- `NEW_MOON_MOD=0 moon ide find-references "@text.SyncSession::pending_sync_count"`
- `NEW_MOON_MOD=0 moon ide peek-def "@oplog.RemoteAdmissionPlanner::pending_count"`

Candidate reuse is source-verified: `RemoteAdmissionPlanner::pending_count`,
`RemoteAdmissionPlanner::reject_pending_dependents`,
`OpLog::has_pending`, `AdmissionReceipt::pending_after_count`, and
`Document::admit_remote`. The new helper/API responsibility must be limited to
cross-package evidence or clear-all ownership; no new low-level planner is
allowed.

Any public method or receipt-field change requires regenerated `.mbti` files
and a reviewed diff. The generated interfaces are not hand-edited.

## P3.2 — Text façade cutover

Change only the Text ingress implementation after P3.1 is accepted.

1. Keep `prepare_for_admission` as the Document recovery guard.
2. Keep only wire/receiver boundary work in the Text shell: exact JSON fields,
   `SyncMessage::from_json_string`, `SyncSession::decode_json`,
   `SyncMessage::to_json_string`, `SyncMessage::to_canonical_bytes`, strict
   structural validation, `validate_insert_scalar`, per-operation parent
   limits, encoded-byte limits, decoded-operation limits, and
   `map_sync_failure`. `SyncSession::export_all` and `export_since` retain
   their history scans as a separate export concern.
3. Pass `message.operations` (the constructor's canonical operation array) and
   `limits.max_pending_operations()` to one `Document::admit_remote` call.
4. Convert the typed result to `SyncReport` or `TextError` using the accepted
   receipt and canonical-redelivery rules above.
5. Invalidate `cached_version` once based on the committed view.
6. Delegate `pending_sync_count` and `clear_pending_sync` to the core-owned
   adapters.
7. Remove the Text admission owner after differential coverage is green:
   `pending_sync_records`, `local_payloads`, `known_ops`, `SyncCandidate`,
   `ApplicableOp`, `ParsedCandidate`, `PreparedSync`, `prepare_sync`, the
   outer Kahn admission ordering, and the per-applicable `apply_remote` loop.
   `canonical_order` may remain only as the deterministic wire/message
   canonicalizer; it must not be called as a second authority planner.
8. Keep `apply_remote`/legacy compatibility only where it is a separate
   documented compatibility surface; the Text message path must not call it
   per operation.

The old algorithm may be retained temporarily as a test-only oracle during
P3.3, but it must not remain a second production owner or a hidden fallback.

## P3.3 — Differential and performance closure

### Red tests before implementation

Add tests in the owning packages for:

- complete message: one Document admission and report applied count equal to
  committed count;
- already-admitted retransmission: exact duplicate count;
- pending retransmission and same-message canonicalization: exact accepted
  duplicate contract, including decoded-wire limit behavior;
- dependency arrival: first message becomes core pending, second message drains
  core pending, and no outer pending array exists;
- current invalid message: atomic rejection with no authority or pending change;
- retained-pending invalid root: root and dependent closure discarded while an
  unrelated current operation commits;
- pending limit: core hard limit, including retained plus staged membership;
- zero-prefix and middle-prefix partial outcomes: committed prefix retained,
  suffix pending, retry does not recommit the prefix;
- `pending_sync_count`: live core count before/after every transition;
- `clear_pending_sync`: accepted clear-all closure, unchanged frontier, stale
  prepared-admission rejection, and no hidden outer state;
- projection recovery: `RecoveryRequired` wins over partial conversion;
- version cache: only non-empty committed receipts invalidate it;
- wire/schema/format/limit compatibility;
- `peer_sync/text` report and error classification;
- structure counters: no `get_all_ops`, no outer `prepare_sync`, one
  `Document::admit_remote`, one typed commit, at most one finalization, and no
  per-operation `apply_remote`.

### H/M baseline and after matrix

The benchmark must use the same receiver fixture for before and after:

```text
resident H: 0 / 1k / 10k / 100k
incoming M: 1 / 10 / 100
scenarios: complete, duplicate-only, pending-only,
           dependency arrival/drain, conflicting identity, partial
```

Record:

- `get_all_ops` calls and expanded history operations;
- outer `prepare_sync` calls;
- Document prepare/admit calls;
- typed commit calls;
- batch projection finalizations and per-operation projection calls;
- pending before/after;
- end-to-end time under the same runtime and release mode.

The current baseline's static structure is recorded in the P3.0
characterization. The pre-cutover native-release observations and [raw
CSV](../performance/2026-08-17-egw-p3-text-ingress-baseline.csv) are persisted
with the [Text ingress baseline](../performance/2026-08-17-egw-p3-text-ingress-baseline.md).
The baseline is single-sample characterization evidence, not a stable
benchmark summary. It uses native release only; it does not prove wasm-gc/JS
browser runtime, editor input-to-paint, main-thread blocking, or Loomark
perceived speed. The probe constructs in-memory messages with
`encoded_size=None`, so the current path includes the fallback
`to_json_string()`/UTF-8 size calculation; the after-path must use the same
boundary or publish a paired known-size lane. Dynamic before/after timings must
use the same fixture and measurement boundary; no P2 Document M-boundary
number may be presented as a Text ingress result. The partial lane requires
an explicit injected-core-failure or model trace because the current public
Text path has no ordinary typed partial result.

`export_all` and `export_since` H-scans remain unchanged. Any optimization of
those export paths requires a separate issue and separate evidence.

## Acceptance Criteria

- [ ] P3.0 characterization is reviewed and the decoded-count,
      canonical-op-count, canonical-redelivery, pending-count, and clear-all
      contracts are accepted.
- [ ] `SyncReport` values remain compatible for complete, duplicate, pending,
      dependency-arrival, and partial/error traces; raw same-message duplicates
      are not added to `duplicate_operations`.
- [ ] Core owns all live pending membership; Text has no second pending array
      or planner.
- [ ] Cross-package typed admission evidence is read-only and has no mutable
      collection escape.
- [ ] One Text message invokes one Document admission and one typed commit;
      projection finalization is zero or one according to committed evidence.
- [ ] Current invalid and limit failures remain atomic.
- [ ] Partial committed prefixes and pending suffixes survive retry without
      duplicate authority commits.
- [ ] Projection recovery errors retain their precedence and retryability.
- [ ] Text version-cache invalidation follows receipt committed evidence.
- [ ] Wire/schema/format/receiver-limit behavior is unchanged.
- [ ] Differential and H/M benchmark evidence is recorded on the same fixture.
- [ ] No `export_all`/`export_since` H-scan, wire/archive, Tree/container,
      editor, or Canopy gitlink change is included.

## Validation

Implementation validation, after plan acceptance and a fresh EGW main-based
branch:

```bash
cd <egw-module-root>
NEW_MOON_MOD=0 moon check --deny-warn
NEW_MOON_MOD=0 moon test
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
git diff --check
git diff -- '*.mbti'
```

Run the affected package checks during the edit loop, then the repository's
final validation gate for each affected EGW package. For this docs-only
planning step, no MoonBit source or generated interface was changed. Run
Markdown/documentation checks available in the Canopy checkout before
publication; the `deps/loom/check-docs.sh` check applies to Loom docs, not
these EGW plan/research files.

## Risks

- **Report drift:** Receipt ownership sets do not automatically preserve the
  old delivery-count semantics. The three-count distinction and canonical
  redelivery field must be tested before removing the outer planner.
- **Clear ambiguity:** A Unit-returning clear method can hide a large closure
  transition. The core generation and dependent-discard behavior must be
  explicit, and no compatibility array may remain.
- **Partial visibility:** A typed partial outcome advances authority before
  returning a Text error. The committed prefix, pending suffix, cache, and
  projection status must be compared together.
- **Cross-package API drift:** `DocumentAdmission` accessors and receipt fields
  widen internal interfaces and require `.mbti` review.
- **Benchmark contamination:** Setup work, export H-scans, and P2's Document
  M-boundary can invalidate a Text-ingress claim. The harness must isolate the
  admission boundary and publish its measurement boundary.
- **Scope expansion:** Tree/container, wire/archive, TextEvent, editor, and
  Canopy gitlink work are separate cuts and remain blocked.

## Notes

- The P2 branch/worktree is retained only as clean historical evidence and is
  not a P3 implementation base.
- P3 must start from fresh current EGW main only after this plan is accepted.
- The issue remains open; `ready-for-agent` must remain absent until contract
  review completes.
- The Canopy gitlink is updated only after the EGW P3 implementation has
  merged and Canopy integration validation is a separate accepted cut.
