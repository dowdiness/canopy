# Generative UI Async Driver Shell

## Decision

Add a private deterministic async driver shell in `ffi/jsx`. It owns transport
handles and one existing `@cognition.GenerativeUiLifecycle`; it does not own
candidate validation, base-revision policy, dry-run policy, DOM application, or
session revision mutation. `GenerativeUiLifecycle::restart` is the only
restart operation, preserving generation identity across cancellation.

The complete-request provider boundary remains separate. Its public request,
status, and error descriptors describe graph-visible whole requests. The
private `ProviderDriverAction` and `ScriptedProviderDriver` are a driver-pattern
reference only; no private type is imported across packages.

## Data flow

1. Browser creates a normal JSX session and an async driver bound to that
   session and base revision.
2. Driver starts generation A through `Start`, obtains A's generation ID, and
   awaits a deterministic JS Promise for A's first chunk.
3. Driver constructs `GenerativeUiInput::chunk` and dispatches it.
4. Browser cancels A. The driver dispatches `GenerativeUiInput::cancel` and
   aborts A's transport controller. The transport records the abort but still
   permits its queued late callback.
5. Driver calls `GenerativeUiLifecycle::restart` for generation B, preserving
   the generation counter and selecting the current session revision.
6. Driver awaits A's late Promise after B starts and dispatches the A envelope;
   cognition returns `Ignored(StaleGeneration)` without touching the session.
7. Driver awaits B chunks and final envelope. Existing replay/commit helpers
   decode and validate B, then reuse `jsx_session_commit_candidate`, including
   dry-run, DOM apply, recovery, and exactly-once revision advancement.
8. Browser asserts A-late revision/markup unchanged, B committed once, abort
   observed, and host state unchanged.

The async export is `Promise::from_async`; provider waits use the real
`@js_async` Promise/Abort path (`run_promise`, `Promise::wait`, and
`AbortController`). Scripted transport uses microtask-delayed local promises;
there is no network or Gemini dependency.

## Tests first

- Add a failing whitebox/browser-facing test for the staged A/B sequence and
  assert the trace, transport abort, revision, mounted markup, and host state.
- Add a failing session-isolation property for two live sessions, disposal,
  distinct handles/internal IDs, and late input rejection.
- Add provider-failure coverage that returns a structured non-commit result.
- Reuse existing session and cognition tests; do not add a second fake DOM or
  lifecycle implementation.

## Files expected

- `ffi/jsx/moon.pkg`: import `moonbitlang/async/js_async`; export only the
  intentionally underscored async test surface.
- `ffi/jsx/generative_ui_replay_adapter.mbt`: extract the shared lifecycle
  completion/validation/commit helper without changing its JSON contract.
- `ffi/jsx/generative_ui_async_driver.mbt`: private driver and deterministic
  JS Promise/Abort scripted transport.
- `ffi/jsx/*_wbtest.mbt`: failing/green shell and isolation tests.
- `examples/web/src/genui.js` and `examples/web/tests/genui.spec.ts`: thin
  browser observability wrapper and staged cancellation/late-event assertions.
- `docs/plans/evidence/2026-07-13-generative-ui-safety-metrics.json` plus the
  relevant plan: record the new deterministic counts and AC-12/AC-14 evidence.

## Acceptance

- A late event cannot change revision or committed markup.
- B commits exactly once at base revision + 1.
- Transport abort is observable.
- Host filter, selection, detail, and focus remain intact.
- Two sessions remain isolated after disposal and late events.
- No live provider integration, second lifecycle, JS-only timing substitute,
  or Rabbita-pointer change.

## Verification record

- [x] `NEW_MOON_MOD=0 moon check ffi/jsx`
- [x] `NEW_MOON_MOD=0 moon test ffi/jsx --target js` — 52/52
- [x] `npx tsc --noEmit -p tsconfig.json` in `examples/web`
- [x] Playwright focused async/session scenarios — 7/7
- [x] Playwright complete GenUI suite — 21/21
- [x] Deterministic safety metrics updated with zero stale revision/markup,
  zero isolation failures, and observed transport aborts.
- [x] Live Gemini/provider integration remains intentionally gated.
