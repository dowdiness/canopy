# Quint ↔ Canopy SyncSession recovery prototype

**PROTOTYPE / throwaway.** This is an isolated validation spike, not production
code and not a supported API. It deliberately uses only the public
`SyncSession`, `SyncIo`, `SyncHost`, wire encoder/decoder, callbacks, and watchdog
seam. No private state or Choreo is involved.

The Quint 0.32.0 model drives this deterministic named-action ITF trace:
`open`, `startRecovery`, `watchdogCurrent`, `watchdogStale`,
`watchdogCurrent`, `watchdogCurrent`, `watchdogExhaust`, `noteSyncApplied`,
`startRecoveryAgain`, `peerLeftTarget`, and terminal `done`. The MoonBit driver dispatches each
name to the corresponding public `SyncSession` API and compares every state:
status, attempt, ordered sent message kinds/count, scheduled count, apply count,
status-callback count, and peer-leave callback count.
Each recovery action explicitly flags its next apply as a retryable
`VersionNotFound`; there is no global first-call dependency. Exhaustion is an
Error transition with no extra send or schedule. The model includes the
`safety` invariant (bounded phase/attempt/counters and `sent == scheduled`).
`--broken` skips the first real `watchdogCurrent` driver operation, so replay
must report `StateDiverged`; it is not accepted merely because the command exits
nonzero.

## One command

```sh
./examples/quint-sync-recovery-prototype/run.sh
```

Set `QUINT_BIN` to an isolated Quint 0.32.0 binary when the default is absent.
The runner typechecks Quint, writes an ITF trace, jq-asserts the fixed named
action list, runs Quint's safety invariant, runs native MoonBit replay, then
verifies the negative control is exactly a `DIVERGENCE:` containing
`StateDiverged`.

Bounded verification also succeeds with Apalache 0.56.1 when Java 17 is used:

```sh
QUINT_BIN=/path/to/quint-0.32.0
nix shell nixpkgs#jdk17_headless -c "$QUINT_BIN" verify \
  examples/quint-sync-recovery-prototype/Recovery.qnt \
  --main Recovery --invariant=safety --max-steps=20
```

It is not part of `run.sh` because the host's default Java 8 cannot run this
Apalache release; CI adoption would need to pin a compatible JDK.

## Reuse check

`quint_connect.replay`/`parse_itf` is used instead of a manual ITF parser; the
public SyncSession seam is used instead of reducer/private access; and
`@wire.encode_*` plus `decode_message_result` are used instead of manual wire
bytes. The driver relies on existing `Array`, `Json`, `Result`,
`Bytes`/`Buffer`, and `Option` APIs; no new low-level parser was introduced.
