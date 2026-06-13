///|
fn make_test_state() -> CanvasState {
  {
    viewport: { x: 0.0, y: 0.0, scale: 1.0 },
    nodes: [
      @graph_model.make_workflow_node(NodeId("1"), TimerTrigger, 100.0, 100.0),
      @graph_model.make_workflow_node(NodeId("2"), HttpRequest, 420.0, 100.0),
      @graph_model.make_workflow_node(NodeId("3"), DataFormatter, 760.0, 100.0),
    ],
    edges: [],
    next_node_id: 4,
    interaction: @graph_model.empty_interaction(),
    action_log: [],
  }
}

///|
test "validate_workflow reports missing typed input ports independently" {
  let nodes = make_test_state().nodes.copy()
  nodes.push(
    @graph_model.make_workflow_node(NodeId("4"), ConditionalBranch, 0.0, 0.0),
  )
  let state : CanvasState = {
    ..make_test_state(),
    nodes,
    edges: [
      {
        id: EdgeId::from_edge(NodeId("3"), "text", NodeId("4"), "text"),
        source: NodeId("3"),
        source_port: "text",
        target: NodeId("4"),
        target_port: "text",
      },
    ],
  }
  let messages = validate_workflow(state)
  assert_true(
    messages
    .iter()
    .any(fn(message) {
      message.node_id == Some("4") &&
      message.message.contains("input “rule”")
    }),
  )
  assert_false(
    messages
    .iter()
    .any(fn(message) {
      message.node_id == Some("4") &&
      message.message.contains("input “text”")
    }),
  )
}

///|
test "get_render_state exposes workflow JSON shape" {
  let handle = create_canvas()
  let json_str = get_render_state(handle)
  assert_true(json_str.contains("\"nodes\""))
  assert_true(json_str.contains("Timer trigger"))
  assert_true(json_str.contains("\"source_port\""))
  assert_true(json_str.contains("\"validation\""))
}

///|
test "runtime live drag updates preview before one durable MoveNodes commit" {
  let runtime = CanvasRuntime::CanvasRuntime()
  runtime.viewport.set({ x: 0.0, y: 0.0, scale: 1.0 })
  let before = runtime.document.peek()
  runtime.pointer_down(Some(NodeId("1")), -510.0, -180.0)
  runtime.pointer_move(-400.0, -100.0)

  let during = runtime.document.peek()
  inspect(during.nodes[0].x, content="-520")
  inspect(during.nodes[0].y, content="-190")
  assert_eq(runtime.actions.peek().length(), 0)

  let preview = runtime.render_state().nodes[0]
  inspect(preview.x, content="-410")
  inspect(preview.y, content="-110")
  assert_eq(before.nodes[0].x, during.nodes[0].x)

  runtime.pointer_up("1", "", false)
  let after = runtime.document.peek()
  inspect(after.nodes[0].x, content="-410")
  inspect(after.nodes[0].y, content="-110")
  assert_eq(runtime.actions.peek().length(), 1)
  match runtime.actions.peek()[0].action() {
    MoveNodes(positions) => {
      assert_eq(positions.length(), 1)
      inspect(positions[0].x, content="-410")
      inspect(positions[0].y, content="-110")
    }
    _ => fail("expected MoveNodes action")
  }
}

///|
test "runtime delete_nodes removes selected nodes and incident edges" {
  let runtime = CanvasRuntime::CanvasRuntime()
  runtime.delete_nodes([NodeId("2")])
  let state = runtime.render_state()
  assert_eq(state.nodes.length(), 5)
  assert_eq(state.edges.length(), 1)
  assert_eq(runtime.actions.peek().length(), 1)
  match runtime.actions.peek()[0].action() {
    DeleteNodes(nodes) => @debug.assert_eq(nodes, [NodeId("2")])
    _ => fail("expected DeleteNodes action")
  }
}

///|
test "runtime sparse inspector follows hover until a node is selected" {
  let runtime = CanvasRuntime::CanvasRuntime()
  runtime.viewport.set({ x: 0.0, y: 0.0, scale: 1.0 })
  runtime.hover_node("1")
  match runtime.render_state().inspector {
    Some(node) => {
      inspect(node.source, content="hovered")
      inspect(node.title, content="Timer trigger")
    }
    None => fail("expected hovered inspector")
  }

  runtime.pointer_down(Some(NodeId("2")), -190.0, -190.0)
  runtime.pointer_up("2", "", false)
  runtime.hover_node("1")
  match runtime.render_state().inspector {
    Some(node) => {
      inspect(node.source, content="selected")
      inspect(node.title, content="HTTP request")
    }
    None => fail("expected selected inspector")
  }
}
