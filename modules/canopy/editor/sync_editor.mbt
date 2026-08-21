// SyncEditor: TextState + UndoManager + reactive Parser.
// Projection views subscribe to the parser's reactive memos.

///|
/// Typed telemetry for one scoped projection-relevant mutation.
pub enum ProjectionObservationPhase {
  AuthorityAccepted
  CommittedTransitionSettled
  ProjectionMirrorSynchronized
} derive(Eq, Debug)

///|
priv struct ProjectionObservationScope {
  observer : (ProjectionObservationPhase) -> Unit
  mut accepted : Bool
  mut transition_settled : Bool
  mut parser_batch_depth : Int
  mut parser_sync_pending : Bool
  mut emitting : Bool
}

///|
priv struct AuthorityCore {
  doc : @text.TextState
  undo : @undo.UndoManager
  identity : Int
}

///|
fn AuthorityCore::get_text(self : AuthorityCore) -> String {
  self.doc.text()
}

///|
fn AuthorityCore::export_all(self : AuthorityCore) -> @text.SyncMessage raise {
  self.doc.sync().export_all()
}

///|
fn AuthorityCore::export_since(
  self : AuthorityCore,
  peer_version : @text.Version,
) -> @text.SyncMessage raise {
  self.doc.sync().export_since(peer_version)
}

///|
fn AuthorityCore::admit_transition_with_tracking(
  self : AuthorityCore,
  msg : @text.SyncMessage,
  limits : @sync.Limits?,
) -> Result[@text.TextAdmissionTransition, @text.TextError] {
  self.undo.set_tracking(false)
  let transition_result : Result[@text.TextAdmissionTransition, @text.TextError] = Ok(
    match limits {
      None => self.doc.sync().apply_transition(msg)
      Some(limits) => self.doc.sync().apply_transition_with_limits(msg, limits)
    },
  ) catch {
    error => Err(error)
  }
  self.undo.set_tracking(true)
  transition_result
}

///|
fn AuthorityCore::causal_snapshot(
  self : AuthorityCore,
) -> @history.CausalSnapshot {
  self.doc.causal_snapshot()
}

///|
fn AuthorityCore::identity(self : AuthorityCore) -> Int {
  self.identity
}

///|
priv struct ProjectionState[T] {
  parser : @loom.Parser[T]
  // Reactive causal authority for host-owned snapshots. This is separate
  // from parser source because CRDT history can advance without changing the
  // rendered text.
  document_version : @incr.Input[@text.Version]
  cached_proj_node : @incr.Derived[@core.ProjNode[T]?]
  registry_memo : @incr.Derived[Map[@core.NodeId, @core.ProjNode[T]]]
  source_map_memo : @incr.Derived[@core.SourceMap]
  // These private roots give the projection graph the same page/process
  // lifetime as its owning editor. A shared-runtime attachment may run
  // runtime-wide collection without sweeping editor-owned memos.
  projection_anchor : @incr.Watch[@core.ProjNode[T]?]
  registry_anchor : @incr.Watch[Map[@core.NodeId, @core.ProjNode[T]]]
  source_map_anchor : @incr.Watch[@core.SourceMap]
  capabilities : LanguageCapabilities[T]
  mut projection_dirty : Bool
  // Once Loom raises Failure, its engine source and published snapshot may no
  // longer agree. Preserve that exact value and reject every later parser or
  // projection operation before it can observe or mutate stale state.
  mut parser_failure : Failure?
  // Structural-edit identity hints accumulated since the last reconcile.
  // Structural edits push their IdentityTransform here; raw-text edits push
  // Opaque (taint) when non-empty. Consumed and cleared once per reparse by
  // `core.build_projection_memos_with_identity_hints`.
  // T4: cleared exactly once per reconcile pass (never stale).
  // T1 invariant: hints reference only prev-tree NodeIds valid at push time.
  pending_transforms : Ref[Array[@core.IdentityTransform]]
}

///|
priv struct InteractionState {
  mut cursor : Int
  hub : EphemeralHub
  cursor_view : PeerCursorView
  peer_id : String
  mut ws : JsWebSocket?
  session : @sync_session.SyncSession
  mut cursor_subscription : EphemeralSubscription?
  // Scoped telemetry state. It coalesces multi-span edits into one A0 and one
  // final C while keeping arm/clear operations inside the editor.
  mut projection_observation_scope : ProjectionObservationScope?
}

///|
fn InteractionState::set_cursor(self : InteractionState, cursor : Int) -> Unit {
  self.cursor = cursor
}

///|
fn InteractionState::set_cursor_prev_grapheme_boundary(
  self : InteractionState,
  text : String,
  position : Int,
) -> Unit {
  self.cursor = @moji.prev_grapheme_boundary(text, position)
}

///|
fn InteractionState::set_cursor_next_grapheme_boundary(
  self : InteractionState,
  text : String,
  position : Int,
) -> Unit {
  self.cursor = @moji.next_grapheme_boundary(text, position)
}

///|
fn InteractionState::clamp_cursor_to_length(
  self : InteractionState,
  text_len : Int,
) -> Unit {
  if self.cursor > text_len {
    self.cursor = text_len
  }
}

///|
fn InteractionState::adjust_cursor_view_for_edit(
  self : InteractionState,
  edit : @loom_core.Edit,
) -> Unit {
  self.cursor_view.adjust_for_edit(edit.start(), edit.old_len(), edit.new_len())
}

///|
priv struct ProjectionFreeEditor {
  authority : AuthorityCore
  interaction : InteractionState
}

///|
pub struct SyncEditor[T] {
  priv authority : AuthorityCore
  priv projection : ProjectionState[T]
  priv interaction : InteractionState
}

///|
/// Builder-based constructor. The framework owns construction order —
/// parser → memos + language extras → capabilities → editor — and returns
/// the language-owned extras `E` alongside the editor, so companions no
/// longer publish memos through caller-threaded `Ref` side-channels.
///
/// The identity-hint channel is framework-owned: the constructor creates the
/// private queue and passes only an opaque consume-only handle to `build_parts`.
/// Callers cannot inject, replace, or mutate the editor's queue.
///
/// `build_parts` receives the parser and the identity-hint consumer and
/// returns the 3 projection memos, the capabilities built from the freshly
/// constructed extras, and the extras value `E` itself.
pub fn[T, E] SyncEditor::new_with_builder(
  agent_id : String,
  make_parser : (@loom_core.SourceId, String, @incr.Runtime?) -> @loom.Parser[T] raise Failure,
  build_parts : (@loom.Parser[T], @core.IdentityHintConsumer) -> (
    @incr.Derived[@core.ProjNode[T]?],
    @incr.Derived[Map[@core.NodeId, @core.ProjNode[T]]],
    @incr.Derived[@core.SourceMap],
    LanguageCapabilities[T],
    E,
  ),
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> (SyncEditor[T], E) raise {
  let free = new_projection_free_editor(agent_id, capture_timeout_ms)
  let pending_transforms : Ref[Array[@core.IdentityTransform]] = Ref([])
  let identity_hint_consumer = @core.IdentityHintConsumer(fn() {
    let pending = pending_transforms.val
    pending_transforms.val = []
    pending
  })
  let source_id = @loom_core.SourceId(
    "canopy-sync-editor:" + free.authority.identity.to_string(),
  )
  let parser = make_parser(source_id, "", parent_runtime)
  let document_version = @incr.Input(
    parser.runtime(),
    free.authority.doc.version(),
    label="sync_editor_document_version",
  )
  let (cached_proj_node, registry_memo, source_map_memo, capabilities, extras) = build_parts(
    parser, identity_hint_consumer,
  )
  let projection : ProjectionState[T] = {
    parser,
    document_version,
    cached_proj_node,
    registry_memo,
    source_map_memo,
    projection_anchor: cached_proj_node.watch(),
    registry_anchor: registry_memo.watch(),
    source_map_anchor: source_map_memo.watch(),
    capabilities,
    projection_dirty: false,
    parser_failure: None,
    pending_transforms,
  }
  (attach_projection(free, projection), extras)
}

///|
/// Construct authority and interaction ownership without parser, reactive
/// runtime, projection memos, transport activation, or subscriptions.
fn new_projection_free_editor(
  agent_id : String,
  capture_timeout_ms : Int,
) -> ProjectionFreeEditor raise {
  let identity = next_editor_identity()
  {
    authority: {
      doc: @text.TextState::new(agent_id),
      undo: @undo.UndoManager::new(agent_id, capture_timeout_ms~),
      identity,
    },
    interaction: {
      cursor: 0,
      hub: EphemeralHub::new(agent_id),
      cursor_view: PeerCursorView::new(),
      peer_id: agent_id,
      ws: None,
      session: @sync_session.SyncSession::SyncSession(),
      cursor_subscription: None,
      projection_observation_scope: None,
    },
  }
}

///|
/// Activate interaction observation exactly once and assemble the public facade.
fn[T] attach_projection(
  free : ProjectionFreeEditor,
  projection : ProjectionState[T],
) -> SyncEditor[T] raise Failure {
  free.interaction.activate_cursor_view()
  { authority: free.authority, projection, interaction: free.interaction }
}

///|
/// Observe one whole mutation request without exposing arm/clear operations.
pub fn[T, R] SyncEditor::observe_projection_during(
  self : SyncEditor[T],
  observer : (ProjectionObservationPhase) -> Unit,
  action : () -> R raise,
) -> (R, Bool) raise {
  self.interaction.observe_projection_during(observer, action)
}

///|
fn[R] InteractionState::observe_projection_during(
  self : InteractionState,
  observer : (ProjectionObservationPhase) -> Unit,
  action : () -> R raise,
) -> (R, Bool) raise {
  guard self.projection_observation_scope is None else {
    raise Failure::Failure("projection observation already active")
  }
  let scope : ProjectionObservationScope = {
    observer,
    accepted: false,
    transition_settled: false,
    parser_batch_depth: 0,
    parser_sync_pending: false,
    emitting: false,
  }
  self.projection_observation_scope = Some(scope)
  let result = action() catch {
    error => {
      self.projection_observation_scope = None
      raise error
    }
  }
  self.projection_observation_scope = None
  (result, scope.accepted)
}

///|
fn[T] SyncEditor::observe_authority_acceptance(self : SyncEditor[T]) -> Unit {
  self.interaction.observe_authority_acceptance()
}

///|
fn InteractionState::observe_authority_acceptance(
  self : InteractionState,
) -> Unit {
  match self.projection_observation_scope {
    None => ()
    Some(scope) =>
      if !scope.accepted {
        scope.accepted = true
        self.emit_projection_observation_phase(
          ProjectionObservationPhase::AuthorityAccepted,
        )
      }
  }
}

///|
fn[T] SyncEditor::observe_committed_transition_settled(
  self : SyncEditor[T],
) -> Unit {
  self.interaction.observe_committed_transition_settled()
}

///|
fn InteractionState::observe_committed_transition_settled(
  self : InteractionState,
) -> Unit {
  match self.projection_observation_scope {
    None => ()
    Some(scope) =>
      if !scope.transition_settled {
        scope.transition_settled = true
        self.emit_projection_observation_phase(
          ProjectionObservationPhase::CommittedTransitionSettled,
        )
      }
  }
}

///|
fn[T] SyncEditor::begin_projection_observation_batch(
  self : SyncEditor[T],
) -> Unit {
  self.interaction.begin_projection_observation_batch()
}

///|
fn InteractionState::begin_projection_observation_batch(
  self : InteractionState,
) -> Unit {
  match self.projection_observation_scope {
    None => ()
    Some(scope) => scope.parser_batch_depth += 1
  }
}

///|
fn[T] SyncEditor::end_projection_observation_batch(
  self : SyncEditor[T],
  succeeded~ : Bool,
) -> Unit {
  self.interaction.end_projection_observation_batch(succeeded~)
}

///|
fn InteractionState::end_projection_observation_batch(
  self : InteractionState,
  succeeded~ : Bool,
) -> Unit {
  match self.projection_observation_scope {
    None => ()
    Some(scope) => {
      scope.parser_batch_depth -= 1
      if !succeeded {
        scope.parser_sync_pending = false
      } else if scope.parser_batch_depth == 0 && scope.parser_sync_pending {
        scope.parser_sync_pending = false
        self.emit_projection_observation_phase(
          ProjectionObservationPhase::ProjectionMirrorSynchronized,
        )
      }
    }
  }
}

///|
fn[T] SyncEditor::observe_parser_synchronized(self : SyncEditor[T]) -> Unit {
  self.interaction.observe_parser_synchronized()
}

///|
fn InteractionState::observe_parser_synchronized(
  self : InteractionState,
) -> Unit {
  match self.projection_observation_scope {
    None => ()
    Some(scope) =>
      if scope.accepted {
        if scope.parser_batch_depth > 0 {
          scope.parser_sync_pending = true
        } else {
          self.emit_projection_observation_phase(
            ProjectionObservationPhase::ProjectionMirrorSynchronized,
          )
        }
      }
  }
}

///|
fn InteractionState::emit_projection_observation_phase(
  self : InteractionState,
  phase : ProjectionObservationPhase,
) -> Unit {
  match self.projection_observation_scope {
    None => ()
    Some(scope) => {
      scope.emitting = true
      (scope.observer)(phase)
      scope.emitting = false
    }
  }
}

///|
fn[T] SyncEditor::reject_projection_observer_reentry(
  self : SyncEditor[T],
) -> Unit raise Failure {
  self.interaction.reject_projection_observer_reentry()
}

///|
fn InteractionState::reject_projection_observer_reentry(
  self : InteractionState,
) -> Unit raise Failure {
  match self.projection_observation_scope {
    None => ()
    Some(scope) =>
      if scope.emitting {
        raise Failure::Failure("projection observer reentrant mutation")
      }
  }
}

// --- Hub and cursor setup ---

///|
/// Activate remote cursor observation exactly once after projection attachment.
fn InteractionState::activate_cursor_view(
  self : InteractionState,
) -> Unit raise Failure {
  guard self.cursor_subscription is None else {
    raise Failure::Failure("interaction already activated")
  }
  let wire_peer_id = self.hub.wire_peer_id
  let cursor_store = self.hub.get_store(Cursor)
  let cursor_view = self.cursor_view
  let subscription = cursor_store.subscribe(fn(event) {
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
  })
  self.cursor_subscription = Some(subscription)
}

// --- Ephemeral presence methods ---

///|
pub fn[T] SyncEditor::set_local_presence(
  self : SyncEditor[T],
  name : String,
  color : String,
  selection? : (Int, Int)? = None,
) -> Unit {
  self.interaction.set_local_presence(name, color, selection~)
}

///|
fn InteractionState::set_local_presence(
  self : InteractionState,
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
  self.interaction.delete_local_presence()
}

///|
fn InteractionState::delete_local_presence(self : InteractionState) -> Unit {
  self.hub.on_peer_leave(self.peer_id)
}

///|
/// Best-effort application of remote ephemeral data. Malformed wire data from
/// a remote peer is silently dropped to avoid crashing the local editor.
pub fn[T] SyncEditor::apply_ephemeral(
  self : SyncEditor[T],
  data : Bytes,
) -> Unit {
  self.interaction.apply_ephemeral(data)
}

///|
fn InteractionState::apply_ephemeral(
  self : InteractionState,
  data : Bytes,
) -> Unit {
  self.hub.apply_all(data)
}

///|
pub fn[T] SyncEditor::encode_ephemeral_all(self : SyncEditor[T]) -> Bytes {
  self.interaction.encode_ephemeral_all()
}

///|
fn InteractionState::encode_ephemeral_all(self : InteractionState) -> Bytes {
  self.hub.encode_all()
}

///|
pub fn[T] SyncEditor::remove_ephemeral_outdated(self : SyncEditor[T]) -> Unit {
  self.interaction.remove_ephemeral_outdated()
}

///|
fn InteractionState::remove_ephemeral_outdated(self : InteractionState) -> Unit {
  self.hub.remove_outdated()
}

///|
pub fn[T] SyncEditor::get_peer_cursors(
  self : SyncEditor[T],
) -> Map[String, PeerCursor] {
  self.interaction.get_peer_cursors()
}

///|
fn InteractionState::get_peer_cursors(
  self : InteractionState,
) -> Map[String, PeerCursor] {
  self.cursor_view.all_cursors()
}

///|
pub fn[T] SyncEditor::get_peer_id(self : SyncEditor[T]) -> String {
  self.interaction.get_peer_id()
}

///|
fn InteractionState::get_peer_id(self : InteractionState) -> String {
  self.peer_id
}

///|
pub fn[T] SyncEditor::get_hub(self : SyncEditor[T]) -> EphemeralHub {
  self.interaction.get_hub()
}

///|
fn InteractionState::get_hub(self : InteractionState) -> EphemeralHub {
  self.hub
}

///|
pub fn[T] SyncEditor::ws_send(self : SyncEditor[T], data : Bytes) -> Unit {
  self.interaction.ws_send(data)
}

///|
fn InteractionState::ws_send(self : InteractionState, data : Bytes) -> Unit {
  if self.ws is Some(ws) {
    ws.send_bytes(data)
  }
}

///|
pub fn[T] SyncEditor::subscribe_ephemeral_local(
  self : SyncEditor[T],
  callback : (Bytes) -> Bool,
) -> EphemeralSubscription {
  self.interaction.subscribe_ephemeral_local(callback)
}

///|
fn InteractionState::subscribe_ephemeral_local(
  self : InteractionState,
  callback : (Bytes) -> Bool,
) -> EphemeralSubscription {
  self.hub.get_store(Cursor).subscribe_local_updates(callback)
}

///|
fn InteractionState::apply_ephemeral_namespace(
  self : InteractionState,
  ns : EphemeralNamespace,
  payload : Bytes,
) -> Unit {
  self.hub.apply(ns, payload)
}

///|
fn InteractionState::encode_ephemeral_namespace(
  self : InteractionState,
  ns : EphemeralNamespace,
) -> Bytes {
  self.hub.encode(ns)
}

///|
fn InteractionState::on_peer_leave(
  self : InteractionState,
  peer_id : String,
) -> Unit {
  self.hub.on_peer_leave(peer_id)
}

///|
fn InteractionState::has_ws(self : InteractionState) -> Bool {
  self.ws is Some(_)
}

// --- SyncStatus API ---

///|
/// Get the current sync status.
pub fn[T] SyncEditor::get_sync_status(self : SyncEditor[T]) -> SyncStatus {
  self.interaction.get_sync_status()
}

///|
fn InteractionState::get_sync_status(self : InteractionState) -> SyncStatus {
  self.session.get_status()
}

///|
fn InteractionState::note_sync_applied(self : InteractionState) -> Unit {
  self.session.note_sync_applied()
}

///|
/// Register a callback that fires on every distinct status transition.
/// Setting again replaces the previous callback. Pass `None` to disable.
pub fn[T] SyncEditor::set_on_status_change(
  self : SyncEditor[T],
  callback : ((SyncStatus) -> Unit)?,
) -> Unit {
  self.interaction.set_on_status_change(callback)
}

///|
fn InteractionState::set_on_status_change(
  self : InteractionState,
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
  self.interaction.set_watchdog_scheduler(scheduler)
}

///|
fn InteractionState::set_watchdog_scheduler(
  self : InteractionState,
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
  self.interaction.set_watchdog_timeout(ms)
}

///|
fn InteractionState::set_watchdog_timeout(
  self : InteractionState,
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
  self.interaction.on_watchdog_fire(request_id, self.sync_io())
}

///|
fn InteractionState::on_watchdog_fire(
  self : InteractionState,
  request_id : Int,
  io : @sync_session.SyncIo,
) -> Unit {
  self.session.on_watchdog_fire(request_id, io)
}

// ── Projection accessors ─────────────────────────────────────────────────

///|
/// Returns the cached projection tree.
/// Safe to call both inside and outside tracked context.
pub fn[T] SyncEditor::get_proj_node(
  self : SyncEditor[T],
) -> @core.ProjNode[T]? raise Failure {
  self.ensure_parser_healthy()
  self.projection.cached_proj_node.read_or_abort()
}

///|
/// Safe to call both inside and outside tracked context.
pub fn[T] SyncEditor::get_source_map(
  self : SyncEditor[T],
) -> @core.SourceMap raise Failure {
  self.ensure_parser_healthy()
  self.projection.source_map_memo.read_or_abort()
}

///|
/// Returns the full node registry (NodeId → ProjNode).
/// Safe to call both inside and outside tracked context.
pub fn[T] SyncEditor::get_registry(
  self : SyncEditor[T],
) -> Map[@core.NodeId, @core.ProjNode[T]] raise Failure {
  self.ensure_parser_healthy()
  self.projection.registry_memo.read_or_abort()
}

///|
/// Reactive view of the cached ProjNode tree. A language-specific memo may
/// return `None` when it has no projection to publish.
/// Returns the underlying Derived cell for use by workspace-coordinator
/// subscribers that need to react to changes rather than read eagerly.
pub fn[T] SyncEditor::cached_proj_node(
  self : SyncEditor[T],
) -> @incr.Derived[@core.ProjNode[T]?] raise Failure {
  self.ensure_parser_healthy()
  self.projection.cached_proj_node
}

///|
/// Reactive view of the node-id → projection-node registry.
pub fn[T] SyncEditor::registry_memo(
  self : SyncEditor[T],
) -> @incr.Derived[Map[@core.NodeId, @core.ProjNode[T]]] raise Failure {
  self.ensure_parser_healthy()
  self.projection.registry_memo
}

///|
/// Reactive view of the source-position → node-id map.
pub fn[T] SyncEditor::source_map_memo(
  self : SyncEditor[T],
) -> @incr.Derived[@core.SourceMap] raise Failure {
  self.ensure_parser_healthy()
  self.projection.source_map_memo
}

///|
/// Returns the parsed AST tree (language-specific type T).
/// Always `Some(_)` — the Parser primes its AST cell in the constructor
/// and malformed input propagates through recovered syntax plus diagnostics,
/// not as `None`. The `?` is kept so this API doesn't need to churn if we later
/// separate "never parsed" from "parse failed".
pub fn[T] SyncEditor::get_tree(self : SyncEditor[T]) -> T? raise Failure {
  self.ensure_parser_healthy()
  Some(self.projection.parser.ast().read_or_abort())
}

///|
pub fn[T] SyncEditor::get_node(
  self : SyncEditor[T],
  id : @core.NodeId,
) -> @core.ProjNode[T]? raise Failure {
  self.ensure_parser_healthy()
  self.projection.registry_memo.read_or_abort().get(id)
}

///|
/// Editor-level cousin of `core/source_map.mbt::SourceMap::nodes_at_position`.
/// Returns only the innermost node (not the full outermost→innermost chain).
/// Natural foundation for click-to-select / hover features. No UI consumer is
/// currently committed; wire it only from an accepted interaction issue.
pub fn[T] SyncEditor::node_at_position(
  self : SyncEditor[T],
  position : Int,
) -> @core.NodeId? raise Failure {
  self.ensure_parser_healthy()
  self.projection.source_map_memo.read_or_abort().innermost_node_at(position)
}

///|
pub fn[T] SyncEditor::get_node_range(
  self : SyncEditor[T],
  id : @core.NodeId,
) -> @loom_core.Range? raise Failure {
  self.ensure_parser_healthy()
  self.projection.source_map_memo.read_or_abort().get_range(id)
}

// ── Span-edit application ────────────────────────────────────────────────

///|
/// Invalidate previously queued structural identity hints without exposing the
/// editor's mutable queue. The language runtime calls this after a resolved
/// structural edit fails legality checks; resolution failures leave the queue
/// untouched. No-op when no hint is pending.
pub fn[T] SyncEditor::invalidate_pending_identity_hints(
  self : SyncEditor[T],
) -> Unit raise Failure {
  self.ensure_parser_healthy()
  self.taint_pending_transforms()
}

///|
fn[T] ProjectionState::taint_pending_transforms(
  self : ProjectionState[T],
) -> Unit {
  if !self.pending_transforms.val.is_empty() {
    self.pending_transforms.val.push(@core.IdentityTransform::Opaque)
  }
}

///|
fn[T] ProjectionState::push_identity_hint(
  self : ProjectionState[T],
  hint : @core.IdentityTransform,
) -> Unit {
  self.pending_transforms.val.push(hint)
}

///|
fn[T] ProjectionState::rollback_identity_hint(
  self : ProjectionState[T],
) -> Unit {
  let _ = self.pending_transforms.val.pop()
}

///|
/// Push `Opaque` to `pending_transforms` iff the array is already non-empty.
/// Raw-text edit paths call this so that any structural hint accumulated before
/// the raw edit is invalidated (T2: no silent stale-hint trust).
/// No-op during normal typing when no structural hint is pending.
fn[T] SyncEditor::taint_pending_transforms(self : SyncEditor[T]) -> Unit {
  self.projection.taint_pending_transforms()
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
) -> Unit raise Failure {
  self.ensure_parser_healthy()
  self.reject_projection_observer_reentry()
  if edits.is_empty() {
    return
  }
  let before_version = self.authority.doc.version()
  let old_source = self.get_text()
  match hint {
    Some(h) => self.projection.push_identity_hint(h)
    None => ()
  }
  let old_cursor = self.get_cursor()
  let sorted = edits.copy()
  sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
  let replay_spans : Array[ProjectionReplaySpan] = []
  self.begin_projection_observation_batch()
  try {
    for edit in sorted {
      let current_source = self.authority.doc.text()
      match
        self.apply_text_edit_mutation_only(
          current_source,
          edit.start,
          edit.delete_len,
          edit.inserted,
          timestamp_ms,
          true,
          SnapToGrapheme,
        ) {
        Some(applied_edit) =>
          replay_spans.push({
            edit: applied_edit,
            inserted: edit.inserted,
            source_after: None,
          })
        None => ()
      }
    }
    if self.authority.doc.version() != before_version {
      self.observe_authority_acceptance()
      let new_source = self.authority.doc.text()
      self.settle_committed_span_change(
        old_source, new_source, before_version, replay_spans,
      )
      self.interaction.set_cursor_next_grapheme_boundary(
        new_source,
        clamp_utf16_offset(new_source, self.interaction.cursor),
      )
    }
  } catch {
    error => {
      self.end_projection_observation_batch(succeeded=false)
      raise error
    }
  }
  self.end_projection_observation_batch(succeeded=true)
  // Drop a pre-pushed hint when the batch produced no text change (T4).
  match hint {
    Some(_) =>
      if old_source == self.get_text() {
        self.projection.rollback_identity_hint()
      }
    None => ()
  }
  match focus_hint {
    @core.FocusHint::RestoreCursor => self.move_cursor(old_cursor)
    @core.FocusHint::MoveCursor(position~) => self.move_cursor(position)
  }
}

// ── Sync / export ────────────────────────────────────────────────────────

///|
fn[T] SyncEditor::adjust_cursor(self : SyncEditor[T]) -> Unit {
  self.interaction.clamp_cursor_to_length(self.authority.doc.len())
}

///|
fn[T : Eq] SyncEditor::admit_with_policy_using_snapshot_reader(
  self : SyncEditor[T],
  msg : @text.SyncMessage,
  limits : @sync.Limits?,
  read_snapshot : () -> String,
) -> @text.SyncReport raise {
  self.ensure_parser_healthy()
  self.reject_projection_observer_reentry()
  let transition = match
    self.authority.admit_transition_with_tracking(msg, limits) {
    Ok(transition) => transition
    Err(error) => raise error
  }
  let authority_advanced = transition.version_after() !=
    transition.version_before()
  if authority_advanced {
    self.observe_authority_acceptance()
  }
  let parser_source = self.projection.parser.source().read_or_abort()
  match transition.availability() {
    @text.TextEffectAvailability::Exact(effects) => {
      let prepared = prepare_text_admission(parser_source, effects)
      self.settle_prepared_text_admission(
        parser_source,
        prepared,
        transition.version_after(),
        authority_advanced,
      )
    }
    @text.TextEffectAvailability::SnapshotRequired => {
      let coherent_source = read_snapshot()
      if authority_advanced {
        self.observe_committed_transition_settled()
      }
      self.interaction.clamp_cursor_to_length(coherent_source.length())
      self.adjust_peer_cursors_after_text_change(
        parser_source,
        coherent_source,
        None,
      )
      self.taint_pending_transforms()
      self.sync_parser_from_supplied_seed(coherent_source)
    }
    @text.TextEffectAvailability::Unavailable =>
      if authority_advanced {
        self.observe_committed_transition_settled()
      }
  }
  let report = transition.finish()
  if report.pending_operations() == 0 {
    // Clear a prior Error status once any sync applies — another peer
    // (via RelayedCrdtOps) having filled the causal gap counts as recovery.
    // A message that still leaves a gap is not recovery, so the status stands.
    self.interaction.note_sync_applied()
  }
  report
}

///|
fn[T : Eq] SyncEditor::admit_with_policy(
  self : SyncEditor[T],
  msg : @text.SyncMessage,
  limits : @sync.Limits?,
) -> @text.SyncReport raise {
  self.admit_with_policy_using_snapshot_reader(msg, limits, () => {
    self.authority.doc.text()
  })
}

///|
/// Take a peer's operations into this document, reporting what landed.
///
/// Operations whose causal prerequisites are absent are retained rather than
/// rejected, and counted in the returned report. That is a state, not a
/// failure. Callers that require a message to be complete apply that policy
/// themselves — `apply_sync` is the one that does.
pub fn[T : Eq] SyncEditor::admit(
  self : SyncEditor[T],
  msg : @text.SyncMessage,
) -> @text.SyncReport raise {
  self.admit_with_policy(msg, None)
}

///|
/// Take operations into this document using caller-selected resource limits.
///
/// This selects policy for one admission only; peer admission through `admit`
/// continues to use the limits configured on the document.
pub fn[T : Eq] SyncEditor::admit_with_limits(
  self : SyncEditor[T],
  msg : @text.SyncMessage,
  limits : @sync.Limits,
) -> @text.SyncReport raise {
  self.admit_with_policy(msg, Some(limits))
}

///|
/// Apply a SyncMessage from a peer, requiring it to be complete.
///
/// This is `admit` plus a completeness policy. The name does not say so; it
/// predates the distinction and is kept because its callers depend on the
/// raise.
pub fn[T : Eq] SyncEditor::apply_sync(
  self : SyncEditor[T],
  msg : @text.SyncMessage,
) -> Unit raise {
  if self.admit(msg).pending_operations() > 0 {
    raise @text.TextError::VersionNotFound
  }
}

///|
pub fn[T] SyncEditor::get_version(self : SyncEditor[T]) -> @text.Version {
  // The reactive version is refreshed alongside every accepted text/CRDT
  // transition. Reuse it instead of expanding the entire operation log again.
  self.projection.document_version.get()
}

///|
pub fn[T] SyncEditor::export_all(
  self : SyncEditor[T],
) -> @text.SyncMessage raise {
  self.authority.export_all()
}

///|
pub fn[T] SyncEditor::export_since(
  self : SyncEditor[T],
  peer_version : @text.Version,
) -> @text.SyncMessage raise {
  self.authority.export_since(peer_version)
}

// ── Pretty-print integration ─────────────────────────────────────────────

///|
/// Returns the pretty-printed ViewNode tree.
/// If capabilities.pretty_post_process is set, it post-processes the layout
/// (e.g. to inject eval annotations).
pub fn[T : @pretty.Pretty] SyncEditor::get_pretty_view(
  self : SyncEditor[T],
) -> @protocol.ViewNode raise Failure {
  guard self.get_tree() is Some(tree) else {
    return @protocol.layout_to_view_tree(@pretty.text(""), width=80)
  }
  let layout = @pretty.Pretty::to_layout(tree)
  let final_layout = match self.projection.capabilities.pretty_post_process {
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
) -> Array[@protocol.ViewPatch] raise Failure {
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
/// `SyncEditor::new_with_builder`.
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
  self.authority.causal_snapshot()
}

///|
/// Process-local construction identity for this `SyncEditor`. Stable for
/// the lifetime of the instance; distinct across separately-constructed
/// instances. Suitable as part of a cache key for derived views (e.g.
/// `(editor.identity(), snapshot.op_count())` for an append-only history
/// memo).
pub fn[T] SyncEditor::identity(self : SyncEditor[T]) -> Int {
  self.authority.identity()
}
