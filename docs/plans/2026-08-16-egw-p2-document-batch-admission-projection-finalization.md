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

**Status:** characterization complete; this plan is a draft and is not an
implementation authorization.

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

- One package-internal Document batch-admission shell over the P1 typed EGW
  capability.
- One `prepare_remote` call for an incomplete incoming batch.
- One `commit_admission` call.
- Direct use of `AdmissionOutcome` and `AdmissionReceipt`.
- One projection-finalization attempt over `receipt.committed()` when that view
  is non-empty.
- Complete, partial, duplicate-only, pending-only, malformed, stale,
  consumed, and hard-pending-limit cases.
- Post-commit projection failure reporting and recovery.
- `IndexedState` cache invalidation/rebuild rules.
- Existing single-operation `apply_remote` compatibility coverage.
- M-boundary benchmarks comparing per-operation ingress with one batch shell.

### Out

- `SyncSession` cutover or removal of its outer pending lifecycle.
- Removal of `get_all_ops()` / H-sized outer admission scans.
- `Document` or `Branch` public API redesign.
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
failure of that recovery operation; while that status is present, no reader
may claim the Document is valid. If implementation preflight finds that the
existing read surface cannot enforce the terminal state without a public API
delta, the plan must stop for review rather than silently permit lazy reads of
a partial tree.

## Current and desired interfaces

The P2 seam is package-internal and provisional. The exact enum and constructor
names are a plan-review decision, not an implementation authorization.

```text
Document::admit_remote(operations, max_pending?)
  → pre-commit failure
  | admission outcome + projected status
  | admission outcome + recovery-required status
```

The value returned at this seam must retain:

- the complete or partial `AdmissionOutcome`, including its
  `AdmissionReceipt`;
- the projection status;
- any projection/recovery error;
- the authority frontier observed after admission;
- whether `receipt.committed()` was projected, skipped, or requires recovery.

A pre-commit lifecycle failure may remain a `DocumentError` if and only if no
authority or derived state changed. Once a receipt exists, a projection failure
must not be collapsed into that pre-commit error shape.

The P2 shell must not delegate to `merge_remote(remote_ops, remote_frontier)`.
That method requires a complete remote frontier closure, while P2 accepts an
incomplete batch that may leave operations in core pending. The P2 shell uses
`prepare_remote` and `commit_admission` directly.

## Desired behavior matrix

| Case | Authority | Projection | Result evidence |
| --- | --- | --- | --- |
| Complete with committed operations | advances | one finalization over committed operations | complete receipt + projected-complete |
| Duplicate-only | unchanged | skipped | complete receipt with empty committed view |
| Pending-only | frontier unchanged; core pending may change | skipped | complete receipt with pending ownership |
| Zero-prefix partial | pending suffix retained; frontier may be unchanged | skipped | partial receipt + causal cause |
| Middle/n-minus-one partial | committed prefix retained; suffix remains core pending | one finalization over exact committed prefix | partial receipt + projected-partial |
| Malformed current input | unchanged | not started | pre-commit error only |
| Stale/consumed/limit rejection | unchanged | not started | pre-commit error only |
| Post-commit projection failure | advanced to receipt frontier | invalidate, then synchronously fresh-checkout | receipt + recovered status, or recovery-required if checkout fails |
| Recovery retry | unchanged by re-projection retry | fresh checkout replaces/reconciles derived state | recovery complete and text equals fresh checkout |

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
   prove authority, pending state, tree, cache, and projection counters remain
   unchanged.
10. Add a post-commit projection-failure test that proves authority frontier
    equals `receipt.frontier_after`, no rollback occurs, the receipt is retained
    in the result, the cache is invalidated before recovery, and the failure is
    not translated into a pre-commit error.
11. Add a recovery test that compares the recovered Document text and frontier
    with `Branch::checkout` at the receipt frontier. The test must prove that a
    partial FugueTree is not reused as the canonical recovered state and that
    readers are enabled only after the fresh tree is installed. Add the
    recovery-required assertion for a deliberately failing recovery seam if the
    package-local test seam can inject that failure without changing public
    APIs.
12. Add a retry test that re-plans only the core pending suffix and does not
    re-commit identities already present in the receipt's committed view.
13. Keep the existing single-operation `apply_remote` tests and add a
    differential assertion that its observable text and frontier remain
    unchanged while its compatibility path is not silently widened to the P2
    batch contract.

### P2.2 — Implement the package-internal batch shell

14. Validate all incoming content and target/origin preconditions before the
    first authority mutation, using existing Document validation and the core
    planner rather than a second pending algorithm.
15. Call `prepare_remote(operations, max_pending?)` exactly once and retain the
    prepared capability until the one typed commit call. Do not call
    `validate_remote_batch` in a way that imposes the complete-frontier closure
    contract on an incomplete P2 batch.
16. Call `commit_admission` exactly once. Map pre-commit `OpLogError` failures
    separately from the returned complete/partial outcome.
17. For a non-empty `receipt.committed()` view, perform one projection
    finalization. Never project staged, retained, discarded, duplicate-only, or
    still-pending identities. For an empty committed view, skip projection.
18. Return the typed admission evidence together with projected-complete or
    projected-partial status. Preserve a partial admission's causal cause and
    receipt even when the committed prefix projects successfully.
19. On a projection error after authority commit, invalidate the cache, retain
    the receipt/frontier in the result, and perform no rollback or second
    authority transition.
20. Recover synchronously by checking out a fresh Branch at the authoritative
    receipt frontier, installing its fresh tree through the confirmed
    package-local seam, and rebuilding or lazily re-enabling `IndexedState`
    only after tree replacement succeeds. If recovery itself fails, preserve
    recovery-required evidence and prevent any reader from treating the
    partially projected Document as valid.
21. Keep all effectful work in the shell: the admission/projection status
    decision must be deterministic from the typed outcome, projection result,
    cache state, and recovery result. Do not make OpLog own Document recovery.

### P2.3 — Differential validation and M-boundary evidence

22. Run complete, duplicate-only, pending-only, all partial-prefix, malformed,
    lifecycle-rejection, projection-failure, recovery, and retry traces against
    both the new shell and fresh `Branch::checkout`.
23. Add release benchmarks for M = 1, 10, 100, and 1000 comparing:
    `M × Document::apply_remote` with `1 × Document::admit_remote`. Separate
    complete, duplicate-only, pending-only, and partial cases.
24. Record prepare count, typed commit count, projection-finalization count,
    end-to-end time, and allocation observations. Do not describe these as
    H-scan or editor-latency evidence; H-scan remains P3 scope.
25. Run the targeted EGW gate, inspect generated interfaces, and update issue
    #1256 with the P2 review/validation evidence. Do not update the Canopy
    gitlink as part of P2.

## Acceptance Criteria

- [ ] P2 has one package-internal batch shell with one `prepare_remote` and one
      `commit_admission` per batch.
- [ ] `merge_remote` is not reused for incomplete incoming batches.
- [ ] Complete and non-empty partial outcomes perform exactly one projection
      finalization over `receipt.committed()` only.
- [ ] Duplicate-only, pending-only, and zero-prefix partial outcomes skip
      projection and retain the correct receipt/pending evidence.
- [ ] Pre-commit malformed, stale, consumed, and limit failures leave authority,
      pending state, tree, cache, and projection counters unchanged.
- [ ] Post-commit projection failure returns the valid admission receipt and
      authoritative frontier, does not roll back authority, invalidates the
      cache, and is never translated into a pre-commit error.
- [ ] Recovery uses a fresh canonical checkout before normal reads resume and
      produces text/frontier equal to that checkout; a partially mutated
      FugueTree is not reused as final state. A failed recovery preserves an
      explicit recovery-required result and does not expose a valid readable
      state.
- [ ] Partial retries re-plan the core-owned suffix without retrying committed
      identities.
- [ ] Existing single-operation `apply_remote` behavior remains covered and
      compatible.
- [ ] No Document/Branch public API, SyncSession, wire/archive, canonical
      TextEvent, TextReplica, Plain projection, or Canopy gitlink change is
      included.
- [ ] M-boundary benchmark evidence is separated from P3 H-scan and editor
      latency claims.

## Validation

### Plan-only validation

From the Canopy root:

```bash
git diff --check
```

No MoonBit or submodule interface changes are expected for this docs-only plan.

### P2 implementation validation after plan acceptance

Run from a fresh EGW worktree rooted at current EGW `origin/main`:

```bash
cd deps/event-graph-walker
NEW_MOON_MOD=0 moon ide outline internal/document
NEW_MOON_MOD=0 moon ide outline internal/branch
NEW_MOON_MOD=0 moon ide peek-def Document::apply_remote
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
- `Branch::checkout` is a canonical replay primitive, but recovery cost is
  proportional to the replayed history. P2 should prove correctness first and
  defer H-scale optimization to P3 or a separately measured phase.
- Restoring a detached `IndexedState` cache after a post-commit projection
  attempt can hide derived-state divergence. Cache restoration is legal only
  on pre-commit no-mutation exits.
- Existing preflight makes several projection errors unreachable for valid
  admissions, but the failure result is still required for invariant defects,
  future projection adapters, and injected tests. Do not erase the recovery
  contract merely because the normal path is expected to succeed.
- The exact result enum/type names and whether the package-internal shell is
  `fn` or `pub fn` remain plan-review decisions. Keep the result private unless
  a real downstream caller requires an intentional interface change.
- P2 benchmarks measure M-boundary batching only. They must not be used to
  claim removal of SyncSession's H-sized `get_all_ops()` path.

## Notes

- P1 compatibility remains in `OpLog::commit_remote` through the P2 transition;
  the new shell is the first Document consumer of `commit_admission`.
- P2 is a Document responsibility phase. SyncSession continues to own its
  current legacy ingress until P3 explicitly cuts that façade over.
- The P2 plan is intentionally docs-only. After plan acceptance, create a
  fresh implementation branch from the latest EGW `main` containing
  `0e4ec93`; do not continue from the retained P1 branch/worktree.
