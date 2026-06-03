///|
fn make_test_state() -> CanvasState {
  {
    viewport: { x: 0.0, y: 0.0, scale: 1.0 },
    nodes: [
      make_workflow_node(NodeId(1), TimerTrigger, 100.0, 100.0),
      make_workflow_node(NodeId(2), HttpRequest, 420.0, 100.0),
      make_workflow_node(NodeId(3), DataFormatter, 760.0, 100.0),
    ],
    edges: [],
    next_node_id: 4,
    next_edge_id: 1,
    interaction: @graph_model.empty_interaction(),
    action_log: [],
  }
}

///|
test "pan_start records start screen position and current pan" {
  let state = make_test_state()
  let s = update_pan_start(state, 150.0, 250.0)
  guard s.interaction.panning is Some(p)
  inspect(p.start_screen_x, content="150")
  inspect(p.start_screen_y, content="250")
  inspect(p.start_pan_x, content="0")
  inspect(p.start_pan_y, content="0")
  inspect(s.interaction.pointer_down, content="true")
  inspect(s.interaction.did_move, content="false")
}

///|
test "pan_move translates viewport by delta from start" {
  let state = make_test_state()
  let s0 = update_pan_start(state, 100.0, 100.0)
  let s1 = update_pan_move(s0, 160.0, 140.0)
  inspect(s1.viewport.x, content="60")
  inspect(s1.viewport.y, content="40")
  inspect(s1.viewport.scale, content="1")
  inspect(s1.interaction.did_move, content="true")
}

///|
test "pan_move is absolute not cumulative" {
  let state = make_test_state()
  let s0 = update_pan_start(state, 0.0, 0.0)
  let s1 = update_pan_move(s0, 50.0, 30.0)
  let s2 = update_pan_move(s1, 80.0, 50.0)
  inspect(s2.viewport.x, content="80")
  inspect(s2.viewport.y, content="50")
}

///|
test "pan_move is no-op when not panning" {
  let state = make_test_state()
  let s = update_pan_move(state, 999.0, 999.0)
  inspect(s.viewport.x, content="0")
  inspect(s.viewport.y, content="0")
}

///|
test "zoom changes scale and records a serializable action" {
  let state = make_test_state()
  let s = update_zoom(state, -1.0, 500.0, 400.0)
  assert_true(s.viewport.scale > 1.0)
  assert_eq(s.action_log.length(), 1)
  match s.action_log[0].action() {
    WorkflowAction::SetViewport(viewport) => assert_eq(viewport, s.viewport)
    _ => fail("expected SetViewport action")
  }
}

///|
test "zoom clamps to min 0.1 and max 8.0" {
  let min_state = {
    ..make_test_state(),
    viewport: { x: 0.0, y: 0.0, scale: 0.11 },
  }
  let min_zoom = update_zoom(min_state, 1.0, 0.0, 0.0)
  assert_eq(min_zoom.viewport.scale, 0.1)
  let max_state = {
    ..make_test_state(),
    viewport: { x: 0.0, y: 0.0, scale: 7.5 },
  }
  let max_zoom = update_zoom(max_state, -1.0, 0.0, 0.0)
  assert_eq(max_zoom.viewport.scale, 8.0)
}

///|
test "zoom keeps cursor world position fixed" {
  let state = make_test_state()
  let cx = 300.0
  let cy = 200.0
  let world_x_before = (cx - state.viewport.x) / state.viewport.scale
  let s = update_zoom(state, 1.0, cx, cy)
  let world_x_after = (cx - s.viewport.x) / s.viewport.scale
  assert_true((world_x_before - world_x_after).abs() < 1.0e-9)
}

///|
test "node_drag_start records offsets for the dragged node" {
  let state = make_test_state()
  let s = update_node_drag_start(state, NodeId(1), 110.0, 120.0)
  guard s.interaction.dragging is Some(d)
  assert_eq(d.node_id, NodeId(1))
  assert_eq(d.origins.length(), 1)
  inspect(d.origins[0].offset_x, content="-10")
  inspect(d.origins[0].offset_y, content="-20")
  assert_true(s.interaction.pointer_down)
  assert_eq(s.interaction.did_move, false)
}

///|
test "node_drag_start includes all selected nodes for multi-drag" {
  let state = @graph_model.set_selection(make_test_state(), [
    NodeId(1),
    NodeId(2),
  ])
  let s = update_node_drag_start(state, NodeId(1), 110.0, 120.0)
  guard s.interaction.dragging is Some(d)
  assert_eq(d.origins.length(), 2)
}

///|
test "node_drag_start is no-op for unknown node id" {
  let state = make_test_state()
  let s = update_node_drag_start(state, NodeId(99), 0.0, 0.0)
  assert_true(s.interaction.dragging is None)
}

///|
test "pointer_up records a MoveNodes action after drag" {
  let state = make_test_state()
  let s0 = update_node_drag_start(state, NodeId(1), 110.0, 120.0)
  let preview = drag_preview_from_move(
    match s0.interaction.dragging {
      Some(drag) => drag
      None => fail("expected active drag")
    },
    200.0,
    300.0,
  )
  let moved_nodes = s0.nodes.map(fn(node) {
    match find_position(preview.positions, node.id) {
      None => node
      Some(pos) => { ..node, x: pos.x, y: pos.y }
    }
  })
  let s1 = {
    ..s0,
    nodes: moved_nodes,
    interaction: { ..s0.interaction, did_move: true },
  }
  let s2 = update_pointer_up(s1, 1, "", false)
  assert_eq(s2.action_log.length(), 1)
  match s2.action_log[0].action() {
    WorkflowAction::MoveNodes(positions) => {
      assert_eq(positions.length(), 1)
      inspect(positions[0].x, content="190")
      inspect(positions[0].y, content="280")
    }
    _ => fail("expected MoveNodes action")
  }
}

///|
test "pointer_up on node without movement selects it" {
  let state = make_test_state()
  let s0 = update_node_drag_start(state, NodeId(1), 100.0, 100.0)
  let s1 = update_pointer_up(s0, 1, "", false)
  @debug.debug_inspect(s1.interaction.selected, content="Some(NodeId(1))")
  @debug.assert_eq(s1.interaction.selected_nodes, [NodeId(1)])
}

///|
test "additive click toggles multi-selection" {
  let state = @graph_model.set_selection(make_test_state(), [NodeId(1)])
  let s0 = update_node_drag_start(state, NodeId(2), 420.0, 100.0)
  let s1 = update_pointer_up(s0, 2, "", true)
  @debug.assert_eq(s1.interaction.selected_nodes, [NodeId(1), NodeId(2)])
  let s2 = update_node_drag_start(s1, NodeId(1), 100.0, 100.0)
  let s3 = update_pointer_up(s2, 1, "", true)
  @debug.assert_eq(s3.interaction.selected_nodes, [NodeId(2)])
}

///|
test "pointer_up on background deselects" {
  let state = @graph_model.set_selection(make_test_state(), [NodeId(1)])
  let s0 = update_pan_start(state, 0.0, 0.0)
  let s1 = update_pointer_up(s0, 0, "", false)
  inspect(s1.interaction.selected is None, content="true")
  assert_eq(s1.interaction.selected_nodes.length(), 0)
}

///|
test "connect_start records source node, source port, and cursor world position" {
  let state = make_test_state()
  let s = update_connect_start(state, NodeId(1), "tick", 250.0, 80.0)
  guard s.interaction.connecting is Some(c)
  assert_eq(c.from_node, NodeId(1))
  inspect(c.from_port, content="tick")
  inspect(c.cursor_x, content="250")
  inspect(c.cursor_y, content="80")
  assert_true(s.interaction.pointer_down)
}

///|
test "connect_move updates cursor world position" {
  let state = make_test_state()
  let s0 = update_connect_start(state, NodeId(1), "tick", 0.0, 0.0)
  let s1 = update_connect_move(s0, 333.0, 444.0)
  guard s1.interaction.connecting is Some(c)
  inspect(c.cursor_x, content="333")
  inspect(c.cursor_y, content="444")
  assert_true(s1.interaction.did_move)
}

///|
test "connect_end commits compatible typed ports" {
  let state = make_test_state()
  let s0 = update_connect_start(state, NodeId(1), "tick", 0.0, 0.0)
  let s1 = update_connect_end(s0, Some(NodeId(2)), Some("in"))
  assert_eq(s1.edges.length(), 1)
  assert_eq(s1.edges[0].source, NodeId(1))
  assert_eq(s1.edges[0].source_port, "tick")
  assert_eq(s1.edges[0].target, NodeId(2))
  assert_eq(s1.edges[0].target_port, "in")
  assert_true(s1.interaction.connecting is None)
  assert_eq(s1.action_log.length(), 1)
}

///|
test "connect_end uses the explicit target port" {
  let nodes = make_test_state().nodes.copy()
  nodes.push(make_workflow_node(NodeId(4), Custom("Any source"), 0.0, 0.0))
  nodes.push(make_workflow_node(NodeId(5), ConditionalBranch, 0.0, 0.0))
  let state : CanvasState = { ..make_test_state(), nodes, }
  let s0 = update_connect_start(state, NodeId(4), "out", 0.0, 0.0)
  let s1 = update_connect_end(s0, Some(NodeId(5)), Some("rule"))
  assert_eq(s1.edges.length(), 1)
  assert_eq(s1.edges[0].source_port, "out")
  assert_eq(s1.edges[0].target_port, "rule")
}

///|
test "connect_end rejects incompatible ports" {
  let state = make_test_state()
  let s0 = update_connect_start(state, NodeId(1), "tick", 0.0, 0.0)
  let s1 = update_connect_end(s0, Some(NodeId(3)), Some("json"))
  assert_eq(s1.edges.length(), 0)
  assert_true(s1.interaction.connecting is None)
  // Rejected attempts are still logged for audit/collaboration streams.
  assert_eq(s1.action_log.length(), 1)
}

///|
test "connect_end does not create self-loops or duplicates" {
  let state = make_test_state()
  let self_loop = update_connect_end(
    update_connect_start(state, NodeId(2), "json", 0.0, 0.0),
    Some(NodeId(2)),
    Some("in"),
  )
  assert_eq(self_loop.edges.length(), 0)

  let with_edge : CanvasState = {
    ..make_test_state(),
    edges: [
      {
        id: EdgeId(1),
        source: NodeId(1),
        source_port: "tick",
        target: NodeId(2),
        target_port: "in",
      },
    ],
    next_edge_id: 2,
  }
  let duplicate = update_connect_end(
    update_connect_start(with_edge, NodeId(1), "tick", 0.0, 0.0),
    Some(NodeId(2)),
    Some("in"),
  )
  assert_eq(duplicate.edges.length(), 1)
}

///|
test "workflow_add_node creates typed custom nodes through serializable action" {
  let state = make_test_state()
  let s = workflow_add_node(state, "custom", 12.0, 34.0)
  assert_eq(s.nodes.length(), 4)
  assert_eq(s.next_node_id, 5)
  assert_eq(s.action_log.length(), 1)
  inspect(s.nodes[3].title, content="Custom step")
  match s.action_log[0].action() {
    WorkflowAction::AddNode(node) => assert_eq(node.id, NodeId(4))
    _ => fail("expected AddNode action")
  }
}

///|
test "validate_workflow reports missing typed input ports independently" {
  let nodes = make_test_state().nodes.copy()
  nodes.push(make_workflow_node(NodeId(4), ConditionalBranch, 0.0, 0.0))
  let state : CanvasState = {
    ..make_test_state(),
    nodes,
    edges: [
      {
        id: EdgeId(1),
        source: NodeId(3),
        source_port: "text",
        target: NodeId(4),
        target_port: "text",
      },
    ],
    next_edge_id: 2,
  }
  let messages = validate_workflow(state)
  assert_true(
    messages
    .iter()
    .any(fn(message) {
      message.node_id == Some(4) && message.message.contains("input “rule”")
    }),
  )
  assert_false(
    messages
    .iter()
    .any(fn(message) {
      message.node_id == Some(4) && message.message.contains("input “text”")
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
  runtime.pointer_down(Some(NodeId(1)), -510.0, -180.0)
  runtime.pointer_move(-400.0, -100.0)

  let during = runtime.document.peek()
  inspect(during.nodes[0].x, content="-520")
  inspect(during.nodes[0].y, content="-190")
  assert_eq(runtime.actions.peek().length(), 0)

  let preview = runtime.render_state().nodes[0]
  inspect(preview.x, content="-410")
  inspect(preview.y, content="-110")
  assert_eq(before.nodes[0].x, during.nodes[0].x)

  runtime.pointer_up(1, "", false)
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
  runtime.delete_nodes([NodeId(2)])
  let state = runtime.render_state()
  assert_eq(state.nodes.length(), 5)
  assert_eq(state.edges.length(), 1)
  assert_eq(runtime.actions.peek().length(), 1)
  match runtime.actions.peek()[0].action() {
    DeleteNodes(nodes) => @debug.assert_eq(nodes, [NodeId(2)])
    _ => fail("expected DeleteNodes action")
  }
}

///|
test "runtime sparse inspector follows hover until a node is selected" {
  let runtime = CanvasRuntime::CanvasRuntime()
  runtime.viewport.set({ x: 0.0, y: 0.0, scale: 1.0 })
  runtime.hover_node(1)
  match runtime.render_state().inspector {
    Some(node) => {
      inspect(node.source, content="hovered")
      inspect(node.title, content="Timer trigger")
    }
    None => fail("expected hovered inspector")
  }

  runtime.pointer_down(Some(NodeId(2)), -190.0, -190.0)
  runtime.pointer_up(2, "", false)
  runtime.hover_node(1)
  match runtime.render_state().inspector {
    Some(node) => {
      inspect(node.source, content="selected")
      inspect(node.title, content="HTTP request")
    }
    None => fail("expected selected inspector")
  }
}
