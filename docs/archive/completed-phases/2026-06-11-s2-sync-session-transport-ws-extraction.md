# S2 — Extract `sync_session` + `transport_ws`

**Date:** 2026-06-11
**Status:** Planned
**Parent:** [Architecture redesign proposal](2026-06-11-architecture-redesign-proposal.md) § S2
**Tier:** `sync-session` Tier 1, `transport-ws` Tier 3 (deferred assignments in ADR to be updated in this PR)
Plan authored by Codex from the converged S2 design.

## Why

S2 must move recovery/state machine/session orchestration out of `SyncEditor` without changing public editor API in this stage, so transport policy and status machinery live in `sync_session` and websocket binding lives in `transport_ws`. This keeps editor as document/parsing/surface coordinator and creates a small, policy-focused sync kernel package that can be reused independent of transport.

## Scope

In:
- `transport_ws/{websocket_js.mbt, websocket_native.mbt, moon.pkg}`
- `sync_session/*` (new package, all session policy types and sync dispatch/recovery drivers)
- `editor/moon.pkg`
- `editor/sync_editor.mbt`, `editor/sync_editor_ws.mbt`, `editor/sync_status.mbt`, `editor/sync_transport.mbt`, `editor/in_memory_transport.mbt`
- `editor/sync_editor_ws_wbtest.mbt`, `editor/sync_status_wbtest.mbt`, `editor/recovery_wbtest.mbt`, `editor/error_path_wbtest.mbt`
- `editor/in_memory_transport_wbtest.mbt`, `editor/ephemeral_hub_transport_wbtest.mbt`
- `ffi/lambda/ws.mbt`, `ffi/lambda/integration_ws_test.mbt`, `workspace/probe/identity_probe_wbtest.mbt`
- `docs/decisions/2026-06-11-library-api-boundary.md`
- `sync_session/README.md`

Out:
- `editor/sync_protocol.mbt` (explicitly untouched in S2)
- `protocol/wire` and `relay` internals
- Existing `ffi` typed-context surface (beyond ws re-exports)

## Current State

`SyncEditor` owns sync recovery state (`recovery`, `recovery_epoch`, `status`, `on_status_change`, `watchdog_scheduler`, `watchdog_timeout_ms`) and all WebSocket lifecycle/dispatch logic in `sync_editor_ws.mbt`.
`SyncTransport`, `InMemoryRoom`, `InMemoryTransport`, and sync protocol helpers are in `editor` package scope.
`error_path_wbtest.mbt` and `sync_protocol.mbt` are the public S1 compatibility witnesses.

## Desired State

`sync_session` owns policy/state primitives only and depends on `@wire`, `event-graph-walker/text`, `byte_codec`; no `editor`, no `ephemeral`, no `transport_ws` imports.
`transport_ws` owns websocket bindings only, preserving JS extern behavior and native no-op stub.
`SyncEditor` keeps public method surface byte-identical, stores `priv session : @sync_session.SyncSession`, and delegates all session-owned sync methods to that session.

## Steps

1. **Create package skeletons.**
Create directories `transport_ws/` and `sync_session/`, each with brace `moon.pkg` files. `transport_ws/moon.pkg` must import only `moonbitlang/core/builtin` if needed and target-gate `websocket_js.mbt` to `"js"`, `websocket_native.mbt` to `["not","js"]`. `sync_session/moon.pkg` is L3/L2 boundary-compliant and imports `@wire`, `moonbitlang/core/debug`, `moonbitlang/core/buffer`, `event-graph-walker/text`, `byte_codec`, plus any sync internals used in moved tests.
**Breakpoint:** `NEW_MOON_MOD=0 moon check transport_ws` and `NEW_MOON_MOD=0 moon check sync_session` should be clean immediately after skeleton setup; expected class of failure before this step is package/entry not found when running package checks globally.
**Verify:** `NEW_MOON_MOD=0 moon check transport_ws` and `NEW_MOON_MOD=0 moon check sync_session`.

2. **Move websocket bindings byte-equivalently into `transport_ws` and keep type behavior.**
Move `editor/websocket_js.mbt` and `editor/websocket_native.mbt` verbatim (byte-equivalent move, no improvements). Preserve external signatures (`#external type JsWebSocket`, `send_bytes`, `close`), and preserve no-op native semantics.
Edit `editor/moon.pkg` to remove direct file imports `websocket_js.mbt`/`websocket_native.mbt` from `options.targets` and add package dependency on `"dowdiness/canopy/transport_ws"`.
Add `pub using @transport_ws { type JsWebSocket }` (or equivalent package-level re-export file) so existing `@editor.JsWebSocket` consumers remain unchanged.
Editor still keeps `ws : JsWebSocket?` in `SyncEditor` for transport handle compatibility.
**Breakpoint:** `NEW_MOON_MOD=0 moon check editor` can fail with `Unbound value JsWebSocket` in editor files if import path or re-export is not updated before body edits.
**Verify:** `NEW_MOON_MOD=0 moon check sync_session` and `NEW_MOON_MOD=0 moon check editor` (package-local test set accepted to still fail only where downstream files are intentionally untouched by this step).

3. **Extract sync status symbols into `sync_session` and re-export from `editor`.**
Move `SyncStatus`, `SyncErrorReason`, and their `Show` impls from `editor/sync_status.mbt` to `sync_session/sync_status.mbt` byte-equivalently (byte-equivalent move, no improvements). `editor/sync_status.mbt` becomes `pub using` re-export-only for these types (NO new `#deprecated` in this stage), preserving source-visible public surface while making canonical ownership sync_session.
Keep show formatting behavior unchanged.
Also add `pub using @sync_session { type SyncStatus, type SyncErrorReason, type SyncTransport, type InMemoryRoom, type InMemoryTransport }` in editor package files that own the export surface.
`@sync_session` imports are used only in editor-internal implementation, while consumers keep `@editor.*` spellings via re-exports.
**Breakpoint:** `NEW_MOON_MOD=0 moon check editor` may report `Value SyncErrorReason is private` / missing constructor paths if `editor/sync_status.mbt` is replaced before `ffi/lambda/ws.mbt` sees `@editor.SyncStatus` re-exports.
**Verify:** `NEW_MOON_MOD=0 moon check sync_session && NEW_MOON_MOD=0 moon check editor` and run `rg "@editor\\.(Disconnected|Idle|Recovering|Error|Exhausted|TargetLeft)"` once after this step to confirm only expected typed paths in compat witnesses remain.

4. **Move transport interface and in-memory transport to `sync_session`.**
Move `editor/sync_transport.mbt` and `editor/in_memory_transport.mbt` (`InMemoryRoom`, `InMemoryTransport`, `SyncTransport` impls) to `sync_session` byte-equivalently. `sync_session` now defines the `SyncTransport` trait and both transport types.
Update editor-internal imports/usages only (`editor/*` plus in-session tests) to `@sync_session`; do not rewrite consumer call-sites in `ffi/*` or `workspace/probe` yet, because `@editor` compatibility remains available through package-level `pub using`.
**Compilation breakpoint:** old `editor/in_memory_transport.mbt` references to trait and constructors will fail with private-symbol/import errors until all callsites switch; expected class is `Unbound value @sync_session.SyncTransport` and unresolved `InMemoryRoom` constructor symbols.
**Verify:** `NEW_MOON_MOD=0 moon check sync_session`, `NEW_MOON_MOD=0 moon check editor` and targeted tests for package API (`in_memory_transport_wbtest` migration in step 10).

5. **Move recovery state machine into `sync_session`.**
Move `editor/recovery.mbt` to `sync_session/recovery.mbt` byte-equivalently. Preserve constants `max_deferred = 32`, `max_retries_after_initial = 3`, struct `RecoveryContext`, `buffer_message`, `advance_retry`, `is_exhausted`, `matches_request_id` semantics exactly.
Expose minimum symbols `pub` for what editor/session consumes, then tighten after compiler-guided pass.
**Breakpoint:** compile is expected to fail in `sync_session` with unresolved `@text.SyncMessage` until `sync_session` imports `event-graph-walker/text`; fix by adding that package import. A second pass may fail in `recovery_wbtest`/editor delegation when methods are not made public; fix by pub-ing only actual external-internal call sites.
**Verify:** `NEW_MOON_MOD=0 moon check sync_session` and `NEW_MOON_MOD=0 moon check editor`.

6. **Move pure sync parse helpers into `sync_session`.**
Move `parse_sync_message_json`, `parse_sync_request_payload`, `parse_sync_response_payload`, and `should_retry_sync_error` out of `editor/sync_editor_ws.mbt` to `sync_session` as pure helper functions. Keep behavior unchanged.
**Breakpoint:** `NEW_MOON_MOD=0 moon check editor` is expected to fail with missing helper symbols if calls remain in editor files; fix by adding editor-local wrapper calls to session helpers via delegation host.
**Verify:** `NEW_MOON_MOD=0 moon check sync_session` and `NEW_MOON_MOD=0 moon check editor` (pre-E2E).

7. **Create `sync_session.SyncHost` and move dispatch + recovery driver.**
Add `sync_session/sync_session.mbt` with:
- a narrow IO record (name it `SyncIo` or equivalent): `send(Bytes)`, `current_version() -> Version`.
- a full `SyncHost` closure-record for dispatch-capable ops, including `apply_sync` (raising), `apply_ephemeral`, `encode_ephemeral`, `export_all`, `export_since`, `on_peer_leave`, and embedding/including `SyncIo`.
- `SyncSession` struct fields: `recovery`, `recovery_epoch`, `status`, `on_status_change`, `watchdog_scheduler`, `watchdog_timeout_ms`, plus `DEFAULT_WATCHDOG_MS` constant.
- Methods moved from `sync_editor_ws.mbt` with signatures preserved as session internals:
  - `on_open`, `on_close`, `on_message` (full `SyncHost`)
  - `on_watchdog_fire`, `send_sync_request`, `send_empty_sync_response` (use `SyncIo`, no `Eq`-bound closures)
  - `enter_recovery`, `handle_recovery_retry`, `set/get_status`, `set_on_status_change`, `set_watchdog_scheduler`, `set_watchdog_timeout`, explicit success entrypoint.
- explicit success-entrypoint that performs `Error -> Idle` transition after successful `apply_sync` for any success path.
All dispatch/recovery logic stays byte-faithful, including:
- `handle_recovery_retry` exhaustion-before-advance and `ctx+status` advance-before-wire-send ordering.
- SyncResponse success drain loop with ordered deferred drain, retryable failure mid-drain re-enters recovery carrying remaining deferred, emits `Idle` before `Recovering`, and transitions Idle-only if recovery not re-entered.
- stale request_id check-before-retry and stale watchdog request drop.
- empty `sync_json` and malformed deltas route retry path, not panic.
- `RecoveryContext.buffer_message` at-cap drop oldest at 32.
- `set_status` emits callback only on distinct transitions.
- one-recovery-at-a-time limitation (second peer failure dropped).
- peer namespace enumeration uses `all_namespaces()` via `@wire` directly (no host namespace field).
- moved parsers must include `using @byte_codec` in-session (Reader is currently package-scoped in editor via `editor/ephemeral_facade.mbt`), or equivalent qualified reader usage.
**Compilation breakpoint:** expected to fail with host record shape mismatch in editor delegating calls, with no-`Eq` `on_watchdog_fire` host construction issues, and missing `Reader` import in `sync_session`; fix by splitting IO/dispatch host records and adding `byte_codec` in-package imports.
**Verify:** `NEW_MOON_MOD=0 moon check sync_session` and `NEW_MOON_MOD=0 moon check editor` immediately after host wrapper additions.

8. **Delegate editor internals to `SyncSession`, preserving public signatures.**
In `editor/sync_editor.mbt`, replace the six sync-state fields with `priv session : @sync_session.SyncSession` while keeping `priv mut ws : JsWebSocket?`.
Update `new_generic` initialization to construct one session object with `DEFAULT_WATCHDOG_MS` and zeroed state.
`SyncEditor::new_generic` signature and all pub method signatures stay byte-identical.
Keep `ws_broadcast_edit` and `ws_broadcast_cursor` as plain editor methods (they touch no session state beyond `ws`, hub, `export_all`).
For each remaining sync lifecycle method requiring session state, build `SyncHost` or `SyncIo` per dispatch call from closures over `self` (`apply_sync`, `export_all`, `export_since`, `get_version`, ephemeral encode/apply, ws send) and delegate into `self.session`.
`editor/sync_editor_ws.mbt` and related methods become wrappers that assemble host once and call `SyncSession`.
**Compilation breakpoint:** `pub fn[T] SyncEditor::on_watchdog_fire` has no `Eq` bound; if this method tries to build full `SyncHost`, `moon check` will fail with bound-related type mismatch — explicitly switch it to `SyncIo` construction and leave full `SyncHost` only for `on_message`.
If pub signatures still differ, the next compile will show signature diffs; fix by restoring wrapper-only behavior exactly.
**Verify:** `NEW_MOON_MOD=0 moon check editor`.

9. **Keep `editor/sync_protocol.mbt` and compatibility witness intact.**
Do not edit `editor/sync_protocol.mbt` in S2. `error_path_wbtest.mbt` stays under editor and remains the S1 compatibility witness for deprecated `@editor` protocol shims.
**Checkpoint:** none (negative constraint). If any edits are made here, stop and revert because this violates the explicit frozen S2 boundary.

10. **Rewrite tests to preserve coverage without private-field coupling.**
Split `editor/sync_editor_ws_wbtest.mbt`:
- state-machine/dispatch-policy + recovery-policy tests become direct `sync_session` wbtests with fake `SyncHost` over local `Ref`s (no lambda dependency, no editor-private field mutation).
- end-to-end behavior tests remain in `editor` and only call public surface (`ws_on_open`, `ws_on_message`, `get_sync_status`, `get_hub`, etc.): e.g. CrdtOps apply, EphemeralUpdate apply, PeerLeft peer removal, open/close transitions.
Split `editor/sync_status_wbtest.mbt` similarly:
- any direct `editor.recovery`, `editor.recovery_epoch`, `editor.recovery.unwrap()`, `editor.set_status` usage moves to session tests; status callback/public transition tests remain editor-level.
`editor/recovery_wbtest.mbt` moves to `sync_session/recovery_wbtest.mbt` unchanged semantics.
`editor/in_memory_transport_wbtest.mbt` moves to `sync_session` only; its bare `encode_message`/`decode_message`/`SyncMessage` calls must be rewritten to `@wire` references (explicit non-byte-equivalent fixup).
`editor/ephemeral_hub_transport_wbtest.mbt` stays in `editor` because it depends on editor shim-path calls and `@ephemeral` test-surface, which `sync_session` avoids in test blocks.
`test_ws_helper_js_wbtest.mbt` and `test_ws_helper_native_wbtest.mbt` stay in `editor`.
`editor/error_path_wbtest.mbt` stays in editor untouched.
Update package-level test-target options in each package `moon.pkg` so file-based gating remains correct after moves.
**Expected fail class:** before migration, moved tests will fail with missing symbols (`write_string`, `encode_message`, `SyncSession`, `RecoveryContext`) until imports are fully aligned. Resolve by explicit `@byte_codec`/`@wire`/`@sync_session` imports.
**Verify:**
- `NEW_MOON_MOD=0 moon check editor` with editor wbtests still in-package after split.
- `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/sync_session` after moving all relocated tests.
- If coverage is incomplete, run by-name audit using all current test names listed in scope.

11. **Consumer adaptation and API continuity checks.**
Validate that `ffi/lambda/ws.mbt` and `ffi/lambda/integration_ws_test.mbt` compile with unchanged calls to `@editor.JsWebSocket`, `@editor.SyncStatus`, and ws APIs **unchanged** (no source migration in these files; behavior unchanged via editor `pub using`).
Update `workspace/probe/identity_probe_wbtest.mbt` only if needed for moved import paths (no behavior changes).
**Expected fail class:** no call-site migration should be required in probe/ffi; if `moon check` still fails, the break is missing `pub using` compatibility in editor exports.
**Verify:** `NEW_MOON_MOD=0 moon check ffi` and `NEW_MOON_MOD=0 moon test -p dowdiness/canopy/workspace`.

12. **Docs updates for this PR.**
Edit `docs/decisions/2026-06-11-library-api-boundary.md`: move `sync-session` and `transport-ws` out of Deferred into actual tier tables as `sync-session` Tier 1 and `transport-ws` Tier 3 with correct package paths.
Add short `sync_session/README.md` with role, invariants, package relationship to `SyncEditor` and `SyncTransport`, and recovery semantics (mirroring `protocol/wire/README.md` pattern).
**Verify:** docs path exists and references the proposal + ADR links.

13. **Global validation and surface gates (end of stage).**
Run:

```bash
NEW_MOON_MOD=0 moon check
moon test
NEW_MOON_MOD=0 moon info && git diff '*.mbti'
NEW_MOON_MOD=0 moon fmt
```

Then run collaboration E2E:

```bash
./scripts/test-ideal-web-e2e.sh
./scripts/test-web-e2e.sh
./scripts/test-demo-react-e2e.sh
./scripts/test-canvas-e2e.sh
```

`editor` `.mbti` diff must keep pub method signatures identical for `SyncEditor`; acceptance is exactly: zero signature changes and moved types represented as `pub using` origin lines.
Record the expected temporary fail points while moving (broken imports, private accessors, test target misrouting) and clear before declaring the stage done.
Do not stage pre-existing dirty files (`pkg.generated.mbti` set, loom gitlink, `graphify-out/`).

## Acceptance Criteria

- `sync_session` owns `SyncSession`, `SyncHost`, `SyncStatus`, `SyncErrorReason`, `RecoveryContext`, `SyncTransport`, `InMemoryRoom`, `InMemoryTransport`, and pure parser/retry helpers.
- `transport_ws` owns websocket extern/no-op surface with js/native target split unchanged.
- `editor/sync_protocol.mbt` remains unchanged in S2.
- `SyncEditor` method signatures remain byte-identical; `.mbti` validation is zero signature changes and moved types represented as `pub using` origin lines (private-field representation is `// private fields`).
- All behavioral invariants in this design are preserved and validated by migrated tests, including:
  - retries-before-advance and stale request-id behavior,
  - deferred drain ordering and mid-drain re-entry semantics,
  - `empty sync_json` retry path,
  - 1MB SyncResponse cap,
  - apply-success `Error -> Idle`,
  - single-recovery limitation, callback equality guard,
  - callback/no-op behavior for stale watchdog.
- `editor` wbtests keep `error_path_wbtest.mbt`; all other listed tests retain coverage after relocation.
- Playwright suites and workspace probe pass.
