// SyncEditor: Unified facade composing TextState + UndoManager + incremental parser.
// Parsing stays edit-aware via ImperativeParser; projection views are memo-derived.

///|
/// Default watchdog timeout in milliseconds.
const DEFAULT_WATCHDOG_MS : Int = 5000

///|
pub struct SyncEditor[T] {
  priv doc : @text.TextState
  priv undo : @undo.UndoManager
  priv parser : @loom.ImperativeParser[T]
  priv parser_rt : @incr.Runtime
  priv source_text : @incr.Signal[String]
  priv syntax_tree : @incr.Signal[@seam.SyntaxNode?]
  priv mut cursor : Int
  priv cached_proj_node : @incr.Memo[@core.ProjNode[T]?]
  priv registry_memo : @incr.Memo[Map[@core.NodeId, @core.ProjNode[T]]]
  priv source_map_memo : @incr.Memo[@core.SourceMap]
  priv capabilities : LanguageCapabilities[T]
  priv hub : EphemeralHub
  priv cursor_view : PeerCursorView
  priv peer_id : String
  priv mut ws : JsWebSocket?
  priv mut recovery : RecoveryContext?
  priv mut recovery_epoch : Int
  priv mut projection_dirty : Bool
  priv mut status : SyncStatus
  priv mut on_status_change : ((SyncStatus) -> Unit)?
  priv mut watchdog_scheduler : ((Int, Int) -> Unit)?
  priv mut watchdog_timeout_ms : Int
}

///|
/// Generic constructor for all languages.
/// The build_memos callback returns 3 memos (ProjNode, registry, SourceMap).
pub fn[T] SyncEditor::new_generic(
  agent_id : String,
  make_parser : (String) -> @loom.ImperativeParser[T],
  build_memos : (
    @incr.Runtime,
    @incr.Signal[String],
    @incr.Signal[@seam.SyntaxNode?],
    @loom.ImperativeParser[T],
  ) -> (
    @incr.Memo[@core.ProjNode[T]?],
    @incr.Memo[Map[@core.NodeId, @core.ProjNode[T]]],
    @incr.Memo[@core.SourceMap],
  ),
  capture_timeout_ms? : Int = 500,
  capabilities? : LanguageCapabilities[T] = LanguageCapabilities::default(),
) -> SyncEditor[T] {
  let parser = make_parser("")
  let parser_rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(parser_rt, "", label="editor_source_text")
  let syntax_tree = @incr.Signal::new(
    parser_rt,
    None,
    label="editor_syntax_tree",
  )
  let (cached_proj_node, registry_memo, source_map_memo) = build_memos(
    parser_rt, source_text, syntax_tree, parser,
  )
  let (hub, cursor_view) = setup_hub_and_cursor(agent_id)
  {
    doc: @text.TextState::new(agent_id),
    undo: @undo.UndoManager::new(agent_id, capture_timeout_ms~),
    parser,
    parser_rt,
    source_text,
    syntax_tree,
    cursor: 0,
    cached_proj_node,
    registry_memo,
    source_map_memo,
    capabilities,
    hub,
    cursor_view,
    peer_id: agent_id,
    ws: None,
    recovery: None,
    recovery_epoch: 0,
    projection_dirty: false,
    status: SyncStatus::Disconnected,
    on_status_change: None,
    watchdog_scheduler: None,
    watchdog_timeout_ms: DEFAULT_WATCHDOG_MS,
  }
}

// --- Hub and cursor setup ---

///|
/// Create an EphemeralHub and PeerCursorView, wiring up the cursor store
/// subscription so remote peer cursors are tracked automatically.
fn setup_hub_and_cursor(agent_id : String) -> (EphemeralHub, PeerCursorView) {
  let hub = EphemeralHub::new(agent_id)
  let cursor_view = PeerCursorView::new()
  let wire_peer_id = hub.wire_peer_id
  let cursor_store = hub.get_store(Cursor)
  ignore(
    cursor_store.subscribe(fn(event) {
      for key in event.added() {
        if key == wire_peer_id {
          continue
        }
        match cursor_store.get(key) {
          Some(value) => cursor_view.apply_raw_update(key, value)
          None => ()
        }
      }
      for key in event.updated() {
        if key == wire_peer_id {
          continue
        }
        match cursor_store.get(key) {
          Some(value) => cursor_view.apply_raw_update(key, value)
          None => ()
        }
      }
      for key in event.removed() {
        if key == wire_peer_id {
          continue
        }
        cursor_view.remove(key)
      }
      true
    }),
  )
  (hub, cursor_view)
}

// --- Ephemeral presence methods ---

///|
pub fn[T] SyncEditor::set_local_presence(
  self : SyncEditor[T],
  name : String,
  color : String,
  selection? : (Int, Int)? = None,
) -> Unit {
  // Write cursor data to cursor store (with name/color for cursor_view compat)
  let map : Map[String, EphemeralValue] = {}
  map["peer_id"] = EphemeralValue::String(self.peer_id)
  // Use selection start as cursor position when provided (CM6 passes
  // the actual caret position via sel_start, not self.cursor).
  let cursor_pos = match selection {
    Some((start, _)) => start
    None => self.cursor
  }
  map["cursor"] = EphemeralValue::I64(cursor_pos.to_int64())
  map["name"] = EphemeralValue::String(name)
  map["color"] = EphemeralValue::String(color)
  match selection {
    Some((start, end)) =>
      map["selection"] = EphemeralValue::List([
        EphemeralValue::I64(start.to_int64()),
        EphemeralValue::I64(end.to_int64()),
      ])
    None => ()
  }
  self.hub
  .get_store(Cursor)
  .set(self.hub.wire_peer_id, EphemeralValue::Map(map)) catch {
    _ => ()
  }
  // Also write to presence store for get_online_peers()
  self.hub.set_presence(name, color, Active)
}

///|
pub fn[T] SyncEditor::delete_local_presence(self : SyncEditor[T]) -> Unit {
  self.hub.on_peer_leave(self.peer_id)
}

///|
/// Best-effort application of remote ephemeral data. Malformed wire data from
/// a remote peer is silently dropped to avoid crashing the local editor.
pub fn[T] SyncEditor::apply_ephemeral(
  self : SyncEditor[T],
  data : Bytes,
) -> Unit {
  self.hub.apply_all(data)
}

///|
pub fn[T] SyncEditor::encode_ephemeral_all(self : SyncEditor[T]) -> Bytes {
  self.hub.encode_all()
}

///|
pub fn[T] SyncEditor::remove_ephemeral_outdated(self : SyncEditor[T]) -> Unit {
  self.hub.remove_outdated()
}

///|
pub fn[T] SyncEditor::get_peer_cursors(
  self : SyncEditor[T],
) -> Map[String, PeerCursor] {
  self.cursor_view.all_cursors()
}

///|
pub fn[T] SyncEditor::get_peer_id(self : SyncEditor[T]) -> String {
  self.peer_id
}

///|
pub fn[T] SyncEditor::get_hub(self : SyncEditor[T]) -> EphemeralHub {
  self.hub
}

///|
pub fn[T] SyncEditor::ws_send(self : SyncEditor[T], data : Bytes) -> Unit {
  match self.ws {
    Some(ws) => ws.send_bytes(data)
    None => ()
  }
}

///|
pub fn[T] SyncEditor::subscribe_ephemeral_local(
  self : SyncEditor[T],
  callback : (Bytes) -> Bool,
) -> EphemeralSubscription {
  self.hub.get_store(Cursor).subscribe_local_updates(callback)
}

// --- SyncStatus API ---

///|
/// Get the current sync status.
pub fn[T] SyncEditor::get_sync_status(self : SyncEditor[T]) -> SyncStatus {
  self.status
}

///|
/// Register a callback that fires on every distinct status transition.
/// Setting again replaces the previous callback. Pass `None` to disable.
pub fn[T] SyncEditor::set_on_status_change(
  self : SyncEditor[T],
  callback : ((SyncStatus) -> Unit)?,
) -> Unit {
  self.on_status_change = callback
}

///|
/// Register a watchdog scheduler. The editor calls
/// `scheduler(request_id, timeout_ms)` after each SyncRequest send.
/// `timeout_ms` is the current value of `watchdog_timeout_ms` at send time,
/// so calling `set_watchdog_timeout` takes effect on the next send.
/// The scheduler should fire `on_watchdog_fire(request_id)` after
/// `timeout_ms` milliseconds. Setting again replaces the previous scheduler.
/// Pass `None` to disable.
pub fn[T] SyncEditor::set_watchdog_scheduler(
  self : SyncEditor[T],
  scheduler : ((Int, Int) -> Unit)?,
) -> Unit {
  self.watchdog_scheduler = scheduler
}

///|
/// Set the watchdog timeout in milliseconds. Default is 5000ms.
pub fn[T] SyncEditor::set_watchdog_timeout(
  self : SyncEditor[T],
  ms : Int,
) -> Unit {
  self.watchdog_timeout_ms = ms
}

///|
/// Called by the FFI layer when the watchdog timer fires.
/// The `request_id` is compared against the current recovery epoch to
/// detect and discard stale firings (e.g. response already arrived).
pub fn[T] SyncEditor::on_watchdog_fire(
  self : SyncEditor[T],
  request_id : Int,
) -> Unit {
  guard self.recovery is Some(ctx) else { return }
  guard ctx.matches_request_id(request_id.to_string()) else { return }
  self.handle_recovery_retry()
}

///|
/// Internal: transition to a new status, emitting callback only on change.
fn[T] SyncEditor::set_status(
  self : SyncEditor[T],
  new_status : SyncStatus,
) -> Unit {
  if self.status == new_status {
    return
  }
  self.status = new_status
  match self.on_status_change {
    Some(cb) => cb(new_status)
    None => ()
  }
}
