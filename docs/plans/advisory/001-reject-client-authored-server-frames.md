# Plan 001: Reject client-authored server-only relay frames

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. Stop
> on any condition listed below instead of broadening the protocol change. When
> done, update this plan's status in `README.md`, unless a reviewer owns
> the index.
>
> **Drift check (run first)**:
> `git diff --stat f6e3a0a5..HEAD -- relay/relay_room.mbt relay/relay_room_wbtest.mbt relay/README.md protocol/wire/wire.mbt sync_session/sync_session.mbt`
> If relay routing changed, compare the excerpts below and stop unless the same
> server-only frame vulnerability is still present.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security / bug
- **Audit finding**: 1, expanded during planning to cover both server-only types
- **Planned at**: commit `f6e3a0a5`, 2026-07-25

## Why this matters

`RelayRoom` authenticates the transport-level sender but broadcasts valid v3
message types it does not explicitly route. A connected client can therefore
send a forged `RelayedCrdtOps` frame naming another peer, and receivers trust
that embedded sender during recovery. The same fallback also accepts forged
`RoomControl` join/leave frames. Both types are produced by the server and must
never be accepted from a client transport.

## Current state

- `relay/relay_room.mbt:88-104` dispatches only client `CrdtOps`, `SyncRequest`,
  and `SyncResponse`; every other valid v3 type is broadcast unchanged:

  ```mbt
  match msg_type {
    b'\x01' => {
      let wrapped = wrap_with_sender(sender, b'\x06', data, 3)
      self.broadcast(sender, wrapped)
    }
    b'\x03' | b'\x04' => ...
    _ => self.broadcast(sender, data)
  }
  ```

- `protocol/wire/wire.mbt:29-41` defines `0x05` as room control and `0x06` as
  relayed CRDT operations. `encode_relayed_crdt_ops` encodes an embedded sender.
- `sync_session/sync_session.mbt:328-338` consumes that embedded sender and can
  enter recovery using it.
- `relay/relay_room_wbtest.mbt:129-144` proves ordinary client `CrdtOps` are
  wrapped with the transport sender.
- `relay/relay_room_wbtest.mbt:176-190` deliberately preserves unknown v3
  message types. Keep this forward-compatible opaque behavior.
- `relay/README.md` currently says all unknown valid-v3 types are opaque
  broadcasts without naming server-only exceptions.

### Required protocol invariant

The relay accepts these complete v3 client frame types:

- `0x01` `CrdtOps`: wrap with the authenticated transport sender and broadcast.
- `0x02` `EphemeralUpdate`: opaque broadcast.
- `0x03`/`0x04` `SyncRequest`/`SyncResponse`: rewrite sender metadata and route.
- Unknown future types: opaque broadcast, preserving the accepted v3 hard-cutover
  decision.

The relay rejects these complete v3 client frame types:

- `0x05` `RoomControl`: only `on_connect`/`on_disconnect` may create it.
- `0x06` `RelayedCrdtOps`: only the relay may create it from client `0x01`.

Short frames retain their explicitly documented transparent behavior. Complete
old-version frames remain dropped.

### Existing API First / reuse check

- **Reuse** `@wire.encode_relayed_crdt_ops` in the spoof regression test so the
  forged frame is valid canonical wire data.
- **Reuse** `encode_peer_joined` or `encode_peer_left` for the room-control
  regression test; these are the relay's existing canonical encoders.
- **Reuse** the existing `Bytes` header indexing and match in
  `RelayRoom::on_message`; no decoder or helper is needed.
- `@wire.decode_message` was checked but must not be added to relay routing: the
  relay is intentionally payload-opaque and unknown v3 types must continue to
  pass through.
- Core candidates `BytesView`, `Reader`, `Option`, `Array`, and `Map` were
  checked. Existing framing already uses them where appropriate; this change
  needs no new data manipulation.
- Introduce no helper, type, loop, mutation, import, or public API.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Baseline relay tests | `NEW_MOON_MOD=0 moon test relay` | `Total tests: 46, passed: 46, failed: 0` before edits |
| Targeted relay tests | `NEW_MOON_MOD=0 moon test relay` | 48 tests pass after adding two regressions |
| Strict lint | `NEW_MOON_MOD=0 ./scripts/check-strict.sh` | exits 0 |
| CI-equivalent full tests | `NEW_MOON_MOD=0 ./scripts/check-test-baseline.sh 7 moon test --release` | exits 0; no non-vendored failure and at most seven known vendored failures |
| JS integration build | `NEW_MOON_MOD=0 ./scripts/build-js.sh` | exits 0 and rebuilds the relay consumer in `ffi/lambda` |
| Format/interfaces | `NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt` | exits 0; no relay `.mbti` change |

## Suggested executor toolkit

Use the `moonbit`, `moonbit-agent-guide`, `moonbit-verification`, and
`moonbit-error-handling` skills if available. Use `moon ide` before inventing
any API; this plan expects no new API.

## Scope

**In scope**:

- `relay/relay_room.mbt`
- `relay/relay_room_wbtest.mbt`
- `relay/README.md`
- `README.md` status row only

**Read-only references**:

- `protocol/wire/wire.mbt`
- `protocol/wire/README.md`
- `sync_session/sync_session.mbt`
- `docs/decisions/2026-07-22-protocol-v3-hard-cutover.md`

**Out of scope**:

- Do not change protocol version 3, wire encodings, enum variants, constants,
  short-frame behavior, or unknown-type forwarding.
- Do not add authentication, room authorization, rate limits, or observability;
  those belong to the hosting shell and Plan 003's retirement decision.
- Do not edit `protocol/wire` or `sync_session`.
- Do not modify `examples/relay-server` in this slice.
- Preserve the pre-existing dirty worktree by using an isolated worktree.

## Git workflow

- Branch: `advisor/001-reject-server-only-relay-frames`
- Suggested commit: `fix(relay): reject client-authored server frames`
- Do not push or open a PR without explicit operator instruction.

## Steps

### Step 1: Pin both exploits with failing tests

In `relay/relay_room_wbtest.mbt`, add two white-box tests adjacent to
`on_message: wraps CrdtOps as RelayedCrdtOps`. Follow the existing
`make_recorder`, `connect_ok`, and message-clearing pattern.

Test A: `on_message: drops client-authored RelayedCrdtOps`

1. Connect `alice` and `bob` and clear join messages.
2. Build a valid forged frame with
   `@wire.encode_relayed_crdt_ops("bob", b"\x42")`.
3. Call `room.on_message("alice", forged)`.
4. Assert both Alice and Bob received zero messages.

Before the fix, Bob receives one frame, so the new test must fail.

Test B: `on_message: drops client-authored RoomControl`

1. Connect `alice` and `bob` and clear join messages.
2. Build a valid server control frame with `encode_peer_left("bob")`.
3. Call `room.on_message("alice", forged)`.
4. Assert both Alice and Bob received zero messages and `peer_count()` remains 2.

Before the fix, Bob receives the forged control frame, so the new test must fail.

**Verify red state**:

```bash
NEW_MOON_MOD=0 moon test relay
```

Expected: exactly the two new tests fail; all 46 pre-existing tests still pass.
If a test unexpectedly passes before the production edit, inspect drift and stop.

### Step 2: Reject the two server-only type bytes

In `RelayRoom::on_message`, add one match arm before the wildcard:

```mbt
b'\x05' | b'\x06' => ()
```

Add a concise intent comment: room control and relayed-operation envelopes are
server-authored; accepting them from a client permits peer-identity spoofing.
Do not parse either payload, close the peer, send an error response, or alter the
wildcard arm.

The resulting dispatch shape must remain:

```mbt
b'\x01' => ...
b'\x03' | b'\x04' => ...
b'\x05' | b'\x06' => ()
_ => self.broadcast(sender, data)
```

**Verify green state**:

```bash
NEW_MOON_MOD=0 moon test relay
```

Expected: `Total tests: 48, passed: 48, failed: 0`.

### Step 3: Document the server-only exception

Update `relay/README.md` under `Protocol behavior` to state that:

- complete v3 room-control and relayed-CRDT frames are server-authored and are
  dropped when received from client peers;
- unknown future v3 types remain opaque broadcasts;
- short-frame passthrough remains unchanged.

Do not claim that relay payloads are generally decoded. The module still reads
only routing envelope metadata.

**Verify**:

```bash
rg -n 'server-authored|RoomControl|RelayedCrdtOps|unknown message types|short' relay/README.md
```

Expected: all four boundaries are discoverable in the README.

### Step 4: Run package, strict, CI-equivalent, JS, format, and API gates

```bash
NEW_MOON_MOD=0 moon info
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 ./scripts/check-strict.sh
NEW_MOON_MOD=0 moon test relay
NEW_MOON_MOD=0 ./scripts/check-test-baseline.sh 7 moon test --release
NEW_MOON_MOD=0 ./scripts/build-js.sh

git diff --check
git diff -- relay/pkg.generated.mbti
git status --short
```

Expected: targeted tests pass; the full-test wrapper accepts only the known
vendored baseline and zero non-vendored failures; the JS build succeeds;
`relay/pkg.generated.mbti` is unchanged; and only the three in-scope files plus
the allowed plan index status are changed by this task.

## Test plan

Add exactly two white-box regression tests to `relay/relay_room_wbtest.mbt`:

- canonical forged `RelayedCrdtOps` from a connected peer is dropped;
- canonical forged `RoomControl` from a connected peer is dropped without
  mutating room membership.

Existing tests must continue to cover:

- `CrdtOps` is wrapped with the transport sender;
- sync requests/responses are routed with rewritten sender metadata;
- short frames pass through;
- old protocol frames are dropped;
- unknown future v3 types pass through.

The CI-equivalent release workspace suite must run through
`scripts/check-test-baseline.sh`; bare `moon test` is not the repository's
machine-checkable full-suite gate because known vendored failures are tracked
separately. Rebuild JS because `examples/relay-server` consumes relay through
`ffi/lambda`. No snapshot updates are allowed.

## Done criteria

- [ ] A connected client cannot broadcast type `0x05` or `0x06`.
- [ ] Legitimate client `0x01` still becomes a server-authored `0x06` frame.
- [ ] Unknown valid-v3 types and short frames retain existing behavior.
- [ ] `NEW_MOON_MOD=0 moon test relay` reports 48/48 passing tests.
- [ ] The strict wrapper and CI-equivalent release-test baseline exit 0.
- [ ] `NEW_MOON_MOD=0 ./scripts/build-js.sh` exits 0.
- [ ] `moon info` and `moon fmt` exit 0 with no relay `.mbti` diff.
- [ ] No public API, wire encoding, or out-of-scope file changed.

## STOP conditions

Stop and report if:

- any production client is found intentionally sending type `0x05` or `0x06`;
- the protocol constants or server/client ownership differ from this plan;
- the fix appears to require decoding arbitrary payloads or changing protocol v3;
- any pre-existing relay test changes expected output;
- `moon info` changes the relay public interface;
- the strict baseline is not green before relay edits for a Canopy-owned reason;
- the task cannot be isolated from pre-existing worktree changes.

## Maintenance notes

Any new server-authored wire type must be added to this deny arm or produced
through a routing branch that overwrites client-supplied identity. Reviewers
should scrutinize the wildcard arm whenever protocol variants are added. This
plan intentionally preserves the relay's opaque-forwarding contract for unknown
future client types.