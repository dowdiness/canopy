# SyncRequest / SyncResponse Recovery Follow-Up

## Status

Ready.

Unblocked now that the container substrate (egw#21) and Model I
undo/transactions (egw#28, canopy#187) have landed. Recovery runs on top of a
stable Document boundary, so we can finalize retry/failure semantics without
reinforcing pre-container assumptions.

## Why

Two observable gaps remain in the current WS recovery flow:

1. **No response watchdog.** `handle_recovery_retry` is only reachable from the
   `SyncResponse` handler. If a response never arrives — lost frame, peer
   stalled on its event loop, relay hiccup — recovery sits forever with no
   retry and no surfaced failure.
2. **No failure surface.** `sync_editor_ws.mbt:117` and `:332` carry `TODO: set
   SyncStatus::Error` placeholders. Recovery exhaustion is invisible to the
   editor and the UI.

Both gaps are pre-container in origin. With the sync boundary settled, we can
close them without re-architecting the substrate.

## Scope

In:
- `editor/sync_editor.mbt` (status cell, callback registration)
- `editor/sync_editor_ws.mbt` (watchdog hook, status transitions)
- `editor/recovery.mbt` (RecoveryContext — no changes to retry budget)
- `editor/sync_editor_ws_wbtest.mbt`, `editor/error_path_wbtest.mbt`, `editor/sync_status_wbtest.mbt`
- `ffi/lambda/ws.mbt` (watchdog scheduler hook, status callback bridge)
- `ffi/lambda/moon.pkg` (export whitelist for new FFI symbols)
- `examples/relay-server/src/index.ts` or the JS glue layer (setTimeout wiring)

Out:
- Relay-side protocol changes (see Design Decisions below).
- Broader transport redesign.
- UI-side Valtio / React wiring — that's downstream work once the FFI hook
  lands.

## Current State

- Recovery entry, three-retry exhaustion, request-id / epoch matching, and
  deferred-message buffering are all implemented in `sync_editor_ws.mbt`.
- `PeerLeft` already aborts recovery when the target leaves.
- Only the "response arrived" branches drive `handle_recovery_retry`; the
  "no response arrived" branch does nothing.
- No `SyncStatus` type exists. Two `TODO: set SyncStatus::Error` comments mark
  the intended failure-surface points.

## Design Decisions

### Reject: relay-side NACK

Considered and rejected. Rationale:

- **PeerLeft already covers absent-target.** The relay broadcasts `PeerLeft(X)`
  before dropping a SyncRequest targeting a removed peer; WebSocket ordering
  guarantees the client sees PeerLeft, which already clears recovery.
- **NACK doesn't cover response-loss.** If the target accepts the request and
  its SyncResponse is lost (WS backpressure, JS stall, transient relay issue),
  no NACK fires. Only a watchdog catches this.
- **Watchdog is necessary regardless**, so NACK becomes pure latency
  optimization on a narrow race, at the cost of new protocol surface that
  every future transport must replicate.

### Accept: client-side watchdog

A single watchdog armed on each SyncRequest send. On fire, invoke the same
`handle_recovery_retry` path the empty-response case uses — unifying timeout
and empty-response retry accounting under the existing three-retry budget.

### Accept: `SyncStatus` enum with callback hook

One callback slot, fires on transition, payload is the new `SyncStatus`.
Rationale in first-principles terms:

- Embedding a Valtio-style cell in `editor/` leaks UI framework concerns into
  the editor package. The architecture keeps framework bindings at the FFI/web
  layer.
- Polling getter requires the consumer to synthesize change detection — with
  useSyncExternalStore this collapses back into a subscribe callback anyway.
- Callback direction (editor → JS) mirrors `ws_on_*` (JS → editor) cleanly.

One slot (not a list), transitions only (not per-tick), no synchronous
re-entry into `SyncEditor` from the callback.

## SyncStatus State Machine

### Type shape

```moonbit
pub enum SyncStatus {
  Disconnected
  Idle
  Recovering(peer_id~ : String, attempt~ : Int)  // attempt: 1..4
  Error(reason~ : SyncErrorReason)
}

pub enum SyncErrorReason {
  Exhausted(peer_id~ : String)   // 3 retries after initial, no success
  TargetLeft(peer_id~ : String)  // PeerLeft mid-recovery
}
```

Including `Disconnected` avoids forcing the FFI layer to synthesize
connection status from a separate signal.

### Transitions

| From            | Trigger                                    | To                       |
|-----------------|--------------------------------------------|--------------------------|
| `Disconnected`  | `ws_on_open`                               | `Idle`                   |
| `Idle`          | `ws_on_close`                              | `Disconnected`           |
| `Idle`          | `enter_recovery(X, msg)`                   | `Recovering(X, 1)`       |
| `Recovering(X,n)` | successful response + drain               | `Idle`                   |
| `Recovering(X,n)` | watchdog fire or empty response, n < 4   | `Recovering(X, n+1)`     |
| `Recovering(X,n)` | watchdog fire or empty response, n == 4  | `Error(Exhausted(X))`    |
| `Recovering(X,_)` | `PeerLeft(X)` received                   | `Error(TargetLeft(X))`   |
| `Recovering(_,_)` | `ws_on_close`                            | `Disconnected`           |
| `Error(_)`      | `ws_on_close`                              | `Disconnected`           |
| `Error(_)`      | next successful `apply_sync` (any source) | `Idle`                   |

Notes:
- `Error → Idle` on next successful apply: treat Error as "last-known bad" —
  as soon as causal progress resumes (another peer fills the gap via
  RelayedCrdtOps), we recover without requiring UI intervention.
- `PeerLeft(X)` during recovery transitions to `Error(TargetLeft)` instead of
  silently clearing to `Idle` as today, so the UI can surface the abort.
- **Attempt counting**: `attempt=1` is the original `enter_recovery` send
  (no retry yet). `max_retries_after_initial=3` in `editor/recovery.mbt`
  means up to 3 additional retries, for a total wire budget of 4 sends
  (attempt 1..4) before `Error(Exhausted)`. With a 5s watchdog this gives
  ~20s worst-case time-to-surface.

### Emission discipline

`SyncEditor` holds `status : SyncStatus` and `on_status_change : Option[(SyncStatus) -> Unit]`. All transitions funnel through one private helper:

```moonbit
fn[T] SyncEditor::set_status(self, new_status : SyncStatus) -> Unit {
  if self.status == new_status { return }  // no-op on equal transitions
  self.status = new_status
  match self.on_status_change {
    Some(cb) => cb(new_status)
    None => ()
  }
}
```

Single funnel guarantees every transition emits exactly once and no path
forgets to emit.

## Watchdog Design

### Mechanics

FFI owns time-keeping; editor owns semantics.

1. `SyncEditor` exposes `set_watchdog_scheduler(fn : (Int) -> Unit)`. The FFI
   layer registers a scheduler at construction.
2. On each `send_sync_request(target, request_id)`, `SyncEditor` invokes the
   registered scheduler with `request_id`. The FFI implementation does
   `setTimeout(() => editor.on_watchdog_fire(request_id), TIMEOUT_MS)`.
3. When the timer fires, FFI calls `on_watchdog_fire(request_id)`. Editor:
   - If `recovery` is `None`: ignore (already resolved or aborted).
   - If current `request_id` differs: ignore (stale timer — a response already
     advanced the epoch).
   - Else: call `handle_recovery_retry()` — same path as empty response.

### Timeout value

Default `WATCHDOG_MS = 5000`. Tunable via `set_watchdog_timeout(ms : Int)`.
Rationale: typical WS round-trip is <100ms; 5s is generous enough to absorb
event-loop stalls and relay backpressure without being user-visibly slow.

### Request-id uniqueness

Already handled — `recovery_epoch` increments on every retry, and
`matches_request_id` checks both the current attempt and carryover cases.
Watchdog fires cross-check against the same field.

### Why reuse `handle_recovery_retry`

Unifying watchdog and empty-response retry under one counter preserves the
"three retries total" contract. Separate counters would complicate exhaustion
logic and introduce edge cases where a watchdog-fire + empty-response
interleave produces >3 total attempts.

## Steps

1. Add `SyncStatus` and `SyncErrorReason` enums in `editor/`. Derive `Eq`,
   `Show`/`Debug` per project conventions.
2. Add `status : SyncStatus` field and `on_status_change` callback slot to
   `SyncEditor`. Initialize to `Disconnected`.
3. Add `set_status` private helper with the equality guard.
4. Thread `set_status` through every transition point listed in the table:
   `ws_on_open`, `ws_on_close`, `enter_recovery`, successful-drain path in
   `SyncResponse` handler, `handle_recovery_retry` exhaustion, `PeerLeft`
   handler, recovery-re-entry after deferred-message failure, and the
   `Error → Idle` restoration point in `apply_sync`'s success path.
5. Replace the two `TODO: set SyncStatus::Error` comments with actual
   transitions.
6. Add watchdog scheduler hook: `set_watchdog_scheduler`,
   `on_watchdog_fire(request_id)`, optional `set_watchdog_timeout`.
7. Invoke scheduler from `send_sync_request`.
8. Wire FFI side: `setTimeout` in `ffi/lambda/ws.mbt` JS glue;
   `on_status_change` callback bridge.
9. Tests:
   - Watchdog fires → retry triggered → exhaustion → `Error(Exhausted)`.
   - Response arrives before watchdog → stale watchdog is ignored.
   - `PeerLeft` during recovery → `Error(TargetLeft)`.
   - Successful recovery from `Error` state via later RelayedCrdtOps →
     `Error → Idle`.
   - Equality guard: no callback emission on no-op transitions.
10. Update active docs: delete or update the archived 2026-03-22 recovery
    design/impl notes' references if they claim pre-container semantics.

## Acceptance Criteria

- [ ] `SyncStatus` enum defined and emitted at every transition listed in the
      table.
- [ ] Exactly one callback slot, fires only on distinct transitions.
- [ ] Watchdog fires on missing response, routes through
      `handle_recovery_retry`, respects the three-retry budget.
- [ ] Watchdog does not fire after response arrival (stale-epoch check).
- [ ] `Error(_)` clears to `Idle` when causal progress resumes via another
      peer.
- [ ] No relay-side protocol changes landed.
- [ ] Tests cover each transition edge, including the stale-watchdog and
      Error-clearing paths.
- [ ] `moon check`, `moon test`, `moon info`, `moon fmt` all clean.

## Validation

```bash
moon check
moon test
moon info && git diff editor/pkg.generated.mbti  # verify API surface
moon fmt
```

Manual: bring up `examples/web` with two browser tabs, force a causal gap
(e.g., disconnect peer B mid-edit, apply edits on A, reconnect B), verify
`SyncStatus` transitions are observable at the FFI boundary.

## Risks

- **Watchdog interference with slow but live peers.** 5s default should be
  safe; if observed flakiness appears in weak-network manual testing, raise
  the default rather than add protocol complexity.
- **Callback re-entry.** If the FFI callback synchronously triggers another
  editor operation that changes status, we could emit twice. The equality
  guard absorbs duplicates; re-entry into methods that mutate recovery state
  is the real concern. Document the contract: callback must not call back
  into `SyncEditor` synchronously.
- **`Error → Idle` auto-clear** may mask persistent issues in UI. Acceptable
  tradeoff: the UI sees the Error transition, can record/log it, and
  subsequent recovery is still visible as a return to Idle.

## Notes

- First-principles analysis that drove the NACK-rejected / watchdog-accepted
  decision is preserved above in the Design Decisions section — future work
  that revisits these tradeoffs should start there.
- Historical context: `docs/archive/completed-phases/2026-03-22-websocket-sync-recovery-design.md`
- Historical context: `docs/archive/completed-phases/2026-03-22-websocket-sync-recovery-impl.md`
