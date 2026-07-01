///|
/// Coarse durable validation stage. It owns the document snapshot plus the
/// validation messages derived from durable nodes/edges only.
struct ValidatedCanvas {
  document : CanvasDocument
  validation : Array[ValidationJson]
} derive(Eq)

///|
/// Coarse normalized graph stage. Kept explicit so the canvas runtime mirrors
/// the graph-editor recompute bench shape: document -> validation ->
/// normalization -> lowering -> render.
struct NormalizedCanvas {
  document : CanvasDocument
  validation : Array[ValidationJson]
} derive(Eq)

///|
struct LoweredCanvas {
  nodes : Array[NodeJson]
  edges : Array[EdgeJson]
  validation : Array[ValidationJson]
} derive(Eq)

///|
struct CanvasFullRenderJson {
  viewport : Viewport
  nodes : Array[NodeJson]
  edges : Array[EdgeJson]
  selected : String?
  selected_nodes : Array[String]
  connecting : ConnectingJson?
  validation : Array[ValidationJson]
  action_count : Int
} derive(Eq)

///|
fn normalize_canvas(validated : ValidatedCanvas) -> NormalizedCanvas {
  {
    document: {
      nodes: validated.document.nodes.copy(),
      edges: validated.document.edges.copy(),
      next_node_id: validated.document.next_node_id,
    },
    validation: validated.validation.copy(),
  }
}

///|
/// Private storage for the example-local canvas runtime. Keep direct `@incr`
/// cell access in this file behind `CanvasRuntime` methods so future reusable
/// runtime work can reshape ownership without host callers depending on cells.
priv struct CanvasRuntimeCells {
  document : @incr.Input[CanvasDocument]
  actions : @incr.Input[Array[GraphOperation]]
  hover : @incr.Input[NodeId?]
  drag_preview : @incr.Input[DragPreview]
  viewport : @incr.Input[Viewport]
  selection : @incr.Input[SelectionState]
  interaction : @incr.Input[InteractionState]
  render_watch : @incr.Watch[CanvasFullRenderJson]
  inspector_watch : @incr.Watch[InspectorNodeJson?]
}

///|
/// Example-local runtime facade. This hardens the private boundary around the
/// split durable/ephemeral `@incr` state. Graph mechanics stay here; workflow
/// validation/render/inspector/add-node policy is injected through the private
/// host-policy seam rather than baked into the cells.
priv struct CanvasRuntime {
  policy : CanvasHostPolicy
  cells : CanvasRuntimeCells
}

///|
fn CanvasRuntime::CanvasRuntime() -> CanvasRuntime {
  CanvasRuntime::with_host_policy(workflow_canvas_host_policy())
}

///|
fn CanvasRuntime::with_host_policy(policy : CanvasHostPolicy) -> CanvasRuntime {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let initial = (policy.initial_state)()
  let document = scope.input(
    @graph_model.canvas_document_from_state(initial),
    label="canvas.document",
  )
  let actions = scope.input(
    initial.action_log.copy(),
    label="canvas.action_log",
  )
  let hover = scope.input(None, label="canvas.hover")
  let drag_preview = scope.input(
    @graph_model.idle_drag_preview(),
    label="canvas.drag_preview",
  )
  let viewport = scope.input(initial.viewport, label="canvas.viewport")
  let selection = scope.input(
    @graph_model.selection_from_interaction(initial.interaction),
    label="canvas.selection",
  )
  let interaction = scope.input(initial.interaction, label="canvas.gesture")

  let validated = scope.derived(
    () => policy.validate_canvas_document(document.get()),
    label="canvas.validation",
  )
  let normalized = validated.map(
    v => normalize_canvas(v),
    label="canvas.normalization",
  )
  let lowered = normalized.map(
    n => policy.lower_canvas(n),
    label="canvas.lowering",
  )
  // Register mapped cells for deterministic scope disposal — replacing
  // scope.derived (which auto-registers) with map would otherwise leave
  // normalized/lowered unregistered, creating a contract gap vs original code.
  // This is about disposal determinism, not GC rooting (the watch chain keeps
  // them alive either way).
  scope.add_cell_ids([normalized.id(), lowered.id()])
  let render = scope.derived(
    () => {
      policy.render_full_canvas(
        lowered.get_or_abort(),
        viewport.get(),
        drag_preview.get(),
        selection.get(),
        interaction.get(),
        actions.get().length(),
      )
    },
    label="canvas.render",
  )

  let node_inspector = scope.derived_map(
    (id : String) => {
      policy.inspector_node_for_document(
        normalized.get_or_abort().document,
        NodeId(id),
      )
    },
    label="canvas.inspector.node_by_id",
  )
  let inspector_scope = scope.child()
  let inspector = inspector_scope.reachable_derived(
    () => {
      let current_selection = selection.get()
      match current_selection.selected {
        Some(id) =>
          policy.inspector_with_source(
            node_inspector.get_or_abort(node_id_to_string(id)),
            policy.selected_inspector_source,
          )
        None =>
          match hover.get() {
            None => None
            Some(id) =>
              policy.inspector_with_source(
                node_inspector.get_or_abort(node_id_to_string(id)),
                policy.hovered_inspector_source,
              )
          }
      }
    },
    label="canvas.inspector.selected_node",
  )

  let render_watch = scope.add_watch(render.watch())
  let inspector_watch = inspector_scope.add_watch(inspector.watch())
  ignore(render_watch.read_or_abort())
  ignore(inspector_watch.read_or_abort())
  rt.gc()
  let cells : CanvasRuntimeCells = {
    document,
    actions,
    hover,
    drag_preview,
    viewport,
    selection,
    interaction,
    render_watch,
    inspector_watch,
  }
  { policy, cells }
}

///|
fn CanvasRuntime::peek_document(self : CanvasRuntime) -> CanvasDocument {
  let document = self.cells.document.peek()
  {
    nodes: document.nodes.copy(),
    edges: document.edges.copy(),
    next_node_id: document.next_node_id,
  }
}

///|
fn CanvasRuntime::set_document(
  self : CanvasRuntime,
  document : CanvasDocument,
) -> Unit {
  self.cells.document.set({
    nodes: document.nodes.copy(),
    edges: document.edges.copy(),
    next_node_id: document.next_node_id,
  })
}

///|
fn CanvasRuntime::action_log_snapshot(
  self : CanvasRuntime,
) -> Array[GraphOperation] {
  self.cells.actions.peek().copy()
}

///|
fn CanvasRuntime::set_action_log(
  self : CanvasRuntime,
  actions : Array[GraphOperation],
) -> Unit {
  self.cells.actions.set(actions.copy())
}

///|
fn CanvasRuntime::set_hover(self : CanvasRuntime, hover : NodeId?) -> Unit {
  self.cells.hover.set(hover)
}

///|
fn CanvasRuntime::peek_drag_preview(self : CanvasRuntime) -> DragPreview {
  let preview = self.cells.drag_preview.peek()
  { positions: preview.positions.copy() }
}

///|
fn CanvasRuntime::set_drag_preview(
  self : CanvasRuntime,
  preview : DragPreview,
) -> Unit {
  self.cells.drag_preview.set({ positions: preview.positions.copy() })
}

///|
fn CanvasRuntime::peek_viewport(self : CanvasRuntime) -> Viewport {
  self.cells.viewport.peek()
}

///|
fn CanvasRuntime::set_viewport(
  self : CanvasRuntime,
  viewport : Viewport,
) -> Unit {
  self.cells.viewport.set(viewport)
}

///|
fn CanvasRuntime::peek_selection(self : CanvasRuntime) -> SelectionState {
  let selection = self.cells.selection.peek()
  {
    selected: selection.selected,
    selected_nodes: selection.selected_nodes.copy(),
  }
}

///|
fn CanvasRuntime::set_selection(
  self : CanvasRuntime,
  selection : SelectionState,
) -> Unit {
  self.cells.selection.set({
    selected: selection.selected,
    selected_nodes: selection.selected_nodes.copy(),
  })
}

///|
fn CanvasRuntime::peek_interaction(self : CanvasRuntime) -> InteractionState {
  self.cells.interaction.peek()
}

///|
fn CanvasRuntime::set_interaction(
  self : CanvasRuntime,
  interaction : InteractionState,
) -> Unit {
  self.cells.interaction.set(interaction)
}

///|
fn CanvasRuntime::read_full_render(
  self : CanvasRuntime,
) -> CanvasFullRenderJson {
  self.cells.render_watch.read_or_abort()
}

///|
fn CanvasRuntime::read_inspector(self : CanvasRuntime) -> InspectorNodeJson? {
  self.cells.inspector_watch.read_or_abort()
}

///|
fn CanvasRuntime::state_peek(self : CanvasRuntime) -> CanvasState {
  let interaction = @graph_model.interaction_with_selection(
    self.peek_interaction(),
    self.peek_selection(),
  )
  @graph_model.canvas_state_from_parts(
    self.peek_document(),
    self.peek_viewport(),
    interaction,
    self.action_log_snapshot(),
  )
}

///|
fn CanvasRuntime::sync_commit_state(
  self : CanvasRuntime,
  state : CanvasState,
) -> Unit {
  self.set_document(@graph_model.canvas_document_from_state(state))
  self.set_viewport(state.viewport)
  self.set_drag_preview(@graph_model.idle_drag_preview())
  self.set_selection(@graph_model.selection_from_interaction(state.interaction))
  self.set_interaction(state.interaction)
  self.set_action_log(state.action_log)
}

///|
fn CanvasRuntime::sync_viewport_state(
  self : CanvasRuntime,
  state : CanvasState,
) -> Unit {
  self.set_viewport(state.viewport)
  self.set_interaction(state.interaction)
}

///|
fn CanvasRuntime::sync_action_viewport_state(
  self : CanvasRuntime,
  state : CanvasState,
) -> Unit {
  self.set_viewport(state.viewport)
  self.set_action_log(state.action_log)
}

///|
fn CanvasRuntime::sync_document_action_state(
  self : CanvasRuntime,
  state : CanvasState,
) -> Unit {
  self.set_document(@graph_model.canvas_document_from_state(state))
  self.set_action_log(state.action_log)
}

///|
fn CanvasRuntime::pointer_down(
  self : CanvasRuntime,
  node_id : NodeId?,
  sx : Double,
  sy : Double,
) -> Unit {
  let state = @graph_model.update_pointer_down(
    self.state_peek(),
    node_id,
    sx,
    sy,
  )
  self.set_drag_preview(@graph_model.idle_drag_preview())
  self.set_interaction(state.interaction)
}

///|
fn CanvasRuntime::pointer_down_handle(
  self : CanvasRuntime,
  node_id : NodeId,
  port_id : String,
  sx : Double,
  sy : Double,
) -> Unit {
  let state = self.state_peek()
  let (wx, wy) = @graph_model.screen_to_world(state.viewport, sx, sy)
  self.set_interaction(
    @graph_model.update_connect_start(state, node_id, port_id, wx, wy).interaction,
  )
}

///|
fn CanvasRuntime::sync_connect_move(
  self : CanvasRuntime,
  state : CanvasState,
  sx : Double,
  sy : Double,
) -> Unit {
  let (wx, wy) = @graph_model.screen_to_world(state.viewport, sx, sy)
  self.set_interaction(
    @graph_model.update_connect_move(state, wx, wy).interaction,
  )
}

///|
fn CanvasRuntime::sync_drag_preview_move(
  self : CanvasRuntime,
  state : CanvasState,
  drag : DragState,
  sx : Double,
  sy : Double,
) -> Unit {
  let (wx, wy) = @graph_model.screen_to_world(state.viewport, sx, sy)
  self.set_drag_preview(@graph_model.drag_preview_from_move(drag, wx, wy))
  self.set_interaction({ ..state.interaction, did_move: true })
}

///|
fn CanvasRuntime::sync_pan_move(
  self : CanvasRuntime,
  state : CanvasState,
  sx : Double,
  sy : Double,
) -> Unit {
  self.sync_viewport_state(@graph_model.update_pan_move(state, sx, sy))
}

///|
fn CanvasRuntime::state_with_active_drag_preview(
  self : CanvasRuntime,
  state : CanvasState,
) -> CanvasState {
  match state.interaction.dragging {
    Some(_) if state.interaction.did_move =>
      @graph_model.state_with_preview_nodes(state, self.peek_drag_preview())
    _ => state
  }
}

///|
fn CanvasRuntime::pointer_move(
  self : CanvasRuntime,
  sx : Double,
  sy : Double,
) -> Unit {
  let state = self.state_peek()
  match state.interaction.connecting {
    Some(_) => self.sync_connect_move(state, sx, sy)
    None =>
      match state.interaction.dragging {
        Some(drag) => self.sync_drag_preview_move(state, drag, sx, sy)
        None =>
          match state.interaction.panning {
            Some(_) => self.sync_pan_move(state, sx, sy)
            None => ()
          }
      }
  }
}

///|
fn CanvasRuntime::pointer_up(
  self : CanvasRuntime,
  node_id : String,
  target_port_id : String,
  additive : Bool,
) -> Unit {
  self.sync_commit_state(
    @graph_model.update_pointer_up(
      self.state_with_active_drag_preview(self.state_peek()),
      node_id,
      target_port_id,
      additive,
    ),
  )
}

///|
fn CanvasRuntime::zoom(
  self : CanvasRuntime,
  delta : Double,
  cx : Double,
  cy : Double,
) -> Unit {
  self.sync_action_viewport_state(
    @graph_model.update_zoom(self.state_peek(), delta, cx, cy),
  )
}

///|
fn CanvasRuntime::hover_node(self : CanvasRuntime, node_id : String) -> Unit {
  let hovered : NodeId? = if node_id == "" {
    None
  } else {
    Some(NodeId(node_id))
  }
  self.set_hover(hovered)
}

///|
fn CanvasRuntime::add_node(
  self : CanvasRuntime,
  kind_key : String,
  sx : Double,
  sy : Double,
) -> Unit {
  let state = self.state_peek()
  let (wx, wy) = @graph_model.screen_to_world(state.viewport, sx, sy)
  self.sync_document_action_state(
    (self.policy.add_node)(state, kind_key, wx, wy),
  )
}

///|
fn CanvasRuntime::delete_nodes(
  self : CanvasRuntime,
  nodes : Array[NodeId],
) -> Unit {
  self.sync_commit_state(
    @graph_model.record_action(self.state_peek(), DeleteNodes(nodes)),
  )
}

///|
fn CanvasRuntime::disconnect_ports(
  self : CanvasRuntime,
  source : NodeId,
  source_port : String,
  target : NodeId,
  target_port : String,
) -> Unit {
  self.sync_document_action_state(
    @graph_model.record_action(
      self.state_peek(),
      DisconnectPorts(source, source_port, target, target_port),
    ),
  )
}

///|
fn input_port_compatibility_for_state(
  state : CanvasState,
  source : NodeId,
  source_port : String,
) -> Array[PortCompatibilityJson] {
  state.nodes
  .iter()
  .flat_map(fn(node) {
    node.inputs
    .iter()
    .map(fn(port) {
      {
        node_id: node.id.to_string(),
        port_id: port.id,
        compatible: @graph_model.can_commit_edge(
          state,
          source,
          source_port,
          node.id,
          port.id,
        ),
      }
    })
  })
  .to_array()
}

///|
fn CanvasRuntime::input_port_compatibility(
  self : CanvasRuntime,
  source : NodeId,
  source_port : String,
) -> Array[PortCompatibilityJson] {
  input_port_compatibility_for_state(self.state_peek(), source, source_port)
}

///|
fn CanvasRuntime::render_state(self : CanvasRuntime) -> RenderStateJson {
  self.policy.render_state_from_parts(
    self.read_full_render(),
    self.read_inspector(),
  )
}

///|
fn CanvasRuntime::action_log_json(self : CanvasRuntime) -> String {
  self.action_log_snapshot().to_json().stringify()
}
