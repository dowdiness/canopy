///|
struct SourceBackedGraph {
  attachment : @graph_dsl.GraphAttachment
  mut source : String
  viewport : Viewport
  interaction : InteractionState
  action_log : Array[GraphOperation]
}

///|
fn SourceBackedGraph::SourceBackedGraph(source : String) -> SourceBackedGraph {
  {
    attachment: @graph_dsl.GraphAttachment::GraphAttachment(source),
    source,
    viewport: { x: 0.0, y: 0.0, scale: 1.0 },
    interaction: @graph_model.empty_interaction(),
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
    viewport: { x: 0.0, y: 0.0, scale: 1.0 },
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
fn source_graph_canvas_state(graph : SourceBackedGraph) -> CanvasState {
  match source_graph_doc_for_render(graph) {
    Some(doc) => {
      let state = canvas_from_graph_doc(doc)
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
} derive(ToJson)

///|
fn source_graph_operation_result(
  applied : Bool,
  source : String,
  diagnostics : Array[String],
  action_count : Int,
  message : String?,
) -> String {
  (
    { applied, source, diagnostics, action_count, message } :
    SourceGraphOperationResultJson)
  .to_json()
  .stringify()
}

///|
fn source_graph_result_for_graph(
  graph : SourceBackedGraph,
  applied : Bool,
  message : String?,
) -> String {
  source_graph_operation_result(
    applied,
    graph.source,
    graph.attachment.diagnostics(),
    graph.action_log.length(),
    message,
  )
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
) -> Result[@graph_dsl.LoweredGraphEdit, String] {
  match operation.action() {
    AddNode(node) =>
      match doc.lower_insert_node_binding(node.title, node.subtitle) {
        Some(edit) => Ok(edit)
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
        Some(edit) => Ok(edit)
        None => Err("cannot lower ConnectPorts into source")
      }
    }
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
fn SourceBackedGraph::apply_lowered_edit(
  self : SourceBackedGraph,
  edit : @graph_dsl.LoweredGraphEdit,
) -> Result[@graph_dsl.GraphDoc, String] {
  let old_source = self.source
  let new_source = edit.new_source()
  match edit.incremental_edit() {
    Some(incremental_edit) =>
      self.attachment.apply_edit(incremental_edit, new_source)
    None => self.attachment.set_source(new_source)
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
pub fn set_source_graph_source(handle : Int, source : String) -> Unit {
  match source_graph_by_handle(handle) {
    Some(graph) => {
      graph.source = source
      graph.attachment.set_source(source)
    }
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
  let lowered = match lower_source_operation(doc, operation) {
    Ok(edit) => edit
    Err(message) =>
      return source_graph_result_for_graph(graph, false, Some(message))
  }
  match graph.apply_lowered_edit(lowered) {
    Ok(doc) => {
      graph.append_operation(realized_source_operation(doc, operation))
      source_graph_result_for_graph(graph, true, None)
    }
    Err(message) => source_graph_result_for_graph(graph, false, Some(message))
  }
}
