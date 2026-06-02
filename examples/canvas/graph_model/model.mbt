///|
pub const GRAPH_OPERATION_VERSION : Int = 1

///|
/// Integer ID for graph nodes in the canvas model.
pub(all) struct NodeId(Int) derive(Debug, Eq)

///|
pub fn NodeId::from_int(n : Int) -> NodeId {
  NodeId(n)
}

///|
pub fn NodeId::to_int(self : NodeId) -> Int {
  let NodeId(n) = self
  n
}

///|
pub impl Show for NodeId with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl ToJson for NodeId with fn to_json(self) {
  self.to_int().to_json()
}

///|
pub impl @json.FromJson for NodeId with fn from_json(json, path) {
  match json {
    Json::Number(n, ..) => NodeId(n.to_int())
    _ => raise @json.JsonDecodeError((path, "NodeId: expected JSON number"))
  }
}

///|
pub(all) struct EdgeId(Int) derive(Debug, Eq)

///|
pub fn EdgeId::from_int(n : Int) -> EdgeId {
  EdgeId(n)
}

///|
pub fn EdgeId::to_int(self : EdgeId) -> Int {
  let EdgeId(n) = self
  n
}

///|
pub impl Show for EdgeId with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl ToJson for EdgeId with fn to_json(self) {
  self.to_int().to_json()
}

///|
pub impl @json.FromJson for EdgeId with fn from_json(json, path) {
  match json {
    Json::Number(n, ..) => EdgeId(n.to_int())
    _ => raise @json.JsonDecodeError((path, "EdgeId: expected JSON number"))
  }
}

///|
/// Logical data carried by workflow ports. `Any` is reserved for custom nodes
/// and future adapters; built-in workflow nodes use concrete types.
pub(all) enum PortType {
  Flow
  Text
  Number
  Boolean
  Json
  Any
} derive(Debug, Eq, ToJson, FromJson)

///|
pub impl Show for PortType with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) struct PortDef {
  id : String
  label : String
  port_type : PortType
} derive(Debug, Eq, ToJson, FromJson)

///|
pub impl Show for PortDef with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Built-in workflow templates. `Custom` keeps the canvas extensible without
/// hard-coding application-specific integrations into the visual layer.
pub(all) enum WorkflowNodeKind {
  TimerTrigger
  HttpRequest
  DataFormatter
  ConditionalBranch
  Loop
  Parallel
  Custom(String)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub impl Show for WorkflowNodeKind with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Visual kind of a node. The canvas stays generic by representing application
/// behavior through workflow metadata rather than embedding executor logic here.
pub(all) enum NodeKind {
  /// Workflow step rendered with typed ports and validation state.
  Workflow(WorkflowNodeKind)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub impl Show for NodeKind with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Pan and zoom state of the canvas viewport.
/// `x` and `y` are the world origin in canvas-local screen space.
pub(all) struct Viewport {
  x : Double
  y : Double
  scale : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub impl Show for Viewport with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// A single node on the canvas. Coordinates are in world space. The visual
/// editor owns layout and display state; executable behavior lives in a future
/// compiler/execution layer keyed by `kind` and ports.
pub(all) struct CanvasNode {
  id : NodeId
  x : Double
  y : Double
  w : Double
  h : Double
  kind : NodeKind
  title : String
  subtitle : String
  inputs : Array[PortDef]
  outputs : Array[PortDef]
  configured : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub impl Show for CanvasNode with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) struct NodePosition {
  node_id : NodeId
  x : Double
  y : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub impl Show for NodePosition with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Serializable user actions. UI event handlers translate pointer/menu events
/// into these values before committing graph or session-state changes.
pub(all) enum WorkflowAction {
  AddNode(CanvasNode)
  MoveNodes(Array[NodePosition])
  ConnectPorts(NodeId, String, NodeId, String)
  SelectNodes(Array[NodeId])
  SetViewport(Viewport)
} derive(Debug, Eq, ToJson)

///|
pub impl Show for WorkflowAction with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Versioned graph operation wrapper. `WorkflowAction` remains the canvas
/// action payload for this first extraction; this envelope is the
/// replay/serialization boundary.
pub struct GraphOperation {
  priv version : Int
  priv action : WorkflowAction
} derive(Debug, Eq)

///|
pub impl Show for GraphOperation with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn GraphOperation::GraphOperation(
  action : WorkflowAction,
) -> GraphOperation {
  { version: GRAPH_OPERATION_VERSION, action }
}

///|
pub fn GraphOperation::version(self : GraphOperation) -> Int {
  self.version
}

///|
pub fn GraphOperation::action(self : GraphOperation) -> WorkflowAction {
  self.action
}

///|
fn require_json_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
  owner : String,
) -> Json raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(value) => value
    None =>
      raise @json.JsonDecodeError(
        (path.add_key(key), "\{owner}: missing '\{key}' field"),
      )
  }
}

///|
fn json_number_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
  owner : String,
) -> Int raise @json.JsonDecodeError {
  match require_json_field(fields, path, key, owner) {
    Json::Number(n, ..) => n.to_int()
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key(key), "\{owner}: '\{key}' must be a number"),
      )
  }
}

///|
fn json_string_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
  owner : String,
) -> String raise @json.JsonDecodeError {
  match require_json_field(fields, path, key, owner) {
    Json::String(s) => s
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key(key), "\{owner}: '\{key}' must be a string"),
      )
  }
}

///|
pub impl ToJson for GraphOperation with fn to_json(self) {
  let fields : Map[String, Json] = {}
  fields["version"] = self.version.to_json()
  match self.action {
    AddNode(node) => {
      fields["type"] = "AddNode".to_json()
      fields["node"] = node.to_json()
    }
    MoveNodes(positions) => {
      fields["type"] = "MoveNodes".to_json()
      fields["positions"] = positions.to_json()
    }
    ConnectPorts(source, source_port, target, target_port) => {
      fields["type"] = "ConnectPorts".to_json()
      fields["source"] = source.to_json()
      fields["source_port"] = source_port.to_json()
      fields["target"] = target.to_json()
      fields["target_port"] = target_port.to_json()
    }
    SelectNodes(nodes) => {
      fields["type"] = "SelectNodes".to_json()
      fields["nodes"] = nodes.to_json()
    }
    SetViewport(viewport) => {
      fields["type"] = "SetViewport".to_json()
      fields["viewport"] = viewport.to_json()
    }
  }
  Json::object(fields)
}

///|
pub impl @json.FromJson for GraphOperation with fn from_json(json, path) {
  let fields = match json {
    Json::Object(fields) => fields
    _ =>
      raise @json.JsonDecodeError(
        (path, "GraphOperation: expected JSON object"),
      )
  }
  let version = json_number_field(fields, path, "version", "GraphOperation")
  if version != GRAPH_OPERATION_VERSION {
    raise @json.JsonDecodeError(
      (
        path.add_key("version"),
        "GraphOperation: unsupported version \{version}",
      ),
    )
  }
  let type_name = json_string_field(fields, path, "type", "GraphOperation")
  let action = match type_name {
    "AddNode" => {
      let node : CanvasNode = @json.from_json(
        require_json_field(fields, path, "node", "AddNode"),
      )
      WorkflowAction::AddNode(node)
    }
    "MoveNodes" => {
      let positions : Array[NodePosition] = @json.from_json(
        require_json_field(fields, path, "positions", "MoveNodes"),
      )
      WorkflowAction::MoveNodes(positions)
    }
    "ConnectPorts" => {
      let source = NodeId(
        json_number_field(fields, path, "source", "ConnectPorts"),
      )
      let source_port = json_string_field(
        fields, path, "source_port", "ConnectPorts",
      )
      let target = NodeId(
        json_number_field(fields, path, "target", "ConnectPorts"),
      )
      let target_port = json_string_field(
        fields, path, "target_port", "ConnectPorts",
      )
      WorkflowAction::ConnectPorts(source, source_port, target, target_port)
    }
    "SelectNodes" => {
      let nodes : Array[NodeId] = @json.from_json(
        require_json_field(fields, path, "nodes", "SelectNodes"),
      )
      WorkflowAction::SelectNodes(nodes)
    }
    "SetViewport" => {
      let viewport : Viewport = @json.from_json(
        require_json_field(fields, path, "viewport", "SetViewport"),
      )
      WorkflowAction::SetViewport(viewport)
    }
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key("type"), "GraphOperation: unknown type '\{type_name}'"),
      )
  }
  { version, action }
}

///|
pub(all) struct DragOrigin {
  node_id : NodeId
  offset_x : Double
  offset_y : Double
} derive(Debug, Eq)

///|
pub impl Show for DragOrigin with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// State captured at the start of a node drag gesture.
pub(all) struct DragState {
  node_id : NodeId
  origins : Array[DragOrigin]
} derive(Debug, Eq)

///|
pub impl Show for DragState with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// State captured at the start of a pan gesture.
pub(all) struct PanState {
  start_screen_x : Double
  start_screen_y : Double
  start_pan_x : Double
  start_pan_y : Double
} derive(Debug, Eq)

///|
pub impl Show for PanState with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// A typed connection between two workflow ports.
pub(all) struct Edge {
  id : EdgeId
  source : NodeId
  source_port : String
  target : NodeId
  target_port : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub impl Show for Edge with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// In-flight connection started from a node's output handle.
/// `cursor_x`/`cursor_y` are world coordinates of the pointer.
pub(all) struct ConnectState {
  from_node : NodeId
  from_port : String
  cursor_x : Double
  cursor_y : Double
} derive(Debug, Eq)

///|
pub impl Show for ConnectState with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) struct InteractionState {
  dragging : DragState?
  panning : PanState?
  connecting : ConnectState?
  selected : NodeId?
  selected_nodes : Array[NodeId]
  /// True from pointerdown until pointerup.
  pointer_down : Bool
  /// True once pointermove fires during the current pointer session.
  did_move : Bool
} derive(Debug, Eq)

///|
pub impl Show for InteractionState with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) struct CanvasState {
  viewport : Viewport
  nodes : Array[CanvasNode]
  edges : Array[Edge]
  next_node_id : Int
  /// Monotonic counter used to mint EdgeIds for newly-created connections.
  next_edge_id : Int
  interaction : InteractionState
  action_log : Array[GraphOperation]
} derive(Debug)

///|
pub impl Show for CanvasState with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn port(id : String, label : String, port_type : PortType) -> PortDef {
  { id, label, port_type }
}

///|
pub fn make_workflow_node(
  id : NodeId,
  kind : WorkflowNodeKind,
  x : Double,
  y : Double,
) -> CanvasNode {
  match kind {
    TimerTrigger =>
      {
        id,
        x,
        y,
        w: 244.0,
        h: 132.0,
        kind: NodeKind::Workflow(TimerTrigger),
        title: "Timer trigger",
        subtitle: "Starts a workflow on a schedule",
        inputs: [],
        outputs: [port("tick", "tick", Flow)],
        configured: true,
      }
    HttpRequest =>
      {
        id,
        x,
        y,
        w: 260.0,
        h: 148.0,
        kind: NodeKind::Workflow(HttpRequest),
        title: "HTTP request",
        subtitle: "Call an API and emit JSON",
        inputs: [port("in", "flow", Flow)],
        outputs: [port("json", "JSON", Json)],
        configured: false,
      }
    DataFormatter =>
      {
        id,
        x,
        y,
        w: 260.0,
        h: 148.0,
        kind: NodeKind::Workflow(DataFormatter),
        title: "Format data",
        subtitle: "Map JSON fields into text",
        inputs: [port("json", "JSON", Json)],
        outputs: [port("text", "text", Text)],
        configured: true,
      }
    ConditionalBranch =>
      {
        id,
        x,
        y,
        w: 270.0,
        h: 156.0,
        kind: NodeKind::Workflow(ConditionalBranch),
        title: "Condition",
        subtitle: "Route items by a boolean rule",
        inputs: [port("text", "text", Text), port("rule", "rule", Boolean)],
        outputs: [port("true", "true", Flow), port("false", "false", Flow)],
        configured: true,
      }
    Loop =>
      {
        id,
        x,
        y,
        w: 244.0,
        h: 132.0,
        kind: NodeKind::Workflow(Loop),
        title: "Loop",
        subtitle: "Repeat work over a collection",
        inputs: [port("items", "items", Json)],
        outputs: [port("each", "each", Json), port("count", "count", Number)],
        configured: true,
      }
    Parallel =>
      {
        id,
        x,
        y,
        w: 244.0,
        h: 132.0,
        kind: NodeKind::Workflow(Parallel),
        title: "Parallel split",
        subtitle: "Run independent branches together",
        inputs: [port("in", "flow", Flow)],
        outputs: [port("a", "A", Flow), port("b", "B", Flow)],
        configured: true,
      }
    Custom(name) =>
      {
        id,
        x,
        y,
        w: 250.0,
        h: 138.0,
        kind: NodeKind::Workflow(Custom(name)),
        title: name,
        subtitle: "Custom workflow step",
        inputs: [port("in", "any", Any)],
        outputs: [port("out", "any", Any)],
        configured: false,
      }
  }
}

///|
pub fn workflow_node_kind_from_key(key : String) -> WorkflowNodeKind {
  if key == "timer" {
    TimerTrigger
  } else if key == "http" {
    HttpRequest
  } else if key == "formatter" {
    DataFormatter
  } else if key == "condition" {
    ConditionalBranch
  } else if key == "loop" {
    Loop
  } else if key == "parallel" {
    Parallel
  } else {
    Custom("Custom step")
  }
}

///|
pub fn empty_interaction() -> InteractionState {
  {
    dragging: None,
    panning: None,
    connecting: None,
    selected: None,
    selected_nodes: [],
    pointer_down: false,
    did_move: false,
  }
}

///|
pub fn find_node(nodes : Array[CanvasNode], id : NodeId) -> CanvasNode? {
  for node in nodes {
    if node.id == id {
      return Some(node)
    }
  }
  None
}

///|
pub fn find_position(
  positions : Array[NodePosition],
  id : NodeId,
) -> NodePosition? {
  for pos in positions {
    if pos.node_id == id {
      return Some(pos)
    }
  }
  None
}

///|
pub fn node_id_in_array(nodes : Array[NodeId], id : NodeId) -> Bool {
  nodes.iter().any(fn(n) { n == id })
}

///|
fn edge_exists(
  edges : Array[Edge],
  source : NodeId,
  source_port : String,
  target : NodeId,
  target_port : String,
) -> Bool {
  edges
  .iter()
  .any(fn(e) {
    e.source == source &&
    e.source_port == source_port &&
    e.target == target &&
    e.target_port == target_port
  })
}

///|
fn port_type_compatible(source : PortType, target : PortType) -> Bool {
  source == target || source == Any || target == Any
}

///|
pub fn port_type_by_id(ports : Array[PortDef], id : String) -> PortType? {
  for port in ports {
    if port.id == id {
      return Some(port.port_type)
    }
  }
  None
}

///|
pub fn can_commit_edge(
  state : CanvasState,
  source : NodeId,
  source_port : String,
  target : NodeId,
  target_port : String,
) -> Bool {
  if source == target ||
    edge_exists(state.edges, source, source_port, target, target_port) {
    false
  } else {
    match (find_node(state.nodes, source), find_node(state.nodes, target)) {
      (Some(source_node), Some(target_node)) =>
        match
          (
            port_type_by_id(source_node.outputs, source_port),
            port_type_by_id(target_node.inputs, target_port),
          ) {
          (Some(source_type), Some(target_type)) =>
            port_type_compatible(source_type, target_type)
          _ => false
        }
      _ => false
    }
  }
}

///|
fn append_edge(
  state : CanvasState,
  source : NodeId,
  source_port : String,
  target : NodeId,
  target_port : String,
) -> CanvasState {
  let edge : Edge = {
    id: EdgeId(state.next_edge_id),
    source,
    source_port,
    target,
    target_port,
  }
  let edges = state.edges.copy()
  edges.push(edge)
  { ..state, edges, next_edge_id: state.next_edge_id + 1 }
}

///|
pub fn set_selection(state : CanvasState, nodes : Array[NodeId]) -> CanvasState {
  let selected = if nodes.length() == 0 { None } else { Some(nodes[0]) }
  let new_interaction : InteractionState = {
    ..state.interaction,
    selected,
    selected_nodes: nodes,
  }
  { ..state, interaction: new_interaction }
}

///|
pub fn apply_action(
  state : CanvasState,
  action : WorkflowAction,
) -> CanvasState {
  match action {
    AddNode(node) => {
      let nodes = state.nodes.copy()
      nodes.push(node)
      { ..state, nodes, next_node_id: state.next_node_id + 1 }
    }
    MoveNodes(positions) => {
      let nodes = state.nodes.map(fn(node) {
        match find_position(positions, node.id) {
          None => node
          Some(pos) => { ..node, x: pos.x, y: pos.y }
        }
      })
      { ..state, nodes, }
    }
    ConnectPorts(source, source_port, target, target_port) =>
      if can_commit_edge(state, source, source_port, target, target_port) {
        append_edge(state, source, source_port, target, target_port)
      } else {
        state
      }
    SelectNodes(nodes) => set_selection(state, nodes)
    SetViewport(viewport) => { ..state, viewport, }
  }
}

///|
fn append_history(
  state : CanvasState,
  operation : GraphOperation,
) -> CanvasState {
  let action_log = state.action_log.copy()
  action_log.push(operation)
  { ..state, action_log, }
}

///|
pub fn apply_operation(
  state : CanvasState,
  operation : GraphOperation,
) -> CanvasState {
  append_history(apply_action(state, operation.action()), operation)
}

///|
pub fn record_action(
  state : CanvasState,
  action : WorkflowAction,
) -> CanvasState {
  apply_operation(state, GraphOperation(action))
}

///|
pub fn replay_operations(
  initial : CanvasState,
  operations : Array[GraphOperation],
) -> CanvasState {
  let mut state = initial
  for operation in operations {
    state = apply_operation(state, operation)
  }
  state
}

///|
/// Default state centers the world origin in a 1440×800 browser viewport
/// and seeds a typed workflow that exercises sequence, transformation, branch,
/// loop, and parallel-flow concepts.
pub impl Default for CanvasState with fn default() -> CanvasState {
  let nodes = [
    make_workflow_node(NodeId(1), TimerTrigger, -520.0, -190.0),
    make_workflow_node(NodeId(2), HttpRequest, -190.0, -190.0),
    make_workflow_node(NodeId(3), DataFormatter, 155.0, -190.0),
    make_workflow_node(NodeId(4), ConditionalBranch, 500.0, -190.0),
    make_workflow_node(NodeId(5), Loop, 150.0, 60.0),
    make_workflow_node(NodeId(6), Parallel, 500.0, 70.0),
  ]
  {
    viewport: { x: 760.0, y: 330.0, scale: 0.75 },
    nodes,
    edges: [
      {
        id: EdgeId(1),
        source: NodeId(1),
        source_port: "tick",
        target: NodeId(2),
        target_port: "in",
      },
      {
        id: EdgeId(2),
        source: NodeId(2),
        source_port: "json",
        target: NodeId(3),
        target_port: "json",
      },
      {
        id: EdgeId(3),
        source: NodeId(3),
        source_port: "text",
        target: NodeId(4),
        target_port: "text",
      },
    ],
    next_node_id: 7,
    next_edge_id: 4,
    interaction: empty_interaction(),
    action_log: [],
  }
}
