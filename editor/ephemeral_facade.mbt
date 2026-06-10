///| Facade re-exporting the ephemeral presence subsystem.
///
/// The ephemeral CRDT presence/awareness layer lives in the sibling package
/// `dowdiness/canopy/ephemeral` (zero dependencies on editor types). Editor
/// re-exports its public surface here so `@editor.EphemeralHub` etc. keep
/// compiling for the web FFI / examples consumers.

///|
/// Public surface — keeps `@editor.*` API stable for downstream consumers.
pub using @ephemeral {
  type EphemeralValue,
  type EphemeralStore,
  type EphemeralStoreEvent,
  type EphemeralEventTrigger,
  type EphemeralSubscription,
  type EphemeralHub,
  type EphemeralNamespace,
  type PeerCursor,
  type PeerCursorView,
  type PeerPresence,
  type PresenceStatus,
  type EditModeState,
  type DragState,
  type DragPosition,
  type EphemeralError,
  adjust_position,
}

///|
/// Generic byte-codec primitives consumed by editor's protocol layer
/// (sync_editor_ws.mbt; the wire codec itself moved to `protocol/wire` in
/// redesign S1). These are wire-format internals, not presence concepts, so
/// editor reads them directly from `@byte_codec` rather than reaching through
/// `@ephemeral`. Brought into local scope without re-exporting, so editor's
/// public API is unchanged.
using @byte_codec {type Reader}

///|
/// Presence namespace helpers consumed by editor's protocol layer. Brought
/// into local scope without re-exporting.
using @ephemeral {all_namespaces}
