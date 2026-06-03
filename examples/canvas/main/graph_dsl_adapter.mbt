///|
fn default_source_graph_viewport() -> Viewport {
  { x: 360.0, y: 330.0, scale: 1.0 }
}

///|
struct SourceNodePosition {
  binding : String
  x : Double
  y : Double
}

///|
struct SourceBackedGraph {
  attachment : @graph_dsl.GraphAttachment
  mut source : String
  mut viewport : Viewport
  mut interaction : InteractionState
  mut drag_preview : DragPreview
  mut layout : Array[SourceNodePosition]
  mut action_log : Array[GraphOperation]
}

///|
fn SourceBackedGraph::SourceBackedGraph(source : String) -> SourceBackedGraph {
  {
    attachment: @graph_dsl.GraphAttachment::GraphAttachment(source),
    source,
    viewport: default_source_graph_viewport(),
    interaction: @graph_model.empty_interaction(),
    drag_preview: idle_drag_preview(),
    layout: [],
    action_log: [],
  }
}

///|
fn SourceBackedGraph::dispose(self : SourceBackedGraph) -> Unit {
  self.attachment.dispose()
}

///|
let _source_registry : Array[SourceBackedGraph?] = []

///|
fn source_graph_by_handle(handle : Int) -> SourceBackedGraph? {
  if handle < 0 || handle >= _source_registry.length() {
    None
  } else {
    _source_registry[handle]
  }
}

///|
fn empty_source_canvas_state() -> CanvasState {
  {
    viewport: default_source_graph_viewport(),
    nodes: [],
    edges: [],
    next_node_id: 1,
    next_edge_id: 1,
    interaction: @graph_model.empty_interaction(),
    action_log: [],
  }
}

///|
fn graph_input_reference(param : @graph_dsl.GraphParam) -> String? {
  for token in param.value_tokens() {
    if token.role() == @graph_dsl.InputReference {
      return Some(token.text())
    }
  }
  None
}

///|
fn canvas_id_for_binding(
  doc : @graph_dsl.GraphDoc,
  binding : String,
) -> NodeId? {
  for i, node in doc.nodes() {
    if node.binding() == binding {
      return Some(NodeId(i + 1))
    }
  }
  None
}

///|
fn graph_node_for_canvas_id(
  doc : @graph_dsl.GraphDoc,
  id : NodeId,
) -> @graph_dsl.GraphNode? {
  let NodeId(raw_id) = id
  let index = raw_id - 1
  let nodes = doc.nodes()
  if index < 0 || index >= nodes.length() {
    None
  } else {
    Some(nodes[index])
  }
}

///|
fn canvas_node_from_graph_node(
  index : Int,
  graph_node : @graph_dsl.GraphNode,
) -> CanvasNode {
  {
    id: NodeId(index + 1),
    x: index.to_double() * 300.0,
    y: 0.0,
    w: 250.0,
    h: 138.0,
    kind: Workflow(Custom(graph_node.constructor_name())),
    title: graph_node.binding(),
    subtitle: graph_node.constructor_name(),
    inputs: [@graph_model.port("input", "input", Any)],
    outputs: [@graph_model.port("out", "out", Any)],
    configured: true,
  }
}

///|
fn source_layout_for_binding(
  layout : Array[SourceNodePosition],
  binding : String,
) -> SourceNodePosition? {
  for position in layout {
    if position.binding == binding {
      return Some(position)
    }
  }
  None
}

///|
fn canvas_node_with_source_layout(
  node : CanvasNode,
  layout : Array[SourceNodePosition],
) -> CanvasNode {
  match source_layout_for_binding(layout, node.title) {
    Some(position) => { ..node, x: position.x, y: position.y }
    None => node
  }
}

///|
fn canvas_state_with_source_layout(
  state : CanvasState,
  layout : Array[SourceNodePosition],
) -> CanvasState {
  let nodes : Array[CanvasNode] = []
  for node in state.nodes {
    nodes.push(canvas_node_with_source_layout(node, layout))
  }
  { ..state, nodes, }
}

///|
fn canvas_from_graph_doc(doc : @graph_dsl.GraphDoc) -> CanvasState {
  let nodes : Array[CanvasNode] = []
  for i, graph_node in doc.nodes() {
    nodes.push(canvas_node_from_graph_node(i, graph_node))
  }
  let edges : Array[Edge] = []
  for target_index, graph_node in doc.nodes() {
    for param in graph_node.params() {
      match graph_input_reference(param) {
        None => ()
        Some(source_binding) =>
          match canvas_id_for_binding(doc, source_binding) {
            None => ()
            Some(source) =>
              edges.push({
                id: EdgeId(edges.length() + 1),
                source,
                source_port: "out",
                target: NodeId(target_index + 1),
                target_port: param.name(),
              })
          }
      }
    }
  }
  {
    viewport: { x: 0.0, y: 0.0, scale: 1.0 },
    nodes,
    edges,
    next_node_id: nodes.length() + 1,
    next_edge_id: edges.length() + 1,
    interaction: @graph_model.empty_interaction(),
    action_log: [],
  }
}

///|
fn source_graph_doc_for_render(
  graph : SourceBackedGraph,
) -> @graph_dsl.GraphDoc? {
  match graph.attachment.current_result() {
    Ok(doc) => Some(doc)
    Err(_) => graph.attachment.last_good()
  }
}

///|
fn source_graph_base_canvas_state(graph : SourceBackedGraph) -> CanvasState {
  match source_graph_doc_for_render(graph) {
    Some(doc) => {
      let state = canvas_state_with_source_layout(
        canvas_from_graph_doc(doc),
        graph.layout,
      )
      {
        ..state,
        viewport: graph.viewport,
        interaction: graph.interaction,
        action_log: graph.action_log.copy(),
      }
    }
    None => { ..empty_source_canvas_state(), viewport: graph.viewport }
  }
}

///|
fn source_graph_canvas_state(graph : SourceBackedGraph) -> CanvasState {
  let state = source_graph_base_canvas_state(graph)
  match graph.interaction.dragging {
    Some(_) if graph.interaction.did_move =>
      state_with_preview_nodes(state, graph.drag_preview)
    _ => state
  }
}

///|
fn source_graph_validation(graph : SourceBackedGraph) -> Array[ValidationJson] {
  let messages : Array[ValidationJson] = []
  for message in graph.attachment.diagnostics() {
    messages.push({ severity: "error", message, node_id: None })
  }
  messages
}

///|
struct SourceGraphOperationResultJson {
  applied : Bool
  source : String
  diagnostics : Array[String]
  action_count : Int
  message : String?
} derive(ToJson, FromJson)

///|
fn source_graph_operation_result_json(
  applied : Bool,
  source : String,
  diagnostics : Array[String],
  action_count : Int,
  message : String?,
) -> SourceGraphOperationResultJson {
  { applied, source, diagnostics, action_count, message }
}

///|
fn source_graph_operation_result(
  applied : Bool,
  source : String,
  diagnostics : Array[String],
  action_count : Int,
  message : String?,
) -> String {
  source_graph_operation_result_json(
    applied, source, diagnostics, action_count, message,
  )
  .to_json()
  .stringify()
}

///|
fn source_graph_result_json_for_graph(
  graph : SourceBackedGraph,
  applied : Bool,
  message : String?,
) -> SourceGraphOperationResultJson {
  source_graph_operation_result_json(
    applied,
    graph.source,
    graph.attachment.diagnostics(),
    graph.action_log.length(),
    message,
  )
}

///|
fn source_graph_result_for_graph(
  graph : SourceBackedGraph,
  applied : Bool,
  message : String?,
) -> String {
  source_graph_result_json_for_graph(graph, applied, message)
  .to_json()
  .stringify()
}

///|
fn decode_graph_operation(json_text : String) -> Result[GraphOperation, String] {
  let json = @json.parse(json_text) catch {
    _ => return Err("operation JSON parse failed")
  }
  let operation : GraphOperation = @json.from_json(json) catch {
    _ => return Err("operation JSON decode failed")
  }
  Ok(operation)
}

///|
fn source_graph_current_doc(
  graph : SourceBackedGraph,
) -> Result[@graph_dsl.GraphDoc, String] {
  match graph.attachment.current_result() {
    Ok(doc) => Ok(doc)
    Err(message) => Err("current source is not graph-valid: " + message)
  }
}

///|
fn lower_source_operation(
  doc : @graph_dsl.GraphDoc,
  operation : GraphOperation,
) -> Result[SourceOperationEdit, String] {
  match operation.action() {
    AddNode(node) =>
      match doc.lower_insert_node_binding(node.title, node.subtitle) {
        Some(edit) => Ok(ExactLoweredEdit(edit))
        None =>
          Err(
            "cannot lower AddNode for binding '" +
            node.title +
            "' and constructor '" +
            node.subtitle +
            "'",
          )
      }
    ConnectPorts(source, source_port, target, target_port) => {
      if source_port != "out" {
        return Err("graph-dsl source connections must use port 'out'")
      }
      if target_port != "input" {
        return Err("graph-dsl target connections must use port 'input'")
      }
      let source_node = match graph_node_for_canvas_id(doc, source) {
        Some(node) => node
        None => return Err("cannot lower ConnectPorts: missing source node")
      }
      let target_node = match graph_node_for_canvas_id(doc, target) {
        Some(node) => node
        None => return Err("cannot lower ConnectPorts: missing target node")
      }
      match
        doc.lower_add_connection(target_node.binding(), source_node.binding()) {
        Some(edit) => Ok(ExactLoweredEdit(edit))
        None => Err("cannot lower ConnectPorts into source")
      }
    }
    DeleteNodes(nodes) => lower_delete_nodes(doc, nodes)
    DisconnectPorts(source, source_port, target, target_port) =>
      lower_disconnect_ports(doc, source, source_port, target, target_port)
    MoveNodes(_) =>
      Err("MoveNodes is local layout state; source lowering is not defined")
    SelectNodes(_) =>
      Err(
        "SelectNodes is local selection state; source lowering is not defined",
      )
    SetViewport(_) =>
      Err("SetViewport is local viewport state; source lowering is not defined")
  }
}

///|
fn SourceBackedGraph::apply_source_edit(
  self : SourceBackedGraph,
  edit : SourceOperationEdit,
) -> Result[@graph_dsl.GraphDoc, String] {
  let old_source = self.source
  let new_source = match edit {
    ExactLoweredEdit(edit) => {
      let new_source = edit.new_source()
      match edit.incremental_edit() {
        Some(incremental_edit) =>
          self.attachment.apply_edit(incremental_edit, new_source)
        None => self.attachment.set_source(new_source)
      }
      new_source
    }
    WholeSourceReplacement(new_source) => {
      self.attachment.set_source(new_source)
      new_source
    }
  }
  self.source = new_source
  match self.attachment.current_result() {
    Ok(doc) => Ok(doc)
    Err(message) => {
      self.source = old_source
      self.attachment.set_source(old_source)
      Err(message)
    }
  }
}

///|
fn realized_source_operation(
  doc : @graph_dsl.GraphDoc,
  operation : GraphOperation,
) -> GraphOperation {
  match operation.action() {
    AddNode(node) =>
      match canvas_id_for_binding(doc, node.title) {
        Some(id) => GraphOperation(AddNode({ ..node, id, }))
        None => operation
      }
    _ => operation
  }
}

///|
fn SourceBackedGraph::append_operation(
  self : SourceBackedGraph,
  operation : GraphOperation,
) -> Unit {
  self.action_log.push(operation)
}

///|
fn source_delete_surviving_selection_bindings(
  doc : @graph_dsl.GraphDoc,
  interaction : InteractionState,
  deleted : Array[NodeId],
) -> Array[String] {
  let bindings : Array[String] = []
  for node_id in interaction.selected_nodes {
    if !@graph_model.node_id_in_array(deleted, node_id) {
      match graph_node_for_canvas_id(doc, node_id) {
        Some(node) => append_unique_string(bindings, node.binding())
        None => ()
      }
    }
  }
  bindings
}

///|
fn source_selection_from_bindings(
  doc : @graph_dsl.GraphDoc,
  bindings : Array[String],
) -> Array[NodeId] {
  let nodes : Array[NodeId] = []
  for binding in bindings {
    match canvas_id_for_binding(doc, binding) {
      Some(id) => nodes.push(id)
      None => ()
    }
  }
  nodes
}

///|
fn SourceBackedGraph::remap_deleted_interaction(
  self : SourceBackedGraph,
  doc : @graph_dsl.GraphDoc,
  survivor_bindings : Array[String],
) -> Unit {
  let selected_nodes = source_selection_from_bindings(doc, survivor_bindings)
  let selected = if selected_nodes.length() == 0 {
    None
  } else {
    Some(selected_nodes[0])
  }
  self.drag_preview = idle_drag_preview()
  self.interaction = {
    dragging: None,
    panning: None,
    connecting: None,
    selected,
    selected_nodes,
    pointer_down: false,
    did_move: false,
  }
}

///|
fn SourceBackedGraph::sync_local_operation_state(
  self : SourceBackedGraph,
  doc : @graph_dsl.GraphDoc,
  operation : GraphOperation,
  survivor_selection_bindings : Array[String],
) -> Unit {
  match operation.action() {
    DeleteNodes(_) => {
      self.remap_deleted_interaction(doc, survivor_selection_bindings)
      self.sync_layout_from_state(source_graph_base_canvas_state(self))
    }
    _ => ()
  }
}

///|
fn SourceBackedGraph::sync_layout_from_state(
  self : SourceBackedGraph,
  state : CanvasState,
) -> Unit {
  let layout : Array[SourceNodePosition] = []
  for node in state.nodes {
    layout.push({ binding: node.title, x: node.x, y: node.y })
  }
  self.layout = layout
}

///|
fn SourceBackedGraph::pointer_down(
  self : SourceBackedGraph,
  node_id : Int,
  sx : Double,
  sy : Double,
) -> Unit {
  let target : NodeId? = if node_id <= 0 { None } else { Some(NodeId(node_id)) }
  let state = update_pointer_down(
    source_graph_base_canvas_state(self),
    target,
    sx,
    sy,
  )
  self.drag_preview = idle_drag_preview()
  self.interaction = state.interaction
}

///|
fn SourceBackedGraph::pointer_move(
  self : SourceBackedGraph,
  sx : Double,
  sy : Double,
) -> Unit {
  let state = source_graph_base_canvas_state(self)
  match state.interaction.connecting {
    Some(_) => {
      let (wx, wy) = screen_to_world(state.viewport, sx, sy)
      self.interaction = update_connect_move(state, wx, wy).interaction
    }
    None =>
      match state.interaction.dragging {
        Some(drag) => {
          let (wx, wy) = screen_to_world(state.viewport, sx, sy)
          let new_interaction : InteractionState = {
            ..state.interaction,
            did_move: true,
          }
          self.drag_preview = drag_preview_from_move(drag, wx, wy)
          self.interaction = new_interaction
        }
        None =>
          match state.interaction.panning {
            Some(_) => {
              let next = update_pan_move(state, sx, sy)
              self.viewport = next.viewport
              self.interaction = next.interaction
            }
            None => ()
          }
      }
  }
}

///|
fn SourceBackedGraph::pointer_up(
  self : SourceBackedGraph,
  node_id : Int,
  target_port_id : String,
  additive : Bool,
) -> Unit {
  let state = source_graph_base_canvas_state(self)
  let commit_state = match state.interaction.dragging {
    Some(_) if state.interaction.did_move =>
      state_with_preview_nodes(state, self.drag_preview)
    _ => state
  }
  let next = update_pointer_up(commit_state, node_id, target_port_id, additive)
  self.sync_layout_from_state(next)
  self.viewport = next.viewport
  self.drag_preview = idle_drag_preview()
  self.interaction = next.interaction
  self.action_log = next.action_log.copy()
}

///|
fn SourceBackedGraph::zoom(
  self : SourceBackedGraph,
  delta : Double,
  cx : Double,
  cy : Double,
) -> Unit {
  let next = update_zoom(source_graph_base_canvas_state(self), delta, cx, cy)
  self.viewport = next.viewport
  self.action_log = next.action_log.copy()
}

///|
fn source_graph_node_payload(
  binding : String,
  constructor_name : String,
) -> CanvasNode {
  {
    id: NodeId(0),
    x: 0.0,
    y: 0.0,
    w: 250.0,
    h: 138.0,
    kind: Workflow(Custom(constructor_name)),
    title: binding,
    subtitle: constructor_name,
    inputs: [],
    outputs: [],
    configured: true,
  }
}

///|
fn next_source_binding(doc : @graph_dsl.GraphDoc, base : String) -> String {
  if doc.find_node(base) is None {
    return base
  }
  for suffix = 2 {
    let candidate = base + suffix.to_string()
    if doc.find_node(candidate) is None {
      break candidate
    }
    continue suffix + 1
  }
}

///|
fn source_graph_insert_unique_result(
  handle : Int,
  binding_base : String,
  constructor_name : String,
) -> SourceGraphOperationResultJson {
  let graph = match source_graph_by_handle(handle) {
    Some(graph) => graph
    None =>
      return source_graph_operation_result_json(
        false,
        "",
        ["source graph handle not found"],
        0,
        Some("source graph handle not found"),
      )
  }
  let doc = match source_graph_current_doc(graph) {
    Ok(doc) => doc
    Err(message) =>
      return source_graph_result_json_for_graph(graph, false, Some(message))
  }
  let binding = next_source_binding(doc, binding_base)
  let operation = GraphOperation(
    AddNode(source_graph_node_payload(binding, constructor_name)),
  )
  let result_json = apply_source_graph_operation(
    handle,
    operation.to_json().stringify(),
  )
  let json = @json.parse(result_json) catch {
    _ =>
      return source_graph_result_json_for_graph(
        graph,
        false,
        Some("source graph operation result JSON parse failed"),
      )
  }
  let result : SourceGraphOperationResultJson = @json.from_json(json) catch {
    _ =>
      return source_graph_result_json_for_graph(
        graph,
        false,
        Some("source graph operation result JSON decode failed"),
      )
  }
  result
}

///|
fn source_graph_connect_sample_result(
  handle : Int,
) -> SourceGraphOperationResultJson {
  let result_json = apply_source_graph_operation(
    handle,
    GraphOperation(ConnectPorts(NodeId(1), "out", NodeId(2), "input"))
    .to_json()
    .stringify(),
  )
  let json = @json.parse(result_json) catch {
    _ =>
      return source_graph_operation_result_json(
        false,
        "",
        ["source graph operation result JSON parse failed"],
        0,
        Some("source graph operation result JSON parse failed"),
      )
  }
  let result : SourceGraphOperationResultJson = @json.from_json(json) catch {
    _ =>
      return source_graph_operation_result_json(
        false,
        "",
        ["source graph operation result JSON decode failed"],
        0,
        Some("source graph operation result JSON decode failed"),
      )
  }
  result
}

///|
pub fn source_graph_insert_unique(
  handle : Int,
  binding_base : String,
  constructor_name : String,
) -> String {
  source_graph_insert_unique_result(handle, binding_base, constructor_name)
  .to_json()
  .stringify()
}

///|
pub fn sample_graph_dsl_source() -> String {
  "osc = sine(freq: 440Hz)\nmeter = scope()"
}

///|
pub fn create_source_graph(source : String) -> Int {
  _source_registry.push(Some(SourceBackedGraph(source)))
  _source_registry.length() - 1
}

///|
pub fn destroy_source_graph(handle : Int) -> Unit {
  match source_graph_by_handle(handle) {
    Some(graph) => graph.dispose()
    None => ()
  }
  if handle >= 0 && handle < _source_registry.length() {
    _source_registry[handle] = None
  }
}

///|
pub fn get_source_graph_source(handle : Int) -> String {
  match source_graph_by_handle(handle) {
    Some(graph) => graph.source
    None => ""
  }
}

///|
fn set_source_graph_source_checked(
  handle : Int,
  source : String,
) -> SourceGraphOperationResultJson {
  let graph = match source_graph_by_handle(handle) {
    Some(graph) => graph
    None =>
      return source_graph_operation_result_json(
        false,
        "",
        ["source graph handle not found"],
        0,
        Some("source graph handle not found"),
      )
  }
  graph.source = source
  graph.attachment.set_source(source)
  match source_graph_current_doc(graph) {
    Ok(_) => source_graph_result_json_for_graph(graph, true, None)
    Err(message) =>
      source_graph_result_json_for_graph(graph, false, Some(message))
  }
}

///|
pub fn set_source_graph_source(handle : Int, source : String) -> Unit {
  ignore(set_source_graph_source_checked(handle, source))
}

///|
pub fn set_source_graph_source_result(handle : Int, source : String) -> String {
  set_source_graph_source_checked(handle, source).to_json().stringify()
}

///|
pub fn source_graph_pointer_down(
  handle : Int,
  node_id : Int,
  sx : Double,
  sy : Double,
) -> Unit {
  match source_graph_by_handle(handle) {
    Some(graph) => graph.pointer_down(node_id, sx, sy)
    None => ()
  }
}

///|
pub fn source_graph_pointer_move(
  handle : Int,
  sx : Double,
  sy : Double,
) -> Unit {
  match source_graph_by_handle(handle) {
    Some(graph) => graph.pointer_move(sx, sy)
    None => ()
  }
}

///|
pub fn source_graph_pointer_up(
  handle : Int,
  node_id : Int,
  target_port_id : String,
  additive : Bool,
) -> Unit {
  match source_graph_by_handle(handle) {
    Some(graph) => graph.pointer_up(node_id, target_port_id, additive)
    None => ()
  }
}

///|
pub fn source_graph_zoom(
  handle : Int,
  delta : Double,
  cx : Double,
  cy : Double,
) -> Unit {
  match source_graph_by_handle(handle) {
    Some(graph) => graph.zoom(delta, cx, cy)
    None => ()
  }
}

///|
pub fn get_source_graph_render_state(handle : Int) -> String {
  match source_graph_by_handle(handle) {
    Some(graph) => {
      let state = source_graph_canvas_state(graph)
      render_state_string(state, source_graph_validation(graph))
    }
    None =>
      render_state_string(empty_source_canvas_state(), [
        {
          severity: "error",
          message: "source graph handle not found",
          node_id: None,
        },
      ])
  }
}

///|
pub fn get_source_graph_action_log(handle : Int) -> String {
  match source_graph_by_handle(handle) {
    Some(graph) => graph.action_log.to_json().stringify()
    None => ([] : Array[GraphOperation]).to_json().stringify()
  }
}

///|
pub fn apply_source_graph_operation(
  handle : Int,
  operation_json : String,
) -> String {
  let graph = match source_graph_by_handle(handle) {
    Some(graph) => graph
    None =>
      return source_graph_operation_result(
        false,
        "",
        ["source graph handle not found"],
        0,
        Some("source graph handle not found"),
      )
  }
  let operation = match decode_graph_operation(operation_json) {
    Ok(operation) => operation
    Err(message) =>
      return source_graph_result_for_graph(graph, false, Some(message))
  }
  let doc = match source_graph_current_doc(graph) {
    Ok(doc) => doc
    Err(message) =>
      return source_graph_result_for_graph(graph, false, Some(message))
  }
  let survivor_selection_bindings = match operation.action() {
    DeleteNodes(deleted) =>
      source_delete_surviving_selection_bindings(
        doc,
        graph.interaction,
        deleted,
      )
    _ => []
  }
  let lowered = match lower_source_operation(doc, operation) {
    Ok(edit) => edit
    Err(message) =>
      return source_graph_result_for_graph(graph, false, Some(message))
  }
  match graph.apply_source_edit(lowered) {
    Ok(doc) => {
      graph.sync_local_operation_state(
        doc, operation, survivor_selection_bindings,
      )
      graph.append_operation(realized_source_operation(doc, operation))
      source_graph_result_for_graph(graph, true, None)
    }
    Err(message) => source_graph_result_for_graph(graph, false, Some(message))
  }
}
