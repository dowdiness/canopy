# EGW P1: typed prepared-admission transition

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/1256>

This plan is the implementation plan for the issue above. The issue must link
back to this plan before implementation starts.

Research record: [`docs/research/2026-08-15-egw-p1-admission-transition-options.md`](../research/2026-08-15-egw-p1-admission-transition-options.md).

**This plan must be reviewed and accepted before a fresh P1 EGW branch is
created from the current `origin/main`.**

## Why

EGW P0 is complete and merged in PR [#118](https://github.com/dowdiness/event-graph-walker/pull/118)
at merge commit
[`99ab590`](https://github.com/dowdiness/event-graph-walker/commit/99ab59012a31abb8454468509dd790be03c3b391).
ADR 0008 is accepted there. P0 establishes core-owned semantic admission over
the retained legacy `@core.Op` payload, but it does not yet make production
admission a single pending-owner, single-authority-transition, or
single-projection-publish path.

The current `PreparedAdmission` already contains more than an operation array:
planned operations, staged representation, discard roots, discarded pending and
staged identities, generation, and single-use state. Its prospective transition
is nevertheless separate from the facts learned while committing. The committed
prefix, retained suffix, duplicates, and partial cause are currently distributed
between the commit return value, `PartialRemoteAdmission`, and mutable planner
state.

P1 makes one admission's ownership transition readable from typed values. It
must distinguish:

- the prospective, generation-bound capability known before authority mutation;
- the actual complete or partial outcome known only after the commit attempt;
- the hard pending-membership precondition that must hold immediately after
  `begin_admission` and therefore before either complete or partial execution.

This is a typed transition boundary, not a new dependency planner and not a
production Canopy cutover.

## Scope

### In

The EGW submodule, starting from the P0 merge on a fresh branch:

- `deps/event-graph-walker/internal/oplog/remote_admission_planner.mbt`
- `deps/event-graph-walker/internal/oplog/oplog.mbt`
- `deps/event-graph-walker/internal/oplog/errors.mbt`
- `deps/event-graph-walker/internal/oplog/*_wbtest.mbt` and related oplog tests
- the intentionally changed EGW `internal/oplog/pkg.generated.mbti`
- `deps/event-graph-walker/text/errors.mbt` for the intentional pending-limit
  error mapping
- the prerequisite, separately merged EGW docs-only amendment to the accepted
  `deps/event-graph-walker/docs/adr/0008-core-owned-batch-remote-admission-over-legacy-op.md`
- package-local ownership, partial-transition, retry, and pending-limit properties

The P1 boundary includes:

- extending `PreparedAdmission` with the complete prospective transition;
- introducing a typed `AdmissionOutcome` and `AdmissionReceipt` for actual
  commit results;
- exact affected-identity accounting for committed, `already_admitted`,
  pending, and discarded membership, with retained/staged provenance and
  duplicate-delivery evidence kept on separate axes;
- an exact pending-membership precondition checked before authority mutation
  and safe for a partial suffix; the current synchronous shell proves the
  bound from planner membership without an independent pending-limit counter;
- a new core capability for typed admission, while preserving the existing
  `commit_remote` compatibility behavior through P2;
- no new planner algorithm: `RemoteAdmissionPlanner` remains the sole owner of
  core pending membership and readiness.

### Out

- `Document` batch-admission shell;
- projection update or publication;
- `SyncSession` changes or removal of its outer pending lifecycle;
- Canopy production-ingress cutover;
- archive or wire schema changes;
- canonical `TextEvent` or position-based authority payload changes;
- `TextReplica`, Persistence Coordinator, Worker replay, or reconnect work;
- public Canopy API redesign;
- Canopy submodule/gitlink changes;
- a new ADR for this phase; a separate EGW docs-only amendment to ADR 0008
  must land before the P1 implementation branch so the accepted decision
  explicitly distinguishes prospective capability from actual outcome.

P1 may intentionally change the EGW internal oplog generated interface and
text error mapping for the new typed capability/limit variant. It must not
widen or otherwise change unrelated Branch/Document or Canopy-facing
interfaces. Every `.mbti` change must be reviewed as an explicit compatibility
decision.

## Current State

The P0 baseline at EGW merge commit `99ab590` provides:

- `OpLog::prepare_remote(incoming, max_pending_after_complete?)` as a
  non-mutating preparation boundary returning `PreparedAdmission`;
- private prepared storage containing planned operations, staged nodes,
  discard roots, discarded-pending and discarded-staged identity sets,
  generation, and single-use `consumed` state;
- `OpLog::begin_admission`, which validates the prepared capability, applies
  the prepared planner transition, advances generation, and consumes the
  capability before the authority commit loop;
- `OpLog::commit_remote`, which commits prepared operations one at a time and
  acknowledges successful identities in the planner;
- `PartialRemoteAdmission`, which carries only the committed prefix and causal
  graph error when a later operation fails;
- the remaining uncommitted suffix in core pending state after a partial
  commit, while mutable planner state also contains retained pending work;
- `StaleAdmission`, `ConsumedAdmission`, and `InvalidAdmission` as lifecycle
  errors that must be decided before authority mutation;
- `PendingForecastExceeded(limit~, predicted~)` as a complete-transition
  forecast, explicitly not a hard post-partial limit;
- `Branch` and `Document` compatibility paths that still consume the legacy
  `commit_remote` result and partial-error shape.

The Canopy submodule pointer is intentionally not at this P0 merge. The local
pointer must not be moved merely to implement or review P1. A P1 implementation
worktree must fetch and verify EGW `origin/main` at or after `99ab590` before
editing.

## Desired State

### 1. Separate prospective capability from actual outcome

`PreparedAdmission` remains a prospective value. It may contain, at minimum:

- commit order and planned operation representations;
- duplicate-delivery evidence detected during preparation, without treating it
  as a canonical owner;
- retained-pending identities already known to survive the transition;
- newly staged identities;
- discarded pending and discarded staged identities, with their provenance;
- generation and any policy revision used for validation;
- the prospective maximum pending membership and its required-pending value;
- single-use state.

It must not claim to contain a committed prefix. The committed prefix is not
knowable until the authority commit loop reaches its failure boundary.

`AdmissionOutcome` is the actual result of one accepted commit attempt. The
proposed shape is:

```moonbit
pub enum AdmissionOutcome {
  Complete(AdmissionReceipt)
  Partial(receipt~ : AdmissionReceipt, error~ : @causal_graph.CausalGraphError)
}
```

`AdmissionReceipt` must expose enough immutable evidence to account for the
transition without inspecting planner internals. It must remain
transition-local rather than copying the complete planner state. The exact MoonBit field
names remain a plan-review decision, but its semantic contents are not optional:

- committed operations and their `RawVersion` identities;
- `already_admitted` identities accepted as authority-owned no-ops;
- `pending_from_transition` identities whose terminal owner is still core
  pending after the actual commit attempt, including the exact retained/staged
  uncommitted suffix; a `duplicate_of_pending` identity appears here only if
  it remains pending after the attempt, never merely because of its arrival
  provenance;
- discarded identities split into `discarded_pending` and `discarded_staged`;
- `pending_before_count` and `pending_after_count`, counting unique live
  pending membership without copying unrelated pending identities;
- non-fallible, receipt-owned `frontier_before` and `frontier_after` snapshots;
- optional duplicate-delivery counts or provenance, kept separate from the
  identity ownership partition.

Conceptually, the receipt storage is equivalent to owning fields such as:

```moonbit
pub struct AdmissionReceipt {
  priv committed : Array[@core.Op]
  priv already_admitted : Array[@core.RawVersion]
  priv pending_from_transition : Array[@core.RawVersion]
  priv discarded_pending : Array[@core.RawVersion]
  priv discarded_staged : Array[@core.RawVersion]
  priv pending_before_count : Int
  priv pending_after_count : Int
  priv frontier_before : @core.Frontier
  priv frontier_after : @core.Frontier
}
```

`pending_from_transition` must preserve retained-versus-staged provenance for
the suffix, whether through separate accessors or an explicitly tagged local
representation. Unrelated retained pending identities are reflected only by
the global counts and white-box planner assertions, not by a receipt-wide
identity snapshot. The receipt is common evidence for both outcome variants;
status and causal failure belong only to `AdmissionOutcome`, so a complete
receipt cannot carry a partial cause.

Receipt fields that contain identities or operations must be defensive,
receipt-owned `Array` snapshots. Accessors may return `ArrayView` values over
those receipt-owned arrays, for example:

```moonbit
pub fn AdmissionReceipt::pending_from_transition(
  self : AdmissionReceipt,
) -> ArrayView[@core.RawVersion]
```

No view over planner-owned mutable storage may escape. Frontier snapshots follow the same rule and must be constructed without
a fallible post-mutation step. Terminal ownership and
staged/retained/discarded provenance are separate views of the same transition,
not overlapping owners.

### Receipt collection ordering

Receipt arrays are deterministic for diagnostics, but their element order is
not part of the P1 contract. Callers must treat identity collections as sets
unless an accessor explicitly documents an ordering guarantee. The commit loop
may still execute `PreparedAdmission::operations()` in prepared order; that
implementation order must not silently become a public receipt-order promise.
This leaves P2 free to change planner collection mechanics without changing
semantic ownership.

### 2. Make partial a normal typed outcome

The new core capability should be shaped as:

```moonbit
pub fn OpLog::commit_admission(
  self : OpLog,
  prepared : PreparedAdmission,
) -> AdmissionOutcome raise OpLogError
```

The name is a proposal for plan review, not permission to add a second commit
algorithm. `AdmissionOutcome::Partial` is a normal returned value because the
authority has advanced and the exact suffix ownership is meaningful. The
following remain pre-mutation errors raised by the capability:

- `StaleAdmission`;
- `ConsumedAdmission`;
- `InvalidAdmission`;
- the hard pending-limit error, using the reviewed `limit~` and
  `required~` vocabulary rather than a complete-only `predicted~` claim.

The compatibility method keeps its existing caller contract through P2:

```moonbit
pub fn OpLog::commit_remote(
  self : OpLog,
  prepared : PreparedAdmission,
) -> Array[@core.Op] raise OpLogError
```

It delegates to the typed capability. A complete outcome returns committed
operations. A partial outcome is translated back to the existing
`PartialRemoteAdmission` error for legacy callers; the new typed path retains
the full receipt. No `Document` or `Branch` migration belongs in P1.

### Close the post-begin error algebra

`commit_admission` has a phase-indexed error boundary:

```text
before begin_admission succeeds / the internal result is Applied:
  lifecycle, structure, and pending-limit failures may raise OpLogError

after begin_admission succeeds with Applied:
  commit_admission returns AdmissionOutcome::Complete or
  AdmissionOutcome::Partial
```

No recoverable `OpLogError` may escape after the planner transition has been
applied or after an authority prefix may have been committed. Prefer a private
post-begin seam equivalent to
`(@core.Op) -> @core.Op raise @causal_graph.CausalGraphError`; if the existing
production adapter still has a wider error type, translate supposedly
impossible variants to an invariant defect at that boundary. The post-begin
commit seam is narrowed to `CausalGraphError`, which becomes
`AdmissionOutcome::Partial`. Any other supposedly impossible internal error is
an invariant defect and must not be exposed as an ordinary recoverable
`OpLogError`; if a real recoverable post-begin condition is discovered, P1 must
add an explicit `AdmissionOutcome` variant before allowing it to escape.

The legacy `commit_remote` wrapper may translate a returned `Partial` outcome
into `PartialRemoteAdmission` after the canonical typed capability has produced
its receipt. That compatibility translation is outside the typed capability's
post-begin guarantee and must not be implemented as an unstructured error from
`commit_admission` itself.

### 3. Validate the pending-membership precondition

Preparation remains non-mutating. It calculates the unique pending membership
that must exist immediately after `begin_admission` applies the discard and
staged-node transition, before the first authority operation is attempted. The
prepared value carries this prospective requirement.

For the current generation, the exact requirement is:

```text
required_pending = count_unique(
  (pending_before - discarded_pending)
  ∪ staged_unique_not_admitted_not_discarded
)
```

`pending_before` is the live planner pending membership before begin.
`staged_unique_not_admitted_not_discarded` contains every unique staged identity
that is not already admitted, already pending, or in the rejection closure.
Because the staged set excludes existing pending identities, the equivalent
shorthand is `live_pending_before - discarded_pending_count +
new_staged_count`, but the set expression is the normative contract. For
`DeferredFast`, the staged count equals the unique planned count; for
`ImmediateGeneral`, it equals the materialized staged-node count and may be
larger than `planned.length()`.

When `max_pending?` is supplied, preparation raises
`PendingLimitExceeded(limit~, required~)` if the requirement exceeds the
bound, without creating a usable capability. At begin, after stale/consumed/
invalid/structure validation and before removing or registering any planner
node, the core revalidates the same generation-bound requirement. A rejected
begin changes neither authority, planner membership, generation, nor pending
policy.

The current lifecycle then obeys:

```text
begin:
  apply discard/register once, leaving pending membership at or below the
  accepted bound

complete:
  all planned identities are acknowledged or duplicate; pending membership
  can only decrease from the begin-after value

partial:
  the exact uncommitted suffix remains in core pending with its provenance;
  pending membership can only decrease from the begin-after value

commit:
  each successful acknowledgement removes one live pending identity; commit
  never adds a new pending identity
```

Therefore the maximum pending membership is immediately after begin and before
the first authority commit. A post-prefix `PendingLimitExceeded` is not an
acceptable design: the hard precondition must be satisfied before authority has
advanced. No mutable pending-limit state or separate planner counter belongs
in P1; a future reentrant or asynchronous shell may revisit that decision with
new evidence.

### 4. Make affected ownership partitions explicit and disjoint

For the unique identities in the transition-local affected domain, the final
partition is:

```text
affected identities =
  committed
  ∪ already_admitted
  ∪ pending
  ∪ discarded

committed, already_admitted, pending, and discarded are pairwise disjoint
```

Their canonical ownership is:

```text
committed        → Authority
already_admitted → Authority
pending          → core pending
discarded        → no owner
```

`already_admitted` is the authority-owned terminal category for an incoming
matching identity. A duplicate of a pending identity is delivery evidence only;
its final ownership is determined by the actual outcome. Delivery evidence may
distinguish:

```text
already-admitted duplicate  → duplicate_of_admitted evidence;
                               terminal identity is already_admitted
pending duplicate           → duplicate_of_pending evidence only;
                               terminal identity is committed, pending, or discarded
same-batch duplicate        → same_batch_duplicate evidence only
```

Duplicate occurrence counts and provenance never create another identity set in
the ownership partition. In particular, a pending duplicate that is awakened
by a dependency in the same admission is placed in `committed` if it commits,
in `pending` only if it remains uncommitted, and in `discarded` if rejection
closure removes it.

`retained`, `staged`, and `discarded` are provenance partitions used to explain
how an affected identity reached its final category; they must not create a
second owner. In particular:

- a committed identity is never also retained or retried;
- an admitted duplicate is not re-committed and is represented in
  `already_admitted` at most once;
- a duplicate of a pending identity is represented in `pending_from_transition`
  only when it remains pending after the commit attempt; if it commits or is
  discarded, it appears only in that terminal category, with duplicate
  provenance kept separately;
- the partial suffix is the exact uncommitted suffix of
  `PreparedAdmission::operations()` and may contain both retained-pending and
  newly staged provenance;
- invalid-root dependents are discarded exactly once;
- unrelated retained pending identities survive unless explicitly in the
  rejection closure;
- no affected identity is lost or assigned two final owners.

## Prerequisite ADR amendment

ADR 0008 is accepted and must not be silently reinterpreted by this Plan. Its
P1 wording currently describes one prepared admission as recording committed,
retained, discarded, duplicate, and partial ownership, while the source-backed
transition boundary proves that a prospective `PreparedAdmission` cannot know
a committed prefix.

Before creating the P1 implementation branch, land a separate EGW docs-only
amendment to ADR 0008 with this meaning:

```text
P1 — typed transition boundary:
PreparedAdmission records the prospective, generation-bound transition.
AdmissionOutcome and AdmissionReceipt record the actual complete or partial
ownership result after the commit attempt.
The boundary owns the hard pending-limit contract.
```

This amendment preserves ADR 0008 as the architecture decision and moves the
prospective/actual distinction into its accepted wording. It is a prerequisite
for implementation, not a new ADR and not a decision to be deferred into the
Plan review.

## Decisions Required at Plan Review

The following decisions are proposed by this plan and must be recorded in the
plan review before implementation:

1. **Value boundary:** accept the strict separation between prospective
   `PreparedAdmission` and actual `AdmissionOutcome`/`AdmissionReceipt`.
2. **Partial algebra:** accept `Partial` as an ordinary typed outcome carrying
   both the receipt and causal failure, while pre-mutation lifecycle and
   pending-limit failures remain errors.
3. **Pending-limit contract:** accept the exact set-based requirement above and the
   begin-time hard precondition. `PendingLimitExceeded(limit~, required~)`
   must be raised before authority mutation; pending membership must be
   monotonic non-increasing after begin, with no stateful pending-limit
   counter in P1.
4. **Limit vocabulary:** rename the optional preparation policy from
   `max_pending_after_complete?` to `max_pending?`, replace the complete-only
   `PendingForecastExceeded(limit~, predicted~)` contract with
   `PendingLimitExceeded(limit~, required~)`, and update its EGW text error
   mapping. If API inventory finds an external caller, retain only a clearly
   named compatibility adapter; never give one label two meanings.
5. **Compatibility lifetime:** keep `commit_remote` as the legacy wrapper
   through P2; do not change Branch, Document, SyncSession, or Canopy callers
   in P1.
6. **Interface delta:** permit only the intentional internal oplog generated
   interface and EGW error-mapping changes; reject unrelated `.mbti` drift.
7. **Receipt shape:** accept transition-local defensive snapshots only:
   committed, `already_admitted`, `pending_from_transition`, discarded
   provenance, global pending before/after counts, and receipt-owned frontier
   snapshots. No complete global pending identity snapshot or planner-owned
   view may escape. Array order is deterministic but non-contractual unless an
   accessor explicitly documents otherwise.

No implementation branch should be created until these decisions are accepted.

## Steps

### P1.0 — Freeze the merged baseline and API evidence

1. Fetch EGW `origin/main` and verify that it contains merge commit `99ab590`
   and the separate docs-only amendment to ADR 0008. Only then create a
   dedicated P1 EGW worktree from that current main; do not start from the
   pre-merge PR head and do not update the Canopy gitlink.
2. Initialize submodules and inspect the package roots and current interfaces:
   `internal/oplog`, `internal/core`, `internal/causal_graph`,
   `internal/branch`, and `internal/document`.
3. Run `moon ide outline`, `peek-def`, and `find-references` for
   `PreparedAdmission`, `OpLog::prepare_remote`, `OpLog::begin_admission`,
   `OpLog::commit_remote`, `PartialRemoteAdmission`, and the generated oplog
   interface. Record the actual existing APIs before defining any new one.
4. Write the first failing ownership, pending-limit, receipt-scope, and
   core-owned-retry tests before changing the transition implementation.

### P1.1 — Model the prospective transition

5. Extend the private `PreparedAdmission` representation only with data that
   is knowable before authority mutation: ordered planned identities,
   duplicate/retained/staged/discarded provenance, generation/policy evidence,
   the exact staged identity set or its equivalent count, and the
   `required_pending` value derived from the set-based contract.
6. Preserve non-mutating `prepare_remote`: it must not advance planner
   generation, alter pending membership, consume a capability, or mutate any
   pending-limit state. Repeated preparation with unchanged state must produce
   equivalent prospective evidence.
7. Add private constructors/validation that make the prepared value internally
   self-consistent and preserve defensive ownership of mutable arrays and
   identity sets. Do not add a live pending-limit planner counter in this
   phase.
8. Define the reviewed `AdmissionReceipt` and `AdmissionOutcome` values. Keep
   actual committed-prefix data out of `PreparedAdmission`.

### P1.2 — Enforce the hard pending-membership precondition

9. Define and test the exact set-based requirement in §3. Include
    first-operation failure, retained existing pending work, every unresolved
    staged node, duplicate identities, and rejection closure; do not substitute
    `planned.length()` for the staged identity set. When `max_pending?` is
    supplied, preparation rejects `required_pending > limit` without creating
    a capability, and begin repeats the generation-bound precondition.
10. At `begin_admission`, validate generation, single-use state, structure,
    and the exact required pending membership against `max_pending?` before
    applying discard/register/consume changes. A rejected begin leaves planner,
    generation, pending membership, and authority unchanged.
11. Register the complete non-discarded staged set once. Complete and partial
    acknowledgements only remove successful identities, so pending membership
    cannot grow after begin. Assert that the begin-after count stays within the
    accepted bound, that suffixes are not lost, and that no identity is counted
    twice; do not add a stateful pending-limit counter.
12. Replace the complete-only forecast API with the reviewed hard-limit
    vocabulary: `max_pending?` and
    `PendingLimitExceeded(limit~, required~)`. Update the EGW text error
    mapping and all P0 forecast tests without changing Document/Branch
    behavior.

### P1.3 — Implement the typed commit capability and wrapper

13. Add `commit_admission` as the one implementation path for the typed result.
    It must commit in prepared order, acknowledge only successful identities,
    and construct receipt-owned snapshots for committed,
    `already_admitted`, `pending_from_transition`, discarded provenance,
    pending before/after counts, and before/after frontiers.
14. On a causal graph failure, return `AdmissionOutcome::Partial` with the
    committed prefix, the exact uncommitted suffix in
    `pending_from_transition`, retained/staged suffix provenance, discard
    evidence, `pending_after_count`, owning frontier snapshot, and causal
    cause. Never authorize retry of the committed prefix.
15. Keep `commit_remote` as a thin compatibility wrapper that maps complete to
    its existing array result and translates a typed partial outcome to the
    existing legacy error shape only after the typed receipt is constructed.
    Do not add a second planner or a second authority commit loop.
16. Narrow the post-begin commit seam to `CausalGraphError` →
    `AdmissionOutcome::Partial`. Any other supposedly impossible internal
    error is an invariant defect, not a recoverable `OpLogError`; add an
    explicit outcome variant before admitting any real recoverable case.
17. Confirm that all semantic decisions, discard closure, pending-limit checks,
    and ownership transfers occur before the first authority mutation or are
    deterministic acknowledgements of an already committed prefix.

### P1.4 — Close exact ownership and lifecycle properties

18. Add complete-admission tests with admitted duplicates, pending duplicates,
    retained pending work, staged arrivals, invalid-root discard, and no
    pending suffix. Split pending-duplicate coverage into two cases:
    an unresolved pending duplicate remains pending, while a pending duplicate
    awakened by a dependency and committed is `committed` with duplicate
    provenance retained only as delivery evidence. Add the discarded case if
    rejection closure invalidates the awakened identity.
19. Add partial tests for zero-prefix failure, middle-prefix failure, and
    n-minus-one-prefix failure. Each test must assert committed operations,
    exact suffix identities, pending-from-transition membership,
    staged/retained provenance, discarded identities, before/after counts,
    required-pending value, and causal cause. White-box assertions may compare the complete
    planner pending maps; the receipt must not copy them.
20. Add core-owned recovery tests after partial admission. The suffix is
    already in core pending: re-plan it with `prepare_remote([])` or with a
    later dependency-bearing batch, and prove that no committed identity is
    attempted twice. Add network-resend idempotence as a separate test; do not
    make reconstructing and resending the receipt suffix the recovery protocol.
21. Add stale, consumed, invalid, and pending-limit-rejection tests. Each must prove
    operation count, frontier, pending membership, generation, required-pending
    calculation, and receipt state are unchanged. Exercise the post-begin seam
    with causal failure and assert that no non-causal recoverable `OpLogError`
    can escape after `Applied`.
22. Add duplicate and conflicting-identity tests that distinguish full payload
    equality from identity reuse. A matching duplicate is an admitted no-op;
    a conflicting identity is rejected before mutation.
23. Add unrelated-retained tests that prove pending work outside the current
    rejection closure remains intact. Compare planner pending membership in
    white-box tests and assert only the before/after counts appear in the
    production receipt.
24. Add a property/model test for the ownership partition:

    ```text
    affected identities = committed ∪ already_admitted ∪ pending ∪ discarded
    committed, already_admitted, pending, and discarded are pairwise disjoint
    committed ∪ already_admitted ⊆ Authority after
    pending ⊆ core pending after
    discarded ∩ (Authority after ∪ core pending after) = {}
    ```

    Track same-batch duplicate occurrences and pending retransmissions only as
    separate delivery evidence; never add them to the ownership partition.

25. Preserve existing planner fixed-point, atomic rejection, alias-mutation,
    and ancestry regressions from P0. The new typed receipt must agree with the
    existing planner state and compatibility wrapper.

### P1.5 — Validate the internal capability without production cutover

26. Run targeted oplog tests and benchmarks, then the full EGW check/test gate.
27. Run `moon fmt` and `moon info`; inspect every generated interface diff.
    Accept only the intentional internal oplog typed-capability/limit delta;
    the new error mapping must not widen unrelated public surfaces.
28. Verify that Branch and Document behavior, SyncSession, wire/archive,
    projection, and the Canopy gitlink are unchanged by the P1 implementation.
    The EGW text error mapping may gain the new pending-limit variant, but no
    text admission behavior or public Canopy API may change.
29. Open the EGW P1 PR only after local validation. Inspect raw CI with
    `gh pr checks <NUMBER>` and do not merge while any required check is
    pending, failing, or unapproved skipped.
30. After merge, record the P1 merge SHA and validation evidence in issue
    #1256. Start P2 only from that updated EGW `main`.

## Acceptance Criteria

- [ ] `PreparedAdmission` remains non-mutating, generation-bound, single-use,
      and contains only prospective transition evidence.
- [ ] A separate typed `AdmissionOutcome` distinguishes complete and partial
      actual transitions; partial carries a common receipt and causal cause as
      a normal value, while receipt status/cause fields cannot contradict the
      enum variant.
- [ ] Before `begin_admission` succeeds with the internal `Applied` result,
      `commit_admission` may raise only pre-mutation `OpLogError` variants.
      After `Applied`, every non-defect exit returns `Complete` or `Partial`;
      no recoverable `OpLogError` can hide an applied planner transition or a
      committed prefix.
- [ ] `pending_from_transition` contains only identities that remain core
      pending after the actual attempt; pending-duplicate provenance never
      determines terminal ownership.
- [ ] `AdmissionReceipt` exposes only transition-local owning evidence:
      committed, `already_admitted`, `pending_from_transition`, discarded
      provenance, unique pending before/after counts, and receipt-owned
      before/after frontier snapshots. It never copies the complete global
      pending identity set or returns a planner-owned view. Identity-array
      order is deterministic but non-contractual unless explicitly documented
      by an accessor.
- [ ] The affected identity partition is exactly
      `committed ∪ already_admitted ∪ pending ∪ discarded`; these sets are
      pairwise disjoint, with committed/already-admitted owned by Authority,
      pending owned by core, and discarded owned by neither. Duplicate
      occurrence evidence is kept on a separate axis.
- [ ] Prepare remains non-mutating, including generation, pending membership,
      pending-limit evidence, and capability consumption.
- [ ] Stale, consumed, invalid, and pending-limit rejection all occur before
      authority mutation and leave authority, planner, generation, pending
      membership, and prepared lifecycle state unchanged.
- [ ] Pending membership uses the exact set-based requirement
      `count_unique((pending_before - discarded_pending) ∪ staged_unique_not_admitted_not_discarded)`,
      is checked before the first authority mutation, and pending membership
      remains monotonically non-increasing after begin.
- [ ] Complete, zero-prefix partial, middle partial, and n-minus-one partial
      cases return exact transition-local receipts and preserve unrelated
      retained pending work, which is verified through white-box planner state.
- [ ] Core-owned recovery re-plans the pending suffix without retrying a
      committed identity; network resend idempotence is tested separately.
- [ ] Matching duplicate delivery is idempotent; conflicting identity reuse is
      rejected atomically.
- [ ] `commit_remote` remains a compatibility wrapper through P2, while the
      typed capability retains receipt information for new callers.
- [ ] Existing Branch/Document behavior and public Canopy interfaces remain
      unchanged; only the EGW text error mapping for the intentional new
      pending-limit variant may change; no production cutover occurs in P1.
- [ ] A separate EGW docs-only amendment to ADR 0008 records the two-value
      boundary before the P1 implementation branch is created; no new ADR is
      created.
- [ ] Only intentionally reviewed EGW internal oplog interface changes and
      pending-limit error-mapping changes exist.
- [ ] EGW targeted tests, `moon check --deny-warn`, `moon test`, formatting,
      interface inspection, and raw PR checks pass.

## Validation

Create a fresh EGW P1 worktree from current `origin/main`, then run from the
EGW root:

```bash
git fetch origin main
git merge-base --is-ancestor 99ab590 origin/main
NEW_MOON_MOD=0 moon ide outline internal/oplog
NEW_MOON_MOD=0 moon ide peek-def PreparedAdmission
NEW_MOON_MOD=0 moon ide peek-def OpLog::prepare_remote
NEW_MOON_MOD=0 moon ide peek-def OpLog::begin_admission
NEW_MOON_MOD=0 moon ide peek-def OpLog::commit_remote
NEW_MOON_MOD=0 moon ide find-references PartialRemoteAdmission
NEW_MOON_MOD=0 moon check --deny-warn
NEW_MOON_MOD=0 moon test
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
git diff --check
git diff -- '*.mbti'
```

Run focused tests for the new oplog ownership/pending-limit files and the existing
planner lifecycle, ancestry, semantic parity, and remote-delivery tests before
running the full suite. Use the repository's supported MoonBit test-selection
syntax rather than inventing a new harness.

The parent Canopy workspace is not part of this P1 validation because the
submodule pointer and production integration remain unchanged. A temporary
post-merge integration worktree may point the submodule at the merged P1 EGW
SHA for compatibility checks, but must not commit the parent gitlink.

Before opening or merging the implementation PR:

```bash
gh pr checks <NUMBER>
```

Every repository-owned required check must be `pass`; no required check may be
pending, failing, or unapproved skipped.

## Risks

- The partial commit boundary is inherently discovered during authority
  execution. Treating the partial prefix as preparation data would make the
  receipt false; keep it exclusively in `AdmissionOutcome`.
- A required-pending calculation based only on complete-after membership, or on
  `planned.length()`, recreates the P0 limitation. The first-operation failure
  case must include every staged node in the set-based begin-after requirement
  before `begin_admission` mutates planner or authority state.
- Retained, staged, duplicate, and discarded are provenance or delivery
  categories, not four additional owners. Receipt construction must enforce the
  disjoint affected-identity partition rather than merely report overlapping
  counters.
- A separate mutable pending-limit state would add invariants without a
  current reentrant admission need. If future execution becomes asynchronous
  or reentrant, revisit this as a new design boundary.
- A wider post-begin callback error can hide an applied planner transition or
  committed prefix if it escapes as ordinary `OpLogError`. Narrow the seam to
  `CausalGraphError`, classify impossible variants as invariant defects, and
  add an outcome variant before admitting a real recoverable case.
- A compatibility wrapper can hide receipt information from legacy callers.
  That is intentional through P2, but the typed capability must remain the
  canonical implementation path so P2 does not need to reconstruct history.
- `PreparedAdmission` and receipt arrays cross package boundaries only through
  reviewed owning/immutable representations. Exposing planner-owned mutable
  collections would violate the state boundary.
- The internal oplog `.mbti` and EGW text error mapping may change for the new
  capability/limit variant. Any unrelated generated-interface change is an API
  regression and must stop the PR.
- The Canopy submodule remains at its existing pointer. Mixing a local P1 EGW
  checkout into a parent commit would accidentally turn an internal capability
  experiment into a production integration change.

## Notes

- Related accepted decision: [ADR 0008 at the P0 merge](https://github.com/dowdiness/event-graph-walker/blob/99ab59012a31abb8454468509dd790be03c3b391/docs/adr/0008-core-owned-batch-remote-admission-over-legacy-op.md).
- Related implementation: [EGW PR #118](https://github.com/dowdiness/event-graph-walker/pull/118).
- The P1 plan deliberately does not introduce a new ADR or reinterpret ADR
  0008. A separate EGW docs-only amendment must land before the implementation
  branch so the accepted decision explicitly states the prospective
  `PreparedAdmission` / actual `AdmissionOutcome` split.
- P2 may move the typed outcome through a Document batch shell and projection
  boundary. P1 must not anticipate that cutover by changing outer pending,
  publication, or Canopy-facing APIs.
- The exact receipt field names and final capability method spelling remain the
  explicit plan-review decisions listed above. The set-based required-pending
  formula, transition-local receipt scope, and no-stateful-counter choice are
  now the recommended result of the alternatives research; implementation must
  update this plan if review rejects any of them.
- The alternatives and source citations are recorded in
  `docs/research/2026-08-15-egw-p1-admission-transition-options.md`.
