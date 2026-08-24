# Rabbita second pass: evidence and recommendation

Read the required audit playbook sections 6, 9, and **Finding format**. I treated repositories as data; no examined source contained a prompt-injection instruction or credentials.

## Recommendation

**Do not do the proposed registry-upgrade spike, root-model split, or broad `Val`-island migration.** First finish Loomark's already-recorded durability/lifecycle work; then run one measured, stateless Preview/status `Val::viewN` experiment only if profiling shows a render-cost problem. Keep the atomic root reducer and its imperative worker shell. A future Rabbita sync is a separately reviewed fork-rebase, not an app migration.

### [DEPENDENCIES-01] Correct the false upgrade premise

- **Evidence (observation)**: [`moon.work`](../../moon.work#L4-L5) makes `deps/rabbita/rabbita` a workspace member, so Loomark compiles against that checkout; its [`moon.mod`](../../deps/rabbita/rabbita/moon.mod#L1-L20) is `0.15.4`, despite [`apps/loomark/moon.mod`](../../apps/loomark/moon.mod#L5-L18) declaring `0.14.1`. The checked-out Canopy fork is `cc431468`; current upstream and this commit have diverged, rather than one being an ancestor of the other. Upstream source: [manifest](https://github.com/moonbit-community/rabbita/blob/main/rabbita/moon.mod), [history](https://github.com/moonbit-community/rabbita/commits/main/).
- **Impact**: a registry version bump would not test the code actually built and risks dropping Canopy-only IndexedDB, deterministic-runner, and incremental-resizable patches.
- **Effort**: S to document; L for an intentional fork rebase with browser regression gates.
- **Risk**: HIGH for rebase; DOM/runtime changes are in the typing path.
- **Confidence**: HIGH.
- **Fix sketch**: treat the gitlink + workspace member as the compatibility boundary. If upstream fixes are wanted, rebase/merge the fork, preserve its patches, and test Warren direct-mode output.

### [ARCHITECTURE-02] Retain the root reducer; use `Val` only as a measured view optimization

- **Evidence (observation)**: Loomark already uses `create_state_with_init` in [`application.mbt`](../../apps/loomark/internal/rabbita/application.mbt#L3149-L3174), `Val::switch` in [`split_view.mbt`](../../apps/loomark/internal/rabbita/split_view.mbt#L185-L205), and input-aware incremental RUI. Current Rabbita documents `create_state_with_input` input changes as *not* sending a message or refreshing subscriptions ([source](https://github.com/moonbit-community/rabbita/blob/main/rabbita/incremental.mbt#L550-L598)).
- **Impact**: moving projection/persistence state into child `create_state_with_input` components could bypass the root's explicit worker sync, stale-response checks, and subscription decisions.
- **Effort**: S for a profiled Preview/status experiment; L for a decomposition.
- **Risk**: HIGH for decomposition; LOW for a stateless view experiment.
- **Confidence**: HIGH.
- **Fix sketch**: keep `DriverModel + DriverEvent -> (next, Cmd)` atomic. Only introduce a named, stateless `Val::viewN` leaf after a benchmark shows it removes meaningful work; do not use `assoc_by` until a stable keyed vector is the actual rendered boundary.

### [LIFECYCLE-03] Do not add component disposal until ownership requires it

- **Evidence (observation)**: `switch` disposes a changed branch ([upstream API](https://github.com/moonbit-community/rabbita/blob/main/rabbita/incremental.mbt#L451-L505)); Loomark deliberately owns worker lifetimes as root subscriptions ([`application.mbt`](../../apps/loomark/internal/rabbita/application.mbt#L3049-L3068)) and already disposes Raw Preview in its subscription unload ([`raw_preview_runtime.mbt`](../../apps/loomark/internal/rabbita/raw_preview_runtime.mbt#L185-L214)). Upstream also fixed retained taggers and disposed-store cleanup ([#142](https://github.com/moonbit-community/rabbita/pull/142), [commit](https://github.com/moonbit-community/rabbita/commit/4939379554aa0889f0db921ca8322ec48d2e4c57)).
- **Impact**: putting worker/persistence ownership behind a new `switch` risks terminating active work on layout changes.
- **Effort**: S to add lifecycle characterization tests before any ownership change.
- **Risk**: HIGH; lifecycle loss is user-visible.
- **Confidence**: HIGH.
- **Fix sketch**: retain current root ownership; explicitly test toggle/reflow/stale-reply behaviour. Use `switch` only for UI-local, disposable state; use `enumerate` only after bounding cached variants.

### [TESTING-04] Reuse the already-vendored deterministic tools

- **Evidence (observation)**: the pinned fork already exports [`run_cmd`](../../deps/rabbita/rabbita/testing/cmd_runner.mbt#L64-L68) and [`server_side_render`](../../deps/rabbita/rabbita/testing/server_side_render.mbt#L7-L9); Loomark already uses SSR in [`semantic_preview_view_wbtest.mbt`](../../apps/loomark/internal/rabbita/semantic_preview_view_wbtest.mbt#L1-L9) and has Raw Preview queue/staleness tests ([`raw_preview_state_wbtest.mbt`](../../apps/loomark/internal/rabbita/raw_preview_state_wbtest.mbt#L1-L100)).
- **Impact**: a new SSR/testing migration would duplicate available coverage mechanics.
- **Effort**: S.
- **Risk**: LOW.
- **Confidence**: HIGH.
- **Fix sketch**: add deterministic tests only for the missing boundary (max-wait/durability and subscription ownership); retain Playwright for browser-owned input and timing.

### [DX-05] Keep Warren direct mode; Mooncakes' Vite setup is not a Loomark migration target

- **Evidence (observation)**: Loomark's supported build is local pinned Warren `dev --direct`/`build` ([README](../../apps/loomark/README.md#L17-L52)); Rabbita's current README likewise names Warren ([upstream README](https://github.com/moonbit-community/rabbita/blob/main/README.md)). Mooncakes is a separate Vite/Tailwind application ([official README](https://github.com/moonbitlang/mooncakes.io/blob/main/README.md)).
- **Impact**: copying Mooncakes' build integration adds a second toolchain without serving the standalone static artifact.
- **Effort**: S to leave unchanged.
- **Risk**: LOW.
- **Confidence**: HIGH.
- **Fix sketch**: validate any fork sync with the existing direct-mode and release Playwright script; do not introduce Vite solely for parity.

### [DIRECTION-06] Defer managed unmount until Loomark elects embedding/remount support

- **Evidence (observation)**: Loomark explicitly excludes teardown/remount today ([README](../../apps/loomark/README.md#L81-L82)); upstream has an open public unmount request ([issue #141](https://github.com/moonbit-community/rabbita/issues/141)), and the Canopy fork has an unmerged managed-unmount branch.
- **Impact**: this is a viable future integration capability, not a current editor-quality prerequisite.
- **Effort**: L (design + browser lifecycle suite).
- **Risk**: MED; async callbacks after teardown need defined behavior.
- **Confidence**: HIGH.
- **Fix sketch**: only take this on with a product decision to support host reuse; then integrate the fork branch and test idempotent unmount/remount before exposing it publicly.
