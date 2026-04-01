// SyncEditor: Unified facade composing TextState + UndoManager + incremental parser.
// Parsing stays edit-aware via ImperativeParser; projection views are memo-derived.

///|
pub struct SyncEditor[T] {
  priv doc : @text.TextState
  priv undo : @undo.UndoManager
  priv parser : @loom.ImperativeParser[T]
  priv parser_rt : @incr.Runtime
  priv source_text : @incr.Signal[String]
  priv syntax_tree : @incr.Signal[@seam.SyntaxNode?]
  priv mut cursor : Int
  priv proj_memo : @incr.Memo[@lambda.VersionedFlatProj]?
  priv cached_proj_node : @incr.Memo[@proj.ProjNode[T]?]
  priv registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode[T]]]
  priv source_map_memo : @incr.Memo[@proj.SourceMap]
  priv hub : EphemeralHub
  priv cursor_view : PeerCursorView
  priv peer_id : String
  priv mut ws : JsWebSocket?
  priv mut recovery : RecoveryContext?
  priv mut recovery_epoch : Int
  priv mut projection_dirty : Bool
}

///|
fn[T] SyncEditor::new(
  agent_id : String,
  make_parser : (String) -> @loom.ImperativeParser[T],
  build_memos : (
    @incr.Runtime,
    @incr.Signal[String],
    @incr.Signal[@seam.SyntaxNode?],
    @loom.ImperativeParser[T],
  ) -> (
    @incr.Memo[@lambda.VersionedFlatProj],
    @incr.Memo[@proj.ProjNode[T]?],
    @incr.Memo[Map[@proj.NodeId, @proj.ProjNode[T]]],
    @incr.Memo[@proj.SourceMap],
  ),
  capture_timeout_ms? : Int = 500,
) -> SyncEditor[T] {
  let parser = make_parser("")
  let parser_rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(parser_rt, "", label="editor_source_text")
  let syntax_tree = @incr.Signal::new(
    parser_rt,
    None,
    label="editor_syntax_tree",
  )
  let (proj_memo, cached_proj_node, registry_memo, source_map_memo) = build_memos(
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
    proj_memo: Some(proj_memo),
    cached_proj_node,
    registry_memo,
    source_map_memo,
    hub,
    cursor_view,
    peer_id: agent_id,
    ws: None,
    recovery: None,
    recovery_epoch: 0,
    projection_dirty: false,
  }
}

///|
/// Convenience constructor for lambda calculus — creates a SyncEditor[@ast.Term].
pub fn SyncEditor::new_lambda(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> SyncEditor[@ast.Term] {
  SyncEditor::new(
    agent_id,
    fn(s) { @loom.new_imperative_parser(s, @parser.lambda_grammar) },
    build_lambda_projection_memos,
    capture_timeout_ms~,
  )
}

///|
/// Generic constructor for languages without FlatProj.
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
    @incr.Memo[@proj.ProjNode[T]?],
    @incr.Memo[Map[@proj.NodeId, @proj.ProjNode[T]]],
    @incr.Memo[@proj.SourceMap],
  ),
  capture_timeout_ms? : Int = 500,
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
    proj_memo: None,
    cached_proj_node,
    registry_memo,
    source_map_memo,
    hub,
    cursor_view,
    peer_id: agent_id,
    ws: None,
    recovery: None,
    recovery_epoch: 0,
    projection_dirty: false,
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
