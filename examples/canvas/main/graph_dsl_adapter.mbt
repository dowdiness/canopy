///|
/// Source-backed Graph DSL host policy stays in this example adapter: viewport
/// defaults, diagnostics, Graph DSL node templates, and render-param enrichment
/// live here while pointer/drag/zoom mechanics continue to reuse
/// `@graph_model` reducers.
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
    drag_preview: @graph_model.idle_drag_preview(),
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
  match doc.find_node(binding) {
    Some(node) => Some(NodeId(node.id()))
    None => None
  }
}

///|
fn graph_node_for_canvas_id(
  doc : @graph_dsl.GraphDoc,
  id : NodeId,
) -> @graph_dsl.GraphNode? {
  doc.find_node_by_id(id.to_string())
}

///|
fn graph_param_value_kind_text(kind : @graph_dsl.GraphValueKind) -> String {
  match kind {
    @graph_dsl.Numeric => "numeric"
    @graph_dsl.StringValue => "string"
    @graph_dsl.EnumValue => "enum"
    @graph_dsl.InputRef => "input-ref"
  }
}

///|
fn graph_param_token_text(
  param : @graph_dsl.GraphParam,
  role : @graph_dsl.GraphTokenRole,
) -> String? {
  let tokens = param.value_tokens()
  match tokens.search_by(fn(token) { token.role() == role }) {
    Some(index) => Some(tokens[index].text())
    None => None
  }
}

///|
fn graph_param_value_text(param : @graph_dsl.GraphParam) -> String {
  let role = match param.value_kind() {
    @graph_dsl.Numeric => @graph_dsl.NumericParameter
    @graph_dsl.StringValue => @graph_dsl.StringField
    @graph_dsl.EnumValue => @graph_dsl.EnumField
    @graph_dsl.InputRef => @graph_dsl.InputReference
  }
  match graph_param_token_text(param, role) {
    Some(text) => text
    None => ""
  }
}

///|
fn graph_param_json(param : @graph_dsl.GraphParam) -> NodeParamJson {
  let value_kind = param.value_kind()
  {
    name: param.name(),
    value_kind: graph_param_value_kind_text(value_kind),
    value: graph_param_value_text(param),
    unit: graph_param_token_text(param, @graph_dsl.Unit),
    editable: match value_kind {
      @graph_dsl.Numeric => true
      _ => false
    },
  }
}

///|
fn source_node_to_json(
  node_index : Map[String, @graph_dsl.GraphNode],
  node : CanvasNode,
) -> NodeJson {
  let base = node_to_json(node)
  match node_index.get(node.id.to_string()) {
    Some(graph_node) =>
      { ..base, params: graph_node.params().map(graph_param_json) }
    None => base
  }
}

///|
fn canvas_node_from_graph_node(
  index : Int,
  graph_node : @graph_dsl.GraphNode,
) -> CanvasNode {
  {
    id: NodeId(graph_node.id()),
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
  for graph_node in doc.nodes() {
    let target = NodeId(graph_node.id())
    for param in graph_node.params() {
      match graph_input_reference(param) {
        None => ()
        Some(source_binding) =>
          match canvas_id_for_binding(doc, source_binding) {
            None => ()
            Some(source) =>
              edges.push({
                id: EdgeId::from_edge(source, "out", target, param.name()),
                source,
                source_port: "out",
                target,
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
      @graph_model.state_with_preview_nodes(state, graph.drag_preview)
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
fn lower_rename_node(
  doc : @graph_dsl.GraphDoc,
  node_id : NodeId,
  new_name : String,
) -> Result[SourceOperationEdit, String] {
  let node = match graph_node_for_canvas_id(doc, node_id) {
    Some(node) => node
    None => return Err("cannot lower RenameNode: missing node")
  }
  match doc.lower_rename_node_binding(node.binding(), new_name) {
    Some(edit) => Ok(ExactLoweredEdit(edit))
    None =>
      Err(
        "cannot lower RenameNode for binding '" +
        node.binding() +
        "' to '" +
        new_name +
        "'",
      )
  }
}

///|
fn lower_set_node_param(
  doc : @graph_dsl.GraphDoc,
  node_id : NodeId,
  parameter : String,
  value : String,
) -> Result[SourceOperationEdit, String] {
  let node = match graph_node_for_canvas_id(doc, node_id) {
    Some(node) => node
    None => return Err("cannot lower SetNodeParam: missing node")
  }
  match doc.lower_set_numeric(node.binding(), parameter, value) {
    Some(edit) => Ok(ExactLoweredEdit(edit))
    None =>
      Err(
        "cannot lower SetNodeParam for binding '" +
        node.binding() +
        "' parameter '" +
        parameter +
        "'",
      )
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
    RenameNode(node_id, new_name) => lower_rename_node(doc, node_id, new_name)
    SetNodeParam(node_id, parameter, value) =>
      lower_set_node_param(doc, node_id, parameter, value)
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
/// Apply one CodeMirror transaction — delivered as an ordered batch of
/// pre-transaction `ChangeDelta`s — to the source-backed graph as a sequence
/// of loom edits.
///
/// `changes_to_edits` rebases each change onto the document the previous one
/// produced, so the attachment's incremental reparse sees the same per-edit
/// stream a user typing into the editor would generate, rather than one
/// whole-document replacement.
///
/// The editor is the source of truth for text: `self.source` always tracks the
/// editor's buffer (`expected_doc`, the editor's authoritative post-transaction
/// text), and the rendered graph is derived — `current_result()` when valid,
/// else `last_good()` (see `source_graph_doc_for_render`). We therefore do NOT
/// roll back when a batch leaves the source not graph-valid: the attachment
/// keeps the invalid `current_source` and its identity tracker realigns node
/// identity across the failed intermediate parses, so the next valid keystroke
/// recovers incrementally with stable identity (no whole-source churn).
fn SourceBackedGraph::apply_codemirror_changes(
  self : SourceBackedGraph,
  changes : Array[@codemirror.ChangeDelta],
  expected_doc : String,
) -> SourceGraphOperationResultJson {
  for edit, new_source in Iter2(changes_to_edits(self.source, changes).iter()) {
    self.attachment.apply_edit(edit, new_source)
    self.source = new_source
  }
  // Stale-editor guard: the deltas are expressed against the editor's
  // pre-transaction buffer. If the incremental result does not equal the
  // editor's authoritative post-transaction text, `self.source` had diverged
  // from the editor (an out-of-band TS-side graph mutation moved the source out
  // from under a stale editor). Reparse the editor's text so the keystroke wins
  // over the racing mutation, rather than splicing onto a mismatched base.
  if self.source != expected_doc {
    self.attachment.set_source(expected_doc)
    self.source = expected_doc
  }
  match source_graph_current_doc(self) {
    Ok(doc) => {
      // Identity is the tracker token, stable across delta reparse — selection
      // survives with no remap; only drop tokens that no longer exist.
      self.prune_selection_to_doc(doc)
      source_graph_result_json_for_graph(self, true, None)
    }
    Err(message) =>
      source_graph_result_json_for_graph(self, false, Some(message))
  }
}

///|
/// Handle-addressed entry point for applying a CodeMirror transaction to a
/// registered source-backed graph. The source CodeMirror editor's
/// `listen(on_change=...)` subscription forwards its `ChangeDelta` batch here.
fn apply_source_graph_codemirror_changes(
  handle : Int,
  changes : Array[@codemirror.ChangeDelta],
  expected_doc : String,
) -> SourceGraphOperationResultJson {
  match source_graph_by_handle(handle) {
    Some(graph) => graph.apply_codemirror_changes(changes, expected_doc)
    None =>
      source_graph_operation_result_json(
        false,
        "",
        ["source graph handle not found"],
        0,
        Some("source graph handle not found"),
      )
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
/// Drop any selected node whose tracker token no longer exists in `doc`, and
/// reset in-flight gesture state. Identity is the token (`NodeId`), stable
/// across delta reparse, so survivors keep their selection with no remapping;
/// deleted or atomically-churned tokens fall out naturally.
fn SourceBackedGraph::prune_selection_to_doc(
  self : SourceBackedGraph,
  doc : @graph_dsl.GraphDoc,
) -> Unit {
  let selected_nodes = self.interaction.selected_nodes.filter(fn(id) {
    doc.find_node_by_id(id.to_string()) is Some(_)
  })
  let selected = match selected_nodes {
    [head, ..] => Some(head)
    [] => None
  }
  self.drag_preview = @graph_model.idle_drag_preview()
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
/// Rewrite one node's selection token after a rename (the token embeds the
/// binding, so renaming changes it). This is a rename-local continuation, not
/// binding-recovery: only the renamed node's `old` token maps to `new`.
fn SourceBackedGraph::rename_selection_token(
  self : SourceBackedGraph,
  old : NodeId,
  new : NodeId,
) -> Unit {
  let selected_nodes = self.interaction.selected_nodes.map(fn(id) {
    if id == old {
      new
    } else {
      id
    }
  })
  let selected = match self.interaction.selected {
    Some(id) if id == old => Some(new)
    other => other
  }
  self.interaction = { ..self.interaction, selected, selected_nodes }
}

///|
fn SourceBackedGraph::rename_layout_binding(
  self : SourceBackedGraph,
  old_binding : String,
  new_binding : String,
) -> Unit {
  self.layout = self.layout.map(fn(position) {
    if position.binding == old_binding {
      { ..position, binding: new_binding }
    } else {
      position
    }
  })
}

///|
fn SourceBackedGraph::sync_local_operation_state(
  self : SourceBackedGraph,
  old_doc : @graph_dsl.GraphDoc,
  new_doc : @graph_dsl.GraphDoc,
  operation : GraphOperation,
) -> Unit {
  match operation.action() {
    DeleteNodes(_) => {
      self.prune_selection_to_doc(new_doc)
      self.sync_layout_from_state(source_graph_base_canvas_state(self))
    }
    RenameNode(node_id, new_binding) =>
      match graph_node_for_canvas_id(old_doc, node_id) {
        Some(node) => {
          self.rename_layout_binding(node.binding(), new_binding)
          // The token embeds the binding, so the renamed node's id changes;
          // carry any live selection of it forward to the new token.
          match new_doc.find_node(new_binding) {
            Some(renamed) =>
              self.rename_selection_token(node_id, NodeId(renamed.id()))
            None => ()
          }
        }
        None => ()
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
  node_id : String,
  sx : Double,
  sy : Double,
) -> Unit {
  let target : NodeId? = if node_id == "" {
    None
  } else {
    Some(NodeId(node_id))
  }
  let state = @graph_model.update_pointer_down(
    source_graph_base_canvas_state(self),
    target,
    sx,
    sy,
  )
  self.drag_preview = @graph_model.idle_drag_preview()
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
      let (wx, wy) = @graph_model.screen_to_world(state.viewport, sx, sy)
      self.interaction = @graph_model.update_connect_move(state, wx, wy).interaction
    }
    None =>
      match state.interaction.dragging {
        Some(drag) => {
          let (wx, wy) = @graph_model.screen_to_world(state.viewport, sx, sy)
          let new_interaction : InteractionState = {
            ..state.interaction,
            did_move: true,
          }
          self.drag_preview = @graph_model.drag_preview_from_move(drag, wx, wy)
          self.interaction = new_interaction
        }
        None =>
          match state.interaction.panning {
            Some(_) => {
              let next = @graph_model.update_pan_move(state, sx, sy)
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
  node_id : String,
  target_port_id : String,
  additive : Bool,
) -> Unit {
  let state = source_graph_base_canvas_state(self)
  let commit_state = match state.interaction.dragging {
    Some(_) if state.interaction.did_move =>
      @graph_model.state_with_preview_nodes(state, self.drag_preview)
    _ => state
  }
  let next = @graph_model.update_pointer_up(
    commit_state, node_id, target_port_id, additive,
  )
  self.sync_layout_from_state(next)
  self.viewport = next.viewport
  self.drag_preview = @graph_model.idle_drag_preview()
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
  let next = @graph_model.update_zoom(
    source_graph_base_canvas_state(self),
    delta,
    cx,
    cy,
  )
  self.viewport = next.viewport
  self.action_log = next.action_log.copy()
}

///|
fn source_graph_node_payload(
  binding : String,
  constructor_name : String,
) -> CanvasNode {
  {
    id: NodeId(""),
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
  let nodes = doc.nodes()
  guard nodes.length() >= 2 else {
    return source_graph_result_json_for_graph(
      graph,
      false,
      Some("sample connect needs at least two nodes"),
    )
  }
  let source = NodeId(nodes[0].id())
  let target = NodeId(nodes[1].id())
  let result_json = apply_source_graph_operation(
    handle,
    GraphOperation(ConnectPorts(source, "out", target, "input"))
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
/// Subscribe to settle notifications for a registered source-backed graph. The
/// source panel's reactive `custom_sub` uses this to replace the old 250ms
/// poll: `listener` fires after every `GraphAttachment` settle (any mutation
/// origin), and the panel pulls `get_source_graph_source` on the ping. Returns
/// `None` for an unknown handle.
fn source_graph_subscribe(
  handle : Int,
  listener : () -> Unit,
) -> @graph_dsl.GraphAttachmentSubscription? {
  match source_graph_by_handle(handle) {
    Some(graph) => Some(graph.attachment.subscribe(listener))
    None => None
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
    Ok(doc) => {
      // Reset/init path: tokens survive content-preserving edits but a reorder
      // churns them (residual limitation), so prune by token existence.
      graph.prune_selection_to_doc(doc)
      source_graph_result_json_for_graph(graph, true, None)
    }
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
  node_id : String,
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
  node_id : String,
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
fn source_render_state_string(
  graph : SourceBackedGraph,
  state : CanvasState,
  validation : Array[ValidationJson],
) -> String {
  let rendered = render_state_json(state, validation)
  match source_graph_doc_for_render(graph) {
    Some(doc) => {
      // Index the doc's nodes by token once so per-node param resolution is
      // O(1); resolving each canvas node back through find_node_by_id would be
      // O(n) per node, i.e. O(n²) over the render.
      let node_index : Map[String, @graph_dsl.GraphNode] = Map::from_array(
        doc.nodes().map(fn(graph_node) { (graph_node.id(), graph_node) }),
      )
      {
        ..rendered,
        nodes: state.nodes.map(fn(node) {
          source_node_to_json(node_index, node)
        }),
      }
      .to_json()
      .stringify()
    }
    None => rendered.to_json().stringify()
  }
}

///|
pub fn get_source_graph_render_state(handle : Int) -> String {
  match source_graph_by_handle(handle) {
    Some(graph) => {
      let state = source_graph_canvas_state(graph)
      source_render_state_string(graph, state, source_graph_validation(graph))
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
  match graph.apply_source_edit(lowered) {
    Ok(new_doc) => {
      graph.sync_local_operation_state(doc, new_doc, operation)
      graph.append_operation(realized_source_operation(new_doc, operation))
      source_graph_result_for_graph(graph, true, None)
    }
    Err(message) => source_graph_result_for_graph(graph, false, Some(message))
  }
}
