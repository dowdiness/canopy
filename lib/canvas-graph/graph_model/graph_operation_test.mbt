///|
fn node_id(n : Int) -> @graph_model.NodeId {
  @graph_model.NodeId::from_int(n)
}

///|
fn replay_base_state() -> @graph_model.CanvasState {
  {
    viewport: { x: 0.0, y: 0.0, scale: 1.0 },
    nodes: [
      @graph_model.make_workflow_node(
        node_id(1),
        @graph_model.WorkflowNodeKind::TimerTrigger,
        100.0,
        100.0,
      ),
      @graph_model.make_workflow_node(
        node_id(2),
        @graph_model.WorkflowNodeKind::HttpRequest,
        420.0,
        100.0,
      ),
    ],
    edges: [],
    next_node_id: 3,
    next_edge_id: 1,
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
    content="{\"version\":1,\"type\":\"ConnectPorts\",\"source\":1,\"source_port\":\"tick\",\"target\":2,\"target_port\":\"in\"}",
  )
}

///|
test "GraphOperation round-trips through JSON" {
  let operation = @graph_model.GraphOperation::GraphOperation(
    @graph_model.WorkflowAction::MoveNodes([
      { node_id: node_id(1), x: 180.0, y: 240.0 },
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
    content="{\"version\":1,\"type\":\"DeleteNodes\",\"nodes\":[1,2]}",
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
    content="{\"version\":1,\"type\":\"DisconnectPorts\",\"source\":1,\"source_port\":\"tick\",\"target\":2,\"target_port\":\"in\"}",
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
    content="{\"version\":1,\"type\":\"RenameNode\",\"node_id\":1,\"name\":\"oscillator\"}",
  )
  let set_param = @graph_model.GraphOperation::GraphOperation(
    @graph_model.WorkflowAction::SetNodeParam(node_id(1), "freq", "880"),
  )
  inspect(
    set_param.to_json().stringify(),
    content="{\"version\":1,\"type\":\"SetNodeParam\",\"node_id\":1,\"parameter\":\"freq\",\"value\":\"880\"}",
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
    760.0,
    100.0,
  )
  let operations = [
    @graph_model.GraphOperation::GraphOperation(
      @graph_model.WorkflowAction::AddNode(added),
    ),
    @graph_model.GraphOperation::GraphOperation(
      @graph_model.WorkflowAction::MoveNodes([
        { node_id: node_id(3), x: 800.0, y: 140.0 },
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
  assert_eq(replayed.nodes[1].x, 800.0)
  assert_eq(replayed.nodes[1].y, 140.0)
  assert_eq(replayed.action_log.length(), 4)
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
  @debug.debug_inspect(deleted.interaction.selected, content="Some(NodeId(2))")
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
        id: @graph_model.EdgeId::from_int(2),
        source: node_id(2),
        source_port: "json",
        target: node_id(1),
        target_port: "tick",
      },
    ],
    next_edge_id: 3,
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
