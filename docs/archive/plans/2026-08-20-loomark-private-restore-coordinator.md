# Private Rabbita Restore Coordinator

**Status:** Blocked — architecture accepted; production cutover waits for #1298, #1299, and #1301.

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/1322>

The issue and this plan are reciprocal. The issue owns active status and blocker state; this
plan owns implementation order, invariants, test surface, and validation.

Decision record:

- [Private restore coordinator for Loomark cold open](../decisions/2026-08-20-loomark-private-restore-coordinator.md)

## Why

The current standalone bootstrap can admit or reject one archive, but planned progressive
restore adds readable-before-editable presentation, a validated accelerator, canonical
fallback, Retry supersession, and continuity-preserving activation. Implementing these as
additional callback branches would distribute authority and ordering rules across Rabbita,
storage, repository, and DOM effects. The accepted decision places that complexity behind
one private coordinator interface.

## Scope

In:

- add `apps/loomark/internal/rabbita/restore_coordinator.mbt`;
- add `apps/loomark/internal/rabbita/restore_coordinator_wbtest.mbt`;
- update `apps/loomark/internal/rabbita/standalone_bootstrap.mbt`;
- update `apps/loomark/internal/rabbita/application.mbt` and `driver_types.mbt`;
- update focused restore/continuity effects in `focus_runtime.mbt` or the existing narrow
  DOM-effect module that owns the operation;
- reuse `apps/loomark/archive/archive.mbt` and
  `apps/loomark/repository/repository.mbt` through their existing interfaces;
- extend `apps/loomark/examples/vanilla/tests/standalone.spec.ts`;
- refresh generated interfaces only when MoonBit reports a real public-surface change.

Out:

- choosing the retained-state candidate or IndexedDB versus OPFS;
- changing canonical v1 full-history authority;
- exposing a public restore lifecycle, candidate, subscription, or mutation handle;
- collaboration wire changes, history compaction, restart undo, or history deletion;
- provisional editing, queued typing, silent fallback, or accelerator-derived visible text.

## Current State

- `application.mbt` claims the one-shot mount before asynchronous storage completion and
  exposes only `mount_standalone` through the generated Rabbita interface.
- `application.mbt` initiates the asynchronous storage read;
  `standalone_bootstrap.mbt` handles its completion, repository classification,
  session adoption, and recovery directly in the Rabbita update loop.
- `archive.mbt` can structurally decode an archive and expose portable Markdown before
  admission.
- `repository.mbt` already exposes `reopen_decoded_local_archive`, so the progressive path
  needs no new repository interface.
- `EditorSession` is the existing private mutation capability.
- `MarkdownDocumentUtf16Selection` preserves anchor, head, bounds, and backwardness; the
  `BlockSelection` conversion in the current focus path writes `NoDirection` and is not a
  valid activation round-trip.
- `recovery_state.mbt` and existing recovery views already define terminal recovery actions
  that the coordinator must preserve rather than duplicate.

## Fixed Invariants

1. Canonical text comes only from canonical v1 archive/history material.
2. Readability does not imply mutation readiness.
3. `EditorSession` enters the live application only after complete constrained admission and
   canonical-text equality.
4. Candidate rejection automatically starts canonical full-history fallback without changing
   visible text.
5. Every asynchronous result is generation-bound; stale results cannot render, activate, or
   replace a session.
6. Input before the editable state is rejected and never replayed later.
7. Activation preserves scroll, logical focus, focus endpoint, and directed UTF-16 selection
   before the editable state becomes visible.
8. Terminal failure never manufactures an editor or substitutes accelerator text.
9. `mount_standalone(String, String) -> String` remains the sole public cold-open interface.
10. Existing storage and DOM adapters are reused; no forwarding port is added.

## Decision Inputs Required Before Production Cutover

| Decision | Required output consumed by this plan |
|---|---|
| [Performance envelope (#1298)](https://github.com/dowdiness/canopy/issues/1298) | Thresholds for authority-to-readable, readable-to-editable, fallback-to-editable, activation, memory, serialized size, cold-history reads, and first-edit displacement. |
| [Retained-state candidate (#1299)](https://github.com/dowdiness/canopy/issues/1299) | One selected candidate or no-accelerator result, its validation evidence, canonical-text equality proof, and capabilities reserved for fallback. |
| [Publication and recovery contract (#1301)](https://github.com/dowdiness/canopy/issues/1301) | Generation publication, integrity, writer coordination, failed-write visibility, recovery, quota behavior, and schema migration rules. |

When a blocker closes, replace this table's requirement with a link to its recorded decision
and concrete values. Do not infer missing values from prototypes or benchmark summaries.

## Desired State

One private coordinator owns `start`, `step`, and `view`. Its exhaustive state distinguishes
authority loading, preparing editing with canonical text, rebuilding from canonical history,
correlated activation, editable completion, terminal readable recovery, and terminal
unavailability. The Rabbita shell interprets typed commands through existing adapters and
cannot independently decide readiness or fallback precedence.

The user sees one stable surface: canonical Markdown becomes read-only as soon as it is
structurally available, remains visible through validation or rebuilding, and becomes
editable only after authority plus activation continuity succeed. Retry supersedes old work;
terminal states expose only the actions accepted by #1296.

## Implementation Steps

### 1. Pin the current contract before extraction

- Add coordinator-level failing tests for the future observable contract before production
  behavior changes.
- Preserve existing archive/repository tests as the authority oracle.
- Record the generated Rabbita interface and current standalone browser behavior as the
  compatibility baseline.
- Manually derive expected state sequences for success, missing archive, rejected archive,
  Retry supersession, and terminal failure.

### 2. Extract the private coordinator without changing behavior

- Introduce private state, event, command, and transition values plus `start`, `step`, and
  `view`.
- Move current bootstrap ordering verbatim behind the coordinator; keep storage,
  classification, recovery, and session adoption behavior unchanged.
- Make the application update loop interpret commands rather than reproduce transition
  policy.
- Keep this move-only refactor in a separate commit. Qualify only names required by the new
  file/package context and record each qualification in the commit message.

### 3. Add progressive canonical readability

- Replace the progressive path's all-in-one classification call with structural archive decode.
- Enter the readable preparation state with `portable_markdown` before causal admission.
- Start admission through `reopen_decoded_local_archive`; retain canonical text on rejection.
- Reject input while the coordinator is not editable and prove no command is queued.
- Move all render/subscription/input readiness checks from the Boolean proxy to coordinator
  state. Retain the Boolean only if persistence policy still needs it.

### 4. Integrate the accepted candidate and canonical fallback

- Wait for #1298, #1299, and #1301; copy their exact outputs into this plan first.
- Translate the selected provider result into private generation-bound coordinator events.
- Validate the candidate independently and compare hydrated text with canonical text.
- On any rejection, integrity failure, unsupported version, incomplete history, unresolved
  dependency, or capability failure, dispose of the candidate and command canonical
  full-history admission.
- Keep candidate/provider details behind existing adapters and out of the coordinator's public
  package surface.

### 5. Make activation correlated and continuity-preserving

- Capture scroll, logical focus, focus endpoint, and `MarkdownDocumentUtf16Selection` before
  replacing the read-only surface.
- Carry anchor, head, ordered bounds, and direction without converting through
  `BlockSelection`/`NoDirection`.
- Apply the new session and continuity after render under the same generation.
- Enter editable only after confirmation. Keep transient failures retryable and classify
  definitive failures as terminal readable recovery.
- Emit polite progress announcements on state entry and one terminal alert without duplicate
  Retry chatter.

### 6. Clean cutover and evidence

- Remove direct bootstrap branches, duplicate readiness conditions, obsolete comments, and
  aliases after every caller uses the coordinator.
- Verify generated interfaces contain no restore lifecycle type and no unintended public
  change.
- Run the accepted performance matrix, including first-edit cost, on the existing startup
  corpus and record the threshold verdict.
- Update architecture/current-state documentation only after the browser smoke test proves
  the cutover.

## Acceptance Criteria

- [ ] `mount_standalone(String, String) -> String` remains the sole public cold-open interface.
- [ ] One private coordinator owns all restore transition, stale-result, fallback, terminal,
  and activation ordering.
- [ ] Canonical Markdown is readable before mutation authority and remains unchanged through
  candidate rejection and fallback.
- [ ] Only complete causal admission plus canonical-text equality can install `EditorSession`.
- [ ] Retry makes every older generation incapable of rendering or activation.
- [ ] Input before editable is rejected and never replayed.
- [ ] Terminal readable and unavailable states expose only their accepted actions.
- [ ] Emoji/non-BMP and backward selections round-trip exact UTF-16 anchor, head, bounds, and
  direction together with scroll and focus endpoint.
- [ ] Activation failure never exposes an editor with lost continuity.
- [ ] Readiness announcements use polite progress and a non-repeating terminal alert.
- [ ] Candidate success and canonical fallback meet the thresholds accepted by #1298 without
  shifting restore cost into the first edit.
- [ ] Archive/repository authority tests, coordinator tests, and standalone browser tests pass.
- [ ] Generated-interface review reports no unintended public change.
- [ ] Documentation links the implementation issue, this plan, the ADR, and the final PR.

## Validation

From `apps/loomark`:

```bash
rtk moon check
rtk moon test
rtk moon fmt
rtk moon info
```

From `apps/loomark/examples/vanilla` after installing its pinned dependencies:

```bash
rtk npm run typecheck:standalone
rtk npm run test:standalone
rtk npm run bench:startup
```

The browser smoke test must exercise the actual delayed restore path, not only a test reducer:
observe canonical read-only text, candidate success or forced fallback, same-surface editable
activation, directed selection, scroll, focus, and announcements.

## Risks

- A reducer that returns broad storage/DOM records would recreate a shallow interface; keep
  commands purposeful and private.
- Installing `EditorSession` before continuity confirmation creates a partially successful
  activation that violates the accepted UX contract.
- Reusing `BlockSelection` for activation silently loses backward direction.
- A benchmark that stops at restore completion can miss deferred first-edit work.
- Updating the candidate or publication contract before their decision tickets close would
  launder prototype assumptions into production semantics.
- The behavior-preserving extraction and new behavior must remain separate commits so either
  can be reviewed or reverted independently.

## Notes

- Architecture decision: <https://github.com/dowdiness/canopy/issues/1320>
- Readiness decision: <https://github.com/dowdiness/canopy/issues/1296>
- Lifecycle research: <https://github.com/dowdiness/canopy/issues/1321>
- Wayfinder map: <https://github.com/dowdiness/canopy/issues/1295>
- Gate R0: [canonical issue #1288](https://github.com/dowdiness/canopy/issues/1288)
  owns live status; its branch-scoped
  [test-only feasibility plan](https://github.com/dowdiness/canopy/blob/docs/loomark-editable-branch-restore-feasibility/docs/plans/2026-08-19-loomark-editable-branch-restore-feasibility.md)
  is supporting evidence, not this plan's status source.
