///|
fn make_test_state() -> CanvasState {
  {
    viewport: Viewport::from_scale(
      origin=try! ScreenPoint::from_xy(x=0.0, y=0.0),
      scale=try! @spatial.Scale::from_double(value=1.0),
    ),
    nodes: [
      @graph_model.make_workflow_node(
        NodeId("1"), TimerTrigger,
        try! @spatial.WorldPoint::from_xy(x=100.0, y=100.0),
      ),
      @graph_model.make_workflow_node(
        NodeId("2"), HttpRequest,
        try! @spatial.WorldPoint::from_xy(x=420.0, y=100.0),
      ),
      @graph_model.make_workflow_node(
        NodeId("3"), DataFormatter,
        try! @spatial.WorldPoint::from_xy(x=760.0, y=100.0),
      ),
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
    @graph_model.make_workflow_node(
      NodeId("4"), ConditionalBranch,
      try! @spatial.WorldPoint::from_xy(x=0.0, y=0.0),
    ),
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
  let messages = validate_workflow_document(
    @graph_model.canvas_document_from_state(state),
  )
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
fn compatibility_for(
  entries : Array[PortCompatibilityJson],
  node_id : String,
  port_id : String,
) -> Bool {
  match
    entries
    .iter()
    .find_first(fn(entry) {
      entry.node_id == node_id && entry.port_id == port_id
    }) {
    Some(entry) => entry.compatible
    None => abort("missing compatibility entry: " + node_id + "." + port_id)
  }
}

///|
test "runtime ignores non-finite drag moves before commit" {
  let runtime = CanvasRuntime::CanvasRuntime()
  let initial = runtime.state_peek()
  let node = initial.nodes[0]
  let screen = initial.viewport.world_to_screen(
    node.position(),
  )
  ignore(runtime.pointer_down(Some(node.id), screen.x(), screen.y()))
  runtime.pointer_move(1.0 / 0.0, screen.y())
  runtime.pointer_up(node.id.to_string(), "", false)
  let next = runtime.state_peek()
  assert_eq(next.nodes[0].position(), node.position())
  assert_true(next.action_log.length() > 0)
  match next.action_log[0].action() {
    MoveNodes(_) => fail("invalid drag move must not commit")
    _ => ()
  }
}

///|
test "runtime pointer admission rejects missing nodes without mutation" {
  let runtime = CanvasRuntime::CanvasRuntime()
  let before = runtime.state_peek()
  assert_false(
    runtime.pointer_down(Some(NodeId("missing")), 0.0, 0.0),
  )
  let after = runtime.state_peek()
  assert_eq(after.interaction, before.interaction)
  assert_eq(after.action_log.length(), before.action_log.length())
}

///|
///|
test "runtime wheel rejects zero and active gesture input" {
  let runtime = CanvasRuntime::CanvasRuntime()
  let before = runtime.state_peek()
  runtime.zoom(0.0, 0, false, 10.0, 10.0)
  let zero = runtime.state_peek()
  assert_eq(zero.viewport, before.viewport)
  assert_eq(zero.action_log.length(), before.action_log.length())

  ignore(runtime.pointer_down(None, 10.0, 10.0))
  let active = runtime.state_peek()
  runtime.zoom(-100.0, 0, false, 20.0, 20.0)
  let during = runtime.state_peek()
  assert_eq(during.viewport, active.viewport)
  assert_eq(during.action_log.length(), active.action_log.length())
  runtime.pointer_interrupt()

  runtime.sync_viewport_state({
    ..runtime.state_peek(),
    viewport: Viewport::from_scale(
      origin=try! ScreenPoint::from_xy(x=0.0, y=0.0),
      scale=try! @spatial.Scale::from_double(value=8.0),
    ),
  })
  let at_max = runtime.state_peek()
  runtime.zoom(-100.0, 0, false, 100.0, 100.0)
  let repeated = runtime.state_peek()
  assert_eq(repeated.viewport, at_max.viewport)
  assert_eq(repeated.action_log.length(), at_max.action_log.length())
}

///|
test "runtime compatibility export batches graph model results" {
  let runtime = CanvasRuntime::CanvasRuntime()
  let entries = runtime.input_port_compatibility(NodeId("2"), "json")
  assert_eq(entries.length(), 6)
  inspect(compatibility_for(entries, "5", "items"), content="true")
  inspect(compatibility_for(entries, "6", "in"), content="false")
  inspect(compatibility_for(entries, "2", "in"), content="false")
  inspect(compatibility_for(entries, "3", "json"), content="false")
}

///|
test "runtime delete_nodes removes selected nodes and incident edges" {
  let runtime = CanvasRuntime::CanvasRuntime()
  runtime.delete_nodes([NodeId("2")])
  let state = runtime.render_state()
  assert_eq(state.nodes.length(), 5)
  assert_eq(state.edges.length(), 1)
  let actions = runtime.action_log_snapshot()
  assert_eq(actions.length(), 1)
  match actions[0].action() {
    DeleteNodes(nodes) => @debug.assert_eq(nodes, [NodeId("2")])
    _ => fail("expected DeleteNodes action")
  }
}

///|
test "runtime edge selection is ephemeral and edge-first" {
  let runtime = CanvasRuntime::CanvasRuntime()
  let initial = runtime.state_peek()
  let edge = initial.edges[0]
  runtime.set_selection({
    selected: Some(NodeId("1")),
    selected_nodes: [NodeId("1")],
  })
  runtime.select_edge(edge.id)
  assert_eq(runtime.render_state().selected_edge, Some(edge.id.to_string()))
  assert_eq(runtime.action_log_snapshot().length(), 0)

  assert_true(runtime.delete_selection())
  let after_edge = runtime.render_state()
  assert_eq(after_edge.selected_edge, None)
  assert_eq(after_edge.nodes.length(), 6)
  assert_eq(after_edge.edges.length(), 2)
  assert_eq(after_edge.selected_nodes, ["1"])
  assert_eq(after_edge.action_count, 1)
  match runtime.action_log_snapshot()[0].action() {
    DisconnectPorts(source, source_port, target, target_port) => {
      @debug.assert_eq(source, NodeId("1"))
      inspect(source_port, content="tick")
      @debug.assert_eq(target, NodeId("2"))
      inspect(target_port, content="in")
    }
    _ => fail("expected DisconnectPorts action")
  }

  assert_true(runtime.delete_selection())
  let after_node = runtime.render_state()
  assert_eq(after_node.nodes.length(), 5)
  assert_eq(after_node.action_count, 2)
  assert_eq(after_node.selected_nodes, [])
}

///|
test "runtime sparse inspector follows hover until a node is selected" {
  let runtime = CanvasRuntime::CanvasRuntime()
  runtime.sync_viewport_state({
    ..runtime.state_peek(),
    viewport: Viewport::from_scale(
      origin=try! ScreenPoint::from_xy(x=0.0, y=0.0),
      scale=try! @spatial.Scale::from_double(value=1.0),
    ),
  })
  runtime.hover_node("1")
  match runtime.render_state().inspector {
    Some(node) => {
      inspect(node.source, content="hovered")
      inspect(node.title, content="Timer trigger")
    }
    None => fail("expected hovered inspector")
  }

  ignore(runtime.pointer_down(Some(NodeId("2")), -190.0, -190.0))
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
