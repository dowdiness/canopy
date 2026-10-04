# Sub-owned Rabbita Worker binding

**Status:** Implementation completed and verified on 2026-10-04, then published to the Rabbita fork's `main` as `8fcdacd3edd35b6be267849b1098140901033ad5` by direct fast-forward push at the user's request. No fork PR was created. The Canopy adoption change pins that commit and aligns its Warren installer.

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/1455>.
The issue records this archived plan, the published fork commit and the Canopy adoption PR.

## Why

A managed command has no native-resource cleanup hook. A logical-name lookup can route a previously queued request to a replacement Worker. The binding must combine existing Sub lifetime with one-shot Cmd settlement and opaque connection identity before the experiment's domain owner is moved.

## Scope

In: `deps/rabbita/rabbita/worker/`, `deps/rabbita/e2e/apps/worker/`, `deps/rabbita/e2e/tests/worker.spec.ts`, fork workspace/test registration and package documentation.

Out: PR #1450 integration, EGW dispatcher, editor/controller migration, storage/flush/retry policy, actor/RPC framework, Worker asset bundling in Loomark, performance claims, runtime Context redesign and production adoption.

## Current state and reuse

Base: Canopy `78bb8ece13bde39211ea7dc363b938d26ed8136f`; Rabbita `139ae60c9fc7efc5a791c6720b67bceb46107e5d`.

- [`websocket/listen.mbt`](../../deps/rabbita/rabbita/websocket/listen.mbt) supplies the retained tagger and unload pattern.
- [`indexed_db/op.mbt`](../../deps/rabbita/rabbita/indexed_db/op.mbt) supplies the managed Op/callback-Promise bridge.
- [`cmd/operation.mbt`](../../deps/rabbita/rabbita/cmd/operation.mbt) supplies Async/settle/resume, but no scope-owned cleanup.
- [`internal/runtime/stores.mbt`](../../deps/rabbita/rabbita/internal/runtime/stores.mbt) installs subscriptions synchronously and frees a store before unloading its Subs. Unload cannot preserve domain state by messaging the freed owner.

Reuse the existing runtime, not the WebSocket named connection registry. Native Worker, listener and timer mutation stays private in the imperative shell; the application retains plain connection and domain request IDs. JSON strings provide an explicit wire representation rather than exposing MoonBit object layouts.

## Contract

Public `listen(key, url, generation, on_event)` returns Sub; `request(connection, payload, reply, timeout_ms)` returns Cmd. The module Worker URL is trusted application configuration. `Connection` contains immutable identity only. Connected means transport construction, not application restoration/readiness.

The key, URL and generation determine subscription identity; tagger identities do not. Every installation has a fresh connection independent of local key names. Requests capture connection and payload at command creation. A missing connection rejects before posting; there is no lookup through a replacement name. All pending requests settle at most once, after removing their timer/bookkeeping. Timeout ends one waiter, not remote execution. Fatal native/protocol errors close the connection and settle all waiters. Unload additionally removes listeners and terminates the Worker, with no event addressed to the destroyed owner.

Wire envelopes are JSON strings with `rabbita_worker: 1`, a string `id`, and `kind`. Request/result carry `payload`; progress renews only the matching pending request's inactivity timer. Unknown/completed IDs are ignored; malformed envelopes fail explicitly. Domain errors remain typed application payloads. No flush or retry is added.

A browser execution gate prevents construction/post in JS nonbrowser environments even if a global Worker polyfill exists. The package is JS-only, not importable by a native/Wasm SSR renderer. Application messages still carry captured connection and domain request identity: already-queued messages require update-time admission checks.

## Steps

1. Preserve original uncommitted research; create latest-main worktree and fork branch; verify dependencies.
2. Fix public/wire contract, implement binding and independent real-browser acceptance fixture in separate worktrees.
3. Integrate, run strict checks/release tests and real browser smoke, review concurrency/API boundaries, resolve findings.
4. Preserve the tested contract in package docs and archive this plan. Following review, publish the fork through the maintainer's direct-main workflow, then adopt its pin through Canopy's PR workflow.

## Boundary matrix

| Boundary | Required observation |
| --- | --- |
| Same key / changed callbacks | Same native Worker; newest event callback |
| Changed URL or generation | New connection; old queued request never posts to replacement |
| Reply race | Once-only correlation; duplicate/late result ignored; queued domain event rejected after replacement |
| Subscription removal / owner unmount | Pending settled once; native Worker/listeners/timers released |
| Independent mounts, same key | No shared connection or mutable Worker state |
| Constructor / post / error / messageerror | Explicit category, no hanging waiter or leaked native resource |
| Invalid protocol | Explicit connection failure |
| Inactivity deadline / progress | Matching progress alone extends timeout; timeout does not undo operation |
| Invalid timeout | Rejected before post |
| JS nonbrowser / Worker polyfill | No construction or post; no native `App::render` coverage claimed |

## Validation

From `deps/rabbita`: `moon check --target js --deny-warn`, affected package release tests, `moon fmt`, `moon info --target js`. Use checkout-local Warren and Chromium for the registered Worker Playwright project; exercise the actual built fixture through a browser separately. Review generated interfaces for accidental API exposure.

Completed checks from `deps/rabbita`:

- `moon fmt rabbita/worker` and `moon fmt e2e/apps/worker`; `moon info --target js`; `moon check --target js --deny-warn`: passed.
- `moon test --target js --release --serial`: 116 passed, 0 failed, including two JS nonbrowser/polyfill regressions.
- Checkout-local Warren production build with `--browser-entry . --public-dir public`: passed, including JS minification.
- The 13 Worker Chromium tests passed against that production bundle with one worker and zero retries. A temporary focused config served the bundle on port 46184 rather than starting every unrelated fixture; that config was removed after verification. The permanent `worker-chromium` project lists all 13 tests.
- Browser smoke independently observed normal replies, an incarnation reset after generation replacement, and owner unmount, with no captured page errors.
- Independent lifecycle/concurrency and public API/protocol reviews reported no surviving high-confidence defects. Generated interfaces expose no native Worker handle or registry.
- Post-push GitHub [`check` run 37201379713](https://github.com/dowdiness/rabbita/actions/runs/37201379713) passed for `8fcdacd3edd35b6be267849b1098140901033ad5`: stable-build, E2E, Vite plugin and typo-check. The upstream-only website deployment workflow was skipped on the fork.
- Canopy adoption smoke: the updated `scripts/install-local-warren.sh` installed Warren from the published pin; `warren --help` ran successfully. `scripts/run-moon-module.sh ci-lenient apps/loomark app` passed its scoped check and all 110 release tests. The installed Warren also rebuilt and minified the real Worker fixture with `--browser-entry . --public-dir public`.

Tests observe settlement counts before application deduplication. Clock-controlled tests pause explicitly, advance through the next render frame, and resume during teardown. Fatal-failure coverage verifies that both pending waiters settle once and that timers/listeners/native Workers are released.

Current usage and wire requirements live in [`worker/README.mbt.md`](https://github.com/dowdiness/rabbita/blob/8fcdacd3edd35b6be267849b1098140901033ad5/rabbita/worker/README.mbt.md). The implementation is published on `dowdiness/rabbita:main` at `8fcdacd3edd35b6be267849b1098140901033ad5`. Canopy adopts that exact commit under immutable tag `canopy-worker-20261004`, updating both `deps/rabbita` and `scripts/install-local-warren.sh`. The fork's direct-main policy does not change Canopy's own PR workflow. The original experiment checkout and its uncommitted research were preserved. No Loomark application migration or native SSR support is included.

## Risks

Transport settlement is not exactly-once domain execution or transactional rollback. Killing a Worker can lose its reply after an effect already happened. No claim is made about resolving the experiment's existing capacity timeout or historical renderer trace failure. Public Cmd/Sub hide unstable Op APIs; continued fork maintenance remains necessary.
