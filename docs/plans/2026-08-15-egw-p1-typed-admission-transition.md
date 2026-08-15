# EGW P1: typed prepared-admission transition

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/1256>

This plan is the implementation plan for the issue above. The issue must link
back to this plan before implementation starts.

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
- the hard pending capacity needed before either complete or partial execution.

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
- package-local ownership, partial-transition, retry, and capacity properties

The P1 boundary includes:

- extending `PreparedAdmission` with the complete prospective transition;
- introducing a typed `AdmissionOutcome` and `AdmissionReceipt` for actual
  commit results;
- exact identity-level accounting for committed, duplicate, retained,
  staged, and discarded membership;
- a hard pending-capacity reservation that is checked before authority
  mutation and remains safe for a partial suffix;
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
- a new ADR for this phase.

P1 may intentionally change the EGW internal oplog generated interface for the
new typed capability. It must not widen or otherwise change unrelated
Branch/Document/Text or Canopy-facing interfaces. Every `.mbti` change must be
reviewed as an explicit compatibility decision.

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
- duplicate identities detected during preparation;
- retained-pending identities already known to survive the transition;
- newly staged identities;
- discarded pending and discarded staged identities, with their provenance;
- generation and any policy revision used for validation;
- the prospective maximum pending membership and its capacity requirement;
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
attempt without inspecting planner internals. The exact MoonBit field names
remain a plan-review decision, but its semantic contents are not optional:

- committed operations and their `RawVersion` identities;
- duplicate identities accepted as already-admitted no-ops;
- the complete pending-after identity view, including unrelated retained work;
- discarded identities, partitioned by retained-pending versus staged origin
  where that provenance matters;
- the staged identities that became the uncommitted partial suffix;
- the before/after frontier needed to prove authority movement;
- complete versus partial status, with the causal graph failure on `Partial`.

Arrays returned in a receipt must be owning or immutable views according to the
EGW API convention; no mutable planner collection may escape.

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
- the hard pending-capacity error, using the reviewed `limit~` and
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

### 3. Reserve pending capacity for both completion paths

Preparation remains non-mutating. It calculates the maximum pending membership
that can be required by any permitted commit result, including the worst case
where the first authority operation fails and the whole planned suffix remains
pending. The prepared value carries this prospective requirement.

At the begin transition, after stale/consumed/invalid validation and before any
authority mutation, the core atomically checks and records the capacity needed
for either complete or partial execution. The transition must then obey:

```text
complete:
  release capacity that is no longer needed

partial:
  transfer the exact uncommitted suffix's capacity to core pending

rejected before mutation:
  change neither authority, planner membership, generation, nor capacity
```

The accounting must count unique pending membership rather than operation
attempts. It must account for existing retained pending identities, new staged
identities, duplicates, and discard closure. The exact formula and internal
reservation representation are plan-review items, but a post-prefix
`PendingLimitExceeded` is not an acceptable design: capacity failure must not
be discovered after authority has advanced.

### 4. Make ownership partitions explicit and disjoint

For every identity delivered by an admission attempt, the final ownership
partition is exactly one of:

```text
Authority
core pending
duplicate of an admitted identity
discarded / rejected
```

`retained`, `staged`, and `discarded` are provenance partitions used to explain
how a prepared identity reached its final category; they must not create a
second owner. In particular:

- a committed identity is never also retained or retried;
- a duplicate is not re-committed and is not counted as pending;
- a partial suffix is exactly the uncommitted staged identities that are now
  core pending;
- invalid-root dependents are discarded exactly once;
- unrelated retained pending identities survive unless explicitly in the
  rejection closure;
- no delivered identity is lost or present in two ownership sets.

## Decisions Required at Plan Review

The following decisions are proposed by this plan and must be recorded in the
plan review before implementation:

1. **Value boundary:** accept the strict separation between prospective
   `PreparedAdmission` and actual `AdmissionOutcome`/`AdmissionReceipt`.
2. **Partial algebra:** accept `Partial` as an ordinary typed outcome carrying
   both the receipt and causal failure, while pre-mutation lifecycle and
   capacity failures remain errors.
3. **Capacity contract:** accept a worst-case pre-mutation reservation covering
   both complete and partial suffixes, and settle the exact required-capacity
   formula and `PendingLimitExceeded(limit~, required~)` spelling.
4. **Compatibility lifetime:** keep `commit_remote` as the legacy wrapper
   through P2; do not change Branch, Document, SyncSession, or Canopy callers
   in P1.
5. **Interface delta:** permit only the intentional internal oplog generated
   interface change for the typed capability and receipt; reject unrelated
   `.mbti` drift.
6. **Receipt shape:** settle the exact field names and whether identity
   collections are arrays, immutable views, or another owning representation.

No implementation branch should be created until these decisions are accepted.

## Steps

### P1.0 — Freeze the merged baseline and API evidence

1. Fetch EGW `origin/main` and verify that it contains merge commit `99ab590`.
   Create a dedicated P1 EGW worktree from that current main; do not start from
   the pre-merge PR head and do not update the Canopy gitlink.
2. Initialize submodules and inspect the package roots and current interfaces:
   `internal/oplog`, `internal/core`, `internal/causal_graph`,
   `internal/branch`, and `internal/document`.
3. Run `moon ide outline`, `peek-def`, and `find-references` for
   `PreparedAdmission`, `OpLog::prepare_remote`, `OpLog::begin_admission`,
   `OpLog::commit_remote`, `PartialRemoteAdmission`, and the generated oplog
   interface. Record the actual existing APIs before defining any new one.
4. Write the first failing ownership and capacity tests before changing the
   transition implementation.

### P1.1 — Model the prospective transition

5. Extend the private `PreparedAdmission` representation only with data that
   is knowable before authority mutation: ordered planned identities,
   duplicate/retained/staged/discarded provenance, generation/policy evidence,
   and the worst-case pending-capacity requirement.
6. Preserve non-mutating `prepare_remote`: it must not advance planner
   generation, alter pending membership, consume a capability, or reserve live
   capacity. Repeated preparation with unchanged state must produce equivalent
   prospective evidence.
7. Add private constructors/validation that make the prepared value internally
   self-consistent and preserve defensive ownership of mutable arrays and
   identity sets.
8. Define the reviewed `AdmissionReceipt` and `AdmissionOutcome` values. Keep
   actual committed-prefix data out of `PreparedAdmission`.

### P1.2 — Add the hard capacity transition

9. Define the unique-membership calculation for the maximum pending state over
   every commit prefix, including first-operation failure, retained existing
   pending work, newly staged work, duplicate identities, and rejection
   closure.
10. At `begin_admission`, validate generation, single-use state, structure,
    and required capacity before applying discard/register/consume changes.
    A rejected begin leaves planner, generation, capacity, and authority
    unchanged.
11. Transfer the prospective capacity to the actual transition exactly once.
    Complete releases unused capacity; partial transfers capacity for the
    exact suffix retained by the planner. Add assertions preventing capacity
    leaks, double release, and post-mutation capacity failure.
12. Replace the complete-only forecast contract with the reviewed hard-limit
    error semantics. Keep the compatibility mapping explicit if the error
    variant changes.

### P1.3 — Implement the typed commit capability and wrapper

13. Add `commit_admission` as the one implementation path for the typed result.
    It must commit in prepared order, acknowledge only successful identities,
    and construct the receipt from the exact prefix, suffix, duplicate,
    retained, staged, and discarded partitions.
14. On a causal graph failure, return `AdmissionOutcome::Partial` with the
    committed prefix, exact pending-after view, staged-to-pending suffix,
    discard evidence, and causal cause. Never authorize retry of the committed
    prefix.
15. Keep `commit_remote` as a thin compatibility wrapper that maps complete to
    its existing array result and partial to the existing legacy error shape.
    Do not add a second planner or a second authority commit loop.
16. Confirm that all semantic decisions, discard closure, capacity checks, and
    ownership transfers occur before the first authority mutation or are
    deterministic acknowledgements of an already committed prefix.

### P1.4 — Close exact ownership and lifecycle properties

17. Add complete-admission tests with duplicates, retained pending work, staged
    arrivals, invalid-root discard, and no pending suffix.
18. Add partial tests for zero-prefix failure, middle-prefix failure, and
    n-minus-one-prefix failure. Each test must assert committed operations,
    exact suffix identities, pending-after membership, staged/retained
    provenance, discarded identities, capacity, and causal cause.
19. Add retry-after-partial tests. Re-prepare only the exact pending suffix,
    complete it, and prove that no committed identity is attempted twice.
20. Add stale, consumed, invalid, and capacity-rejection tests. Each must prove
    operation count, frontier, pending membership, generation, reservation,
    and receipt state are unchanged.
21. Add duplicate and conflicting-identity tests that distinguish full payload
    equality from identity reuse. A matching duplicate is an admitted no-op;
    a conflicting identity is rejected before mutation.
22. Add unrelated-retained tests that prove pending work outside the current
    rejection closure remains intact and is represented in the pending-after
    view.
23. Add a property/model test for the ownership partition:

    ```text
    delivered identities = Authority ∪ core-pending ∪ Duplicate ∪ Discarded
    these sets are pairwise disjoint
    every committed identity is in Authority exactly once
    every retained suffix identity is in core pending exactly once
    ```

24. Preserve existing planner fixed-point, atomic rejection, alias-mutation,
    and ancestry regressions from P0. The new typed receipt must agree with the
    existing planner state and compatibility wrapper.

### P1.5 — Validate the internal capability without production cutover

25. Run targeted oplog tests and benchmarks, then the full EGW check/test gate.
26. Run `moon fmt` and `moon info`; inspect every generated interface diff.
    Accept only the intentional internal oplog typed-capability delta.
27. Verify that Branch, Document, Text, SyncSession, wire/archive, projection,
    and Canopy gitlink files are unchanged by the P1 implementation.
28. Open the EGW P1 PR only after local validation. Inspect raw CI with
    `gh pr checks <NUMBER>` and do not merge while any required check is
    pending, failing, or unapproved skipped.
29. After merge, record the P1 merge SHA and validation evidence in issue
    #1256. Start P2 only from that updated EGW `main`.

## Acceptance Criteria

- [ ] `PreparedAdmission` remains non-mutating, generation-bound, single-use,
      and contains only prospective transition evidence.
- [ ] A separate typed `AdmissionOutcome` distinguishes complete and partial
      actual transitions; partial carries a receipt and causal cause as a
      normal value.
- [ ] `AdmissionReceipt` exposes exact identity-level evidence for committed,
      duplicate, pending-after, staged, retained, and discarded membership,
      including the before/after frontier needed by callers.
- [ ] The final ownership partition for every delivered identity is exactly one
      of Authority, core pending, admitted duplicate, or discarded; no identity
      is lost or dual-owned.
- [ ] Prepare remains non-mutating, including generation, pending membership,
      live capacity, and capability consumption.
- [ ] Stale, consumed, invalid, and pending-capacity rejection all occur before
      authority mutation and leave authority, planner, generation, capacity,
      and prepared lifecycle state unchanged.
- [ ] Capacity is checked/reserved before the first authority mutation for the
      worst complete or partial pending membership; partial suffix retention
      cannot fail later for lack of capacity.
- [ ] Complete, zero-prefix partial, middle partial, and n-minus-one partial
      cases return exact receipts and preserve unrelated retained pending work.
- [ ] Retrying a partial suffix never retries a committed identity and ends
      with the exact suffix either in Authority, as a duplicate, or discarded.
- [ ] Matching duplicate delivery is idempotent; conflicting identity reuse is
      rejected atomically.
- [ ] `commit_remote` remains a compatibility wrapper through P2, while the
      typed capability retains receipt information for new callers.
- [ ] Existing Branch/Document/Text behavior and public Canopy interfaces remain
      unchanged; no production cutover occurs in P1.
- [ ] Only intentionally reviewed EGW internal oplog `.mbti` changes exist.
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

Run focused tests for the new oplog ownership/capacity files and the existing
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
- A capacity calculation based only on complete-after membership recreates the
  P0 limitation. The first-operation failure case must be included before
  `begin_admission` mutates planner or authority state.
- Retained, staged, duplicate, and discarded are provenance categories, not
  four additional owners. Receipt construction must enforce disjoint final
  ownership rather than merely report overlapping counters.
- A compatibility wrapper can hide receipt information from legacy callers.
  That is intentional through P2, but the typed capability must remain the
  canonical implementation path so P2 does not need to reconstruct history.
- `PreparedAdmission` and receipt arrays cross package boundaries only through
  reviewed owning/immutable representations. Exposing planner-owned mutable
  collections would violate the state boundary.
- The internal oplog `.mbti` may change for the new capability. Any unrelated
  generated-interface change is an API regression and must stop the PR.
- The Canopy submodule remains at its existing pointer. Mixing a local P1 EGW
  checkout into a parent commit would accidentally turn an internal capability
  experiment into a production integration change.

## Notes

- Related accepted decision: [ADR 0008 at the P0 merge](https://github.com/dowdiness/event-graph-walker/blob/99ab59012a31abb8454468509dd790be03c3b391/docs/adr/0008-core-owned-batch-remote-admission-over-legacy-op.md).
- Related implementation: [EGW PR #118](https://github.com/dowdiness/event-graph-walker/pull/118).
- The P1 plan deliberately does not introduce a new ADR; it operationalizes
  the P1 ownership boundary already accepted by ADR 0008.
- P2 may move the typed outcome through a Document batch shell and projection
  boundary. P1 must not anticipate that cutover by changing outer pending,
  publication, or Canopy-facing APIs.
- The exact receipt field names, capacity formula, and final capability method
  spelling are the explicit plan-review decisions listed above. Once accepted,
  implementation must update this plan if any of them change.
