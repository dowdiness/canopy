# EGW peer-sync contract spike

**Date:** 2026-07-22

**Status:** Completed and archived — GO WITH CONDITIONS

**Related:**
[EGW companion and Canopy migration](../plans/2026-07-22-egw-companion-canopy-migration.md) ·
[EGW collaboration responsibility boundary](../decisions/2026-07-21-egw-collaboration-responsibility-boundary.md) ·
[Typed spreadsheet room and join UX](../superpowers/specs/2026-07-22-typed-spreadsheet-room-join-ux.md) ·
[Typed spreadsheet EGW boundary experiment](../../loom/incr/plans/013-typed-spreadsheet-egw-boundary-experiment.md)

**Reader:** Maintainers proving the first peer-sync contract shared by EGW text
and container drivers before assigning a public package boundary.

**Decision:** Prove behavior in an isolated, private EGW 0.4 experiment before
moving Canopy code, publishing a companion, changing dependency versions, or
implementing room transport.

**Keep until:** Complete. The ADR records the result and the follow-up migration
plan adopts the private spike as semantic evidence.

**Disposition:** Archived after the collaboration ADR recorded the conditional
GO. The follow-up migration plan keeps the private package until its scenarios
have one canonical production owner, then deletes it. No additional ADR was
needed because the existing collaboration ADR owns this decision.

## Why

The current text collaboration path and typed-spreadsheet container path both
need bootstrap, version exchange, causal-gap recovery, reconnect, and status
semantics. Their current package locations cannot establish that the behavior is
actually shared:

- Canopy's `sync_session` is tied to the EGW text façade.
- EGW core already owns document-local causal pending storage and replay.
- Canopy's collaboration runtime, wire protocol, and relay combine concerns that
  the accepted ADR separates.
- The typed-spreadsheet application is a separate module on exact EGW 0.4 and is
  not a member of the parent Canopy workspace.
- Parent Canopy still requests EGW 0.3 in its published manifest even though the
  checked submodule is 0.4.

Starting with a package extraction would turn assumptions into API. This spike
instead asks whether text and container produce the same deterministic
peer-sync decisions when given equivalent collaboration events.

## STOP conditions

1. **No EGW edit without approval.** Planning and read-only inspection are
   authorized. Before changing any file in `event-graph-walker`, obtain explicit
   user approval naming that repository and the spike action.
2. **No publication or external action.** Do not push an EGW branch, publish a
   package, open a PR, or comment on an issue without separate approval.
3. **No cross-version test module.** Do not create a Canopy module that imports
   both Canopy's EGW 0.3 dependency graph and EGW 0.4. Run the executable proof
   inside the EGW 0.4 module.
4. **No workspace override as evidence.** A parent workspace override does not
   prove that a future published Canopy consumer resolves the intended EGW
   version.
5. **No second causal queue.** Stop if a candidate companion needs to retain raw
   CRDT operations or replay causal dependencies outside EGW core.
6. **No forced common contract.** If text and container reports or failures
   imply materially different recovery semantics, record the difference and
   return a no-go result.

## Scope

### In

- Read-only verification of current EGW text, container, and shared sync APIs.
- A private, removable experiment inside the EGW 0.4 module after approval.
- Deterministic reducer-shaped peer-sync state and decision tests.
- Separate text and container adapters over existing public EGW APIs.
- A deterministic delivery harness that can reorder, duplicate, drop, and later
  deliver opaque messages without opening sockets.
- Scenario evidence for bootstrap, incremental sync, duplicates, missing
  dependencies, concurrent offline edits, reconnect, peer departure during
  recovery, and convergence.
- A go/no-go recommendation for a later EGW-versioned companion.

### Out

- Room and join UI implementation.
- WebSocket, WebRTC, Cloudflare, or relay changes.
- Presence, remote cursors, persistence, authentication, or access control.
- Reset or document-replacement semantics.
- Performance optimization or sparse-impact reporting.
- A public peer-sync API or published package.
- Canopy dependency upgrades or submodule pointer updates.
- A generic `egw_incr` bridge.

## Current state

### EGW 0.4

The text and container façades already expose document-bound synchronization
through version, full export, incremental export, and apply operations. EGW
validates causal dependencies and keeps document-local pending operations.
Strict façade JSON codecs carry sync messages across process boundaries.

The exact report and failure surfaces must be checked from generated interfaces
and `moon ide` before coding. In particular, do not assume that text and
container expose identical report accessors merely because their high-level
sync flow is similar.

### Canopy

`sync_session` contains useful recovery and status evidence, but its current
host contract names text-façade versions and messages. `protocol/wire` and relay
tests provide evidence for peer control, directed requests, duplicates, and
malformed frames. They are reference inputs for the scenario matrix, not code
to import into the EGW proof.

The earlier WebSocket client and sync-recovery plans predate the accepted
five-layer boundary. This plan supersedes them as the active collaboration
contract spec; their implementation history moves to the archive.

Parent `moon.mod` requests EGW 0.3 while the workspace selects the checked EGW
0.4 submodule. An external consumer therefore resolves behavior different from
the workspace-tested source. Treat external collaboration consumption as
unverified until the manifest is reconciled before publication.

### Typed spreadsheet

The application-specific adapter on branch
`advisor/013-egw-boundary-experiment` uses the exact published EGW 0.4 release.
Local browser commits now route through EGW authority and one projection path.

Remote transport is not implemented. Existing adapter tests prove container
convergence and local draft preservation, but do not define a reusable peer-sync
state machine.

## Desired state

The spike ends with executable evidence, not a public abstraction:

- Text and container drivers consume equivalent peer-sync events and produce
  decisions with the same meanings.
- EGW core remains the only owner of pending CRDT operation storage and replay.
- The candidate companion interprets EGW reports and failures and decides peer
  recovery commands without owning transport lifecycle.
- Generic connection state, transport backpressure, and provider behavior are
  represented only as external capabilities or test events.
- The evidence identifies which semantics can move to an EGW-versioned
  companion and which must remain in a reusable runtime or provider.
- A no-go result is acceptable and records the façade differences that prevent
  safe reuse.

## Reuse check

### Reuse in the proof

- **EGW text and container sync sessions:** `sync()`, `export_all`,
  `export_since`, and `apply` are the authority boundary. Verify exact names and
  error shapes with `moon ide` before implementation.
- **EGW façade versions and sync-message codecs:** use existing owning-type
  serialization and parsing. Do not define a second wire format.
- **EGW apply reports and shared sync failures:** use actual pending, duplicate,
  applied, malformed, identity-conflict, and limit signals where exposed.
- **Existing text/container multi-replica tests:** reuse their operation setup
  and convergence assertions rather than retesting CRDT algorithms through a
  new implementation.
- **Typed-spreadsheet adapter scenarios:** reuse the established meanings of
  full attach, incremental apply, authoritative projection, and dirty-draft
  preservation when assessing the container driver.

### Checked but not reused in the executable proof

- **Canopy `SyncSession`, `SyncHost`, and recovery state:** reference their
  scenarios, but do not import them because they are text-bound and are the
  boundary under evaluation.
- **`protocol/wire`:** reference peer-control and request/response behavior, but
  do not make its Canopy-specific frame family the candidate contract.
- **`InMemoryRoom` and `InMemoryTransport`:** reference transport semantics, but
  do not import the parent Canopy module into the EGW 0.4 proof. Use a test-local
  deterministic scheduler with no production transport API.
- **Relay and Cloudflare glue:** use only as evidence for provider events and
  routing metadata.

### MoonBit core candidates to check

Before adding state or collection logic, inspect concrete candidates with
`moon ide`:

- `Map` for peer-indexed state;
- `Array` or `ReadOnlyArray` for returned decisions;
- `Option` and `Result` for transitions and apply outcomes;
- `Bytes` or `BytesView` for opaque test delivery; and
- `Buffer` or `StringBuilder` only if existing codecs do not cover
  serialization.

Prefer existing owning-type methods and pattern matching. Any local mutation
must only build a returned value or drive the deterministic delivery harness.

### New private definitions

The spike may introduce private, removable concepts for:

- peer-sync state;
- peer-sync events;
- peer-sync decisions;
- a pure transition function; and
- text/container driver records that supply existing EGW operations.

Do not introduce a public trait or generated interface change during the spike.
The responsibility boundary is deterministic peer recovery only; reactive
projection and transport I/O remain outside it.

## Steps

### Phase 0 — verify APIs and scenario semantics

1. From the EGW 0.4 module root, inspect the text, tree, container, and shared
   sync package outlines and generated interfaces. Record actual apply report,
   pending-operation, duplicate, version, and error APIs in this plan.
2. Use `peek-def` and `find-references` to determine where document-local pending
   operations are stored and replayed for text and container. Name that code in
   the spike evidence so no companion queue is added accidentally.
3. Inspect current Canopy `sync_session`, wire, relay, and recovery tests. Reduce
   them to behavioral scenarios without copying their types or frame format.
4. Inspect typed-spreadsheet adapter tests for full sync, incremental sync,
   convergence, and dirty drafts. Record which behavior belongs to the
   application rather than peer-sync.
5. Finalize one scenario matrix with common inputs, observable EGW outcomes, and
   expected peer-sync decisions. Mark façade-specific assertions explicitly.

### Phase 1 — private EGW proof, after explicit authorization

6. Add one private experiment package inside the EGW 0.4 module. Keep all
   candidate state, events, decisions, and driver records non-public so
   `moon info` shows no public API drift.
7. Model the functional core as a deterministic transition from peer-sync state
   and one event to next state plus decisions. Keep clocks, message delivery,
   and document mutation in the test shell.
8. Add a text driver record that delegates version, export, parse, apply, and
   report inspection to existing text APIs.
9. Add a container driver record with the same responsibilities using existing
   container APIs. Map façade-specific applied counts only at this adapter edge.
10. Add a deterministic delivery harness that stores test envelopes, not CRDT
    pending operations. It must support deliver, delay, duplicate, drop,
    disconnect, reconnect, and peer-left events.
11. Prove initial full bootstrap for text and container. A fresh receiver must
    converge after applying existing full-sync messages.
12. Prove incremental synchronization after a shared baseline for both drivers.
13. Prove duplicate delivery is idempotent and does not initiate peer recovery.
14. Prove out-of-order or missing-dependency delivery reaches EGW core, appears
    through the actual report/failure surface, and yields a peer recovery
    decision without retaining payloads in companion state.
15. Prove failure classification distinguishes retryable causal gaps from
    malformed messages, conflicting identity, and limit failures. The latter
    failures must surface or escalate without an unbounded peer-request loop.
16. Prove concurrent offline edits converge after bidirectional exchange.
17. Prove reconnect uses full synchronization and clears recovery only after EGW
    reports causal progress.
18. Prove peer departure during recovery cancels peer-specific recovery without
    clearing EGW's document-local pending state.
19. Run the same decision-trace assertions for text and container. Keep separate
    document-content assertions at each driver edge.

### Phase 2 — evaluate the boundary

20. Compare the two traces and classify every difference as façade mapping,
    EGW semantic difference, application policy, or accidental implementation
    detail.
21. Check that candidate state contains no CRDT payload queue, application
    document identity, presence, room, transport, `incr`, or projection state.
22. If the traces establish one contract, write a bounded proposal for a later
    EGW-versioned companion. If they do not, record a no-go result and the
    smallest façade-specific boundaries that remain valid.
23. Update the collaboration ADR with the result. Do not publish an API or move
    production code under this plan.
24. Remove private spike code unless the follow-up migration plan explicitly
    adopts it. Archive this plan with its result and update the collaboration
    backlog.

## Result

The private EGW 0.4 experiment at local commit `c296d8f` established one
event/decision contract for the real text and container façades. It remains on
unpublished branch `advisor/peer-sync-contract-spike` in an isolated worktree.

No push, package publication, parent pointer update, or public API change
occurred.

The test-only reducer covers admission, version comparison, full bootstrap,
incremental local commits, bounded recovery, disconnect/reconnect, peer
departure, and fatal escalation. State contains only peer lifecycle and retry
metadata.

A test scheduler holds envelopes only before apply. Text
`pending_sync_records` and container `pending_sync_ops` remain the sole causal
pending queues after delivery.

Fifteen deterministic scenarios prove identical decision traces for text and
container bootstrap, duplicate delivery, incremental sync, offline concurrent
edits, out-of-order recovery, reconnect, and version-confirmed convergence.

Both façades classify malformed, invalid-content, conflicting-identity, and
limit failures as terminal without request/retry loops. Multi-peer incremental
fan-out is also pinned.

Validation from the EGW worktree passed:

- targeted `moon check --deny-warn` and 15/15 tests;
- full `moon check --deny-warn` and 681/681 tests;
- `moon fmt` and `moon info`; and
- an empty generated interface for the private package, with no existing
  `.mbti` drift.

Independent `moonbit-reviewer` review returned PASS. Independent
`qwen3.8-max-preview` review returned GO WITH CONDITIONS and found no spike
defect after the multi-peer fan-out test was added.

Consumer validation exposed the expected migration blocker. Parent Canopy full
`moon check` and targeted `sync_session` do not compile against the workspace's
EGW 0.4. Loom's lambda fixture uses the older raising/apply shape, while
`sync_session` still names removed text failure variants.

The unaffected boundaries pass: `protocol/wire` passed 19/19 tests, `relay`
passed 45/45, and the nested exact-EGW-0.4 typed-spreadsheet adapter passed 19/19
JS tests.

**Decision:** GO for a shared EGW-versioned companion contract. NO-GO for
publication or Canopy migration until a follow-up plan reconciles the parent
EGW 0.3 manifest, the checked EGW 0.4 source, Loom's text fixture, and Tier 1
`sync_session` compatibility without a workspace override.

## Acceptance criteria

- [x] Actual EGW 0.4 text and container APIs are recorded from generated
      interfaces and `moon ide`, without inferred method names.
- [x] Existing document-local pending storage and replay ownership is named and
      remains solely in EGW core.
- [x] One scenario matrix covers full bootstrap, incremental sync, duplicate
      delivery, missing/out-of-order dependencies, concurrent offline edits,
      reconnect, peer departure during recovery, and convergence.
- [x] Both drivers distinguish retryable missing dependencies from malformed,
      conflicting-identity, and limit failures without an unbounded recovery
      loop.
- [x] Text and container run through the same private transition semantics.
- [x] Candidate peer-sync state contains no raw CRDT operation or sync-message
      queue.
- [x] The deterministic delivery harness remains test-only and does not become a
      second transport protocol.
- [x] No public trait, generic `egw_incr`, room, presence, persistence, reset,
      WebSocket, relay, or Cloudflare API is introduced.
- [x] No EGW, Canopy, Loom, or incr dependency version changes occur.
- [x] The collaboration ADR records the spike result before this plan is
      archived.
- [x] Generated interfaces show no unintended public API drift.

## Validation

### Preflight API checks

Run serially from `event-graph-walker/`:

```bash
NEW_MOON_MOD=0 moon ide outline text/text_doc.mbt
NEW_MOON_MOD=0 moon ide outline text/sync.mbt
NEW_MOON_MOD=0 moon ide outline container/document.mbt
NEW_MOON_MOD=0 moon ide outline sync/types.mbt
NEW_MOON_MOD=0 moon ide doc "Map::*"
NEW_MOON_MOD=0 moon ide doc "Bytes::*"
NEW_MOON_MOD=0 moon ide doc "Option::*"
NEW_MOON_MOD=0 moon ide doc "Result::*"
NEW_MOON_MOD=0 moon ide find-references "@text.SyncReport::pending_operations"
NEW_MOON_MOD=0 moon ide find-references "@container.SyncReport::pending_operations"
```

Use `peek-def` on the actual report, version, and sync-message symbols returned
by the outlines before defining adapters.

### EGW proof

From `event-graph-walker/` after authorization and implementation:

```bash
moon fmt
moon info
git diff -- '**/pkg.generated.mbti'
moon check
moon test
```

Run targeted tests for the private experiment package first, then the full EGW
suite. No generated interface change is expected.

### Consumer regression checks

The spike does not edit consumers, but verify assumptions from their owning
roots before recording a go result:

```bash
# Parent Canopy
moon check
moon test

# Nested incr workspace
cd loom/incr
NEW_MOON_MOD=0 moon test --target js examples/typed_spreadsheet_incr_tea_demo/egw_adapter
```

Use the current CI workflow as the source of truth for any additional JS and
browser jobs required by a later migration plan.

### Documentation

From the parent Canopy root, verify the agent-instruction alias and whitespace:

```bash
bash scripts/check-agent-doc-links.sh
git diff --check
```

`check-agent-doc-links.sh` checks only the `CLAUDE.md` alias. Resolve every
relative Markdown link changed by the spike separately; the repository does not
currently provide a general Markdown link checker.

From `loom/incr/` when nested links change:

```bash
python3 scripts/check-documentation-boundaries.py
git diff --check
```

## Risks

- Text and container may expose different report semantics. A no-go result is
  preferable to hiding that difference behind an overly generic adapter.
- Existing Canopy recovery may combine CRDT recovery with connection status.
  The scenario matrix must separate those behaviors rather than porting the
  current state machine intact.
- A test delivery harness can become a disguised second causal queue. It may
  delay envelopes only before apply; after delivery, EGW core owns causal
  pending state.
- Parent workspace resolution can mask published dependency versions. Consumer
  migration must later verify without workspace overrides.
- Any later EGW companion must be committed, pushed, and published before
  Canopy updates its dependency or parent submodule pointer.
- Tier 1 compatibility for `protocol/wire`, `sync_session`, and `ephemeral`
  remains active until a separate migration plan and release cycle supersede
  it.
