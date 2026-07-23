// SyncEditor: TextState + UndoManager + reactive Parser.
// Projection views subscribe to the parser's reactive memos.

///|
pub struct SyncEditor[T] {
  priv doc : @text.TextState
  priv undo : @undo.UndoManager
  priv parser : @loom.Parser[T]
  priv mut cursor : Int
  priv cached_proj_node : @incr.Derived[@core.ProjNode[T]?]
  priv registry_memo : @incr.Derived[Map[@core.NodeId, @core.ProjNode[T]]]
  priv source_map_memo : @incr.Derived[@core.SourceMap]
  priv capabilities : LanguageCapabilities[T]
  priv hub : EphemeralHub
  priv cursor_view : PeerCursorView
  priv peer_id : String
  priv mut ws : JsWebSocket?
  priv session : @sync_session.SyncSession
  priv mut projection_dirty : Bool
  // Structural-edit identity hints accumulated since the last reconcile.
  // Structural edits push their IdentityTransform here; raw-text edits push
  // Opaque (taint) when non-empty. Consumed and cleared once per reparse by
  // the reconcile_node closure in build_lambda_projection_memos.
  // T4: cleared exactly once per reconcile pass (never stale).
  // T1 invariant: hints reference only prev-tree NodeIds valid at push time.
  priv pending_transforms : Ref[Array[@core.IdentityTransform]]
  // Process-local construction identity. Two `SyncEditor` instances
  // constructed separately have different identities; the same instance
  // always returns the same value. Used as a cache key in history-view
  // memoization (see `editor/sync_editor_history.mbt`).
  priv identity : Int
}

///|
/// Generic constructor for all languages.
/// `make_parser` builds a `@loom.Parser[T]` from an initial source string.
/// `build_memos` receives the parser handle and returns the 3 projection memos
/// (ProjNode, registry, SourceMap) it wants SyncEditor to own.
pub fn[T] SyncEditor::new_generic(
  agent_id : String,
  make_parser : (String, @incr.Runtime?) -> @loom.Parser[T],
  build_memos : (@loom.Parser[T]) -> (
    @incr.Derived[@core.ProjNode[T]?],
    @incr.Derived[Map[@core.NodeId, @core.ProjNode[T]]],
    @incr.Derived[@core.SourceMap],
  ),
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
  capabilities? : LanguageCapabilities[T] = LanguageCapabilities::default(),
  // Optional shared Ref for the structural-edit hint channel. The caller
  // (e.g. new_lambda_editor) creates a `Ref([])`, passes it here AND into
  // build_memos so the reconcile_node closure can consume+clear it. Callers
  // that don't use hints omit this; they get an isolated Ref that is never read.
  identity_hints? : Ref[Array[@core.IdentityTransform]],
) -> SyncEditor[T] {
  let pending_transforms = match identity_hints {
    Some(r) => r
    None => Ref([])
  }
  let parser = make_parser("", parent_runtime)
  let (cached_proj_node, registry_memo, source_map_memo) = build_memos(parser)
  let (hub, cursor_view) = setup_hub_and_cursor(agent_id)
  {
    doc: try! @text.TextState::new(agent_id),
    undo: @undo.UndoManager::new(agent_id, capture_timeout_ms~),
    parser,
    cursor: 0,
    cached_proj_node,
    registry_memo,
    source_map_memo,
    capabilities,
    hub,
    cursor_view,
    peer_id: agent_id,
    ws: None,
    session: @sync_session.SyncSession::SyncSession(),
    projection_dirty: false,
    pending_transforms,
    identity: next_editor_identity(),
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
        if cursor_store.get(key) is Some(value) {
          cursor_view.apply_raw_update(key, value)
        }
      }
      for key in event.updated() {
        if key == wire_peer_id {
          continue
        }
        if cursor_store.get(key) is Some(value) {
          cursor_view.apply_raw_update(key, value)
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
  let map : Map[String, EphemeralValue] = Map([])
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
  if selection is Some((start, end)) {
    map["selection"] = EphemeralValue::List([
      EphemeralValue::I64(start.to_int64()),
      EphemeralValue::I64(end.to_int64()),
    ])
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
  if self.ws is Some(ws) {
    ws.send_bytes(data)
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
  self.session.get_status()
}

///|
/// Register a callback that fires on every distinct status transition.
/// Setting again replaces the previous callback. Pass `None` to disable.
pub fn[T] SyncEditor::set_on_status_change(
  self : SyncEditor[T],
  callback : ((SyncStatus) -> Unit)?,
) -> Unit {
  self.session.set_on_status_change(callback)
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
  self.session.set_watchdog_scheduler(scheduler)
}

///|
/// Set the watchdog timeout in milliseconds. Default is 5000ms.
pub fn[T] SyncEditor::set_watchdog_timeout(
  self : SyncEditor[T],
  ms : Int,
) -> Unit {
  self.session.set_watchdog_timeout(ms)
}

///|
/// Called by the FFI layer when the watchdog timer fires.
/// The `request_id` is compared against the current recovery epoch to
/// detect and discard stale firings (e.g. response already arrived).
pub fn[T] SyncEditor::on_watchdog_fire(
  self : SyncEditor[T],
  request_id : Int,
) -> Unit {
  self.session.on_watchdog_fire(request_id, self.sync_io())
}

// ── Projection accessors ─────────────────────────────────────────────────

///|
/// Returns the cached projection tree.
/// Safe to call both inside and outside tracked context.
pub fn[T] SyncEditor::get_proj_node(self : SyncEditor[T]) -> @core.ProjNode[T]? {
  self.cached_proj_node.read_or_abort()
}

///|
/// Safe to call both inside and outside tracked context.
pub fn[T] SyncEditor::get_source_map(self : SyncEditor[T]) -> @core.SourceMap {
  self.source_map_memo.read_or_abort()
}

///|
/// Returns the full node registry (NodeId → ProjNode).
/// Safe to call both inside and outside tracked context.
pub fn[T] SyncEditor::get_registry(
  self : SyncEditor[T],
) -> Map[@core.NodeId, @core.ProjNode[T]] {
  self.registry_memo.read_or_abort()
}

///|
/// Reactive view of the cached ProjNode tree. A language-specific memo may
/// return `None` when it has no projection to publish.
/// Returns the underlying Derived cell for use by workspace-coordinator
/// subscribers that need to react to changes rather than read eagerly.
pub fn[T] SyncEditor::cached_proj_node(
  self : SyncEditor[T],
) -> @incr.Derived[@core.ProjNode[T]?] {
  self.cached_proj_node
}

///|
/// Reactive view of the node-id → projection-node registry.
pub fn[T] SyncEditor::registry_memo(
  self : SyncEditor[T],
) -> @incr.Derived[Map[@core.NodeId, @core.ProjNode[T]]] {
  self.registry_memo
}

///|
/// Reactive view of the source-position → node-id map.
pub fn[T] SyncEditor::source_map_memo(
  self : SyncEditor[T],
) -> @incr.Derived[@core.SourceMap] {
  self.source_map_memo
}

///|
/// Returns the parsed AST tree (language-specific type T).
/// Always `Some(_)` — the Parser primes its AST cell in the constructor
/// and malformed input propagates through recovered syntax plus diagnostics,
/// not as `None`. The `?` is kept so this API doesn't need to churn if we later
/// separate "never parsed" from "parse failed".
pub fn[T] SyncEditor::get_tree(self : SyncEditor[T]) -> T? {
  Some(self.parser.ast().read_or_abort())
}

///|
pub fn[T] SyncEditor::get_node(
  self : SyncEditor[T],
  id : @core.NodeId,
) -> @core.ProjNode[T]? {
  self.registry_memo.read_or_abort().get(id)
}

///|
/// Editor-level cousin of `core/source_map.mbt::SourceMap::nodes_at_position`.
/// Returns only the innermost node (not the full outermost→innermost chain).
/// Natural foundation for click-to-select / hover features; see docs/TODO.md §9
/// "Wire SourceMap query API into editor click-path" — Inspector traceability
/// workstream.
pub fn[T] SyncEditor::node_at_position(
  self : SyncEditor[T],
  position : Int,
) -> @core.NodeId? {
  self.source_map_memo.read_or_abort().innermost_node_at(position)
}

///|
pub fn[T] SyncEditor::get_node_range(
  self : SyncEditor[T],
  id : @core.NodeId,
) -> @loom_core.Range? {
  self.source_map_memo.read_or_abort().get_range(id)
}

// ── Span-edit application ────────────────────────────────────────────────

///|
/// Push `Opaque` to `pending_transforms` iff the array is already non-empty.
/// Raw-text edit paths call this so that any structural hint accumulated before
/// the raw edit is invalidated (T2: no silent stale-hint trust).
/// No-op during normal typing when no structural hint is pending.
fn[T] SyncEditor::taint_pending_transforms(self : SyncEditor[T]) -> Unit {
  if !self.pending_transforms.val.is_empty() {
    self.pending_transforms.val.push(@core.IdentityTransform::Opaque)
  }
}

///|
/// Apply a list of SpanEdits through the text CRDT, then adjust the cursor
/// per the FocusHint. Edits are applied in reverse document order to avoid
/// position shifts. All edits are recorded for undo.
///
/// `hint` carries the structural-edit identity hint for this batch of span
/// edits. When provided, it is accumulated in `pending_transforms` for the
/// next reconcile pass. Callers that do not know the hint omit this
/// parameter (default: not pushed).
pub fn[T : Eq] SyncEditor::apply_span_edits(
  self : SyncEditor[T],
  edits : Array[@core.SpanEdit],
  focus_hint : @core.FocusHint,
  timestamp_ms : Int,
  hint? : @core.IdentityTransform,
) -> Unit {
  if edits.is_empty() {
    return
  }
  // Snapshot text before applying edits so we can detect net-no-op batches
  // (e.g. CommitEdit with the same text). Only needed when a hint is provided.
  let text_before : String? = match hint {
    Some(h) => {
      self.pending_transforms.val.push(h)
      Some(self.get_text())
    }
    None => None
  }
  let old_cursor = self.get_cursor()
  let sorted = edits.copy()
  sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
  for edit in sorted {
    self.apply_text_edit_internal(
      edit.start,
      edit.delete_len,
      edit.inserted,
      timestamp_ms,
      true, // record_undo — grouped by capture timeout
      false, // move_cursor_to_edit_end
    )
  }
  // Drop a pre-pushed hint when the batch produced no text change (T4).
  // Real changes need the hint available during apply_local_text_change's
  // immediate reconcile pass; no-op batches have no reparse to consume it.
  match (hint, text_before) {
    (Some(_), Some(before)) =>
      if before == self.get_text() {
        let _ = self.pending_transforms.val.pop()
      }
    _ => ()
  }
  match focus_hint {
    @core.FocusHint::RestoreCursor => self.move_cursor(old_cursor)
    @core.FocusHint::MoveCursor(position~) => self.move_cursor(position)
  }
}

// ── Sync / export ────────────────────────────────────────────────────────

///|
fn[T] SyncEditor::adjust_cursor(self : SyncEditor[T]) -> Unit {
  let text_len = self.doc.len()
  if self.cursor > text_len {
    self.cursor = text_len
  }
}

///|
pub fn[T : Eq] SyncEditor::apply_sync(
  self : SyncEditor[T],
  msg : @text.SyncMessage,
) -> Unit raise {
  self.taint_pending_transforms()
  let old_source = self.doc.text()
  self.undo.set_tracking(false)
  let report_result : Result[@text.SyncReport, @text.TextError] = Ok(
    self.doc.sync().apply(msg),
  ) catch {
    error => Err(error)
  }
  self.undo.set_tracking(true)
  // Reconcile derived state even when apply reports an error, because the
  // document may have been partially mutated before the failure surfaced.
  let new_source = self.doc.text()
  self.adjust_cursor()
  self.adjust_peer_cursors_after_text_change(old_source, new_source, None)
  self.sync_parser_after_text_change(old_source, new_source, None)
  // Keep the legacy Unit-raising SyncHost seam while EGW remains the sole
  // owner of causally pending operations.
  let report = match report_result {
    Ok(report) => report
    Err(error) => raise error
  }
  if report.pending_operations() > 0 {
    raise @text.TextError::VersionNotFound
  }
  // Clear a prior Error status once any sync applies — another peer
  // (via RelayedCrdtOps) having filled the causal gap counts as recovery.
  self.session.note_sync_applied()
}

///|
pub fn[T] SyncEditor::get_version(self : SyncEditor[T]) -> @text.Version {
  self.doc.version()
}

///|
pub fn[T] SyncEditor::export_all(
  self : SyncEditor[T],
) -> @text.SyncMessage raise {
  self.doc.sync().export_all()
}

///|
pub fn[T] SyncEditor::export_since(
  self : SyncEditor[T],
  peer_version : @text.Version,
) -> @text.SyncMessage raise {
  self.doc.sync().export_since(peer_version)
}

// ── Pretty-print integration ─────────────────────────────────────────────

///|
/// Returns the pretty-printed ViewNode tree.
/// If capabilities.pretty_post_process is set, it post-processes the layout
/// (e.g. to inject eval annotations).
pub fn[T : @pretty.Pretty] SyncEditor::get_pretty_view(
  self : SyncEditor[T],
) -> @protocol.ViewNode {
  guard self.get_tree() is Some(tree) else {
    return @protocol.layout_to_view_tree(@pretty.text(""), width=80)
  }
  let layout = @pretty.Pretty::to_layout(tree)
  let final_layout = match self.capabilities.pretty_post_process {
    Some(post) => post(layout)
    None => layout
  }
  @protocol.layout_to_view_tree(final_layout, width=80)
}

///|
/// Compute incremental pretty-view patches.
/// Uses a separate ViewUpdateState from the structural view.
pub fn[T : @pretty.Pretty] compute_pretty_patches(
  state : ViewUpdateState,
  editor : SyncEditor[T],
) -> Array[@protocol.ViewPatch] {
  let patches : Array[@protocol.ViewPatch] = []
  let current = editor.get_pretty_view()
  match state.previous {
    None => patches.push(@protocol.ViewPatch::FullTree(root=Some(current)))
    Some(prev) => diff_view_nodes(prev, current, patches)
  }
  state.previous = Some(current)
  patches
}

// ── History / construction identity ──────────────────────────────────────

///|
/// Process-local counter for `SyncEditor` construction identities. Single
/// counter shared across all `T`. Single-threaded under the MoonBit
/// web/native runtime; if multi-thread editor construction is ever added,
/// this must be made atomic.
let editor_identity_counter : Ref[Int] = { val: 0 }

///|
/// Allocate the next construction identity. Called once per
/// `SyncEditor::new_generic`.
fn next_editor_identity() -> Int {
  let id = editor_identity_counter.val
  editor_identity_counter.val = id + 1
  id
}

///|
/// Read-only view of the document's causal DAG. The returned snapshot is a
/// live alias over the underlying egw `Document` — it reflects subsequent
/// edits made through this `SyncEditor`. See `@history.CausalSnapshot` for
/// the available accessors.
pub fn[T] SyncEditor::causal_snapshot(
  self : SyncEditor[T],
) -> @history.CausalSnapshot {
  self.doc.causal_snapshot()
}

///|
/// Process-local construction identity for this `SyncEditor`. Stable for
/// the lifetime of the instance; distinct across separately-constructed
/// instances. Suitable as part of a cache key for derived views (e.g.
/// `(editor.identity(), snapshot.op_count())` for an append-only history
/// memo).
pub fn[T] SyncEditor::identity(self : SyncEditor[T]) -> Int {
  self.identity
}
