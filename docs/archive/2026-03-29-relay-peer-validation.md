# Relay Peer ID Validation

## Status

Done (PR #188, 2026-04-17). Unblocked once container Phase 3 (unified sync) landed via egw#21.

Shipped:
- `on_connect` returns `Bool`; rejects empty and duplicate peer IDs.
- `on_message` drops frames from non-member senders.
- `on_disconnect` is a no-op for non-members (prevents ghost `PeerLeft` from spuriously clearing ephemeral state in `editor/sync_editor_ws`).
- CF Worker closes rejected duplicates with application close code 4001.
- 5 new `*_wbtest.mbt` tests; `.mbti` diff limited to the two intended return-type changes.

## Why

`RelayRoom` currently trusts caller-supplied peer IDs and membership state.
That keeps the room implementation simple, but it leaves duplicate IDs and
invalid disconnect/message cases dependent on external glue rather than the room
API itself.

This work is intentionally deferred until the container implementation defines
the next sync boundary. Tightening validation earlier risks hardening the wrong
interface.

## Scope

In:
- `relay/relay_room.mbt`
- `relay/relay_room_wbtest.mbt`
- `relay/error_path_wbtest.mbt`
- `crdt_relay.mbt` if API adaptation is required

Out:
- changes to the wire protocol
- auth or identity issuance

## Current State

- `RelayRoom` documents that peer IDs are trusted and that there is no duplicate
  or membership validation.
- The active backlog calls out duplicate/invalid peer rejection as unfinished.

## Desired State

- The room API has explicit, tested behavior for duplicate peer IDs and invalid
  membership operations.
- Invalid room operations do not silently rely on caller discipline.
- The validation rules match the post-container sync design rather than the
  current pre-container assumptions.

## Steps

1. Define the desired API behavior for duplicate connect, invalid disconnect,
   and invalid sender/message cases.
2. Implement validation in `RelayRoom`.
3. Update tests for both happy-path and error-path behavior.
4. Adjust any FFI adapter behavior if needed.

## Acceptance Criteria

- [x] Duplicate peer IDs are rejected or ignored by defined, tested behavior.
- [x] Invalid disconnects and invalid sender message cases have defined behavior.
- [x] Relay tests cover the new validation rules.

## Validation

```bash
moon test
moon check
```

## Risks

- Tightening validation may require small adapter changes if existing callers
  depended on silent no-op behavior.
- Doing this too early could lock in validation behavior that no longer matches
  the container-based sync design.

## Notes

- Relevant code: `relay/relay_room.mbt`
