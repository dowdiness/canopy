# Quint SyncSession recovery verification

This is Canopy's durable verification suite for the public `SyncSession`
recovery protocol. It is verification-only: production MoonBit packages do not
depend on Quint, Choreo, or `quint_connect`.

## Verification architecture

The suite deliberately uses three layers with different guarantees:

1. **`RecoveryCore.qnt`** — pure local policy:
   `State + Event -> { post_state, effects }`.
2. **`RecoveryDistributed.qnt`** — monomorphic three-peer network shell for
   bounded symbolic verification with Apalache.
3. **`RecoveryChoreo.qnt`** — message-soup simulation and seeded trace
   generation for black-box conformance against the real MoonBit
   `SyncSession`.

`Recovery.qnt` retains the compact deterministic local witness used to diagnose
retry exhaustion, recovery reset, and target leave.

### Guarantee boundary

| Layer | Guarantee |
|---|---|
| `Recovery.qnt` | bounded symbolic local safety + deterministic implementation replay |
| `RecoveryDistributed.qnt` | bounded symbolic distributed safety through six steps |
| `RecoveryChoreo.qnt` | seeded randomized simulation and generated-trace conformance |
| MoonBit adapter | public-observable conformance for every replayed trace |

The six-step distributed bound is intentional and minimal: after initialization
it covers `open -> start -> watchdog x4 -> exhausted`. The model also explores
Bob/Carol target choice, empty/helpful responses, response/watchdog ordering,
stale messages and timers, target leave, error reset, and two successive recovery
cycles. No liveness property is claimed.

Choreo itself still does not translate through `quint verify` at the pinned
versions because its generic rows and higher-order transition framework fail in
the Quint/Apalache pipeline. `RecoveryDistributed.qnt` supplies the symbolic
network guarantee without copying Choreo or changing production code.

## Stable Choreo trace contract

Generic Choreo executions expose only `step` through `mbt::actionTaken`.
`RecoveryChoreo.qnt` therefore records a typed command in:

```text
RecoveryChoreo::choreo::s.extensions.command
```

The MoonBit adapter configures this as `nondet_path` and decodes commands such
as `OpenPeer`, `StartRecovery`, `RespondEmpty`, `DeliverHelpful`, and
`FireWatchdog`. It never infers behavior from Choreo's opaque transition
record. `quint_connect.replay_suite` creates a fresh driver for every trace.

The adapter drives only public seams:

- `SyncSession::on_open`, `on_message`, `on_watchdog_fire`, and
  `note_sync_applied`;
- `SyncIo` send and watchdog callbacks;
- `SyncHost` apply/status/peer-leave callbacks;
- public wire encoders and decoder.

It compares status, attempt, ordered outgoing message kinds, watchdog count and
latest request ID, apply count, status callbacks, and peer-leave callbacks.
Bob/Carol response construction remains a modeled environment step; a second
real session is not required for recovery-policy conformance.

## One command

From the repository root:

```sh
./examples/quint-sync-recovery/run.sh
```

The command runs:

- flat and distributed Quint typechecks;
- local and distributed bounded `quint verify` checks;
- 500 seeded raw-distributed traces with explicit coverage assertions;
- 200 seeded Choreo traces replayed through real public `SyncSession` APIs,
  including repeated recovery;
- a deterministic named Choreo witness;
- model and implementation mutation controls.

The mutation controls are gating: attempt 5 must violate `safety`, and skipping
a real empty-response delivery must produce `StateDiverged`.

## Pinned toolchain

- Quint: `@informalsystems/quint@0.32.0`, locked by `package-lock.json`
- Apalache: Quint 0.32.0 bundled default, 0.56.1
- Java: 17 or newer; the runner uses `nixpkgs#jdk17_headless` when local Java is
  older and Nix is available
- Choreo: git submodule `deps/choreo` at
  `000cf4eed315187dc6f216a148781cff7dde6521`
- MoonBit adapter: `mizchi/quint_connect@0.1.0`

Initialize dependencies after checkout with:

```sh
git submodule update --init --recursive
```

The runner installs the locked npm dependencies when the local Quint binary is
missing. CI installs them explicitly with `npm ci`.

## Maintenance contract

Changes to any of these surfaces must run and, where semantics change, update
this suite:

- `modules/canopy/sync_session/**`
- `modules/canopy/protocol/wire/**`
- the event-graph-walker sync-message dependency
- retry limits, request-ID matching, watchdog behavior, response handling,
  status transitions, or peer-leave policy

The path-filtered `Quint Sync Recovery Verification` CI job enforces the suite
and is included in `All Checks Passed`.

## Reuse check

- `RecoveryDistributed` imports and uses `RecoveryCore.apply_event`; retry
  policy is not duplicated.
- `RecoveryChoreo` uses the same core and adds only network scheduling.
- `quint_connect.parse_itf_with_config` and `replay_suite` provide nested ITF
  parsing and fresh-driver multi-trace replay.
- MoonBit reuses `Json`/`Map`, `Array`, `Result`, `Option`, `Bytes`/`Buffer`,
  public `SyncSession`, and public wire APIs.
- `replay_stateless` and `InMemoryTransport` were checked but are not suitable:
  state/effect comparison and controlled network scheduling are required.

Remaining mutation is confined to the imperative verification shell: captured
callbacks, queued observations, controlled failure injection, and external
process/file execution. Recovery decisions remain in the pure Quint core.
