// SyncEditor: Unified facade composing TextDoc + UndoManager + incremental parser.
// Parsing stays edit-aware via ImperativeParser; projection views are memo-derived.

///|
pub struct SyncEditor {
  priv doc : @text.TextDoc
  priv undo : @undo.UndoManager
  priv parser : @loom.ImperativeParser[@ast.Term]
  priv parser_rt : @incr.Runtime
  priv source_text : @incr.Signal[String]
  priv syntax_tree : @incr.Signal[@seam.SyntaxNode?]
  priv mut cursor : Int
  priv prev_flat_proj : Ref[@proj.FlatProj?]
  priv prev_syntax_root : Ref[@seam.SyntaxNode?]
  priv proj_memo : @incr.Memo[@proj.FlatProj?]
  priv cached_proj_node : @incr.Memo[@proj.ProjNode?]
  priv registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode]]
  priv source_map_memo : @incr.Memo[@proj.SourceMap]
  priv next_node_id : Ref[Int]
  priv ephemeral : EphemeralStore
  priv cursor_view : PeerCursorView
  priv peer_id : String
  priv ephemeral_peer_id : String
}

///|
pub fn SyncEditor::new(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  ephemeral_timeout_ms? : UInt64 = 60000UL,
) -> SyncEditor {
  let parser = @loom.new_imperative_parser("", @parser.lambda_grammar)
  let parser_rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(parser_rt, "", label="editor_source_text")
  let syntax_tree = @incr.Signal::new(
    parser_rt,
    None,
    label="editor_syntax_tree",
  )
  let prev_flat_proj : Ref[@proj.FlatProj?] = Ref::new(None)
  let prev_syntax_root : Ref[@seam.SyntaxNode?] = Ref::new(None)
  let next_node_id : Ref[Int] = Ref::new(0)
  let (proj_memo, cached_proj_node, registry_memo, source_map_memo) = build_projection_memos(
    parser_rt, source_text, syntax_tree, prev_flat_proj, prev_syntax_root, next_node_id,
  )
  let ephemeral = EphemeralStore::new(ephemeral_timeout_ms)
  let cursor_view = PeerCursorView::new()
  let ephemeral_peer_id = to_wire_peer_id(agent_id)
  // Subscribe to ephemeral store events to update cursor_view (skip local peer)
  ignore(
    ephemeral.subscribe(fn(event) {
      for key in event.added() {
        if key == ephemeral_peer_id {
          continue
        }
        match ephemeral.get(key) {
          Some(value) => cursor_view.apply_raw_update(key, value)
          None => ()
        }
      }
      for key in event.updated() {
        if key == ephemeral_peer_id {
          continue
        }
        match ephemeral.get(key) {
          Some(value) => cursor_view.apply_raw_update(key, value)
          None => ()
        }
      }
      for key in event.removed() {
        if key == ephemeral_peer_id {
          continue
        }
        cursor_view.remove(key)
      }
      true
    }),
  )
  {
    doc: @text.TextDoc::new(agent_id),
    undo: @undo.UndoManager::new(agent_id, capture_timeout_ms~),
    parser,
    parser_rt,
    source_text,
    syntax_tree,
    cursor: 0,
    prev_flat_proj,
    prev_syntax_root,
    proj_memo,
    cached_proj_node,
    registry_memo,
    source_map_memo,
    next_node_id,
    ephemeral,
    cursor_view,
    peer_id: agent_id,
    ephemeral_peer_id,
  }
}

// --- Ephemeral presence methods ---

///|
pub fn SyncEditor::set_local_presence(
  self : SyncEditor,
  name : String,
  color : String,
  selection? : (Int, Int)? = None,
) -> Unit {
  let map : Map[String, EphemeralValue] = {}
  map["peer_id"] = EphemeralValue::String(self.peer_id)
  map["cursor"] = EphemeralValue::I64(self.cursor.to_int64())
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
  // ephemeral_peer_id is always a valid numeric string from to_wire_peer_id,
  // so set() cannot fail; catch is defensive only.
  self.ephemeral.set(self.ephemeral_peer_id, EphemeralValue::Map(map)) catch {
    _ => ()
  }
}

///|
pub fn SyncEditor::delete_local_presence(self : SyncEditor) -> Unit {
  // ephemeral_peer_id is always valid; see set_local_presence.
  self.ephemeral.delete(self.ephemeral_peer_id) catch {
    _ => ()
  }
}

///|
/// Best-effort application of remote ephemeral data. Malformed wire data from
/// a remote peer is silently dropped to avoid crashing the local editor.
pub fn SyncEditor::apply_ephemeral(self : SyncEditor, data : Bytes) -> Unit {
  self.ephemeral.apply(data) catch {
    _ => ()
  }
}

///|
pub fn SyncEditor::encode_ephemeral_all(self : SyncEditor) -> Bytes {
  self.ephemeral.encode_all()
}

///|
pub fn SyncEditor::remove_ephemeral_outdated(self : SyncEditor) -> Unit {
  self.ephemeral.remove_outdated()
}

///|
pub fn SyncEditor::get_peer_cursors(
  self : SyncEditor,
) -> Map[String, PeerCursor] {
  self.cursor_view.all_cursors()
}

///|
pub fn SyncEditor::get_peer_id(self : SyncEditor) -> String {
  self.peer_id
}

///|
pub fn SyncEditor::subscribe_ephemeral_local(
  self : SyncEditor,
  callback : (Bytes) -> Bool,
) -> EphemeralSubscription {
  self.ephemeral.subscribe_local_updates(callback)
}
