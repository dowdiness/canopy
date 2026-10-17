# Loomark local-tabs MoonBit Worker

**Status:** Implemented and locally verified on 2026-10-04. Draft synthetic-only experiment; publication is tracked on PR #1450. Not approved for merge or deployment.

Canonical issue: <https://github.com/dowdiness/canopy/issues/1458>.
Related experiment: [#1450](https://github.com/dowdiness/canopy/pull/1450).

## Why and original state

The original `apps/loomark/experimental/local-tabs/worker.mjs` owned request scheduling and called the string-returning `engine/main/main.mbt` EGW facade. The internal stringify/parse boundary obscured direct ownership of the two replicas. The experiment's six commits were rebased onto main `a0d3575a`; Rabbita remains pinned to `8fcdacd3`, and the nested workspace retains the separate EGW trial at `07a6a833`.

## Scope

- Replace `engine/main` with a compiled module Worker owning FIFO dispatch and direct EGW calls.
- Update experiment build scripts and `client.mjs` to load the separate `worker.js` artifact.
- Preserve `store.mjs`, `core.mjs`, structured-clone wire, checkpoints and failure injection.
- Add direct real-Worker contract coverage; update existing experiment guidance.

Out of scope: main-thread controller migration, switching to the generic Rabbita request envelope, root dependency pins, production notes/storage/account/sync, capacity-timeout and renderer-main performance fixes. Original checkout research and README changes remain untouched.

## Desired state and invariants

- MoonBit owns editor/merged EGW replicas and a single asynchronous request consumer; no JS dispatcher or global EGW handle facade remains.
- Every admitted intent remains FIFO, including delayed responses, save transactions and diagnostics; one rejected request does not prevent the next valid request.
- Recovery replays whole validated packets and verifies the accepted display Version before Ready; writers are fresh and Undo reset remains explicit.
- Main retains the immutable packet before save authorization; only IDB transaction completion acknowledges it. Lost replies recover the identical packet without duplicate journal rows.
- One native intent spans one Undo group across diff hunks; UTF-16/scalar and native-result checks remain.
- Native wire encoding preserves safe-integer IDs and the `changes.approximate` array attribute. No MoonBit runtime representation is sent across the thread boundary.

## Steps

1. Establish a scoped legacy baseline and pin contracts from Worker, client, store and existing browser tests.
2. Implement direct MoonBit Worker ownership and independent direct-Worker regressions in separate worktrees.
3. Build a separate Worker artifact, switch the caller and remove the obsolete dispatcher/facade.
4. Exercise actual Chromium Worker restore/edit/save/FIFO/lost-reply recovery, existing functional/fault/lifecycle/isolation checks, and scoped MoonBit checks/tests.
5. Resolve independent concurrency/persistence/native-boundary review findings; record observed results and archive this plan.

## Validation

From `apps/loomark/experimental/local-tabs`: `npm run build`; `node --test core.test.mjs protocol.test.mjs`; run `node serve.mjs`, then `node worker-test.mjs`, `node browser-test.mjs`, selected existing `fault-test.mjs` scenarios, `node lifecycle-test.mjs`, and `node normal-mode-test.mjs`. Run affected Loomark release tests from the nested workspace and manually inspect the actual page. Record fault selections explicitly; do not rerun the known capacity timeout or trace failure merely to reconfirm them.

## Acceptance and risks

The observable invariants above must pass in the real compiled Worker, not just a mock or unit suite. Preserve the current journal schema, failure behavior and ordinary-mode isolation. The generic Rabbita binding is available but its main-controller integration remains a separate change. Historical performance results and synthetic composition do not establish current capacity, renderer latency or real OS IME correctness. On completion, preserve build/ownership guidance in the experiment README and archive this plan with exact scoped evidence.

## Outcome and observed evidence

`engine/main/{main,protocol,native}.mbt` now owns the Worker with private typed
requests, sessions, packets, projection offers and duplicate-command results.
`worker-native.mjs` only adapts platform primitives and the existing core/store
helpers. `npm run build` emits `loomark.js`, `worker.js` and `fixture.js`; the
caller loads `worker.js`. The old dispatcher and global EGW facade are removed.
The generated Worker package interface remains empty. Main-thread controller
migration is intentionally separate.

Independent persistence/FIFO review found no high-confidence defect. The native
codec review found two compatibility differences: malformed envelopes could
overtake an older pending reply, and offers omitted the original own
`payloads: undefined` property. Both were corrected. The FIFO regression failed
before the correction and passed afterward; a real-Worker pull/project probe
confirmed the offer property and text projection.

Final local runtime: Linux, compiler/core `0.10.14+7d59c7ec9`, Moon
`0.1.20260920`, Node `24.14.1`, headless Playwright Chromium `153.0.8010.12`.
Strict app-binding/Worker checks and all three asset builds passed. Final
Worker SHA-256:
`2be36f066c4d9d31d0919bb63ed8821bf12569b63bfe992a3da319ef9cadc2aa`.

Observed checks: 11 pure/protocol tests, 3 direct Worker scenarios, 13 existing
browser scenarios, 13 selected fault scenarios, 4 lifecycle scenarios,
ordinary-mode isolation and 388 Loomark release tests passed. Fault selections
excluded only the previously reported missed-history capacity case. A separate
live-page check saved/reloaded `base 日本語😀` with a fresh writer and no page
errors or main-thread EGW global. These are not full-workspace CI, renderer
performance, real OS IME, headed-browser or Windows-wrapper claims.

The 388-test command, from the experiment directory, selected the owning
packages explicitly; this Moon version does not treat the module directory or
a package-name wildcard as that selection:

```sh
moon test ../../app ../../app/internal/sync ../../app/internal/documents \
  ../../app/internal/replica_persistence ../../app/internal/replication \
  ../../app/internal/source_repository ../../app/internal/document_http \
  ../../app/internal/account_http ../../internal/local_tabs \
  ../../internal/recent_documents ../../internal/view ../../internal/timeout \
  ../../internal/sidebar ../../internal/document_lead ../../internal/browser \
  ../../server/internal/document_store ../../server/documents ../../main \
  ../../examples/sidebar_fixture fixture --target js --release
```

Current build/ownership guidance and scoped results are in the
[experiment README](../../apps/loomark/experimental/local-tabs/README.md).
Original-checkout research and README files were compared byte-for-byte with
their preserved snapshots and remain unchanged. This record describes the local
validation before publication. Subsequent commit, push and CI status is tracked
on [PR #1450](https://github.com/dowdiness/canopy/pull/1450); no merge or production
deployment is authorized.
