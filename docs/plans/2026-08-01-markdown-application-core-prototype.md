# Markdown Application Core Pure Reducer Prototype

**Status:** Isolated prototype; not the materialized Application Train plan and
not evidence that #1073 is complete or unblocked.

## Objective

Test whether Raw/Preview application state can live behind one deterministic
MoonBit reducer seam before Rabbita mount/unmount is available.

## Package and interface

- Implement only in `probe/markdown_application_core`.
- The seam is `ApplicationState + ApplicationEvent -> Transition`.
- `Transition` returns the next immutable state and immutable effect decisions.
- Canonical Markdown source is treated as an opaque committed value; Loom and
  Canopy editor/projection packages remain its production authorities.
- The prototype assumes `ReplaceCanonicalSource` is an infallible, atomic shell
  command. A production design must specify acknowledgement or reconciliation
  before adopting this transition contract.

## In scope

- Raw and Preview mode selection.
- Committed canonical source replacement without normalization.
- Immutable versioned snapshots containing source and mode.
- Atomic rejection of unknown snapshot versions.
- Ordered pure decisions for shell-owned canonical-source replacement.
- Idempotent source/mode transitions.

## Out of scope

- Block editing, parsing, projection, diagnostics, semantic identity, selection,
  focus-token execution, rendering, DOM, Rabbita, Browser App/Session, disposal,
  JavaScript encoding, Vanilla/Waku/React/Vue, and submodule changes.
- Promotion into a production package before #1067/#1068 materialize exact
  package ownership and the canonical Browser App/Session contract.

## Behavioral matrix

| Input | Expected transition |
| --- | --- |
| New committed source in Raw or Preview | Preserve text byte-for-byte; mode unchanged |
| Same committed source | State unchanged; no decision |
| Select the other supported mode | Source unchanged; mode changes |
| Select current mode | State unchanged; no decision |
| Restore supported snapshot | Source and mode change atomically; request replacement only when source differs |
| Restore unknown snapshot version | State unchanged; return one typed rejection decision |
| LF / CRLF / CR / EOF source | Preserve the exact `String`; no line-ending policy |

Projection shape, containers, ranges, identity, and focus/selection decisions are
explicitly not exercised because this prototype does not parse or render source.

## Reuse check

- Reuse `String` as the opaque canonical source and immutable
  `@vector.Vector` for ordered decisions.
- `SourceSnapshot` was checked but represents analysis staleness rather than
  restorable application state.
- `TreeEditorState` was checked but owns projected Block editor state, which is
  outside this Raw/Preview prototype.
- `SyncEditor` was checked but is a mutable CRDT, websocket, undo, and
  incremental-runtime shell rather than a pure application reducer.
- The prototype introduces only its state, event, decision, snapshot, and
  transition vocabulary; `reduce` is their deterministic responsibility
  boundary. It introduces no loop or imperative helper.

## Validation

```bash
moon check --package-path probe/markdown_application_core --deny-warn
moon test --package dowdiness/canopy/probe/markdown_application_core
moon test --package dowdiness/canopy/probe/markdown_application_core --release
moon info probe/markdown_application_core
moon fmt --check
./scripts/validate-pr-ready.sh --target probe/markdown_application_core
```
