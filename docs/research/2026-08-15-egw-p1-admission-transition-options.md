# P1 admission-transition alternatives research

## Question

Is the draft P1 design — prospective `PreparedAdmission`, actual typed
`AdmissionOutcome`, and a hard pending-membership precondition — the best
boundary for EGW, or is a simpler or safer design available?

This note records the investigation before the P1 plan is accepted. It is
research, not an implementation authorization.

## Sources inspected

Primary local sources:

- EGW P0 merge [PR #118](https://github.com/dowdiness/event-graph-walker/pull/118)
  and merge commit
  [`99ab590`](https://github.com/dowdiness/event-graph-walker/commit/99ab59012a31abb8454468509dd790be03c3b391).
- `internal/oplog/remote_admission_planner.mbt`: the P0 planner state,
  preparation overlay, begin transition, acknowledgement, and remaining
  membership.
- `internal/oplog/oplog.mbt`: `prepare_remote`, `begin_admission`, the
  operation-by-operation commit shell, and `commit_remote`.
- `internal/oplog/errors.mbt`: P0 lifecycle, forecast, and partial variants.
- `internal/oplog/remote_admission_oracle_wbtest.mbt`: the fixed-point
  ownership/order oracle.
- `internal/oplog/oplog_semantic_parity_wbtest.mbt`: the complete-only P0
  forecast contract and partial regression.
- ADR 0003: Recoverable Edit Atomicity versus non-rollback CRDT convergence.
- ADR 0004: the planner as the sole pending owner and the prepared-capability
  lifecycle.
- ADR 0005: full-payload identity conflict handling.
- ADR 0008: the accepted P0/P1/P2/P3 boundary.
- MoonBit API inspection from the P0 module: `ArrayView`, mutable and
  immutable `HashSet`, `Iter`, `Result`, `Option`, and `@core.Frontier`.

Primary external sources:

- [Collaborative Text Editing with Eg-walker: Better, Faster, Smaller](https://arxiv.org/html/2409.14252v1), especially the event-graph and
  prepare/effect-version separation.
- [Eg-walker reference implementation](https://github.com/josephg/eg-walker-reference),
  as linked by the paper.

## Facts that constrain P1

The paper and reference implementation support keeping event-graph admission
and transient merge/projection state separate: the event graph is immutable,
and the prepare/effect versions belong to the merge walker rather than to a
pending-admission receipt. Neither primary source specifies a pending limit,
partial authority-commit result, or Document/Branch compatibility wrapper.
They therefore validate the phase boundary but do not provide a better P1
receipt or capacity contract to import.

### Prepared state and commit state are different facts

P0's `PreparedAdmission` contains `planned`, `storage`, discard roots,
discarded-pending and discarded-staged sets, `next_arrival`, a generation, and
single-use state (`remote_admission_planner.mbt:74-83`). It has no committed
prefix. `prepare_remote` only constructs this value and checks the P0
complete-transition forecast (`oplog.mbt:348-375`).

`begin_with_semantics` validates generation, single-use, staged payloads,
waiting metadata, and compatibility order before it removes discarded pending
nodes or registers staged nodes (`remote_admission_planner.mbt:1201-1398`).
`commit_remote_with` then acknowledges each identity only after the operation
commit succeeds and raises `PartialRemoteAdmission` on a later causal-graph
failure (`oplog.mbt:434-470`). Therefore the committed prefix cannot be a
truthful field of the prepared value.

P0 also distinguishes duplicate delivery from ownership: a matching admitted
identity is accepted by `preflight_remote_identities` and is not staged, while a
matching identity already in planner pending is also skipped by preparation and
remains canonical pending (`oplog.mbt:310-325`,
`remote_admission_planner.mbt:996-1025`). Same-batch duplicate occurrences are
a third delivery-level case; they may be coalesced without creating another
identity owner. A receipt must therefore classify incoming occurrences
separately from terminal RawVersion ownership.

### The exact begin-after pending membership is larger than the planned count

At begin, P0 registers every non-discarded staged node, not only operations in
`plan.planned`. The `ImmediateGeneral` path builds `staged_nodes` from every
non-discarded overlay node (`remote_admission_planner.mbt:1150-1185`) and
registers every one before the commit loop (`:1320-1390`). The fast path registers
every planned operation (`:909-968`, `:1250-1290`).

A first-operation causal failure leaves all registered, unacknowledged nodes in
pending. Because retained planned operations already belong to pending, while
new staged identities exclude existing pending identities, the exact
begin-after requirement is:

```text
required_pending = count_unique(
  (pending_before - discarded_pending)
  ∪ staged_unique_not_admitted_not_discarded
)
```

The equivalent shorthand is
`live_pending_before - discarded_pending_count + new_staged_count` when the
sets are normalized as above. `new_staged_count` means the unique,
non-admitted, non-existing-pending, non-discarded staged identities materialized
by prepared storage. It is not `planned.length()` in the general path:
unresolved staged nodes are registered and remain pending even though they are
not in the commit order. This calculation uses live canonical membership
(`pending.length()`), not stale queue/waiter references; P0 removes canonical
nodes immediately and compacts only disposable indexes
(`remote_admission_planner.mbt:519-537`, `:1443-1520`).

The complete-after membership is different. `remaining_raws` excludes planned
identities and discarded identities, then includes retained pending and
unplanned staged identities (`remote_admission_planner.mbt:1557-1590`). P0's
`max_pending_after_complete` checks this smaller set and explicitly allows a
partial suffix to exceed it (`oplog.mbt:348-351`,
`oplog_semantic_parity_wbtest.mbt:475-526`). P1 should instead check the
begin-after requirement before authority mutation.

### A separate mutable pending-limit state is not required by the current shell

P0 has one synchronous `OpLog` commit shell: begin applies the full prospective
pending transition, then the commit loop can only remove pending nodes through
successful acknowledgement. Generation invalidation prevents a second prepared
admission from using the same planner state
(`remote_admission_planner.mbt:590-631`, `:1201-1398`). The production commit
callback is the local graph/log operation (`oplog.mbt:472-486`); it does not
re-enter another admission.

Therefore the safest minimal hard pending-limit implementation is:

1. prepare calculates and stores `required_pending` plus the optional hard
   `max_pending?` policy in the opaque prepared value;
2. begin revalidates the plan and checks the exact requirement against the bound
   before any planner mutation;
3. after begin, all successful acknowledgements monotonically decrease live
   pending membership and commit never adds a pending identity;
4. complete and partial results need no additional mutable pending-limit state.

A mutable planner budget field would add invariants for compaction, rejection,
stale plans, and lifecycle changes without covering a currently possible
interleaving. It should be deferred unless a future asynchronous/reentrant
admission shell requires simultaneous transitions. This keeps the core
functional decision (`required_pending`) separate from shell state.

## Alternatives

### A. Separate prospective capability and actual typed outcome — recommended

`PreparedAdmission` remains opaque, generation-bound, non-mutating, and
single-use. A new `AdmissionOutcome` distinguishes `Complete(receipt)` from
`Partial(receipt, causal_error)`. `commit_admission` is the canonical core
shell; `commit_remote` maps the typed result back to its existing array/error
contract through P2.

**Why it fits:** it follows the actual P0 mutation boundary, preserves partial
ownership evidence, keeps partial non-rollback, and does not move Document or
Branch in P1. It also uses MoonBit's exhaustive enum matching rather than
encoding complete/partial in nullable fields or strings.

### B. Put the committed prefix into `PreparedAdmission` — reject

This is impossible without making preparation a speculative mutable commit or
mutating the value after begin. It would make a pre-commit capability carry a
fact that is determined only by the injected/causal commit failure boundary.
It also makes a consumed capability's post-commit state observable as mutable
history rather than an immutable result.

### C. Extend `PartialRemoteAdmission` and keep errors as the only result — reject

This preserves old callers but cannot express a complete receipt, and it makes
successful authority progress and exceptional control flow share one error
channel. ADR 0003 distinguishes valid CRDT progress from recoverable local
failure; P1 needs the same distinction inside the core boundary.

### D. Return `Result[AdmissionOutcome, PreMutationError]` — do not add a second
error algebra

MoonBit's `Result` exists and is appropriate for pure fallible computations, but
EGW already has `OpLogError` as the typed integration boundary. Adding a
parallel `PreMutationError` would duplicate `StaleAdmission`,
`ConsumedAdmission`, `InvalidAdmission`, and the pending-limit variant, then
require adapters in every caller. Keep pre-mutation failures as `raise
OpLogError`; make only partial a normal `AdmissionOutcome` value.

### E. Add mutable planner pending-limit state — defer

A live budget field models a future concurrent/reentrant shell, but the current
synchronous begin/register/acknowledge lifecycle already proves the bound from
actual pending membership. The field creates new invariants for `compact`,
`reject_pending_members`, `acknowledge_admitted`, stale plans, and partial
transfer. It is not justified by current execution semantics.

### F. Keep P0's forecast API and add a second hard-limit API — reject

Keeping `max_pending_after_complete?` and adding another optional hard limit
would preserve compatibility but create two similarly named policies on one
preparation function. Adding a second preparation method repeats the API
proliferation P0 deliberately removed. The in-repository limit callers are
whitebox tests, and the hard contract is a deliberate P1 semantic replacement.

### G. Rename the optional policy to `max_pending?` and replace the forecast error
— recommended API migration

P1 should make the optional policy mean the peak pending membership permitted
for either complete or partial execution. Rename the optional label to
`max_pending?` and use `PendingLimitExceeded(limit~, required~)`. Update the
P0 forecast tests and the EGW text error mapping accordingly. The generated
internal oplog interface change is intentional and must be reviewed; no
Document/Branch/Canopy production behavior changes.

This is safer than silently keeping a complete-only name for a hard peak
contract. If compatibility with an external caller is discovered during the
P1.0 API inventory, retain the old method only as a clearly named compatibility
adapter; do not overload one argument with two meanings.

## Recommended P1 boundary

The investigation finds no better overall architecture than Alternative A,
but it finds four required corrections to the draft Plan:

1. **Use the exact begin-after membership formula.** The hard precondition must
   be based on the normalized set of live pending plus every unique staged
   identity, not planned operations. Add a red test with a ready prefix and
   unresolved staged suffix where `planned.length() < new_staged_count`.
2. **Do not add mutable pending-limit state.** Store prospective
   `required_pending` in `PreparedAdmission`; begin checks it before mutation,
   and the commit loop proves monotonic non-increase afterward.
3. **Keep receipts transition-local.** Do not copy the complete global pending
   identity set. Own defensive snapshots for committed,
   `already_admitted`, `pending_from_transition`, discarded provenance,
   before/after counts, and before/after frontiers.
4. **Make recovery core-owned.** A partial suffix is already pending; recovery
   re-plans it through the core planner. Network resend idempotence is a
   separate property, not the normal recovery protocol.

The receipt should be opaque and immutable at the package boundary. Its
identity partition is:

```text
affected identities = committed ∪ already_admitted ∪ pending ∪ discarded
these four sets are pairwise disjoint
```

Canonical ownership maps committed and already-admitted identities to
Authority, pending identities to core pending, and discarded identities to no
owner. A matching duplicate is already owned by Authority; same-batch duplicate
occurrences and pending retransmissions are auxiliary delivery evidence, not
identity owners. Retained/staged/discarded categories are provenance axes.
Receipt arrays must be owning snapshots, with accessors allowed to return
views over receipt-owned storage only.

### ADR 0008 amendment prerequisite

ADR 0008's accepted P1 sentence says that the "prepared admission" records
committed, retained, discarded, duplicate, and partial ownership. The P0 code
and the actual commit boundary prove that a prospective prepared value cannot
contain a committed prefix. Before creating the P1 implementation branch, a
separate EGW docs-only amendment must update ADR 0008 to say:

```text
P1 — typed transition boundary:
PreparedAdmission records the prospective, generation-bound transition.
AdmissionOutcome and AdmissionReceipt record the actual complete or partial
ownership result after the commit attempt.
The boundary owns the hard pending-limit contract.
```

This preserves the accepted architecture decision without silently reading new
meaning into the old wording and does not create a new ADR.

## Existing API reuse

Source-verified candidates:

- `PreparedAdmission::operations() -> ArrayView[@core.Op]` for compatibility
  order (`remote_admission_planner.mbt:1541-1545`);
- `PreparedAdmission::remaining_raws(planner)` for complete-after comparison
  (`:1557-1590`), not as the hard peak formula;
- `RemoteAdmissionPlanner::pending_raws()` for white-box before/after
  assertions (`:1601-1611`), not for copying the complete pending set into a
  production receipt;
- `RemoteAdmissionPlanner::begin_with_semantics` as the one validation and
  registration boundary (`:1201-1398`);
- `acknowledge_admitted` for monotonic pending removal and waiter wake-up
  (`:590-631`);
- `reject_pending_members` for the existing rejection closure partition
  (`:668-683`);
- `OpLog::get_frontier()` for non-fallible before/after
  `@core.Frontier` snapshots (`oplog.mbt:253-267`); `get_frontier_raw()` remains
  available only when a caller explicitly needs raw identities;
- `ArrayView::to_owned`, `ArrayView::iter`, `HashSet::to_array`, and
  `HashSet::is_disjoint` for immutable receipt construction and property tests.

Checked but not selected:

- `Result`: not selected as a second public pre-mutation error algebra because
  `OpLogError` already owns the typed raised boundary;
- `Option`: useful for optional `max_pending?`, but not a transition result;
- `@core.Frontier`: selected for the receipt's non-fallible owning
  before/after frontier fields; raw-identity conversion must not be a fallible
  post-mutation receipt step;
- `@immut/hashset`: not selected for the receipt because an opaque receipt with
  read-only `ArrayView` accessors matches current `PreparedAdmission` and
  preserves deterministic order; use immutable sets only if review finds a
  membership-query requirement;
- `@rle.Rle`: not relevant to identity ownership accounting.

## Conclusion

Alternative A remains the recommendation. The better version is a minimal,
serialized transition: exact begin-after pending-membership precondition in the
prepared capability, atomic begin-time validation, monotonic acknowledgement,
transition-local owning receipt snapshots, and a typed immutable actual outcome.
Partial recovery remains core-owned, while duplicate occurrence evidence stays
separate from identity ownership. This closes P1's ownership gap without
inventing a second planner, mutable pending-limit state, parallel error
algebra, or premature Document/Canopy migration.
