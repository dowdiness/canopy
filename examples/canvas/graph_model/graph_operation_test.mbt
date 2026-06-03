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
  let selected = @graph_model.set_selection(replay_base_state(), [
    node_id(1),
    node_id(2),
  ])
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
