///|
fn node_id(n : Int) -> @graph_model.NodeId {
  @graph_model.NodeId(n.to_string())
}

///|
fn viewport_for_test(
  origin_x : Double,
  origin_y : Double,
  scale : Double,
) -> @spatial.Viewport {
  @spatial.Viewport::from_scale(
    origin=try! @spatial.ScreenPoint::from_xy(x=origin_x, y=origin_y),
    scale=try! @spatial.Scale::from_double(value=scale),
  )
}

///|
fn viewport_json_with_coordinates(
  x : Double,
  y : Double,
  scale : Double,
) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["x"] = x.to_json()
  fields["y"] = y.to_json()
  fields["scale"] = scale.to_json()
  Json::object(fields)
}

///|
fn viewport_json(scale : Double) -> Json {
  viewport_json_with_coordinates(20.0, -10.0, scale)
}

///|
fn viewport_operation_json(viewport : Json) -> Json {
  let fields : Map[String, Json] = Map([])
  let version : Int = 2
  fields["version"] = version.to_json()
  fields["type"] = "SetViewport".to_json()
  fields["viewport"] = viewport
  Json::object(fields)
}

///|
fn replay_base_state() -> @graph_model.CanvasState {
  {
    viewport: viewport_for_test(0.0, 0.0, 1.0),
    nodes: [
      @graph_model.make_workflow_node(
        node_id(1),
        @graph_model.WorkflowNodeKind::TimerTrigger,
        try! @spatial.WorldPoint::from_xy(x=100.0, y=100.0),
      ),
      @graph_model.make_workflow_node(
        node_id(2),
        @graph_model.WorkflowNodeKind::HttpRequest,
        try! @spatial.WorldPoint::from_xy(x=420.0, y=100.0),
      ),
    ],
    edges: [],
    next_node_id: 3,
    interaction: @graph_model.empty_interaction(),
    action_log: [],
  }
}

///|
fn fan_in_base_state(allows_fan_in : Bool) -> @graph_model.CanvasState {
  let base_target = @graph_model.make_workflow_node(
    node_id(3),
    @graph_model.WorkflowNodeKind::Custom("Join"),
    try! @spatial.WorldPoint::from_xy(x=760.0, y=100.0),
  )
  let target = @graph_model.CanvasNode::from_parts(
    id=base_target.id,
    position=base_target.position(),
    size=base_target.size(),
    kind=base_target.kind,
    title=base_target.title,
    subtitle=base_target.subtitle,
    inputs=[
      @graph_model.port(
        "in",
        "flow",
        @graph_model.PortType::Flow,
        allows_fan_in~,
      ),
    ],
    outputs=base_target.outputs,
    configured=base_target.configured,
  )
  {
    viewport: viewport_for_test(0.0, 0.0, 1.0),
    nodes: [
      @graph_model.make_workflow_node(
        node_id(1),
        @graph_model.WorkflowNodeKind::TimerTrigger,
        try! @spatial.WorldPoint::from_xy(x=100.0, y=100.0),
      ),
      @graph_model.make_workflow_node(
        node_id(2),
        @graph_model.WorkflowNodeKind::TimerTrigger,
        try! @spatial.WorldPoint::from_xy(x=420.0, y=100.0),
      ),
      target,
    ],
    edges: [],
    next_node_id: 4,
    interaction: @graph_model.empty_interaction(),
    action_log: [],
  }
}

///|
test "GraphOperation serializes as a versioned JSON operation" {
  let operation = @graph_model.GraphOperation::GraphOperation(
    @graph_model.WorkflowAction::ConnectPorts(
      node_id(1),
      "tick",
      node_id(2),
      "in",
    ),
  )
  inspect(
    operation.to_json().stringify(),
    content="{\"version\":2,\"type\":\"ConnectPorts\",\"source\":\"1\",\"source_port\":\"tick\",\"target\":\"2\",\"target_port\":\"in\"}",
  )
}

///|
test "GraphOperation round-trips through JSON" {
  let operation = @graph_model.GraphOperation::GraphOperation(
    @graph_model.WorkflowAction::MoveNodes([
      @graph_model.NodePosition::from_node_and_position(
        node_id=node_id(1),
        position=try! @spatial.WorldPoint::from_xy(x=180.0, y=240.0),
      ),
    ]),
  )
  let decoded : @graph_model.GraphOperation = @json.from_json(
    operation.to_json(),
  )
  @debug.assert_eq(decoded, operation)
}

///|
test "DeleteNodes serializes node ids" {
  let operation = @graph_model.GraphOperation::GraphOperation(
    @graph_model.WorkflowAction::DeleteNodes([node_id(1), node_id(2)]),
  )
  inspect(
    operation.to_json().stringify(),
    content="{\"version\":2,\"type\":\"DeleteNodes\",\"nodes\":[\"1\",\"2\"]}",
  )
  let decoded : @graph_model.GraphOperation = @json.from_json(
    operation.to_json(),
  )
  @debug.assert_eq(decoded, operation)
}

///|
test "DisconnectPorts serializes endpoint ports" {
  let operation = @graph_model.GraphOperation::GraphOperation(
    @graph_model.WorkflowAction::DisconnectPorts(
      node_id(1),
      "tick",
      node_id(2),
      "in",
    ),
  )
  inspect(
    operation.to_json().stringify(),
    content="{\"version\":2,\"type\":\"DisconnectPorts\",\"source\":\"1\",\"source_port\":\"tick\",\"target\":\"2\",\"target_port\":\"in\"}",
  )
  let decoded : @graph_model.GraphOperation = @json.from_json(
    operation.to_json(),
  )
  @debug.assert_eq(decoded, operation)
}

///|
test "source-backed edit actions serialize node and parameter payloads" {
  let rename = @graph_model.GraphOperation::GraphOperation(
    @graph_model.WorkflowAction::RenameNode(node_id(1), "oscillator"),
  )
  inspect(
    rename.to_json().stringify(),
    content="{\"version\":2,\"type\":\"RenameNode\",\"node_id\":\"1\",\"name\":\"oscillator\"}",
  )
  let set_param = @graph_model.GraphOperation::GraphOperation(
    @graph_model.WorkflowAction::SetNodeParam(node_id(1), "freq", "880"),
  )
  inspect(
    set_param.to_json().stringify(),
    content="{\"version\":2,\"type\":\"SetNodeParam\",\"node_id\":\"1\",\"parameter\":\"freq\",\"value\":\"880\"}",
  )
  let decoded : Array[@graph_model.GraphOperation] = @json.from_json(
    [rename.to_json(), set_param.to_json()].to_json(),
  )
  @debug.assert_eq(decoded, [rename, set_param])
}

///|
test "RenameNode updates the canvas node title" {
  let renamed = @graph_model.apply_action(
    replay_base_state(),
    @graph_model.WorkflowAction::RenameNode(node_id(1), "Daily trigger"),
  )
  inspect(renamed.nodes[0].title, content="Daily trigger")
  inspect(renamed.nodes[1].title, content="HTTP request")
}

///|
test "operation log round-trips and replays into canvas graph state" {
  let added = @graph_model.make_workflow_node(
    node_id(3),
    @graph_model.WorkflowNodeKind::DataFormatter,
    try! @spatial.WorldPoint::from_xy(x=760.0, y=100.0),
  )
  let operations = [
    @graph_model.GraphOperation::GraphOperation(
      @graph_model.WorkflowAction::AddNode(added),
    ),
    @graph_model.GraphOperation::GraphOperation(
      @graph_model.WorkflowAction::MoveNodes([
        @graph_model.NodePosition::from_node_and_position(
          node_id=node_id(3),
          position=try! @spatial.WorldPoint::from_xy(x=800.0, y=140.0),
        ),
      ]),
    ),
    @graph_model.GraphOperation::GraphOperation(
      @graph_model.WorkflowAction::ConnectPorts(
        node_id(1),
        "tick",
        node_id(2),
        "in",
      ),
    ),
    @graph_model.GraphOperation::GraphOperation(
      @graph_model.WorkflowAction::DeleteNodes([node_id(2)]),
    ),
  ]
  let decoded : Array[@graph_model.GraphOperation] = @json.from_json(
    operations.to_json(),
  )
  @debug.assert_eq(decoded, operations)
  let replayed = @graph_model.replay_operations(replay_base_state(), decoded)
  assert_eq(replayed.nodes.length(), 2)
  assert_eq(replayed.edges.length(), 0)
  assert_eq(replayed.nodes[1].id, node_id(3))
  assert_eq(replayed.nodes[1].position().x(), 800.0)
  assert_eq(replayed.nodes[1].position().y(), 140.0)
  assert_eq(replayed.action_log.length(), 4)
}

///|
fn assert_rejects_viewport_operation(json : Json) -> Unit raise {
  let rejected = try {
    let _ : @graph_model.GraphOperation = @json.from_json(json)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
fn viewport_error_message(json : Json) -> String raise {
  try {
    let _ : @graph_model.GraphOperation = @json.from_json(json)
    fail("expected invalid viewport operation")
  } catch {
    @json.JsonDecodeError((_, message)) => message
    _ => fail("expected viewport JSON decode error")
  }
}

///|
test "viewport coordinate errors identify their fields" {
  let non_number_fields : Map[String, Json] = Map([])
  non_number_fields["x"] = "not-a-number".to_json()
  non_number_fields["y"] = (-10.0).to_json()
  non_number_fields["scale"] = 1.0.to_json()
  let non_number = viewport_operation_json(Json::object(non_number_fields))
  let non_finite_fields : Map[String, Json] = Map([])
  non_finite_fields["x"] = 20.0.to_json()
  non_finite_fields["y"] = Json::number(0.0 / 0.0)
  non_finite_fields["scale"] = 1.0.to_json()
  let non_finite = viewport_operation_json(Json::object(non_finite_fields))
  assert_eq(
    viewport_error_message(non_number),
    "Viewport: 'x' must be a number",
  )
  assert_eq(viewport_error_message(non_finite), "Viewport: 'y' must be finite")
}

///|
test "valid node geometry preserves its flat JSON shape" {
  let node = @graph_model.make_workflow_node(
    node_id(9),
    @graph_model.WorkflowNodeKind::Custom("Sized"),
    try! @spatial.WorldPoint::from_xy(x=12.0, y=-4.0),
  )
  let operation = @graph_model.GraphOperation::GraphOperation(
    @graph_model.WorkflowAction::AddNode(node),
  )
  inspect(
    operation.to_json().stringify(),
    content="{\"version\":2,\"type\":\"AddNode\",\"node\":{\"id\":\"9\",\"x\":12,\"y\":-4,\"w\":250,\"h\":138,\"kind\":[\"Workflow\",[\"Custom\",\"Sized\"]],\"title\":\"Sized\",\"subtitle\":\"Custom workflow step\",\"inputs\":[{\"id\":\"in\",\"label\":\"any\",\"port_type\":\"Any\"}],\"outputs\":[{\"id\":\"out\",\"label\":\"any\",\"port_type\":\"Any\"}],\"configured\":false}}",
  )
  let decoded : @graph_model.GraphOperation = @json.from_json(
    operation.to_json(),
  )
  @debug.assert_eq(decoded, operation)
}

///|
test "valid viewport operations preserve their JSON shape during replay" {
  let viewport = viewport_for_test(20.0, -10.0, 2.5)
  let operation = @graph_model.GraphOperation::GraphOperation(
    @graph_model.WorkflowAction::SetViewport(viewport),
  )
  inspect(
    operation.to_json().stringify(),
    content="{\"version\":2,\"type\":\"SetViewport\",\"viewport\":{\"x\":20,\"y\":-10,\"scale\":2.5}}",
  )
  let decoded : @graph_model.GraphOperation = @json.from_json(
    operation.to_json(),
  )
  let replayed = @graph_model.replay_operations(replay_base_state(), [decoded])
  assert_eq(replayed.viewport, viewport)
  @debug.assert_eq(replayed.action_log, [operation])
}

///|
test "invalid node geometry JSON is rejected before replay" {
  let node = @graph_model.make_workflow_node(
    node_id(9),
    @graph_model.WorkflowNodeKind::Custom("Sized"),
    try! @spatial.WorldPoint::from_xy(x=12.0, y=-4.0),
  )
  let operation_json = operation => {
    let fields : Map[String, Json] = Map([])
    fields["version"] = (2).to_json()
    fields["type"] = "AddNode".to_json()
    fields["node"] = operation
    Json::object(fields)
  }
  let valid_operation = operation_json(
    match
      @graph_model.GraphOperation::GraphOperation(
        @graph_model.WorkflowAction::AddNode(node),
      ).to_json() {
      Json::Object(fields) =>
        match fields.get("node") {
          Some(value) => value
          None => fail("expected node field")
        }
      _ => fail("expected operation object")
    },
  )
  match valid_operation {
    Json::Object(operation_fields) =>
      match operation_fields.get("node") {
        Some(Json::Object(fields)) => {
          let negative_width = fields.copy()
          negative_width["w"] = (-1.0).to_json()
          assert_rejects_viewport_operation(
            operation_json(Json::object(negative_width)),
          )
          let non_finite_height = fields.copy()
          non_finite_height["h"] = Json::number(1.0 / 0.0)
          assert_rejects_viewport_operation(
            operation_json(Json::object(non_finite_height)),
          )
          let non_finite_x = fields.copy()
          non_finite_x["x"] = Json::number(0.0 / 0.0)
          assert_rejects_viewport_operation(
            operation_json(Json::object(non_finite_x)),
          )
        }
        _ => fail("expected node object JSON")
      }
    _ => fail("expected operation object JSON")
  }
}

///|
test "invalid viewport JSON is rejected before replay or action logging" {
  let zero_scale = @json.parse(
    "{\"version\":2,\"type\":\"SetViewport\",\"viewport\":{\"x\":20,\"y\":-10,\"scale\":0}}",
  ) catch {
    _ => abort("expected valid operation JSON")
  }
  let negative_scale = @json.parse(
    "{\"version\":2,\"type\":\"SetViewport\",\"viewport\":{\"x\":20,\"y\":-10,\"scale\":-2}}",
  ) catch {
    _ => abort("expected valid operation JSON")
  }
  assert_rejects_viewport_operation(zero_scale)
  assert_rejects_viewport_operation(negative_scale)
  assert_rejects_viewport_operation(
    viewport_operation_json(viewport_json(0.0 / 0.0)),
  )
  assert_rejects_viewport_operation(
    viewport_operation_json(viewport_json(1.0 / 0.0)),
  )
  assert_rejects_viewport_operation(
    viewport_operation_json(
      viewport_json_with_coordinates(1.0 / 0.0, -10.0, 1.0),
    ),
  )
  assert_rejects_viewport_operation(
    viewport_operation_json(
      viewport_json_with_coordinates(20.0, 0.0 / 0.0, 1.0),
    ),
  )
  assert_eq(replay_base_state().action_log.length(), 0)
}

///|
test "DeleteNodes removes incident edges and deleted selection" {
  let selected = @graph_model.apply_action(
    replay_base_state(),
    @graph_model.WorkflowAction::SelectNodes([node_id(1), node_id(2)]),
  )
  let connected = @graph_model.record_action(
    selected,
    @graph_model.WorkflowAction::ConnectPorts(
      node_id(1),
      "tick",
      node_id(2),
      "in",
    ),
  )
  let deleted = @graph_model.record_action(
    connected,
    @graph_model.WorkflowAction::DeleteNodes([node_id(1)]),
  )
  assert_eq(deleted.nodes.length(), 1)
  assert_eq(deleted.edges.length(), 0)
  @debug.assert_eq(deleted.interaction.selected_nodes, [node_id(2)])
  @debug.debug_inspect(
    deleted.interaction.selected,
    content="Some(NodeId(\"2\"))",
  )
}

///|
test "DisconnectPorts removes only the matching edge" {
  let connected_once = @graph_model.record_action(
    replay_base_state(),
    @graph_model.WorkflowAction::ConnectPorts(
      node_id(1),
      "tick",
      node_id(2),
      "in",
    ),
  )
  let with_unrelated : @graph_model.CanvasState = {
    ..connected_once,
    edges: [
      ..connected_once.edges,
      {
        id: @graph_model.EdgeId::from_edge(
          node_id(2),
          "json",
          node_id(1),
          "tick",
        ),
        source: node_id(2),
        source_port: "json",
        target: node_id(1),
        target_port: "tick",
      },
    ],
  }
  let disconnected = @graph_model.record_action(
    with_unrelated,
    @graph_model.WorkflowAction::DisconnectPorts(
      node_id(1),
      "tick",
      node_id(2),
      "in",
    ),
  )
  assert_eq(disconnected.nodes.length(), 2)
  assert_eq(disconnected.edges.length(), 1)
  @debug.assert_eq(disconnected.edges[0].source, node_id(2))
  @debug.assert_eq(disconnected.edges[0].target, node_id(1))
  assert_eq(disconnected.action_log.length(), 2)
}

///|
test "default input ports reject a second distinct incoming edge" {
  let connected_once = @graph_model.record_action(
    fan_in_base_state(false),
    @graph_model.WorkflowAction::ConnectPorts(
      node_id(1),
      "tick",
      node_id(3),
      "in",
    ),
  )
  assert_eq(connected_once.edges.length(), 1)
  inspect(
    @graph_model.can_commit_edge(
      connected_once,
      node_id(2),
      "tick",
      node_id(3),
      "in",
    ),
    content="false",
  )
  let rejected = @graph_model.record_action(
    connected_once,
    @graph_model.WorkflowAction::ConnectPorts(
      node_id(2),
      "tick",
      node_id(3),
      "in",
    ),
  )
  assert_eq(rejected.edges.length(), 1)
  assert_eq(rejected.action_log.length(), 2)
}

///|
test "explicit fan-in input ports accept distinct incoming edges" {
  let connected_once = @graph_model.record_action(
    fan_in_base_state(true),
    @graph_model.WorkflowAction::ConnectPorts(
      node_id(1),
      "tick",
      node_id(3),
      "in",
    ),
  )
  inspect(
    @graph_model.can_commit_edge(
      connected_once,
      node_id(2),
      "tick",
      node_id(3),
      "in",
    ),
    content="true",
  )
  inspect(
    @graph_model.can_commit_edge(
      connected_once,
      node_id(1),
      "tick",
      node_id(3),
      "in",
    ),
    content="false",
  )
  let connected_twice = @graph_model.record_action(
    connected_once,
    @graph_model.WorkflowAction::ConnectPorts(
      node_id(2),
      "tick",
      node_id(3),
      "in",
    ),
  )
  assert_eq(connected_twice.edges.length(), 2)
}

///|
test "PortDef JSON defaults fan-in capability to false" {
  let json = @json.parse(
    "{\"id\":\"in\",\"label\":\"flow\",\"port_type\":\"Flow\"}",
  ) catch {
    _ => abort("expected valid PortDef JSON")
  }
  let decoded : @graph_model.PortDef = @json.from_json(json)
  inspect(decoded.allows_fan_in, content="false")
  match decoded.to_json() {
    Json::Object(fields) => assert_true(fields.get("allows_fan_in") is None)
    _ => abort("expected PortDef object JSON")
  }
  let fan_in = @graph_model.port(
    "in",
    "flow",
    @graph_model.PortType::Flow,
    allows_fan_in=true,
  )
  match fan_in.to_json() {
    Json::Object(fields) =>
      match fields.get("allows_fan_in") {
        Some(Json::True) => ()
        _ => abort("expected explicit fan-in flag in PortDef JSON")
      }
    _ => abort("expected PortDef object JSON")
  }
}
