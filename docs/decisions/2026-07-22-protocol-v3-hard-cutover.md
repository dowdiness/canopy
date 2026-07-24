# Protocol v3 hard cutover

**Date:** 2026-07-22

**Status:** Accepted

**Related:**

- [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)
- [Library API boundary](2026-06-11-library-api-boundary.md)
- [Archived EGW companion and Canopy migration](../archive/2026-07-22-egw-companion-canopy-migration.md)

**Reader:** Maintainers changing Canopy collaboration frames, relays, clients,
or the EGW dependency used inside those frames.

**Decision:** Move Canopy's collaboration frame version from `0x02` to `0x03`
as a coordinated hard cut. Do not add a v2 decoder, identity bridge, or mixed-
version room mode.

**Keep until:** Permanently. ADRs are superseded rather than deleted.

**Disposition:** Supersede this ADR only if a deployed rolling-upgrade or
persistent-room requirement justifies a negotiated multi-version protocol.

## Context

Canopy protocol v2 carries EGW versions and sync messages as opaque bytes or
JSON strings. Real EGW 0.3 and 0.4 processes accepted their own payloads but
rejected every tested cross-version version, full-sync, incremental-sync, and
empty-incremental fixture in both directions.

The outer Canopy frame did not corrupt either payload family. Keeping the v2
version byte while changing the enclosed EGW schema would therefore let frame
decoding succeed before sync failed at the EGW boundary. That failure is too
late and is indistinguishable from malformed or causally incomplete data.

EGW 0.4 intentionally removed the v0.3 local-logical-version identity model and
provides no legacy decoder or migration heuristic. A bridge would create a
second compatibility protocol with its own identity and rollout obligations.
No current product requirement justifies that protocol.

## Decision details

- `protocol/wire.protocol_version` is `0x03`.
- All v3 encoders write that byte through the existing shared constant.
- Endpoint decoding rejects a v2 frame as
  `ProtocolError::UnsupportedVersion(version=b'\x02')` before message or EGW
  payload decoding.
- The relay drops complete frames whose version byte is not `0x03`. It does not
  allow old peers to form a parallel v2 session through a v3 room.
- Existing transparent handling of data shorter than the three-byte protocol
  header remains unchanged.
- Unknown message types inside a valid v3 frame retain their existing opaque
  relay behavior.
- Peer, relay, and browser artifacts must deploy together. There is no rolling
  mixed-version window.
- A reconnecting cached v2 client must reload the v3 application; it cannot
  resume its old room session.
- The public Tier 1 MoonBit signatures remain unchanged. The runtime value of
  the already-public `protocol_version : Byte` is intentionally different.

## Why a hard cut is acceptable

The collaboration product uses temporary rooms and does not promise durable
in-flight frame replay across deployments.

Room state and unfinished local UI state are not a wire migration mechanism.
Coordinating the browser and relay artifacts is cheaper and safer than
translating two incompatible CRDT identity models.

This decision does not authorize the EGW companion publication, Canopy's EGW
dependency bump, rooms, transport productization, or persistence. Those remain
under their existing gates.

## Compatibility and deployment

The version bump, frozen fixture updates, explicit v2 rejection tests, relay
version filtering, and documentation ship in one atomic source commit. A
deployment must publish the matching relay and browser artifacts together.

If deployment must be rolled back, roll back both artifacts to the same v2
commit. Do not run a v2 relay with v3 clients or a v3 relay with v2 clients.
Temporary rooms created on one protocol version are abandoned rather than
migrated.

## Consequences

- Mixed v2/v3 collaboration fails early and deliberately.
- Cached v2 clients may appear disconnected until reloaded.
- No bridge code, dual decoder, protocol negotiation, or legacy EGW identity
  enters `protocol/wire`, `sync_session`, or the EGW companion.
- Frozen byte fixtures change only at frame byte zero. Message tags, namespace
  tags, room subtypes, flags, and payload layouts remain unchanged.
- TypeScript and Cloudflare glue remain byte-opaque and require rebuild and
  coordinated deployment, not a second codec implementation.
- A future protocol change follows `protocol/wire/README.md` and requires a new
  compatibility statement.

## Validation

The cutover is accepted only when:

1. v2 complete frames produce `UnsupportedVersion(2)` at endpoint decode;
2. the relay drops v2 complete frames;
3. all v3 round-trip, frozen relay, routing, editor, session, and ephemeral
   tests pass;
4. `protocol/wire/pkg.generated.mbti` has no signature drift;
5. browser and relay artifacts build from the same commit; and
6. collaboration E2E passes with two v3 browser contexts.
