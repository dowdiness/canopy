# protocol/wire — sync wire protocol

The single definition of canopy's binary sync wire format. It is a **Tier 1
library surface** under the
[library API boundary ADR](../../docs/decisions/2026-06-11-library-api-boundary.md):
"unused in-tree" is not a deletion trigger here, and API changes follow the
deprecation idiom with at least one release cycle.

Extracted from `editor/sync_protocol.mbt` in architecture-redesign S1
([archived plan](../../docs/archive/completed-phases/2026-06-11-s1-protocol-wire-extraction.md)). `editor`,
`relay`, and `ephemeral` consume this package exclusively; `editor` retains
deprecated forwarding shims for the historical `@editor.*` spellings. This
package imports substrate only (`byte_codec`, core) — never editor, ephemeral,
relay, or language packages.

## Frame layout

Every sync frame is:

```text
[version: u8][msg_type: u8][flags: u8][payload…]
```

- `version` — `protocol_version` (currently `0x02`). A frame with any other
  version byte is rejected (`ProtocolError::UnsupportedVersion`).
- `msg_type` — one of:

  | byte | message | payload |
  |---|---|---|
  | `0x01` | `CrdtOps` | opaque CRDT op bytes |
  | `0x02` | `EphemeralUpdate` | `[namespace: u8][bytes]` |
  | `0x03` | `SyncRequest` | opaque, or peer-addressed `[target][request_id][version_json]` (length-prefixed strings) |
  | `0x04` | `SyncResponse` | opaque, or peer-addressed `[target][request_id][sync_json]` |
  | `0x05` | room control | `[sub_type: u8][peer_id]` — `sub_join` (`0x01`) / `sub_leave` (`0x02`) |
  | `0x06` | `RelayedCrdtOps` | `[sender][payload]` |

- `flags` — reserved, always `flags_none` (`0x00`).

Strings are length-prefixed UTF-16LE via `byte_codec`'s `write_string` /
`read_string` (uvarint byte length, then bytes).

## Frame-namespace API (ephemeral payloads)

`EphemeralNamespace` (`Cursor` / `EditMode` / `Drag` / `Presence`) and its wire
mapping (`namespace_to_byte`, `namespace_from_byte`, `all_namespaces`) live
here: the namespace byte is part of the `EphemeralUpdate` frame, so the mapping
is wire format, not presence model. The `ephemeral` package re-exports the API
for its consumers; presence *values* (the namespace payload codec) remain
ephemeral's own concern.

## Version-bump protocol

`protocol_version` changes are never silent. A bump must, **in the same
commit**:

1. change the `protocol_version` byte here (the only definition);
2. update the frozen wire fixtures that pin the on-wire bytes —
   `relay/wire_frozen_wbtest.mbt` and, if value layouts changed,
   `ephemeral/wire_format_fixture_wbtest.mbt` — with hand-derived literals,
   never by re-running the encoder;
3. state the compatibility story for in-flight peers (old-version frames are
   dropped by `decode_message_result`, so a bump is a hard cut for live
   collaboration sessions);
4. exercise editor + relay + ephemeral consumers (`moon test` at workspace
   root covers all three) and the collaboration E2E suites.

Adding a message type is backward-tolerant (unknown types decode to
`ProtocolError::UnknownMessageType` and are dropped) and does not require a
version bump; changing the layout of an existing type does.
