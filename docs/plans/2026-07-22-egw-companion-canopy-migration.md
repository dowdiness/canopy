# EGW companion and Canopy compatibility migration

**Date:** 2026-07-22

**Status:** Canopy migration is blocked at the wire compatibility gate;
EGW companion source remains separately approval-gated

**Related:**
[Collaboration responsibility ADR](../decisions/2026-07-21-egw-collaboration-responsibility-boundary.md) ·
[Archived peer-sync contract spike](../archive/2026-07-22-egw-peer-sync-contract-spike.md) ·
[Typed-spreadsheet room and join UX](../superpowers/specs/2026-07-22-typed-spreadsheet-room-join-ux.md) ·
[EGW 0.3/0.4 wire evidence](../research/2026-07-22-egw-03-04-wire-compatibility.md)

**Reader:** Maintainers migrating EGW, Loom, and Canopy without hiding version
skew behind a workspace override or breaking Tier 1 collaboration APIs.

**Decision:** Publish a minimal EGW-versioned peer-sync policy before Canopy
consumes it. Migrate Loom and Canopy to that published EGW version.

Preserve the current Tier 1 `protocol/wire`, `sync_session`, and `ephemeral`
interfaces, then extract payload-opaque session mechanics behind the existing
`sync_session` façade. Transport productization remains a later plan.

**Keep until:** EGW, Loom, and Canopy resolve the same published EGW version
without a workspace override, compatibility validation passes, and the private
spike package has been adopted into production tests or deleted.

**Disposition:** When complete, update the collaboration ADR with release and
compatibility evidence, then move this plan to `docs/archive/`. Keep durable API
and release decisions in the ADR; delete temporary compatibility snapshots and
worktrees.

## Why

The private EGW 0.4 spike proved one event/decision contract with real text and
container drivers. It also exposed the next blocker:

- parent `moon.mod` requests EGW 0.3;
- parent `moon.work` selects the checked EGW 0.4 submodule;
- Loom's lambda fixture still uses the older text façade shape; and
- Tier 1 `sync_session` names the removed `@text.SyncFailure` type.

Parent full checks therefore fail under the workspace's EGW 0.4 even though
`protocol/wire`, `relay`, and the nested exact-0.4 container adapter pass.
Adding rooms or WebSockets now would preserve the accidental text-boundary and
make the compatibility problem harder to isolate.

The migration must separate two reasons to change:

1. EGW-derived version, apply-report, failure, and recovery meaning changes with
   EGW.
2. Connection lifecycle, stale envelopes, watchdogs, and backpressure change
   with collaboration runtime policy.

## Goal

Deliver a version-aligned semantic foundation for later transport work:

- an EGW-versioned, payload-free per-peer sync policy with concrete text and
  container adapters;
- Canopy and Loom compiled and tested against the same published EGW version;
- byte-for-byte Tier 1 public interface preservation in Canopy;
- payload-opaque session mechanics behind `sync_session`; and
- no second causal pending-operation queue.

## Non-goals

- Room/share/join UI.
- WebSocket, WebRTC, Cloudflare, relay, or provider implementation.
- Presence, cursors, persistence, authorization, or bearer-link revocation.
- Reset or document replacement.
- A generic `egw_incr` bridge.
- Performance optimization or sparse-impact reporting.
- Silently reusing the existing protocol version for incompatible EGW
  payloads. This plan may prove compatibility; an incompatible result requires
  a separate wire-version decision before migration continues.
- Changing the ephemeral schema.
- Deprecating Tier 1 APIs during this migration.
- Supporting EGW 0.3 and 0.4 in one MoonBit module graph.

## Authorization and STOP gates

Planning and read-only inspection are authorized. The private spike was
explicitly authorized and committed locally at `c296d8f`; it is not published.
This plan does not extend that authorization to public source or external
repository actions.

1. **EGW public source gate:** obtain explicit approval before adding public
   companion packages or changing EGW source outside the private spike.
2. **EGW external-action gate:** commit, push, PR, merge, and package publication
   are separate approvals. Do not infer one from another.
3. **Loom source gate:** obtain explicit approval before editing the Loom
   submodule repository. Push a Loom commit before updating its parent pointer.
4. **Canopy dependency gate:** update parent manifests or submodule pointers only
   after the required EGW and Loom commits are reachable from their remotes.
5. **No workspace override as release evidence:** a passing parent workspace
   with local EGW selected does not prove published resolution.
6. **Tier 1 interface gate:** stop on any unintended `protocol/wire`,
   `sync_session`, or `ephemeral` signature, visibility, constructor, error, or
   trait-bound change.
7. **Wire compatibility gate:** stop before the Canopy bump if EGW 0.3 and the
   target release cannot exchange the current `CrdtOps`, `SyncRequest`, and
   `SyncResponse` payloads. Choose an explicit bridge or protocol-version plan;
   never let a v2 frame decode successfully and fail later as hidden sync JSON.
8. **Single causal queue gate:** stop if the companion or Canopy runtime needs to
   retain applied CRDT operations for causal replay.
9. **Scope gate:** stop if compatibility requires transport, room, presence,
   persistence, application projection, or `incr` state.

## Current state

### EGW

The checked submodule and isolated spike are EGW 0.4. Text and container own
nominal `Version`, `SyncMessage`, and `SyncReport` types.

Both depend on shared `@sync.Failure` and keep their own document-local pending
arrays.

Local commit `c296d8f` adds a private, test-only
`internal/peer_sync_contract` package. Fifteen scenarios prove common decision
traces, bounded retries, terminal failure handling, offline convergence,
reconnect, and peer departure.

The package interface is empty. Full EGW validation passed 681/681 tests with
deny-warn.

The spike deliberately combines EGW policy and session lifecycle so their seam
can be tested. Production code must split them rather than copying that reducer
as one package.

### Loom

`loom/examples/lambda/moon.mod` requests EGW 0.3.

Its `EgwPeer::new` assumes `TextState::new` does not raise, and `bridge_sync`
ignores the non-`Unit` apply receipt. These are source compatibility fixes in
the Loom repository, not Canopy-owned edits.

### Canopy

Parent `moon.mod` requests EGW 0.3 while `moon.work` contains the EGW 0.4
submodule. Tier 1 `sync_session` exports `@text.Version` and
`@text.SyncMessage` through `SyncIo` and `SyncHost`.

The payload helpers in `sync_session` still match obsolete text-level failure
cases, including timeout. Current EGW provides shared failure and retryability
APIs instead.

`sync_session` already owns watchdog timeout and retry exhaustion, so it must
not recreate an EGW timeout variant.

`protocol/wire` and `relay` are EGW-opaque and already pass independently.
Their public surfaces remain unchanged.

### Typed spreadsheet

The nested demo is outside parent `moon.work` and requests exact published EGW
0.4. Its adapter tests pass 19/19 on JS. It is a consumer validation target, not
a package to migrate in this plan.

## Desired ownership and package DAG

```text
EGW sync                  shared Failure and limits
  ├─ text                 text Version/Message/Report + document pending queue
  ├─ container            container Version/Message/Report + document pending queue
  └─ peer_sync            per-peer EGW recovery policy; imports sync only
       ├─ peer_sync/text       concrete text report/error adapter
       └─ peer_sync/container  concrete container report/error adapter

Canopy internal/collaboration_session
  └─ generic peer lifecycle, stale envelope, watchdog, backpressure state
       └─ imported by Tier 1 sync_session façade
            ├─ existing protocol/wire
            ├─ EGW peer_sync + peer_sync/text
            └─ existing SyncHost/SyncIo/SyncTransport public surface
```

The EGW policy is per peer and stores no room or peer map. The Canopy runtime
owns peer IDs and connection lifecycle but does not import EGW types. The
`sync_session` shell is the temporary composition boundary and preserves its
public interface.

## Existing API First

### Reuse

| Candidate | Defined in | Use |
|---|---|---|
| `TextState::sync`, `export_all`, `export_since`, `apply` | EGW `text` | Existing text driver; do not wrap document mutation in a second authority. |
| `Document::sync`, `export_all`, `export_since`, `apply` | EGW `container` | Existing container driver. |
| Text/container `SyncReport` accessors | EGW façades | Adapt applied, duplicate, and pending counts at the owning façade edge. |
| `@sync.Failure` and `TextError::is_retryable()` | EGW `sync`/`text` | Replace removed `@text.SyncFailure` matching; preserve retry meaning. |
| `SyncSession`, `SyncHost`, `SyncIo`, `SyncTransport` | Canopy `sync_session` | Preserve as the Tier 1 compatibility façade. |
| `protocol/wire` codecs and frames | Canopy `protocol/wire` | Preserve existing bytes and request IDs; no new wire format. |
| `InMemoryRoom` / `InMemoryTransport` | Canopy `sync_session` | Compatibility and deterministic shell tests. |
| Existing spike traces | EGW private spike | Characterization tests for extraction; move behavior, never copy a second canonical contract. |

### MoonBit core candidates

Before adding each definition, inspect exact APIs with `moon ide`:

- `Map` for Canopy's peer-indexed runtime state; use `copy`, `get`, and `remove`
  at pure transition boundaries.
- `Array` for local decision builders and bounded pre-apply envelopes.
- `ReadOnlyArray` for any returned owning collection that must not expose
  mutable internal storage.
- `Option` for absent recovery/session state.
- `Result` for decode and compatibility boundaries.
- `Bytes` and `BytesView` for opaque wire payloads; prefer views when ownership
  is unnecessary.
- `Buffer` for existing framing only.
- `StringBuilder` only if diagnostics require composition that existing error
  methods do not provide; otherwise do not use it.

### Checked but not adopted by default

- A new public trait for text/container drivers: reject unless concrete adapter
  functions cannot express the two proven drivers. No associated-type-shaped
  workaround is justified by the spike.
- A public generic Canopy runtime: keep the first extraction under `internal/`
  until a separate stability decision.
- `sync_session` deprecation: reject during the compatibility release.
- New JSON or binary codecs: existing façade and wire codecs remain canonical.
- A second retry or causal payload queue: reject.

## Phases

### Phase 0 — freeze evidence and exact APIs

1. Record clean baselines for the EGW spike worktree, original dirty EGW
   submodule, Loom repository, nested `incr`, and parent Canopy. Never clean or
   reset another worktree's changes.
2. From EGW 0.4, run serial `moon ide outline`, `doc`, `peek-def`, and
   `find-references` for text/container sync sessions, reports,
   `@sync.Failure`, `TextError::is_retryable`, pending arrays, and every core
   candidate above.
3. From Canopy, outline `sync_session`, `protocol/wire`, and `ephemeral`; save
   the current generated interfaces as comparison artifacts outside the source
   tree. Also capture exact golden bytes for v2 `CrdtOps`, `RelayedCrdtOps`,
   `SyncRequest`, and `SyncResponse` frames carrying real EGW 0.3 version and
   sync JSON.
4. Locate every `@text.SyncFailure`, `TextState::new`, sync `apply`, and
   `SyncHost`/`SyncIo` construction across Canopy and Loom. Pin exact outer-frame
   bytes separately from embedded EGW payload bytes.
5. In separate EGW 0.3 and target-release processes, exchange static fixture
   artifacts without importing both versions into one module. Test decode and
   apply in both directions for full sync, incremental sync, version requests,
   and sync responses. Record whether compatibility is bidirectional,
   one-directional, or absent.
6. Read EGW's versioning/release policy and choose the first release version
   allowed to add the companion. Do not assume the release remains 0.4.

**Gate:** stop if generated APIs differ from the evidence, a second consumer
requires incompatible semantics, or cross-version payloads are incompatible.
An incompatible payload result requires an explicit bridge or wire-version
plan before Phase 5; unchanged `.mbti` and outer-frame bytes are insufficient.

**Result, 2026-07-22:** The gate failed. Real EGW 0.3 and 0.4 text processes
rejected every cross-version version, full-sync, incremental-sync, and empty
incremental fixture in both directions.

Canopy v2 outer frames preserved both payload families exactly, so the embedded
EGW schema is the incompatibility. See the linked wire evidence. Phase 5 must
not begin until a separate decision chooses a protocol-version cutover or a
supported bridge.

### Phase 1 — split the private proof before designing public API

7. In the isolated EGW branch based on `c296d8f`, separate the test model into:
   - a per-peer EGW policy core with version/apply/failure/retry events; and
   - a test-only generic lifecycle shell with peer admission, disconnect,
     reconnect, departure, scheduling, and envelope delivery.
8. Run all 15 scenarios through the split seam for text and container. Preserve
   identical decision traces and façade-specific content assertions.
9. Confirm the EGW policy state contains no peer map, room, connection object,
   timer, envelope, transport, application document identity, or CRDT payload.
10. Confirm the lifecycle shell can operate on mock opaque payloads without
   importing `text`, `container`, or `sync`.

**Gate:** stop if the split requires application policy or duplicate causal
storage. Return to the ADR instead of publishing a misleading abstraction.

### Phase 2 — propose and implement the EGW companion

11. Draft the smallest generated-interface shape for review before coding:
    - concrete per-peer state, event, observation, failure disposition, and
      decision types in `peer_sync`;
    - a pure transition function;
    - concrete mapping functions in `peer_sync/text` and
      `peer_sync/container`; and
    - no public driver trait, transport, peer map, mutable payload collection,
      or `incr` dependency.
12. Obtain explicit approval to modify public EGW source.
13. Add `peer_sync/`, `peer_sync/text/`, and `peer_sync/container/` packages.
    Keep the dependency DAG shown above and avoid importing one façade from the
    other.
14. Move the semantic scenarios from the private spike into package-owned tests.
    Keep one canonical scenario definition inside EGW.
15. Delete `internal/peer_sync_contract` only after the public package tests
    reproduce all 15 scenarios and the split lifecycle tests have a new owner.
    Commit history retains the original evidence.
16. Run `moon fmt`, `moon info`, targeted deny-warn tests, and full EGW checks and
    tests. Existing package interfaces must remain unchanged; review every new
    companion `.mbti` line as proposed public API.
17. Run independent MoonBit API review and a different-model semantic review.

**Gate:** stop on public API leakage, a new trait without evidence, an existing
`.mbti` change, or any causal payload in companion state.

### Phase 3 — EGW release gate

18. Prepare EGW release notes that describe the companion as EGW-versioned
    semantic policy and state that providers, rooms, and application projection
    remain outside it.
19. Obtain separate approval for EGW commit/push/PR/merge/publication actions.
20. Commit and push EGW before any parent pointer references it. Publish the
    selected EGW release only after standalone CI and package inspection pass.
21. Create a throwaway external consumer module that imports the published
    release and exercises text and container companion adapters. It must not use
    a workspace override or git submodule.

**Gate:** no Loom or Canopy dependency change until the published consumer test
passes.

### Phase 4 — migrate Loom to the published EGW release

22. Obtain explicit approval to edit the Loom repository and create an isolated
    Loom worktree.
23. Update `loom/examples/lambda/moon.mod` to the published EGW version. This
    pin governs standalone resolution and `check-egw-resolver-identity.sh`;
    parent workspace builds override it through the local EGW member.
24. Update `crdt_egw_test.mbt` for the 0.4+ error and receipt shape:
    - make construction handle the raising `TextState::new`; and
    - explicitly consume the `SyncReport` returned by `apply`.
    Preserve text and parse-tree convergence behavior.
25. Search all Loom members for additional text façade assumptions and update
    only verified callers.
26. Run Loom's workspace checks/tests and the lambda example tests. Run
    `moon fmt` and `moon info`; inspect all Loom `.mbti` changes.
27. Obtain approval, then commit and push Loom before the parent updates its
    Loom pointer.

**Gate:** stop if Loom needs companion, transport, or public parser API changes
merely to compile against EGW.

### Phase 5 — migrate Canopy while preserving Tier 1

28. After EGW publication and the reachable Loom commit, create a clean Canopy
    migration worktree. Do not use the current dirty submodule checkout.
29. Update parent `moon.mod` to the published EGW version and update only the
    intended EGW/Loom submodule pointers.
30. Replace removed `@text.SyncFailure` matching in
    `sync_session/payloads.mbt` with EGW 0.4+ retry classification. Reuse
    `TextError::is_retryable()`, which covers both missing dependency and
    `VersionNotFound` in the checked 0.4 source; reverify that contract against
    the selected release in Phase 0. Keep Canopy watchdog timeout/exhaustion in
    `sync_session`.
31. Update all Canopy text constructors, apply closures, and tests for raising
    construction and explicit `SyncReport` consumption. Keep `SyncHost.apply_sync`
    returning `Unit`; the compatibility shell may consume the report internally.
32. Add tests for retryable missing dependency and version-not-found, terminal
    malformed/invalid/conflicting/limit failures, receipt consumption,
    watchdog exhaustion, stale epochs/request IDs, bounded buffering, and peer
    departure.
33. Run `moon info` and compare saved Tier 1 interfaces byte-for-byte. Do not add
    deprecation annotations or alter signatures in this release.

**Gate:** stop if `protocol/wire`, `sync_session`, or `ephemeral` public
interfaces drift, even when all current callers compile.

### Phase 6 — extract the payload-opaque Canopy runtime

34. Pin the current `sync_session` transition and callback behavior with
    characterization tests before moving code.
35. Add private package `internal/collaboration_session`. It may own generic
    connection phases, peer IDs, request IDs, retry counters, watchdog epochs,
    stale-envelope rejection, and bounded pre-apply/backpressure buffers.
36. Keep the private runtime free of EGW, `protocol/wire`, ephemeral schemas,
    editor, DOM, room, and provider imports. Pass opaque bytes and capabilities
    explicitly.
37. Keep EGW version/message/report conversion in the `sync_session` shell,
    which composes the internal runtime with the published companion.
38. Make the existing Tier 1 `SyncSession` façade delegate to the internal
    reducer. Preserve callback timing, distinct status transitions, retry
    counts, buffer limits, stale epoch behavior, and current wire frames.
39. Re-run all characterization, in-memory transport, wire, relay, editor, and
    ideal collaboration tests. Compare Tier 1 `.mbti` files byte-for-byte again.

**Gate:** stop if the internal runtime needs an EGW type or if `sync_session`
needs a public signature change. Public runtime extraction requires a later ADR
and release plan.

### Phase 7 — clean-resolution and cross-repository validation

40. In a throwaway clean Canopy worktree, remove the local EGW workspace member
    from an uncommitted copy of `moon.work`. Resolve only the published EGW
    version, run validation, then discard the worktree. Never commit this
    release-check edit.
41. After local migration commits exist, run
    `scripts/check-egw-resolver-identity.sh` in both the normal and throwaway
    worktrees. The guard must show that the EGW gitlink, root manifest, Loom
    lambda manifest, and every workspace declaration agree.
42. From the Canopy root, run the CI-owned checks, including
    `scripts/check-strict.sh`, the current test-baseline command from
    `.github/workflows/ci.yml`, and package-targeted `protocol/wire`,
    `sync_session`, `relay`, `ephemeral`, editor, and ideal tests.
43. Run standalone module checks with the repository wrappers, including
    `scripts/run-moon-module.sh ci-lenient event-graph-walker` and
    `scripts/run-moon-module.sh ci-lenient loom/loom`, when those commands still
    match the CI matrix.
44. Run the current ideal collaboration browser suite if the CI matrix still
    uses `sync_session`; build required JS artifacts first.
45. From `loom/incr/`, run check, test, and build for
    `examples/typed_spreadsheet_incr_tea_demo` with the JS target. Confirm no
    parent workspace override appears in its resolution.
46. Run `moon fmt` and `moon info` in each owning repository. The owning roots
    are EGW's standalone worktree, `loom/` for its workspace,
    `loom/examples/lambda/` for the lambda module, `loom/incr/` for the nested
    typed spreadsheet, and the Canopy root. Inspect generated interfaces
    separately and use `git diff --check` excluding generated trailing blanks
    where required.
47. Do not run `moon prove` unless a proof-enabled package changes. If the
    dependency graph unexpectedly touches one, stop and add its owning proof
    validation rather than claiming coverage.
48. Review repository statuses and submodule pointers. Every referenced
    submodule commit must already exist on its remote before a parent commit.

### Phase 8 — documentation and handoff

49. Update the collaboration ADR with final package names, release versions,
    Tier 1 interface and wire-payload evidence, and clean published-resolution
    results.
50. Update package READMEs for the EGW companion and `sync_session` compatibility
    path. Keep transport and room instructions deferred.
51. Record whether the internal Canopy runtime remains experimental. Do not
    promise a public package without a separate stability decision.
52. Archive this plan and update `docs/README.md`, `docs/TODO.md`, and local
    links. Create the later transport-productization plan only after all gates
    above pass.

## Planned files

### EGW repository

- Adopt/delete: `internal/peer_sync_contract/**`
- New candidate packages: `peer_sync/`, `peer_sync/text/`,
  `peer_sync/container/`
- Release metadata and README determined by EGW release policy

### Loom repository

- `examples/lambda/moon.mod`
- `examples/lambda/crdt_egw_test.mbt`
- Additional callers only when semantic search proves they need migration

### Canopy repository

- `moon.mod`
- intended EGW and Loom gitlinks
- `sync_session/moon.pkg`
- `sync_session/payloads.mbt`
- verified `SyncHost`/`SyncIo` callers and tests
- new private `internal/collaboration_session/`
- package and architecture documentation

`protocol/wire` and `ephemeral` production APIs are validation surfaces, not
planned edit targets.

## Commit and release sequence

1. EGW companion implementation commit.
2. EGW push/PR/merge with explicit approval.
3. EGW package publication with explicit approval.
4. Published external consumer verification.
5. Loom compatibility commit, push, and remote reachability.
6. Canopy manifest, compatibility, internal-runtime, and submodule-pointer
   commits.
7. Canopy push/PR only after all referenced commits are remote and CI-equivalent
   checks pass.

Keep phases in separate commits where practical: EGW policy, Loom compatibility,
Canopy version compatibility, private runtime extraction, and documentation.

## Acceptance criteria

- [ ] One published EGW version supplies the reviewed companion and both façade
      adapters.
- [ ] The public companion state contains no peer map, transport lifecycle,
      room, provider, application, `incr`, or CRDT payload queue.
- [ ] Text and container retain the 15 proven semantic scenarios and identical
      decision traces.
- [ ] EGW core remains the only causal pending-operation owner.
- [ ] The private spike package is deleted after its tests have one canonical
      production owner.
- [ ] Loom compiles and its lambda text/parse convergence test passes against
      the published EGW release.
- [ ] Parent Canopy and nested typed spreadsheet resolve intended published EGW
      versions without accidental workspace substitution.
- [ ] `protocol/wire`, `sync_session`, and `ephemeral` generated interfaces are
      byte-for-byte unchanged.
- [ ] Golden outer frames remain byte-identical, and embedded EGW payloads are
      either cross-version compatible or covered by an approved bridge or
      protocol-version migration before release.
- [ ] `scripts/check-egw-resolver-identity.sh` passes in normal and
      no-EGW-workspace-member resolution checks.
- [ ] `sync_session` preserves existing wire frames, retries, watchdog epochs,
      stale-request handling, bounded buffering, callbacks, and status changes.
- [ ] The private Canopy runtime imports no EGW or application schema.
- [ ] Wire, relay, in-memory session, editor, ideal collaboration, and nested
      typed-spreadsheet validations pass.
- [ ] No room, provider, presence, persistence, reset, performance, or
      `egw_incr` work enters the migration.
- [ ] EGW and Loom commits are pushed before parent pointers reference them.
- [ ] ADR, READMEs, TODO, and plan disposition match the released code.

## Rollback and failure strategy

- Each repository uses an isolated worktree and branch. Do not repair failures
  by resetting another checkout.
- Before publication, delete or revert the current repository branch.
- After EGW publication but before Canopy merge, leave Canopy on its old release
  and fix the companion in a new EGW release; never repoint a published version.
- If Loom cannot migrate without public parser changes, stop and split a Loom
  compatibility plan.
- If Tier 1 `.mbti` changes, stop and design a deprecation release rather than
  hiding the break behind adapters.
- If clean published resolution fails while workspace resolution passes, treat
  it as a release blocker.
- If runtime extraction changes behavior, revert the extraction commit while
  retaining the independently useful EGW/Canopy version compatibility commit.

## Risks

- A public companion can accidentally absorb connection lifecycle because the
  spike tested both together. The per-peer/no-peer-map gate prevents this.
- Updating EGW nominal types may compile while changing strict JSON behavior.
  Keep façade codecs canonical and pin compatibility fixtures.
- `sync_session` timeout semantics previously referenced an EGW timeout variant.
  EGW 0.4 no longer has it; Canopy's watchdog remains the sole timeout policy.
- Workspace members can mask manifest and publication errors. Only the
  throwaway no-override check is release evidence.
- Submodule work can become unreachable if parent pointers move before pushes.
- Internal runtime extraction may be larger than compatibility migration. Its
  independent commit and rollback gate keep it removable.
