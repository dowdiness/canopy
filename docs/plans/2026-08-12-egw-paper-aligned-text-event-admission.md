# EGW Gate A: canonical TextEvent admission correctness

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/1241>

This plan is the implementation plan for the issue above. The issue links back
here.

## Why

The accepted Eg-walker direction keeps EventGraph, OpLog, and Frontier as
Causal Authority, uses a Plain-text editing projection during ordinary editing,
and creates Transient merge state only for concurrent merge or replay. Before
production `Document` can move toward that lifecycle, the internal position-based
canonical event boundary must prove that existing admission, pending, duplicate,
partial-commit, delete-winner, tombstone, undelete, and convergence semantics
are preserved.

The current `TextEvent` material is test-only and incomplete. It accepts some
malformed remote edits before replay fails, has no complete `Undelete` model,
has only a one-way compatibility adapter, and refreshes through full checkout.
Full checkout is acceptable as a projection oracle in this gate; it is not the
future normal path.

## Scope

In:

- `deps/event-graph-walker/internal/branch/text_event_api_prototype_wbtest.mbt`
- `deps/event-graph-walker/internal/branch/text_event_op_adapter_prototype_wbtest.mbt`

The two baseline files are published test-only inputs at EGW commit
[`44164cd`](https://github.com/dowdiness/event-graph-walker/tree/44164cdac7c9fcf7c206be995e4c6192afc45190), branch
`prototype/gate-a-text-event-baseline`. A fresh Gate A worktree must start from
Canopy `main`, initialize the recorded EGW submodule, then fetch and apply that
exact baseline commit (or copy the two files at those immutable paths) before
A1. The baseline is experimental test code only; it does not change EGW
production APIs or behavior.

- `deps/event-graph-walker/internal/oplog/remote_admission_oracle_wbtest.mbt`
- `deps/event-graph-walker/internal/oplog/oplog_remote_delivery_generated_wbtest.mbt`
- `deps/event-graph-walker/internal/oplog/admission_overhead_benchmark_wbtest.mbt`
- new package-local Gate A whitebox/property test files under
  `deps/event-graph-walker/internal/branch/` and
  `deps/event-graph-walker/internal/oplog/`
- the Gate A benchmark/evidence record under `docs/performance/`
- the accepted projection-lifecycle wording needed to distinguish position
  query capability from per-scalar causal metadata

Out:

- production `Document` or `Branch` projection changes;
- removal of persistent FugueTree;
- critical-version detection, placeholder replay, or order-statistic merge
  implementation;
- Persistence Coordinator, warm reconnect, cold reopen, or Worker replay;
- public checkpoint/restore APIs, durable materialized-state formats, wire or
  archive schema changes;
- production `.mbti` changes;
- container TextBlock lifecycle;
- cleanup or reset of the dirty `deps/loom` worktree;
- publishing the current throwaway prototype as production behavior.

## Current State

- `TextEventLog` models `RawVersion` plus causal parents and position-based
  insert/delete events, but currently accepts remote positions without
  parent-relative semantic validation and has no `Undelete` variant.
- `TextEventLog::merge_event` refreshes visible text through full checkout after
  admission. This remains a test oracle only for Gate A.
- `text_event_op_adapter_prototype_wbtest.mbt` lowers canonical events to one
  legacy `Op` per current single-scalar event and derives Fugue origins at the
  compatibility boundary. Reverse lifting is absent.
- `OpLog::prepare_remote` is non-mutating and delegates pending/ready ordering
  to `RemoteAdmissionPlanner`. The fixed-point oracle already compares planned
  identities, remaining pending identities, frontier, and operation count.
- `OpLog::commit_remote` may return `PartialRemoteAdmission`; existing Branch
  and Document projection paths retain and project the committed prefix before
  returning the typed error.
- `Branch::checkout` reconstructs visible text from a committed frontier and is
  the projection oracle, not the admission or representation oracle.
- Existing remote admission tests cover duplicate collapse, identity conflict,
  pending dependencies, non-mutating prepare, partial commit, and planner
  fixed-point behavior.
- Existing production public interfaces and generated interfaces are not to be
  changed by this gate.

## Desired State

Gate A provides a test-only canonical event boundary with these properties:

1. A canonical insert event owns exactly one Unicode scalar and exactly one
   `RawVersion` identity. Non-BMP scalars are atomic; combining sequences are
   multiple scalar events.
2. A canonical delete event carries a parent-relative visible position. An
   undelete event carries an explicit causal target because deleted content has
   no visible position.
3. Canonical events contain no Fugue origins. Origins and legacy target metadata
   are derived only while lowering to the compatibility representation.
4. Receipt preflight rejects malformed payloads, identity conflicts, invalid
   shapes, and resource-limit violations before graph, OpLog, or pending state
   mutation.
5. Causally incomplete but preflight-valid events are buffered outside
   EventGraph/Causal Authority until they can be lowered. The existing
   `RemoteAdmissionPlanner` remains the only ready/pending admission algorithm;
   the TextEvent harness must not implement a second dependency planner.
6. Ready-time semantic validation checks parent-relative position bounds and
   delete/undelete targets before `commit_remote` begins.
7. Complete, duplicate, buffered, rejected, and partial outcomes are observed
   independently through a test-only `AdmissionObservation` record.
8. Partial admission advances projection exactly to the committed prefix,
   retains the exact remaining pending state, and returns the existing typed
   issue without authorizing retry of the committed prefix.
9. Canonical-to-legacy and legacy-to-canonical adapters satisfy normalization
   laws for the canonicalizable one-scalar domain. Non-canonical legacy empty
   inserts remain explicit compatibility cases.
10. Every committed frontier's observed text equals `Branch::checkout` text,
    while admission behavior equals the existing fixed-point oracle.
11. Permutations, duplicates, malformed input, concurrent branches, tombstone
    follow-up, delete-winner, undelete, and fresh-writer scenarios converge or
    fail according to the existing contract.
12. The Gate A admission path does not expand full history or build a duplicate
    causal map for every admission.
13. No production `.mbti`, public API, archive, or wire format changes.

## Steps

### A1 — Pin event identity, normalization, and observation

1. Re-read the published Gate A baseline at EGW commit `44164cd` and the
   existing Op/RawVersion APIs; verify package roots and generated interfaces
   before editing. Confirm that one scalar per insert is the intended canonical
   domain and record any non-canonical legacy cases explicitly.
2. Extend the test-only edit algebra with `Undelete` carrying an explicit
   causal target. Keep canonical events free of Fugue origins.
3. Define test-only normalization/equality helpers for canonical events and
   legacy operations. Compare `(agent, seq)` candidates by full normalized
   payload, never by destination-local LV.
4. Define the test-only `AdmissionObservation` record with committed,
   buffered, duplicates, rejected, before/after frontier, before/after pending,
   before/after visible text, and terminal error fields. Capture observations at
   the existing TextEvent admission seam rather than exposing them publicly.
5. Make local event construction enforce one scalar per insert and explicit
   parent-relative position bounds. Add non-BMP and combining-sequence cases.
6. Add canonical-to-legacy lowering for one canonical scalar event to one legacy
   Op, deriving origins/targets only from a transient compatibility trace.
7. Add legacy-to-canonical lifting for the canonicalizable one-scalar domain;
   document and test the normalization boundary for empty legacy inserts and
   other non-canonical payloads.
8. Add adapter laws: `lift(lower(event)) == normalize(event)`,
   `lower(lift(op)) == normalize(op)` for canonicalizable operations, and
   conflicting normalized payloads under one RawVersion are rejected.

### A2 — Close validation, planner delegation, and differential properties

9. Add receipt preflight before any canonical graph mutation. Validate UTF-16,
   scalar count, edit shape, RawVersion format, duplicate/conflict identity,
   parent/target encoding, and the existing admission/resource limits.
10. Keep causally incomplete canonical events out of EventGraph and Causal
    Authority while buffered. Define the test-only lowering seam as:

    ```text
    try_lower(event, parent_context)
      -> MissingContext
       | Invalid(CanonicalValidationError)
       | Lowered(Op)
    ```

    `try_lower` performs the ready-time parent-relative position and target
    validation needed to construct a legacy `Op`; it must never mutate the
    graph, planner, or pending store. `MissingContext` is retained in bounded
    canonical staging and retried only when the directly referenced parent or
    target becomes available. `Invalid` is rejected and its explicit invalid
    dependents are discarded according to existing policy. `Lowered(Op)` is
    handed to the existing `OpLog::prepare_remote` / fixed-point planner.
    That planner remains the only owner of ready ordering, duplicate collapse,
    and legacy pending semantics. Canonical staging stores only bounded
    RawVersion-keyed envelopes and unresolved direct dependencies; it does not
    calculate topological order or winner state. It also does not mutate legacy
    planner state until `Lowered(Op)` is returned.
11. Ensure ready-time semantic validation completes before `commit_remote`
    starts, and that no second validation pass or planner is introduced after
    legacy preparation.
12. Add negative atomicity tests proving receipt-preflight and ready-time
    rejection leave operation count, frontier, visible text, and planner state
    unchanged, except for explicitly specified invalid-root dependent discard.
13. Add complete-admission tests for sequential edits, remote edits, duplicate
    delivery, concurrent fresh writers, and parent-before/parent-after delivery.
14. Add partial-admission tests that assert committed prefix, frontier,
    visible projection, exact remaining pending identities, terminal error, and
    no retry of the committed prefix. Compare behavior with existing
    `PartialRemoteAdmission` tests.
15. Add delete-winner, stale delete, undelete, tombstone follow-up, concurrent
    delete/insert, and malformed target tests. Delegate winner calculation and
    projection semantics to existing legacy behavior rather than duplicating it.
16. Add differential tests that compare the canonical log's committed frontier
    and visible text with `Branch::checkout` after compatibility lowering.
17. Add randomized/permutation tests for valid event sets, duplicates, pending
    delivery, concurrent branches, and malformed events. Require equal visible
    text and equivalent RawVersion frontiers for replicas admitting the same
    valid set.

### A3 — Add admission guardrails and close the gate

18. Extend the existing admission-overhead benchmark with adapter-only cost,
    one admission after 10,000 and 100,000 preloaded operations, admitted
    duplicate, pending duplicate, identity conflict, batch prepare/commit, and
    reverse pending drain.
19. Add a structural review/test guard that Gate A does not call
    `get_all_ops`/`get_all_runs` or construct an operation-count-sized duplicate
    causal map on the normal admission path. Timing is supplementary evidence,
    not the sole guard.
20. Run targeted EGW tests for branch, OpLog, and new Gate A files. Fix test
    fixtures before considering any prototype promotion.
21. Run EGW `moon check` and `moon test`; run parent Canopy checks only if the
    submodule pointer or parent integration is touched.
22. Run `moon fmt && moon info` in the EGW module as required, inspect every
    generated `.mbti` diff, and reject unintended public/API drift.
23. Record the Gate A evidence and limitations in a dated performance/evidence
    document. Explicitly state that full checkout is an oracle and that Gate A
    does not establish paper-level load, merge, memory, or storage parity.
24. Complete the local validation gate before opening the implementation PR.
    After opening it, inspect raw statuses with `gh pr checks <NUMBER>`; every
    required check must be `pass`, with no `pending`, `fail`, or unapproved
    `skipped` result. Do not merge or declare the implementation PR ready for
    merge until both the local validation gate and all required CI checks are
    green.
25. Update issue #1241 with validation evidence and leave the current
    production projection unchanged. Any later promotion must be a new phase
    with its own review and submodule push order.

## Acceptance Criteria

- [ ] The canonical event model contains one `RawVersion` per scalar insert;
      non-BMP scalars remain atomic and combining sequences are not silently
      coalesced.
- [ ] `Undelete` has an explicit causal target and preserves existing
      delete-winner/tombstone semantics through the legacy oracle.
- [ ] Canonical events contain no Fugue origin fields.
- [ ] Receipt-preflight malformed input cannot change EventGraph, OpLog,
      frontier, pending state, or visible text.
- [ ] Buffered events are preflight-valid, remain outside EventGraph, and are
      drained without a second dependency-planner implementation.
- [ ] Ready-time position and target validation occurs before `commit_remote`.
- [ ] Duplicate identity is idempotent only when the full normalized payload
      matches; conflicting reuse is rejected before mutation.
- [ ] Complete admission, pending drain, partial admission, and invalid-root
      dependent discard match existing fixed-point planner behavior.
- [ ] Partial admission projects the committed prefix, retains exact remaining
      pending identities, returns the typed issue, and does not authorize
      retrying the committed prefix.
- [ ] Canonical/legacy adapter normalization laws pass for the canonicalizable
      one-scalar domain and explicit compatibility exceptions are tested.
- [ ] Differential projection text matches `Branch::checkout` for all
      committed test traces.
- [ ] Random delivery permutations and duplicate/concurrent traces converge to
      equal visible text and equivalent RawVersion frontiers.
- [ ] The large-history single-admission guard shows no full-history expansion
      or duplicate causal-map maintenance on the admission path.
- [ ] The release-mode benchmark outcome is recorded in the dated Gate A
      evidence document.
- [ ] EGW checks/tests pass and generated `.mbti` files have no unintended
      changes.
- [ ] No production `Document`, `Branch`, public API, archive schema, wire
      schema, or persistent Fugue lifecycle changes are included.

## Validation

Run from the EGW submodule root (`deps/event-graph-walker`):

```bash
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
git diff -- '*.mbti'
```

Run focused tests/benchmarks using the repository's existing MoonBit test and
benchmark selection conventions for:

- `internal/branch` Gate A whitebox tests;
- `internal/oplog` fixed-point oracle and admission lifecycle tests;
- `internal/oplog/admission_overhead_benchmark_wbtest.mbt` and its Gate A
  extensions;
- existing Branch merge and checkout tests.

Run the release benchmark command from the EGW submodule root and record its
outcome in the dated Gate A evidence document:

```bash
NEW_MOON_MOD=0 moon bench --release
```

Before coding, verify APIs and callers from the EGW submodule root
(`deps/event-graph-walker`):

```bash
NEW_MOON_MOD=0 moon ide outline internal/branch
NEW_MOON_MOD=0 moon ide outline internal/oplog
NEW_MOON_MOD=0 moon ide peek-def OpLog::prepare_remote
NEW_MOON_MOD=0 moon ide peek-def OpLog::commit_remote
NEW_MOON_MOD=0 moon ide find-references Branch::checkout
NEW_MOON_MOD=0 moon ide find-references PartialRemoteAdmission
```

The parent workspace is not required for this test-only submodule gate unless
its pointer or integration files change. Do not run or alter `deps/loom` as
part of this gate.

After opening the implementation PR, inspect raw CI results with:

```bash
gh pr checks <NUMBER>
```

Open the implementation PR only after the local validation gate succeeds.
Do not merge or declare that PR ready for merge until every required CI check is
`pass`; a `pending`, `fail`, or `skipped` required check is not green.

## Risks

- The published baseline is test-only and pinned to EGW commit `44164cd`. A
  fresh agent must fetch that immutable commit or copy its two files before
  A1; it must not assume untracked files exist in a new worktree. Preserve any
  unrelated dirty worktree and use a dedicated branch/worktree for Gate A; do
  not reset `deps/loom` or publish the prototype implicitly.
- A canonical position event cannot be lowered until its parent context is
  available. The test harness may buffer canonical envelopes, but it must not
  grow a second causal dependency planner or silently treat buffered events as
  Causal Authority.
- Parent-relative semantic validation must not use the receiver's newer visible
  text. Using the wrong version will reject valid concurrent edits or admit
  invalid positions.
- A one-to-many adapter would invalidate the one-RawVersion-per-scalar contract;
  keep the canonicalizable domain one-to-one and make non-canonical legacy
  compatibility explicit.
- `Branch::checkout` can hide admission errors if used as the only oracle.
  Keep admission, adapter, and projection oracles separate.
- Partial admission is intentionally not rollback. Tests that expect the
  pre-commit visible text after a typed partial error are incorrect.
- Existing delete-winner and tombstone behavior is subtle. Reuse the existing
  projection/merge implementation as the oracle rather than reimplementing
  winner logic in TextEvent.
- The accepted projection-lifecycle ADR mentions version mappings. The target
  clarification permits query capability and run/piece-level spans but forbids
  one causal identity/tombstone record per scalar in the normal projection.
- Gate A proves correctness of the boundary only. It does not prove the paper's
  startup, memory, partial-replay, or merge performance.

## Notes

- Related ADRs: `docs/decisions/2026-07-22-indexed-projection-lifecycle.md` and
  `docs/decisions/2026-08-12-causal-authority-residency.md`.
- Related evidence: `docs/performance/2026-08-10-loomark-startup-history-corpus.md`.
- The next phase, after this gate, must separately design the Plain-text
  editing projection and its differential migration stages. It must not be
  folded into Gate A merely because the canonical event model is now proven.
