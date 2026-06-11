///| Re-exports for the sync surface extracted in redesign S2
/// (docs/plans/2026-06-11-s2-sync-session-transport-ws-extraction.md).
///
/// Downstream consumers keep their historical `@editor` spellings; canonical
/// ownership is `@transport_ws` (WebSocket binding, L3 adapter) and
/// `@sync_session` (transport-agnostic sync policy, L2). The editor import of
/// `transport_ws` is transitional: it exists because `SyncEditor`'s stable
/// surface (`ws_on_open`, the `ws` handle) still names `JsWebSocket`, and it
/// is removed when that surface is deprecated no earlier than one release
/// after S2.

///|
pub using @transport_ws { type JsWebSocket }

///|
pub using @sync_session { type SyncStatus, type SyncErrorReason }
