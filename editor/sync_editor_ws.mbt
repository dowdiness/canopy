// WebSocket lifecycle methods for SyncEditor.
//
// Since redesign S2 the sync state machine (status, recovery, retries,
// watchdog, dispatch) lives in @sync_session; these methods keep the stable
// SyncEditor surface and delegate, supplying document/ephemeral operations
// through SyncIo / SyncHost closure records built per call.

///|
/// Narrow IO record for the retry/send paths (no `Eq` bound required).
fn[T] SyncEditor::sync_io(self : SyncEditor[T]) -> @sync_session.SyncIo {
  @sync_session.SyncIo::SyncIo(send=data => self.ws_send(data), current_version=() => {
    self.get_version()
  })
}

///|
/// Full dispatch host for `on_message`.
fn[T : Eq] SyncEditor::sync_host(
  self : SyncEditor[T],
) -> @sync_session.SyncHost {
  @sync_session.SyncHost::SyncHost(
    io=self.sync_io(),
    apply_sync=msg => self.apply_sync(msg),
    export_all=() => self.export_all(),
    export_since=peer_version => self.export_since(peer_version),
    apply_ephemeral=(ns, payload) => self.hub.apply(ns, payload),
    encode_ephemeral=ns => self.hub.encode(ns),
    on_peer_leave=peer_id => self.hub.on_peer_leave(peer_id),
  )
}

///|
/// Called when WebSocket connects. Stores the ws reference.
/// Note: the relay server handles PeerJoined broadcast on connect —
/// the client does NOT send PeerJoined itself (that would duplicate it).
pub fn[T] SyncEditor::ws_on_open(
  self : SyncEditor[T],
  ws : JsWebSocket,
) -> Unit {
  self.ws = Some(ws)
  self.session.on_open()
}

///|
pub fn[T : Eq] SyncEditor::ws_on_message(
  self : SyncEditor[T],
  data : Bytes,
) -> Unit {
  self.session.on_message(data, self.sync_host())
}

///|
pub fn[T] SyncEditor::ws_on_close(self : SyncEditor[T]) -> Unit {
  self.ws = None
  self.session.on_close()
}

///|
pub fn[T] SyncEditor::ws_broadcast_edit(self : SyncEditor[T]) -> Unit {
  guard self.ws is Some(_) else { return }
  let crdt_msg = self.export_all() catch { _ => return }
  let json_str = crdt_msg.to_json_string()
  let buf = Buffer()
  buf.write_string_utf16le(json_str.view())
  self.ws_send(@wire.encode_message(CrdtOps(buf.to_bytes())))
}

///|
pub fn[T] SyncEditor::ws_broadcast_cursor(self : SyncEditor[T]) -> Unit {
  guard self.ws is Some(_) else { return }
  let cursor_data = self.hub.encode(Cursor)
  if cursor_data.length() > 0 {
    self.ws_send(@wire.encode_message(EphemeralUpdate(Cursor, cursor_data)))
  }
}
