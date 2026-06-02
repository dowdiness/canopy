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
  selected : Int?
  selected_nodes : Array[Int]
  connecting : ConnectingJson?
  validation : Array[ValidationJson]
  action_count : Int
} derive(Eq)

///|
fn validate_canvas_document(document : CanvasDocument) -> ValidatedCanvas {
  {
    document: {
      nodes: document.nodes.copy(),
      edges: document.edges.copy(),
      next_node_id: document.next_node_id,
      next_edge_id: document.next_edge_id,
    },
    validation: validate_workflow(
      canvas_state_from_parts(
        document,
        default_viewport(),
        @graph_model.empty_interaction(),
        [],
      ),
    ),
  }
}

///|
fn normalize_canvas(validated : ValidatedCanvas) -> NormalizedCanvas {
  {
    document: {
      nodes: validated.document.nodes.copy(),
      edges: validated.document.edges.copy(),
      next_node_id: validated.document.next_node_id,
      next_edge_id: validated.document.next_edge_id,
    },
    validation: validated.validation.copy(),
  }
}

///|
fn lower_canvas(normalized : NormalizedCanvas) -> LoweredCanvas {
  {
    nodes: normalized.document.nodes.map(node_to_json),
    edges: normalized.document.edges.map(edge_to_json),
    validation: normalized.validation.copy(),
  }
}

///|
fn preview_position_for(preview : DragPreview, node_id : Int) -> NodePosition? {
  find_position(preview.positions, NodeId(node_id))
}

///|
fn render_node_with_preview(node : NodeJson, preview : DragPreview) -> NodeJson {
  match preview_position_for(preview, node.id) {
    None => node
    Some(pos) => { ..node, x: pos.x, y: pos.y }
  }
}

///|
fn canvas_node_with_preview(
  node : CanvasNode,
  preview : DragPreview,
) -> CanvasNode {
  match preview_position_for(preview, node_id_to_int(node.id)) {
    None => node
    Some(pos) => { ..node, x: pos.x, y: pos.y }
  }
}

///|
fn state_with_preview_nodes(
  state : CanvasState,
  preview : DragPreview,
) -> CanvasState {
  {
    ..state,
    nodes: state.nodes.map(fn(node) { canvas_node_with_preview(node, preview) }),
  }
}

///|
fn connecting_to_json(connecting : ConnectState?) -> ConnectingJson? {
  match connecting {
    None => None
    Some(c) => {
      let NodeId(from) = c.from_node
      Some({
        from,
        from_port: c.from_port,
        cursor_x: c.cursor_x,
        cursor_y: c.cursor_y,
      })
    }
  }
}

///|
fn render_full_canvas(
  lowered : LoweredCanvas,
  viewport : Viewport,
  drag_preview : DragPreview,
  selection : SelectionState,
  interaction : InteractionState,
  action_count : Int,
) -> CanvasFullRenderJson {
  let selected : Int? = match selection.selected {
    None => None
    Some(id) => Some(node_id_to_int(id))
  }
  let selected_nodes = selection.selected_nodes.map(node_id_to_int)
  {
    viewport,
    nodes: lowered.nodes.map(fn(node) {
      render_node_with_preview(node, drag_preview)
    }),
    edges: lowered.edges.copy(),
    selected,
    selected_nodes,
    connecting: connecting_to_json(interaction.connecting),
    validation: lowered.validation.copy(),
    action_count,
  }
}

///|
fn inspector_node_for_document(
  document : CanvasDocument,
  node_id : Int,
) -> InspectorNodeJson? {
  match find_node(document.nodes, NodeId(node_id)) {
    None => None
    Some(node) =>
      Some({
        id: node_id,
        title: node.title,
        subtitle: node.subtitle,
        configured: node.configured,
        input_count: node.inputs.length(),
        output_count: node.outputs.length(),
        source: "",
      })
  }
}

///|
fn inspector_with_source(
  inspector : InspectorNodeJson?,
  source : String,
) -> InspectorNodeJson? {
  match inspector {
    None => None
    Some(node) => Some({ ..node, source, })
  }
}

///|
fn render_state_from_parts(
  full : CanvasFullRenderJson,
  inspector : InspectorNodeJson?,
) -> RenderStateJson {
  {
    viewport: full.viewport,
    nodes: full.nodes.copy(),
    edges: full.edges.copy(),
    selected: full.selected,
    selected_nodes: full.selected_nodes.copy(),
    connecting: full.connecting,
    validation: full.validation.copy(),
    action_count: full.action_count,
    inspector,
  }
}

///|
/// Incr-backed canvas model. Durable graph edits flow through `document`;
/// hover, drag preview, viewport, selection, and pointer gesture state are
/// independent Inputs so high-frequency UI changes avoid durable recomputation.
struct CanvasRuntime {
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
fn CanvasRuntime::CanvasRuntime() -> CanvasRuntime {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let initial = CanvasState::default()
  let document = scope.input(
    canvas_document_from_state(initial),
    label="canvas.document",
  )
  let actions = scope.input(
    initial.action_log.copy(),
    label="canvas.action_log",
  )
  let hover = scope.input(None, label="canvas.hover")
  let drag_preview = scope.input(
    idle_drag_preview(),
    label="canvas.drag_preview",
  )
  let viewport = scope.input(initial.viewport, label="canvas.viewport")
  let selection = scope.input(
    selection_from_interaction(initial.interaction),
    label="canvas.selection",
  )
  let interaction = scope.input(initial.interaction, label="canvas.gesture")

  let validated = scope.derived(
    () => validate_canvas_document(document.get()),
    label="canvas.validation",
  )
  let normalized = scope.derived(
    () => normalize_canvas(validated.get_or_abort()),
    label="canvas.normalization",
  )
  let lowered = scope.derived(
    () => lower_canvas(normalized.get_or_abort()),
    label="canvas.lowering",
  )
  let render = scope.derived(
    () => {
      render_full_canvas(
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
    (id : Int) => {
      inspector_node_for_document(normalized.get_or_abort().document, id)
    },
    label="canvas.inspector.node_by_id",
  )
  let inspector_scope = scope.child()
  let inspector = inspector_scope.reachable_derived(
    () => {
      let current_selection = selection.get()
      match current_selection.selected {
        Some(id) =>
          inspector_with_source(
            node_inspector.get_or_abort(node_id_to_int(id)),
            "selected",
          )
        None =>
          match hover.get() {
            None => None
            Some(id) =>
              inspector_with_source(
                node_inspector.get_or_abort(node_id_to_int(id)),
                "hovered",
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
  {
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
}

///|
fn CanvasRuntime::state_peek(self : CanvasRuntime) -> CanvasState {
  let interaction = interaction_with_selection(
    self.interaction.peek(),
    self.selection.peek(),
  )
  canvas_state_from_parts(
    self.document.peek(),
    self.viewport.peek(),
    interaction,
    self.actions.peek(),
  )
}

///|
fn CanvasRuntime::sync_commit_state(
  self : CanvasRuntime,
  state : CanvasState,
) -> Unit {
  self.document.set(canvas_document_from_state(state))
  self.viewport.set(state.viewport)
  self.drag_preview.set(idle_drag_preview())
  self.selection.set(selection_from_interaction(state.interaction))
  self.interaction.set(state.interaction)
  self.actions.set(state.action_log.copy())
}

///|
fn CanvasRuntime::sync_viewport_state(
  self : CanvasRuntime,
  state : CanvasState,
) -> Unit {
  self.viewport.set(state.viewport)
  self.interaction.set(state.interaction)
}

///|
fn CanvasRuntime::sync_action_viewport_state(
  self : CanvasRuntime,
  state : CanvasState,
) -> Unit {
  self.viewport.set(state.viewport)
  self.actions.set(state.action_log.copy())
}

///|
fn CanvasRuntime::sync_document_action_state(
  self : CanvasRuntime,
  state : CanvasState,
) -> Unit {
  self.document.set(canvas_document_from_state(state))
  self.actions.set(state.action_log.copy())
}

///|
fn CanvasRuntime::pointer_down(
  self : CanvasRuntime,
  node_id : NodeId?,
  sx : Double,
  sy : Double,
) -> Unit {
  let state = update_pointer_down(self.state_peek(), node_id, sx, sy)
  self.drag_preview.set(idle_drag_preview())
  self.interaction.set(state.interaction)
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
  let (wx, wy) = screen_to_world(state.viewport, sx, sy)
  self.interaction.set(
    update_connect_start(state, node_id, port_id, wx, wy).interaction,
  )
}

///|
fn CanvasRuntime::pointer_move(
  self : CanvasRuntime,
  sx : Double,
  sy : Double,
) -> Unit {
  let state = self.state_peek()
  match state.interaction.connecting {
    Some(_) => {
      let (wx, wy) = screen_to_world(state.viewport, sx, sy)
      self.interaction.set(update_connect_move(state, wx, wy).interaction)
    }
    None =>
      match state.interaction.dragging {
        Some(drag) => {
          let (wx, wy) = screen_to_world(state.viewport, sx, sy)
          let new_interaction : InteractionState = {
            ..state.interaction,
            did_move: true,
          }
          self.drag_preview.set(drag_preview_from_move(drag, wx, wy))
          self.interaction.set(new_interaction)
        }
        None =>
          match state.interaction.panning {
            Some(_) => self.sync_viewport_state(update_pan_move(state, sx, sy))
            None => ()
          }
      }
  }
}

///|
fn CanvasRuntime::pointer_up(
  self : CanvasRuntime,
  node_id : Int,
  target_port_id : String,
  additive : Bool,
) -> Unit {
  let state = self.state_peek()
  let commit_state = match state.interaction.dragging {
    Some(_) if state.interaction.did_move =>
      state_with_preview_nodes(state, self.drag_preview.peek())
    _ => state
  }
  self.sync_commit_state(
    update_pointer_up(commit_state, node_id, target_port_id, additive),
  )
}

///|
fn CanvasRuntime::zoom(
  self : CanvasRuntime,
  delta : Double,
  cx : Double,
  cy : Double,
) -> Unit {
  self.sync_action_viewport_state(update_zoom(self.state_peek(), delta, cx, cy))
}

///|
fn CanvasRuntime::hover_node(self : CanvasRuntime, node_id : Int) -> Unit {
  let hovered : NodeId? = if node_id <= 0 {
    None
  } else {
    Some(NodeId(node_id))
  }
  self.hover.set(hovered)
}

///|
fn CanvasRuntime::add_node(
  self : CanvasRuntime,
  kind_key : String,
  sx : Double,
  sy : Double,
) -> Unit {
  let state = self.state_peek()
  let (wx, wy) = screen_to_world(state.viewport, sx, sy)
  self.sync_document_action_state(workflow_add_node(state, kind_key, wx, wy))
}

///|
fn CanvasRuntime::render_state(self : CanvasRuntime) -> RenderStateJson {
  render_state_from_parts(
    self.render_watch.read_or_abort(),
    self.inspector_watch.read_or_abort(),
  )
}

///|
fn CanvasRuntime::action_log_json(self : CanvasRuntime) -> String {
  self.actions.peek().to_json().stringify()
}
