# Quint ↔ Canopy SyncSession recovery prototype

**PROTOTYPE / throwaway.** This is isolated verification code, not a supported
API. It uses only public `SyncSession`, `SyncIo`, `SyncHost`, wire codecs,
callbacks, and the watchdog seam. Production packages do not depend on Quint or
Choreo.

The prototype now exercises two complementary paths:

1. `Recovery.qnt` generates the original deterministic local recovery trace.
2. `RecoveryCore.qnt` defines a pure local `State + Event -> Decision` core;
   `RecoveryChoreo.qnt` wraps it with three peers, Choreo's message soup,
   one-shot message/event consumption, responder choice, and watchdog events.

The Choreo wrapper uses `alice`, `bob`, and `carol`. Its generic `step` explores
which process runs, whether a responder returns an empty or helpful response,
and whether a response or watchdog is handled first. The bounded `safety`
invariant checks retry/counter bounds, status/attempt consistency,
`sent == scheduled`, and that a peer never recovers from itself.

A deterministic Choreo witness is also emitted as an MBT ITF trace:

`openAlice → openBob → openCarol → aliceStartsRecovery(bob) →
bobRepliesEmpty(1) → aliceReceivesEmpty → aliceFiresStaleTimeout(1) →
bobRepliesHelpful(2) → aliceReceivesHelpful`

The MoonBit adapter projects the nested
`RecoveryChoreo::choreo::display` state with
`quint_connect.parse_itf_with_config`, dispatches the named actions to one real
public `SyncSession`, and compares status, attempt, ordered sent-message kinds,
watchdog schedule count and latest public scheduler request ID, apply count,
status callbacks, and peer-leave callbacks. The active target is compared via
public `Recovering`/`Error` status; after returning to `Idle`, the public API no
longer exposes the former target. Responder-only Choreo actions are environment
steps and therefore do not call the local session.

Two falsification controls are mandatory:

- `--broken` skips the real empty-response delivery; replay must report
  `StateDiverged`.
- `modelMutationStep` deliberately bypasses the core and creates attempt 5;
  Quint's `safety` invariant must reject it.

## One command

```sh
./examples/quint-sync-recovery-prototype/run.sh
```

The runner requires Quint 0.32.0 (`QUINT_BIN` can override the default). It
fetches Choreo once when needed and verifies the exact pinned commit
`000cf4eed315187dc6f216a148781cff7dde6521`; set `CHOREO_DIR` to an existing
checkout at that commit to avoid the fetch. Choreo is assembled in a temporary
directory rather than copied into Canopy.

The command performs:

- local Quint typecheck, safety simulation, ITF replay, and driver mutation;
- raw-core and Choreo typechecks;
- 100 randomized Choreo traces up to 12 steps with `safety`, plus coverage
  assertions for attempts 0–4, exhaustion, both possible targets, and helpful
  recovery;
- the ten-state deterministic Choreo ITF replay;
- the Choreo driver mutation and model mutation controls.

## Symbolic verification boundary

The original flat `Recovery.qnt` still passes bounded Apalache verification
with Java 17:

```sh
QUINT_BIN=/path/to/quint-0.32.0
nix shell nixpkgs#jdk17_headless -c "$QUINT_BIN" verify \
  examples/quint-sync-recovery-prototype/Recovery.qnt \
  --main Recovery --invariant=safety --max-steps=20
```

At the pinned versions, the Choreo wrapper typechecks and simulates but does
**not** translate through `quint verify`: Quint/Apalache reports internal or row
type translation errors for Choreo models, including Choreo's own
`two_phase_commit` example. Consequently, the distributed result is randomized
simulation plus deterministic implementation conformance, not symbolic
verification. This is an adoption risk, not hidden evidence of proof.

## Reuse check

- `RecoveryChoreo` reuses `RecoveryCore.apply_event` rather than duplicating
  retry policy.
- `quint_connect.parse_itf_with_config` and `replay` are used instead of a
  custom ITF parser/replay kernel.
- Public `SyncSession` APIs and `@wire.encode_*`/`decode_message_result` are
  used instead of private state or handwritten wire bytes.
- MoonBit `Json`/`Map`, `Array`, `Result`, `Bytes`/`Buffer`, and `Option` APIs
  handle projection and observation.

New MoonBit helpers are limited to the adapter boundary: injecting a failed
relayed operation, delivering an encoded response, and normalizing Choreo's
flat display into the existing comparison shape.
