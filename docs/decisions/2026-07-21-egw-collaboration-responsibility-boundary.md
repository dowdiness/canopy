# EGW collaboration responsibility boundary

**Date:** 2026-07-21

**Status:** Accepted target architecture; protocol v3 cutover, EGW peer-sync
publication, and EGW v0.5 dependency convergence completed (2026-07-23)

**Related:**

- [Library API boundary](2026-06-11-library-api-boundary.md)
- [Archived EGW companion and Canopy migration](../archive/2026-07-22-egw-companion-canopy-migration.md)
- [Archived peer-sync contract spike](../archive/2026-07-22-egw-peer-sync-contract-spike.md)
- [Typed spreadsheet EGW register and projection boundary](../../loom/incr/docs/decisions/2026-07-20-typed-spreadsheet-egw-register-projection.md)
- [Protocol v3 hard cutover](2026-07-22-protocol-v3-hard-cutover.md)

**Reader:** Maintainers designing or reviewing CRDT synchronization,
collaboration sessions, transport providers, or collaborative applications
across EGW, Canopy, and their submodules.

**Decision:** Separate collaboration into five layers according to their reasons
to change: EGW core, an EGW-versioned peer-sync companion, a reusable
payload-opaque collaboration runtime, infrastructure providers, and application
policy.

**Keep until:** Permanently. ADRs are durable and are superseded rather than
deleted.

**Disposition:** Supersede this record if implementation evidence from both text
and container drivers shows that the peer-sync or runtime boundary cannot remain
independent of the adjacent layers.

## Context

The current code demonstrates all required collaboration capabilities, but its
package placement is not the target architecture:

- EGW owns façade-specific versions, strict JSON sync messages, canonical bytes,
  causal validation, and document-bound export/apply operations. It deliberately
  leaves transport and product policy to consumers.
- Canopy's current `sync_session` is described as transport-agnostic while its
  host contract remains tied to the EGW text façade.
- Canopy's current wire protocol combines CRDT data, peer control, and
  application-defined ephemeral namespaces in one frame family.
- The relay is mostly an infrastructure provider, but it also recognizes the
  current Canopy frame types for broadcast and directed routing.
- The typed-spreadsheet container adapter is a second real driver. Reimplementing
  peer bootstrap and causal recovery in that application would repeat logic
  already needed by the text driver.

Implementation evidence:

- [EGW network boundary](../../event-graph-walker/docs/NETWORK_SYNC.md)
- [Canopy sync session](../../sync_session/README.md)
- [Wire protocol](../../protocol/wire/README.md)
- [Relay](../../relay/README.md)

These sources and older ADRs describe the current system. They do not prove
that its package boundaries are ideal.

## Boundary rule

Ownership follows the event that forces a component to change:

| Reason to change | Owning layer |
|---|---|
| CRDT operations, causal rules, façade versions, sync-message formats, or document-local pending replay change | EGW core |
| EGW apply reports, per-peer version exchange, recovery commands, or CRDT-derived retry classification change | EGW peer-sync companion |
| Generic connection/session transitions, envelopes, transport backpressure, watchdog scheduling, or transport capabilities change | Collaboration runtime |
| Network, hosting, room routing, access control, reconnect backoff, or persistence changes | Infrastructure provider |
| Document identity, share/join behavior, drafts, selection, projection, reset, diagnostics, or presence meaning changes | Application |

A current package name or API tier is not an ownership argument by itself.

## Decision

### A. EGW core

EGW core owns document-level CRDT synchronization and causal validation
semantics. It remains the sole owner of document-local pending-operation
storage and replay.

It does not own peers, rooms, presence, connection sessions, physical
transports, persistence policy, projection, or UI state.

### B. EGW peer-sync companion

A companion package versioned with EGW owns the protocol state that must track
EGW semantics:

- adapters for the text, tree, and container façades;
- per-peer protocol state and version exchange;
- interpretation of EGW apply reports and failures;
- bootstrap and causal-gap recovery commands; and
- retry classification whose meaning comes from EGW.

The companion is a deterministic core. It accepts peer-sync events and returns
next state plus commands.

It does not retain or replay pending CRDT operations; valid sync messages reach
EGW core, whose document-local queue owns that work. The companion also does not
open sockets, choose rooms, schedule network reconnects, carry presence, or
depend on `incr` or application schemas.

### C. Reusable payload-opaque collaboration runtime

A separately reusable runtime owns generic collaboration-session mechanics:

- a pure connection/session reducer;
- generic control and data envelopes;
- bounded transport-backpressure buffering and stale-envelope rejection;
- watchdog scheduling and observable status policy; and
- transport capability interfaces.

This runtime treats document versions and CRDT messages as opaque payloads. It
does not delay or reorder a CRDT payload based on causal dependencies; layers A
and B own that interpretation.

The runtime may be incubated in Canopy, but its target boundary is independently
reusable. It must not depend on Canopy editor state, an EGW façade, or the
spreadsheet adapter.

### D. Infrastructure providers

Providers form the imperative shell around the runtime. They own WebSocket or
WebRTC integration, Cloudflare Durable Objects, peer-ID issuance, room
membership and routing, authorization, reconnect backoff, and optional storage.
Network and storage remain separate capabilities even when one deployment
implements both.

Providers may inspect generic envelope metadata needed for target or broadcast
routing. The enclosed CRDT payload and application schema remain opaque; a
provider does not decode CRDT operations or decide application reset semantics.

### E. Application policy

Canopy editors and other applications own collaborative product behavior:

- logical document and room selection;
- share and join UX;
- committed-state projection;
- local drafts, selection, focus, and viewport state;
- reset or document-replacement semantics;
- diagnostics and trace presentation; and
- the meaning and rendering of presence.

The application supplies identities and capabilities to lower layers. It does
not duplicate CRDT merge, peer-sync, or transport-provider logic.

## Cross-layer distinctions

- Layer A stores and replays document-local operations whose causal predecessors
  are missing.
- Layer B interprets EGW reports and failures, then decides whether to request
  data from a peer. Layer C executes generic timer and send capabilities;
  reconnecting a failed WebSocket belongs to layer D.
- Layer C owns stable connection/session transitions and transport backpressure.
  Layer E decides how those states are explained and presented.
- Presence may use a layer-C envelope and a layer-D transport, but its schema,
  expiry, and product meaning belong to layer E. Presence never enters the
  committed EGW document by default.
- Logical document identity belongs to the application. Lower layers may route
  it only as an opaque key.
- Reset is application-level document replacement, not a room-control shortcut
  or CRDT transport operation.

## Relationship to earlier decisions

This ADR partially supersedes only the target implementation ownership assigned
to sync wire and session policy in the
[2026-06-11 library API boundary ADR](2026-06-11-library-api-boundary.md).
The current Tier 1 status and compatibility obligations of `protocol/wire`,
`sync_session`, and `ephemeral` remain active until a later ADR and migration
explicitly supersede each surface.

A new EGW companion follows EGW's own versioning policy. Any separately
published collaboration runtime must receive an explicit stability
classification rather than inheriting one by implication.

The typed-spreadsheet ADR continues to own register encoding, authoritative
projection, draft preservation, and diagnostics. This ADR owns the target
placement of peer-sync, collaboration runtime, and provider responsibilities.

## Rejected alternatives

### Keep all synchronization policy in Canopy

Rejected because non-Canopy text, tree, and container consumers would need to
reimplement EGW-specific bootstrap and causal recovery. It would also preserve
the current accidental text-façade dependency in the nominally reusable
session layer.

### Move all collaboration code into EGW

Rejected because rooms, access control, WebSocket lifecycle, persistence,
presence, and UI policy change for deployment or product reasons rather than
CRDT reasons. Moving them would couple EGW releases to infrastructure and
application churn.

### Preserve current package placement because it is already documented

Rejected because an ADR records a reasoned decision; it does not make that
boundary permanently ideal. New evidence from the container driver is allowed
to supersede a narrower historical assignment.

### Introduce a generic `egw_incr` bridge

Rejected because synchronization and reactive projection are separate
responsibilities. The typed-spreadsheet adapter remains application-specific
unless multiple projection drivers establish a reusable contract.

## Consequences

- Some current Canopy Tier 1 APIs are compatibility surfaces rather than target
  ownership boundaries.
- EGW may gain a peer-sync companion, but its core remains free of rooms,
  presence, and physical transports.
- The collaboration runtime must become payload-opaque before it can serve both
  text and container drivers.
- Existing consumers require deprecation shims or adapters during migration.
- Published dependency convergence must be verified without a workspace
  override before a compatibility release is considered complete.
- The current binary relay and the separate JSON-history relay must not be
  treated as one protocol without an explicit convergence or retirement plan.
- Functional-core/imperative-shell boundaries apply at every layer: protocol
  and session decisions are deterministic; scheduling and I/O stay in
  providers and application shells.

## Spike evidence

The 2026-07-22 private EGW 0.4 spike established one deterministic
peer-sync event/decision contract for real text and container drivers. Its
payload-free state covers admission, version exchange, incremental send,
full-sync recovery, bounded retry, disconnect/reconnect, peer departure, and
terminal failures.

Both façades produced identical decision traces. Their EGW document state
remained the sole owner of causal pending operations.

The private test package has an empty generated interface. EGW validation passed
15/15 targeted and 681/681 full tests with deny-warn checks.

Independent MoonBit review passed. Independent `qwen3.8-max-preview` review
returned GO WITH CONDITIONS and found no spike defect after multi-peer send
fan-out was pinned.

The contract result stood with one original condition: consumer compatibility
still had to be proven across EGW, Loom, Canopy, and Tier 1 `sync_session`.
That condition was resolved by the shipped migration evidence below.

A follow-up fixture exchange confirmed that EGW 0.3 and 0.4 are wire
incompatible in both directions. Each release accepted and applied its own
version, full-sync, and incremental JSON, but rejected every corresponding
cross-version fixture.

Canopy protocol-v2 outer frames carried both payload families without
corruption; the incompatibility is the enclosed EGW identity and JSON schema.

The protocol v3 ADR resolves this gate with a coordinated hard cut. Endpoint
decoders and the relay reject v2 complete frames, and no bridge is implied by
the companion contract.

## Shipped evidence

The EGW v0.5 release publishes `peer_sync`, `peer_sync/text`, and
`peer_sync/container`. The companion state remains payload-free, and EGW core
remains the sole owner of causal pending-operation storage and replay.

Loom and Canopy migrated to that published release through the required
bottom-up sequence. Clean-resolution checks passed without a workspace
override, while generated interfaces for Tier 1 `protocol/wire`,
`sync_session`, and `ephemeral` remained unchanged.

Protocol v3 shipped as the required hard cut. Endpoint decoders and the relay
reject complete v2 frames; no dual decoder, identity bridge, or mixed-version
room mode was retained.

The payload-opaque runtime, infrastructure provider, and two-browser product
slice remain deferred. Their ownership continues to follow Layers C–E of this
ADR.

## Migration gates

The compatibility release satisfied gates 1–4. Gates 5–9 remain constraints
for the deferred runtime and provider product work:

1. Pin text and container sync fixtures, pending-operation behavior, and failure
   semantics against their owning EGW versions.
2. Demonstrate one peer-sync capability contract with both real drivers while
   proving that EGW core remains the only causal pending-operation queue.
3. Locate only EGW-derived handshake and recovery decisions in the versioned
   companion; keep transport lifecycle and backpressure outside it.
4. Commit and push the EGW companion in its repository, publish its release,
   and only then update Canopy to that published dependency. Verify resolution
   without a workspace override.
5. Introduce a payload-opaque collaboration reducer while preserving the
   current Tier 1 `protocol/wire`, `sync_session`, and `ephemeral` surfaces
   through compatibility adapters for at least one Canopy release.
6. Separate generic control/data framing from Canopy-specific ephemeral
   schemas, with an explicit wire-compatibility decision.
7. Restrict providers to generic routing metadata and keep CRDT payloads opaque.
8. Validate provider routing, duplicate and out-of-order delivery, reconnect,
   and two-browser convergence without synchronizing local drafts or selection.
9. Run cross-repository CI and inspect generated interfaces before a separate
   decision removes compatibility paths.

## Non-goals

- Implementing or moving code in this documentation change.
- Moving room, presence, WebSocket, Cloudflare, or persistence policy into EGW.
- Choosing a persistent-room product model.
- Synchronizing selection, focus, or uncommitted drafts.
- Proposing a public EGW API before the text and container drivers establish
  common semantics and compatibility evidence.
