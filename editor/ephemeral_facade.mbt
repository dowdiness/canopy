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
/// Internal cross-boundary helpers consumed by editor's protocol layer
/// (sync_protocol.mbt, sync_editor_ws.mbt). Brought into local scope without
/// re-exporting, so editor's public API is unchanged.
using @ephemeral {
  type Reader,
  read_string,
  write_string,
  namespace_to_byte,
  namespace_from_byte,
  all_namespaces,
}
