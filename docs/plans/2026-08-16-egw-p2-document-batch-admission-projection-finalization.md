# EGW P2: Document batch admission and projection finalization

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/1256>

This plan is the P2 plan for the issue above. The issue must link back to this
file before P2 implementation starts.

P1 is accepted and merged in EGW at
[`0e4ec9347c4655449cf3dd5a2a543f1d9cfe335b`](https://github.com/dowdiness/event-graph-walker/commit/0e4ec9347c4655449cf3dd5a2a543f1d9cfe335b).
The Canopy `deps/event-graph-walker` gitlink remains intentionally unchanged.

Related accepted decision: [EGW ADR 0008](https://github.com/dowdiness/event-graph-walker/blob/0e4ec9347c4655449cf3dd5a2a543f1d9cfe335b/docs/adr/0008-core-owned-batch-remote-admission-over-legacy-op.md).
Related implementation plan: [EGW P1 typed prepared-admission transition](https://github.com/dowdiness/canopy/blob/0497f39e0152ee6214f853c65c31d2a867c9e524/docs/plans/2026-08-15-egw-p1-typed-admission-transition.md).

**Status:** characterization complete; the review-boundary corrections are
incorporated in this revision, but implementation is not authorized until the
plan is accepted.

## Why

P1 makes one remote admission's actual authority transition observable through
`AdmissionOutcome` and `AdmissionReceipt`. The current production Document
paths still use the legacy `commit_remote` result and reconstruct a local
complete/partial distinction around it. P2 must connect the typed outcome to
one Document batch shell without losing the fact that authority may already
have advanced when derived projection fails.

The central failure mode is post-commit projection divergence:

```text
Authority frontier: advanced
FugueTree:          old or partially projected
IndexedState:       stale, partial, or invalidated
```

A projection failure is therefore a derived-state recovery result, not remote
invalidity and not authority rollback. P2 must preserve the admission receipt,
make the projection state observable, and establish a recovery path that can be
compared with a fresh canonical replay.

## Scope

### In

- One Document batch-admission shell over the P1 typed EGW capability, with a
  direct-dependent `pub` seam that is not `pub(all)` and is not a transitive
  Canopy public API.
- One `prepare_remote` call for an incomplete incoming batch.
- One `commit_admission` call.
- Direct use of `AdmissionOutcome` and `AdmissionReceipt`.
- One projection-finalization attempt over `receipt.committed()` when that view
  is non-empty.
- A complete-frontier `merge_remote` compatibility wrapper over the same P2
  shell; it must not retain a second authority/projection lifecycle.
- Complete, partial, duplicate-only, pending-only, malformed, stale,
  consumed, and hard-pending-limit cases.
- Post-commit projection failure reporting and recovery.
- Document-owned projection health and read/mutation admission guards.
- Pure Document target preflight; all pending cleanup remains inside the typed
  core transition.
- `IndexedState` cache invalidation/rebuild rules.
- Existing single-operation `apply_remote` compatibility coverage.
- M-boundary benchmarks comparing per-operation ingress with one batch shell.

### Out

- `SyncSession` cutover or removal of its outer pending lifecycle.
- Removal of `get_all_ops()` / H-sized outer admission scans.
- Broad `Document` or `Branch` public API redesign. The intentional
  direct-dependent `pub` `admit_remote` seam specified below is the limited
  exception.
- Wire or archive changes.
- Canonical position-based `TextEvent` or `TextReplica`.
- Plain projection or persistent Fugue lifecycle replacement.
- New dependency planner or pending owner.
- Canopy submodule/gitlink update.
- P3 façade cutover and end-to-end editor integration.
- A new ADR. ADR 0008 already accepts one core admission, one projection
  finalization, and non-rollback recovery after authority commit.

## Characterization result (P2.0)

Characterization was performed against the merged P1 EGW tree in a separate
throwaway worktree. The probes were deleted after execution; they are evidence
for this plan, not production tests.

### Current direct path

`internal/document/document.mbt` currently performs the following conceptual
sequence in `Document::apply_remote_with`:

```text
validate content and targets
→ prepare_remote
→ take IndexedState cache
→ legacy commit_remote callback
→ restore cache
→ project_remote_ops(committed array)
```

The same file's `Document::merge_remote_with` validates a complete batch,
prepares it, creates `Branch::from_tree_and_oplog`, invalidates the cache,
commits through the legacy callback, then calls `Branch::advance` and translates
partial admission back to `PartialRemoteAdmission`.

`project_remote_ops` applies operations one at a time. With a warm cache and a
small batch it uses `apply_projection_with_visible_change` and incrementally
updates `IndexedState`; otherwise it invalidates and projects lazily. It does
not currently catch a post-commit projection error and invalidate the cache
before rethrowing it. In the direct shell, the detached cache has already been
restored before projection starts.

### Failure injection points

The projection seam exposes three error classes through the existing adapters:

- `MissingOrigin` when an origin cannot be resolved;
- `MissingCausalEntry` when an admitted LV has no causal entry;
- `Fugue` when a tree operation cannot be applied, such as a missing target.

`fugue_projection.apply_all` explicitly documents that a later failure
preserves earlier successful tree mutations. The permanent projection test
`internal/fugue_projection/projection_test.mbt` already proves this prefix
property. `Branch::checkout` and the fast path of `Branch::advance` use the
same `apply_projections` adapter, so they inherit the property. The merge
context also applies operations sequentially.

The throwaway probes added the following direct evidence:

- A two-operation direct projection with a valid prefix and a later missing
  origin projected the prefix, raised `DocumentError::MissingOrigin`, and left
  the cache ready for the partial tree.
- The same failure injected through `Document::apply_remote_with` showed that
  the current shell restores the detached cache before projection; after the
  injected authority state was ahead, the tree contained the projected prefix,
  and the cache remained present rather than entering a recovery-required
  state.
- A Branch `MergeContext::apply_operations` probe with a valid operation
  followed by a missing LV raised `BranchError::MissingOp` after preserving
  the valid prefix.
- The probes passed as 2/2 Document tests and 1/1 Branch test on the P1 merge
  tree, then the temporary files and worktree were removed.

The injected direct cases deliberately violate the normal authority/tree
invariant so that the post-commit seam is observable. They do not claim that
well-formed P1 admission normally creates a missing origin. They establish that
ordinary `DocumentError` translation is insufficient once a projection failure
can occur after authority mutation.

### Recovery primitive comparison

| Candidate | Characterization | P2 position |
| --- | --- | --- |
| A. Rebuild the current FugueTree in place | No existing `FugueTree::copy`, reset, or canonical rebuild-in-place API was found. A partial tree cannot be assumed reusable. | Reject as the primary recovery primitive unless API discovery finds an existing reset operation. |
| B. `Branch::checkout` on a fresh tree, then install the result | `Branch::checkout` creates a fresh `FugueTree` and replays the OpLog to a frontier. `Branch::inner_tree` exposes the resulting tree, but Document has no existing tree-replacement method and its `tree` field is not currently replaceable. | Preferred recovery candidate, conditional on a package-local replacement seam being confirmed during P2 preflight. |
| C. Mark projection dirty and lazily rebuild | `IndexedState::invalidate` plus `ensure` can rebuild the index, but this repairs only the cache. It cannot repair a partially mutated FugueTree. | Use for cache lifecycle only, never as the sole tree-recovery contract. |

`Document::checkout_branch` already wraps `Branch::checkout`, and
`Branch::inner_tree` is an existing package API. P2 must verify whether making
the private Document tree field replaceable or adding a package-private
replacement operation is the smallest safe seam. It must not expose a public
mutable tree or return a planner-owned collection.

### Cache decision

The cache rule is phase-indexed:

1. Before authority mutation, stale/consumed/invalid/limit failures may restore
   the detached warm cache exactly because the tree and authority are unchanged.
2. Once authority has advanced or projection has started, the detached cache
   must not be restored blindly on a projection failure.
3. After any projection failure, invalidate `IndexedState` and report recovery
   required until the tree has been replaced or otherwise proven equal to a
   fresh canonical checkout.
4. After successful projection, a warm cache may remain incrementally valid;
   otherwise `ensure` may rebuild it lazily. A successful cache rebuild is not a
   substitute for tree recovery.

### Readability and recovery timing

The current `Document::to_text`, position, and visibility readers can call
`IndexedState::ensure` against whatever FugueTree is present; they do not carry
a recovery-required guard. P2 must not leave a partially projected tree
readable merely because lazy cache rebuilding succeeds.

The recommended P2 policy is synchronous recovery: after a post-commit
projection failure, invalidate the cache, perform a fresh `Branch::checkout`
at the authoritative receipt frontier, install the fresh tree, and only then
return the typed result. A successful fresh checkout is reported as a
recovered projection status. `ProjectionRecoveryRequired` is reserved for a
failure of that recovery operation.

Document must own this state rather than relying on callers to remember the
last result:

```text
private ProjectionHealth
  Ready
  RecoveryRequired(authoritative_frontier)
```

The constructor starts at `Ready`. `recover_projection` owns the transition
through `RecoveryRequired` before checkout and back to `Ready` only after fresh
tree installation; callers never perform those state changes independently.

`recover_projection(frontier)` is the only operation that installs a replacement
tree, and it owns the complete health/cache/cursor transition for both
pre-commit and post-commit divergence:

1. Invalidate `IndexedState`, clear `cursor`, and set
   `ProjectionHealth::RecoveryRequired(frontier)` before attempting recovery.
2. Run a fresh `Branch::checkout` at the supplied authoritative frontier.
3. On success, install the fresh tree, invalidate the cache again so it can
   rebuild from that tree, clear `cursor` again, and set health to `Ready`.
4. On failure, leave the health at `RecoveryRequired(frontier)`, keep the
   cache invalidated, keep `cursor` clear, and return the typed recovery error.

Callers do not set health, invalidate the cache, clear the cursor, or install a
replacement tree themselves. The same boundary is used when pure preflight
finds existing projection divergence and when post-commit projection fails.
Fallible local mutations and remote admission first retry recovery and
propagate an intentional internal
`DocumentError::ProjectionRecoveryRequired(frontier~)` if it still fails.
Non-fallible derived readers (`to_text`, `visible_count`, position readers, and
visible-item readers) retry recovery and abort with an explicit invariant
message if recovery still fails; they must never silently read the partial
tree. Authority-only readers such as the frontier and OpLog inspection remain
available. This preserves existing non-fallible reader signatures while making
`RecoveryRequired` Document-owned and fail-closed.

## Admission ownership and target preflight

The current `Document::preflight_remote_targets` is not pure: its invalid-root
path calls `OpLog::discard_pending_dependents`. P2 must not call that mutating
path outside `commit_admission`.

The P2 shell calls `prepare_remote` first; core preparation owns semantic
pending cleanup, staged registration, ready ordering, and the receipt's
`discarded_pending`/`discarded_staged` evidence. Document performs two pure
projection-consistency checks without changing OpLog or planner state:

1. **Prepared-target check:** inspect `prepared.operations()`. An origin must
   already be present in the FugueTree or be an Insert introduced by the same
   prepared batch; the latter is allowed because the final projection may
   establish it in that batch.
2. **Incoming known-origin check:** inspect the original incoming operations,
   including operations that are not ready and therefore are absent from
   `prepared.operations()`. For every origin already known to the authority's
   causal graph, require that the corresponding origin is present in the
   FugueTree. Unknown origins and targets whose semantic arrival/readiness is
   not yet established are not classified by Document; that meaning remains
   owned by OpLog admission.

These checks must not reimplement target-is-Insert validation, missing-parent
semantics, pending discard, rejection closure, or any other admission rule.
They only detect projection consistency. A graph-known origin that is missing
from the tree is projection divergence, not a remote-invalid root. The shell
calls `recover_projection` at the current authoritative frontier and reruns
both pure checks against the same prepared capability and original incoming
operations. It never discards pending work for this case. If recovery or the
second check fails, the admission returns the typed recovery-required result;
if a later admission error rejects the prepared input, authority/planner/
frontier remain unchanged even though derived state may already have been
repaired. Core pending additions, removals, and rejection closure must all
remain represented by one `PreparedAdmission` → `AdmissionOutcome` transition.

## Current and desired interfaces

The P2 implementation remains package-internal, but its intentional
`admit_remote` seam is exposed to direct dependents with `pub`, not `pub(all)`;
it is not a transitive Canopy public API. The private constructor names are
implementation details. The direct-dependent `pub` boundary and these semantic
fields are fixed by this plan:

```moonbit
pub fn Document::admit_remote(...)
  -> DocumentAdmission
  raise DocumentError

pub struct DocumentAdmission {
  outcome : @oplog.AdmissionOutcome
  projection : ProjectionStatus
}

pub enum ProjectionStatus {
  Skipped
  Projected
  Recovered
  RecoveryRequired(error~ : @branch.BranchError)
}
```

`Skipped` means no non-empty `receipt.committed()` view required projection and
no recovery was needed. `Projected` means direct finalization succeeded.
`Recovered` means `recover_projection` was required and succeeded, whether the
divergence was found during preflight or after commit. `RecoveryRequired` means
fresh checkout failed and the Document remains fail-closed. The final payload
may add accessors or a frontier convenience field during implementation, but it
must retain the complete or partial `AdmissionOutcome`/`AdmissionReceipt`, the
projection status, and the authority frontier available from the receipt.

Admission effects and derived-state effects are independent axes:

- a pre-commit rejection leaves authority, planner, and authoritative frontier
  unchanged;
- if no projection divergence was detected, it also leaves tree/cache/cursor
  unchanged;
- if pure preflight required recovery, the same rejection may leave derived
  state repaired and `Ready`, or fail closed as `RecoveryRequired`; it must not
  restore the old broken tree or cache merely because admission was rejected;
- once a receipt exists, a projection failure is never collapsed into a
  pre-commit error shape.

The incomplete P2 shell uses `prepare_remote` and `commit_admission` directly.
`merge_remote(remote_ops, remote_frontier)` is not an alternative lifecycle:
its complete-frontier compatibility wrapper first performs only the existing
`validate_remote_batch` closure check, then delegates actual authority commit,
projection finalization, health guards, and recovery to `admit_remote`. It must
not call legacy `commit_remote`, `Branch::advance`, or a second projection
shell.

## Desired behavior matrix

| Case | Authority | Projection | Result evidence |
| --- | --- | --- | --- |
| Complete with committed operations | advances | one finalization over committed operations | complete receipt + projected-complete |
| Duplicate-only | unchanged | skipped | complete receipt with empty committed view |
| Pending-only | frontier unchanged; core pending may change | skipped | complete receipt with pending ownership |
| Zero-prefix partial | pending suffix retained; frontier may be unchanged | skipped | partial receipt + causal cause |
| Middle/n-minus-one partial | committed prefix retained; suffix remains core pending | one finalization over exact committed prefix | partial receipt + projected-partial |
| Malformed current input | unchanged | not started; tree/cache unchanged | pre-commit error only |
| Stale/consumed/limit rejection without divergence | unchanged | not started; tree/cache unchanged | pre-commit error only |
| Preflight divergence followed by pre-commit rejection | unchanged | repaired to the current frontier, or fail-closed as `RecoveryRequired` | rejection has no admission transition; derived-state axis is explicit |
| Post-commit projection failure | advanced to receipt frontier | `recover_projection` invalidates/clears/marks health, then synchronously fresh-checks out | receipt + recovered status, or recovery-required if checkout fails |
| Recovery retry | unchanged by re-projection retry | `recover_projection` owns replacement, cache, cursor, and health transitions | recovery complete and text equals fresh checkout |

For duplicate-only, pending-only, and zero-prefix partial outcomes,
`receipt.committed()` is empty and projection is completely skipped. For a
non-empty partial outcome, only `receipt.committed()` is projected; the core
pending suffix is never projected by the Document shell.

## Steps

### P2.0 — Freeze characterization and API evidence

1. Before implementation, create a fresh EGW worktree from current EGW
   `origin/main` containing `0e4ec93`; do not start from the retained P1
   feature worktree and do not update the Canopy gitlink.
2. Re-run the Existing API First checks from the EGW module root for
   `Document`, `IndexedState`, `Branch::checkout`, `Branch::advance`,
   `Branch::inner_tree`, `FugueTree::new`, `OpLog::prepare_remote`,
   `OpLog::commit_admission`, and `AdmissionReceipt`.
3. Confirm the package-local replacement seam for `Document.tree`. If no
   existing replacement operation is available, keep replacement private to
   `internal/document` and record the field-mutability change as an internal
   implementation detail rather than a public API.
4. Preserve the characterization conclusions above as the P2 preflight
   evidence. Do not promote the throwaway probes to production behavior.

### P2.1 — Write red tests before the shell

5. Add a package-local test trace or equivalent test-only instrumentation that
   counts preparation, typed commit, and projection-finalization boundaries.
   Prefer existing injectable commit shells; add a projection callback only if
   API discovery confirms no narrower test seam exists. Do not add counters to
   production OpLog state.
6. Add a complete batch test with M operations asserting one prepare, one
   `commit_admission`, one projection finalization, the expected receipt, and
   text equal to a fresh checkout.
7. Add duplicate-only and pending-only tests asserting empty committed views
   and zero projection finalizations. Pending ownership remains in core.
8. Add zero-prefix, middle-prefix, and n-minus-one partial tests. Project only
   the exact committed prefix, retain the suffix in core pending, preserve the
   typed receipt/cause, and count one finalization only when the prefix is
   non-empty.
9. Add malformed-current-input, stale, consumed, and pending-limit tests that
   prove authority, planner/pending ownership, tree, cache, and projection
   counters remain unchanged when no divergence was detected. Add the focused
   regression where graph-known Insert `Y` is absent from the tree while
   incoming `X` has a missing dependency and is unready: detect divergence
   before the core transition can place `X` in pending, recover the current
   frontier, and rerun both pure checks against the same incoming batch. Add a
   variant that forces a later pre-commit rejection and proves authority,
   planner, and frontier remain unchanged while derived state is repaired or
   remains explicitly `RecoveryRequired`.
10. Add a post-commit projection-failure test that proves authority frontier
    equals `receipt.frontier_after`, no rollback occurs, the receipt is retained
    in the result, and `recover_projection(receipt.frontier_after)` owns cache
    invalidation, cursor clearing, health transition, and the recovery attempt.
    The failure is never translated into a pre-commit error.
11. Add a recovery test that compares the recovered Document text and frontier
    with `Branch::checkout` at both a preflight frontier and a receipt frontier.
    The test must prove that a partial FugueTree is not reused as the canonical
    recovered state, that `ProjectionHealth` returns to `Ready` only after
    fresh-tree installation, and that the cursor is cleared. Add a deliberately
    failing recovery seam assertion: health remains `RecoveryRequired`, derived
    readers fail closed, and a later mutation/admission retries recovery before
    mutating. Both entry points must exercise the same `recover_projection`
    transition.
12. Add a retry test that re-plans only the core pending suffix and does not
    re-commit identities already present in the receipt's committed view.
13. Make `Document::apply_remote(op)` a thin compatibility wrapper over the
    direct-dependent `pub` `admit_remote([op])` seam without changing its public
    signature. Map a recovered complete result to `Unit`, a recovered partial
    result back to the existing `PartialRemoteAdmission` error, preserve
    pre-commit errors, and expose recovery failure as
    `DocumentError::ProjectionRecoveryRequired`. The P2 shell is the single
    implementation path for one-op and batch authority commit plus projection
    finalization; do not retain the old legacy shell.
14. Make `Document::merge_remote(ops, frontier)` a complete-frontier
    compatibility wrapper: test that it performs only pure
    `validate_remote_batch` closure validation, then delegates actual authority
    commit, projection, health guards, and recovery to `admit_remote`. It must
    not call legacy `commit_remote`, `Branch::advance`, or an independent
    projection shell, including while `RecoveryRequired`.
15. Add a cursor regression: create a local sequential-insert cursor, perform
    complete/partial/recovered remote admission, then insert locally and prove
    text/frontier equality with fresh checkout. `cursor` is cleared at batch
    entry and after every fresh-tree installation.

### P2.2 — Implement the package-internal batch shell

16. Validate incoming content before any admission state change, then call
    `prepare_remote(operations, max_pending?)` exactly once. Do not call the
    mutating `OpLog::discard_pending_dependents` path from Document. Core
    preparation owns all pending mutation and receipt provenance.
17. Run both pure Document projection-consistency checks: the prepared-target
    check over `prepared.operations()` and the incoming known-origin check over
    the original operations, including unready operations omitted from the
    prepared plan. If either finds a graph-known origin absent from the tree,
    call `recover_projection(current_authoritative_frontier)` and rerun both
    checks against the same prepared capability and incoming operations. Never
    classify that divergence as a pending invalid root, and never reimplement
    target kind, dependency, or pending semantics. Do not call
    `validate_remote_batch` for incomplete P2 admission.
18. Retain the prepared capability until the one `commit_admission` call. Map
    pre-commit `OpLogError` failures separately from the returned
    complete/partial outcome, while preserving any derived-state repair made
    by preflight recovery.
19. For a non-empty `receipt.committed()` view, perform one projection
    finalization. Never project staged, retained, discarded, duplicate-only, or
    still-pending identities. For an empty committed view, skip projection.
20. Return the typed admission evidence together with `Skipped`, `Projected`,
    or `Recovered` status. Preserve a partial admission's causal cause and
    receipt even when the committed prefix projects successfully; return
    `RecoveryRequired` when the shared recovery boundary cannot repair the
    derived state.
21. On a projection error after authority commit, retain the receipt/frontier
    and perform no rollback or second authority transition. Call
    `recover_projection(receipt.frontier_after)`; that boundary, not this
    caller, invalidates the cache, clears the cursor, sets
    `ProjectionHealth::RecoveryRequired`, checks out the fresh tree, installs
    it on success, and returns `Ready` or the typed recovery error.
22. Use the same `recover_projection` boundary for preflight and post-commit
    divergence. On success it returns a `Recovered` projection status; on
    failure it leaves `RecoveryRequired` and fail-closed derived readers. A
    pre-commit rejection after successful preflight recovery must not restore
    the old tree or detached cache.
23. Keep all effectful work in the shell: the admission/projection status
    decision must be deterministic from the typed outcome, projection result,
    health, cache state, and recovery result. Do not make OpLog own Document
    recovery or call a mutating pending-discard helper.

### P2.3 — Differential validation and M-boundary evidence

24. Run complete, duplicate-only, pending-only, all partial-prefix, malformed,
    lifecycle-rejection, projection-failure, preflight-divergence, recovery,
    merge-wrapper, and retry traces against both the new shell and fresh
    `Branch::checkout`.
25. Add release benchmarks for M = 1, 10, 100, and 1000 comparing:
    `M × Document::apply_remote` with `1 × Document::admit_remote`. Separate
    complete, duplicate-only, pending-only, and partial cases.
26. Record separate `projection_finalization_attempts` and
    `recovery_checkouts`; a post-commit failure is one direct finalization
    attempt followed by a recovery checkout, not two finalization attempts.
    Each benchmark must fail fast: complete accepts only the expected Complete
    outcome and committed count; duplicate/pending accepts only an empty
    committed view; partial accepts only the expected prefix length. Unexpected
    outcomes or errors are test failures, never measurements.
27. Record end-to-end time and allocation observations. Do not describe these
    as H-scan or editor-latency evidence; H-scan remains P3 scope.
28. Run the targeted EGW gate, inspect generated interfaces, and update issue
    #1256 with the P2 review/validation evidence. Do not update the Canopy
    gitlink as part of P2.

## Acceptance Criteria

- [ ] P2 has one batch shell with one `prepare_remote` and one
      `commit_admission` per batch; its intentional direct-dependent
      `Document::admit_remote` seam is `pub`, not `pub(all)`.
- [ ] Document owns private `ProjectionHealth`; `recover_projection` alone owns
      health, cache, cursor, and replacement-tree transitions for both pre- and
      post-commit divergence.
- [ ] Fallible mutation/admission retries recovery before mutation; non-fallible
      derived readers fail closed instead of reading a partial tree.
- [ ] `merge_remote` validates only complete-frontier closure, then delegates
      authority commit, projection, health guards, and recovery to
      `admit_remote`; it does not retain a legacy lifecycle or serve incomplete
      P2 batches.
- [ ] Document runs separate pure prepared-target and incoming known-origin
      checks; the latter includes unready incoming operations, while semantic
      target/dependency/pending decisions remain in OpLog.
- [ ] Document target preflight is pure and no Document path calls
      `OpLog::discard_pending_dependents` outside the typed transition.
- [ ] Complete and non-empty partial outcomes perform exactly one projection
      finalization over `receipt.committed()` only.
- [ ] Duplicate-only, pending-only, and zero-prefix partial outcomes skip
      projection and retain the correct receipt/pending evidence.
- [ ] Pre-commit malformed, stale, consumed, and limit failures leave authority,
      planner, frontier, tree, cache, and projection counters unchanged when no
      divergence was detected.
- [ ] If preflight recovery was required before a later pre-commit rejection,
      authority/planner/frontier remain unchanged while derived state is either
      repaired to the authoritative frontier or explicitly `RecoveryRequired`;
      the old broken tree/cache is never restored.
- [ ] Post-commit projection failure returns the valid admission receipt and
      authoritative frontier, does not roll back authority, and is never
      translated into a pre-commit error; the shared recovery boundary handles
      invalidation and recovery.
- [ ] Recovery uses a fresh canonical checkout before normal reads resume and
      produces text/frontier equal to that checkout; a partially mutated
      FugueTree is not reused as final state. A failed recovery preserves an
      explicit recovery-required result and does not expose a valid readable
      state.
- [ ] Partial retries re-plan the core-owned suffix without retrying committed
      identities.
- [ ] The direct-dependent `pub` `DocumentAdmission` / `ProjectionStatus` seam
      retains typed outcome/receipt and projection status without becoming a
      transitive Canopy API; private constructor names remain implementation
      details.
- [ ] Existing single-operation `apply_remote` keeps its public signature and
      delegates to the P2 shell; complete/partial/pre-commit/recovery mappings
      remain explicit.
- [ ] Remote admission clears `cursor` at entry and after fresh-tree recovery;
      local edits after recovery match fresh checkout.
- [ ] No broad Canopy public API, SyncSession, wire/archive, canonical
      TextEvent, TextReplica, Plain projection, or Canopy gitlink change is
      included. The intentional direct-dependent `pub` seam and any reviewed
      generated `.mbti` delta are the only interface exceptions.
- [ ] M-boundary benchmarks separately record projection finalization attempts
      and recovery checkouts, fail fast on wrong outcomes, and are separated
      from P3 H-scan and editor latency claims.

## Validation

### Plan-only validation

From the Canopy root:

```bash
git diff --check
```

This docs-only change makes no MoonBit or submodule interface changes. The
implementation gate must nevertheless inspect the intentional direct-dependent
`pub` seam and any resulting generated `.mbti` delta.

### P2 implementation validation after plan acceptance

Run from a fresh EGW worktree rooted at current EGW `origin/main`:

```bash
cd deps/event-graph-walker
NEW_MOON_MOD=0 moon ide outline internal/document
NEW_MOON_MOD=0 moon ide outline internal/branch
NEW_MOON_MOD=0 moon ide peek-def Document::apply_remote
NEW_MOON_MOD=0 moon ide peek-def Document::admit_remote
NEW_MOON_MOD=0 moon ide peek-def DocumentAdmission
NEW_MOON_MOD=0 moon ide peek-def ProjectionStatus
NEW_MOON_MOD=0 moon ide peek-def Document::merge_remote
NEW_MOON_MOD=0 moon ide peek-def Branch::checkout
NEW_MOON_MOD=0 moon ide peek-def Branch::inner_tree
NEW_MOON_MOD=0 moon ide peek-def OpLog::prepare_remote
NEW_MOON_MOD=0 moon ide peek-def OpLog::commit_admission
NEW_MOON_MOD=0 moon ide find-references apply_projections
NEW_MOON_MOD=0 moon ide find-references Branch::checkout
NEW_MOON_MOD=0 moon check --deny-warn
NEW_MOON_MOD=0 moon test internal/document
NEW_MOON_MOD=0 moon test internal/branch
NEW_MOON_MOD=0 moon test internal/fugue_projection
NEW_MOON_MOD=0 moon test
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
git diff --check
git diff -- '*.mbti'
```

Run the P2 M-boundary benchmarks with `moon bench --release` from the EGW
root. Inspect raw PR checks before merge. If the implementation changes only
private package internals, reject any unexpected generated `.mbti` delta; if a
public package-internal interface is intentionally exported, document that
specific delta in the PR and issue.

## Risks

- The Canopy checkout currently retains unrelated dirty files and an old EGW
  gitlink. P2 planning and implementation must not reset them or silently make
  the parent repository depend on the P1 submodule commit.
- `Branch::inner_tree` returns a tree alias, not a Document replacement
  operation. Reusing it without a confirmed replacement seam could leave the
  Document pointing at the partially mutated tree.
- `ProjectionHealth` must be Document-owned. A returned typed status without a
  health field would allow ignored results to reach readers, local mutation,
  or the next admission. The chosen fail-closed behavior for non-fallible
  readers and the recovery error carrier must remain explicit.
- `Branch::checkout` is a canonical replay primitive, but recovery cost is
  proportional to the replayed history. P2 should prove correctness first and
  defer H-scale optimization to P3 or a separately measured phase.
- Restoring a detached `IndexedState` cache after a post-commit projection
  attempt can hide derived-state divergence. Cache restoration is legal only
  when no preflight recovery occurred; a later pre-commit rejection must not
  restore the old broken tree or cache after derived state was repaired.
- Reusing the current mutating `preflight_remote_targets` helper would create a
  planner transition outside the P1 receipt. Split it into pure prepared-target
  and incoming known-origin projection checks, while core retains target,
  dependency, and pending semantics.
- The unready incoming known-origin check is necessary even when the operation
  is absent from `prepared.operations()`: otherwise a graph-known origin missing
  from Fugue could remain hidden behind pending and the Document would stay
  falsely `Ready`.
- Existing preflight makes several projection errors unreachable for valid
  admissions, but the failure result is still required for invariant defects,
  future projection adapters, and injected tests. Do not erase the recovery
  contract merely because the normal path is expected to succeed.
- The direct-dependent `pub` `admit_remote` result boundary and semantic fields
  are fixed by this plan; private constructor names may vary. Do not widen it
  to `pub(all)` or leave a second legacy `merge_remote` lifecycle.
- P2 benchmarks measure M-boundary batching only. They must not be used to
  claim removal of SyncSession's H-sized `get_all_ops()` path.

## Notes

- P1 compatibility remains in `OpLog::commit_remote` through the P2 transition;
  the new shell is the first Document consumer of `commit_admission`.
- P2 is a Document responsibility phase. SyncSession continues to own its
  current legacy ingress until P3 explicitly cuts that façade over.
- `merge_remote` remains a complete-frontier compatibility wrapper: after
  pure `validate_remote_batch` closure validation it delegates authority commit,
  projection, health guards, and recovery to `admit_remote`; it is not the
  implementation path for incomplete P2 batches. `apply_remote` is the thin
  one-operation wrapper over the same P2 shell.
- The P2 plan is intentionally docs-only. After plan acceptance, create a
  fresh implementation branch from the latest EGW `main` containing
  `0e4ec93`; do not continue from the retained P1 branch/worktree.
