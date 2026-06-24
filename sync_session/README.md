# sync_session — transport-agnostic sync policy

The sync state machine extracted from `editor/` in architecture-redesign S2
([plan](../docs/plans/2026-06-11-s2-sync-session-transport-ws-extraction.md)).
**Tier 1 library surface** per the
[library API boundary ADR](../docs/decisions/2026-06-11-library-api-boundary.md):
"unused in-tree" is not a deletion trigger here, and API changes follow the
deprecation idiom with at least one release cycle.

## What lives here

- `SyncStatus` / `SyncErrorReason` — observable connection/recovery state,
  emitted through `set_on_status_change` only on distinct transitions.
- `SyncSession` — recovery state machine and message dispatch: one recovery
  at a time, three retries after the initial SyncRequest (exhaustion is
  checked *before* advancing, so retries 0–2 each send and 3 surfaces
  `Error(Exhausted)`), deferred-message buffering capped at 32 with
  drop-oldest, stale request-id / watchdog-epoch discard, 1 MB SyncResponse
  cap on the responder side.
- `SyncTransport` — the transport seam (trait); `InMemoryRoom` /
  `InMemoryTransport` — the in-process reference implementation used by
  tests and local collaboration probes.

## What deliberately does not live here

Document state, parsing, and presence. The owning editor supplies those
per call through two closure records:

- `SyncIo` — `send` + `current_version`; enough for the retry/send paths
  (`on_watchdog_fire`). Kept narrow because the editor's watchdog surface
  has no `Eq` bound and cannot build the full host.
- `SyncHost` — `SyncIo` plus `apply_sync` / `export_all` / `export_since`
  and ephemeral routing closures; consumed only by `on_message`.

This package imports `protocol/wire` (frame codec, namespace enumeration)
and the egw text CRDT types only — never `editor`, `ephemeral`, or a
concrete transport. WebSocket binding lives in `transport_ws/` (Tier 3,
L3 adapter); `SyncEditor` keeps its stable surface and delegates here.
