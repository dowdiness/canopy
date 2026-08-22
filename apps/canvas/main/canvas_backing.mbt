///|
/// One private handle namespace for workflow and source-backed canvases.
/// The payload keeps the canonical state owner explicit without making either
/// backing implement a broad public canvas abstraction.
priv enum CanvasBacking {
  Runtime(CanvasRuntime)
  Source(SourceBackedGraph)
}

///|
let canvas_instances : Array[CanvasBacking?] = []

///|
/// Return the live backing at a handle without conflating an empty slot with a
/// different backing kind.
fn canvas_backing(handle : Int) -> CanvasBacking? {
  canvas_instances.get(handle).bind(backing => backing)
}

///|
/// Runtime-only public entry points historically indexed their registry
/// directly. Keep their out-of-range failure behavior while rejecting a valid
/// source or destroyed slot instead of interpreting it as a runtime.
fn canvas_runtime_for_public(handle : Int) -> CanvasRuntime? {
  match canvas_backing(handle) {
    Some(Runtime(runtime)) => Some(runtime)
    Some(Source(_)) => None
    None => {
      if handle < 0 || handle >= canvas_instances.length() {
        ignore(canvas_instances[handle])
      }
      None
    }
  }
}

///|
fn CanvasBacking::state(self : CanvasBacking) -> CanvasState {
  match self {
    Runtime(runtime) => runtime.state_peek()
    Source(graph) => source_graph_base_canvas_state(graph)
  }
}

///|
fn CanvasBacking::select_edge(self : CanvasBacking, edge : EdgeId) -> Unit {
  match self {
    Runtime(runtime) => runtime.select_edge(edge)
    Source(graph) => graph.select_edge(edge)
  }
}

///|
fn CanvasBacking::clear_selected_edge(self : CanvasBacking) -> Unit {
  match self {
    Runtime(runtime) => runtime.clear_selected_edge()
    Source(graph) => graph.clear_selected_edge()
  }
}

///|
fn CanvasBacking::pointer_down_handle(
  self : CanvasBacking,
  node_id : NodeId,
  port_id : String,
  sx : Double,
  sy : Double,
) -> Bool {
  match self {
    Runtime(runtime) => runtime.pointer_down_handle(node_id, port_id, sx, sy)
    Source(graph) => graph.pointer_down_handle(node_id, port_id, sx, sy)
  }
}

///|
fn CanvasBacking::pointer_down(
  self : CanvasBacking,
  node_id : NodeId?,
  sx : Double,
  sy : Double,
) -> Bool {
  match self {
    Runtime(runtime) => runtime.pointer_down(node_id, sx, sy)
    Source(graph) => {
      let source_node_id = match node_id {
        Some(node_id) => node_id.to_string()
        None => ""
      }
      graph.pointer_down(source_node_id, sx, sy)
    }
  }
}

///|
fn CanvasBacking::pointer_move(
  self : CanvasBacking,
  sx : Double,
  sy : Double,
) -> Unit {
  match self {
    Runtime(runtime) => runtime.pointer_move(sx, sy)
    Source(graph) => graph.pointer_move(sx, sy)
  }
}

///|
fn CanvasBacking::pointer_up(
  self : CanvasBacking,
  node_id : String,
  target_port_id : String,
  additive : Bool,
) -> Unit {
  match self {
    Runtime(runtime) => runtime.pointer_up(node_id, target_port_id, additive)
    Source(graph) => graph.pointer_up(node_id, target_port_id, additive)
  }
}

///|
fn CanvasBacking::pointer_interrupt(self : CanvasBacking) -> Unit {
  match self {
    Runtime(runtime) => runtime.pointer_interrupt()
    Source(graph) => graph.pointer_interrupt()
  }
}

///|
fn CanvasBacking::zoom(
  self : CanvasBacking,
  delta_y : Double,
  delta_mode : Int,
  ctrl_key : Bool,
  cx : Double,
  cy : Double,
) -> Unit {
  match self {
    Runtime(runtime) => runtime.zoom(delta_y, delta_mode, ctrl_key, cx, cy)
    Source(graph) => graph.zoom(delta_y, delta_mode, ctrl_key, cx, cy)
  }
}

///|
/// Workflow hover is a runtime-only ephemeral concern. A source-backed graph
/// deliberately ignores it because its inspector is driven by source-backed
/// selection and parser state.
fn CanvasBacking::hover_node(self : CanvasBacking, node_id : String) -> Bool {
  match self {
    Runtime(runtime) => {
      runtime.hover_node(node_id)
      true
    }
    Source(_) => false
  }
}

///|
fn CanvasBacking::render_state_json(self : CanvasBacking) -> String {
  match self {
    Runtime(runtime) => runtime.render_state().to_json().stringify()
    Source(graph) => graph.render_state_json()
  }
}
