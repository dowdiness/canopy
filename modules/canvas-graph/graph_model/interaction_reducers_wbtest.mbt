///|
fn screen_point(x : Double, y : Double) -> ScreenPoint {
  try! ScreenPoint::from_xy(x~, y~)
}

///|
fn world_point(x : Double, y : Double) -> WorldPoint {
  try! WorldPoint::from_xy(x~, y~)
}

///|
fn scale(value : Double) -> @spatial.Scale {
  try! @spatial.Scale::from_double(value~)
}

///|
fn viewport_for_test(
  origin_x : Double,
  origin_y : Double,
  scale_value : Double,
) -> Viewport {
  Viewport::from_scale(
    origin=screen_point(origin_x, origin_y),
    scale=scale(scale_value),
  )
}

///|
fn make_test_state() -> CanvasState {
  {
    viewport: viewport_for_test(0.0, 0.0, 1.0),
    nodes: [
      make_workflow_node(
        NodeId("1"),
        TimerTrigger,
        try! WorldPoint::from_xy(x=100.0, y=100.0),
      ),
      make_workflow_node(
        NodeId("2"),
        HttpRequest,
        try! WorldPoint::from_xy(x=420.0, y=100.0),
      ),
      make_workflow_node(
        NodeId("3"),
        DataFormatter,
        try! WorldPoint::from_xy(x=760.0, y=100.0),
      ),
    ],
    edges: [],
    next_node_id: 4,
    interaction: empty_interaction(),
    action_log: [],
  }
}

///|
test "pan_start records pointer and viewport snapshots" {
  let state = make_test_state()
  let s = update_pan_start(state, screen_point(150.0, 250.0))
  guard! s.interaction.panning is Some(p)
  inspect(p.start_pointer().x(), content="150")
  inspect(p.start_pointer().y(), content="250")
  let snapshot = try! p.viewport_at(p.start_pointer())
  let origin = snapshot.screen_origin()
  inspect(origin.x(), content="0")
  inspect(origin.y(), content="0")
  inspect(snapshot.scale().to_double(), content="1")
  inspect(s.interaction.pointer_down, content="true")
  inspect(s.interaction.did_move, content="false")
}

///|
test "pan_move translates viewport by delta from start" {
  let state = make_test_state()
  let s0 = update_pan_start(state, screen_point(100.0, 100.0))
  let s1 = update_pan_move(s0, screen_point(160.0, 140.0))
  let origin = s1.viewport.screen_origin()
  inspect(origin.x(), content="60")
  inspect(origin.y(), content="40")
  inspect(s1.viewport.scale().to_double(), content="1")
  inspect(s1.interaction.did_move, content="true")
}

///|
test "pan_move is absolute not cumulative" {
  let state = make_test_state()
  let s0 = update_pan_start(state, screen_point(0.0, 0.0))
  let s1 = update_pan_move(s0, screen_point(50.0, 30.0))
  let s2 = update_pan_move(s1, screen_point(80.0, 50.0))
  let origin = s2.viewport.screen_origin()
  inspect(origin.x(), content="80")
  inspect(origin.y(), content="50")
}

///|
test "pan_move preserves the initial viewport snapshot" {
  let state = {
    ..make_test_state(),
    viewport: viewport_for_test(10.0, -20.0, 2.5),
  }
  let started = update_pan_start(state, screen_point(100.0, 200.0))
  let moved = update_pan_move(started, screen_point(115.0, 207.0))
  let origin = moved.viewport.screen_origin()
  assert_eq(origin.x(), 25.0)
  assert_eq(origin.y(), -13.0)
  assert_eq(moved.viewport.scale().to_double(), 2.5)
}

///|
test "pan_move is no-op when not panning" {
  let state = make_test_state()
  let s = update_pan_move(state, screen_point(999.0, 999.0))
  let origin = s.viewport.screen_origin()
  inspect(origin.x(), content="0")
  inspect(origin.y(), content="0")
}

///|
test "pan and drag reject non-finite input" {
  let state = make_test_state()
  let invalid_start = try {
    ignore(ScreenPoint::from_xy(x=0.0 / 0.0, y=0.0))
    false
  } catch {
    @spatial.CoordinateError::NonFinite => true
  }
  assert_true(invalid_start)

  let invalid_move = try {
    ignore(ScreenPoint::from_xy(x=1.0 / 0.0, y=20.0))
    false
  } catch {
    @spatial.CoordinateError::NonFinite => true
  }
  assert_true(invalid_move)

  let invalid_drag = try {
    ignore(WorldPoint::from_xy(x=0.0, y=1.0 / 0.0))
    false
  } catch {
    @spatial.CoordinateError::NonFinite => true
  }
  assert_true(invalid_drag)

  // Typed inputs that overflow during reduction still leave state untouched.
  let extreme_started = update_pan_start(state, screen_point(-1.0e308, 0.0))
  let overflowing_move = update_pan_move(
    extreme_started,
    screen_point(1.0e308, 0.0),
  )
  assert_eq(overflowing_move.viewport, extreme_started.viewport)
  assert_eq(overflowing_move.interaction.did_move, false)
}

///|
test "zoom rejects an overflowing anchored origin" {
  let state = {
    ..make_test_state(),
    viewport: viewport_for_test(0.0, 0.0, 1.0e-308),
  }
  let scale = try! @spatial.Scale::from_double(value=2.0)
  let unchanged = update_viewport_scale_around(
    state,
    scale,
    screen_point(1.0e308, 0.0),
  )
  assert_eq(unchanged.viewport, state.viewport)
  assert_eq(unchanged.action_log.length(), 0)
}

///|
test "semantic viewport scale no-op does not record an action" {
  let state = make_test_state()
  let scale = try! @spatial.Scale::from_double(
    value=state.viewport.scale().to_double(),
  )
  let next = update_viewport_scale_around(state, scale, screen_point(0.0, 0.0))
  assert_eq(next.viewport, state.viewport)
  assert_eq(next.action_log.length(), 0)
}

///|
test "semantic scale changes viewport and records a serializable action" {
  let state = make_test_state()
  let scale = try! @spatial.Scale::from_double(value=1.5)
  let s = update_viewport_scale_around(state, scale, screen_point(500.0, 400.0))
  assert_true(s.viewport.scale().to_double() > 1.0)
  assert_eq(s.action_log.length(), 1)
  match s.action_log[0].action() {
    WorkflowAction::SetViewport(viewport) => assert_eq(viewport, s.viewport)
    _ => fail("expected SetViewport action")
  }
}

///|
test "semantic scale keeps cursor world position fixed" {
  let state = make_test_state()
  let cx = 300.0
  let cy = 200.0
  let anchor = screen_point(cx, cy)
  let world_x_before = try! state.viewport.screen_to_world(anchor).x()
  let scale = try! @spatial.Scale::from_double(value=1.5)
  let s = update_viewport_scale_around(state, scale, anchor)
  let world_x_after = try! s.viewport.screen_to_world(anchor).x()
  assert_true((world_x_before - world_x_after).abs() < 1.0e-9)
}

///|
test "node_drag_start records offsets for the dragged node" {
  let state = make_test_state()
  let s = update_node_drag_start(state, NodeId("1"), world_point(110.0, 120.0))
  guard! s.interaction.dragging is Some(d)
  assert_eq(d.initial_ids(), [NodeId("1")])
  let positions = try! d.positions_at(world_point(110.0, 120.0))
  inspect(positions[0].point.x(), content="100")
  inspect(positions[0].point.y(), content="100")
  assert_true(s.interaction.pointer_down)
  assert_eq(s.interaction.did_move, false)
}

///|
test "node_drag_start includes all selected nodes for multi-drag" {
  let state = apply_action(
    make_test_state(),
    SelectNodes([NodeId("1"), NodeId("2")]),
  )
  let s = update_node_drag_start(state, NodeId("1"), world_point(110.0, 120.0))
  guard! s.interaction.dragging is Some(d)
  assert_eq(d.initial_ids().length(), 2)
}

///|
test "node_drag_start is no-op for unknown node id" {
  let state = make_test_state()
  let s = update_node_drag_start(state, NodeId("99"), world_point(0.0, 0.0))
  assert_true(s.interaction.dragging is None)
}

///|
test "pointer_up records a MoveNodes action after drag" {
  let state = make_test_state()
  let s0 = update_node_drag_start(state, NodeId("1"), world_point(110.0, 120.0))
  let preview = try! drag_preview_from_move(
    match s0.interaction.dragging {
      Some(drag) => drag
      None => fail("expected active drag")
    },
    world_point(200.0, 300.0),
  )
  let s1 = {
    ..state_with_preview_nodes(s0, preview),
    interaction: { ..s0.interaction, did_move: true },
  }
  let s2 = update_pointer_up(s1, "1", "", false)
  assert_eq(s2.action_log.length(), 1)
  match s2.action_log[0].action() {
    WorkflowAction::MoveNodes(positions) => {
      assert_eq(positions.length(), 1)
      inspect(positions[0].point.x(), content="190")
      inspect(positions[0].point.y(), content="280")
    }
    _ => fail("expected MoveNodes action")
  }
}

///|
test "invalid drag move is ignored before pointer up" {
  let state = make_test_state()
  let started = update_node_drag_start(
    state,
    NodeId("1"),
    world_point(-1.0e308, 0.0),
  )
  let drag = match started.interaction.dragging {
    Some(drag) => drag
    None => fail("expected active drag")
  }
  let rejected = try {
    ignore(drag_preview_from_move(drag, world_point(1.0e308, 200.0)))
    false
  } catch {
    @spatial.CoordinateError::NonFinite => true
  }
  assert_true(rejected)
  let released = update_pointer_up(started, "1", "", false)
  assert_eq(released.nodes[0].position().x(), 100.0)
  assert_eq(released.nodes[0].position().y(), 100.0)
  match released.action_log[0].action() {
    MoveNodes(_) => fail("invalid drag move must not commit")
    _ => ()
  }
}

///|
test "pointer_up on node without movement selects it" {
  let state = make_test_state()
  let s0 = update_node_drag_start(state, NodeId("1"), world_point(100.0, 100.0))
  let s1 = update_pointer_up(s0, "1", "", false)
  @debug.debug_inspect(s1.interaction.selected, content="Some(NodeId(\"1\"))")
  @debug.assert_eq(s1.interaction.selected_nodes, [NodeId("1")])
}

///|
test "additive click toggles multi-selection" {
  let state = apply_action(make_test_state(), SelectNodes([NodeId("1")]))
  let s0 = update_node_drag_start(state, NodeId("2"), world_point(420.0, 100.0))
  let s1 = update_pointer_up(s0, "2", "", true)
  @debug.assert_eq(s1.interaction.selected_nodes, [NodeId("1"), NodeId("2")])
  let s2 = update_node_drag_start(s1, NodeId("1"), world_point(100.0, 100.0))
  let s3 = update_pointer_up(s2, "1", "", true)
  @debug.assert_eq(s3.interaction.selected_nodes, [NodeId("2")])
}

///|
test "pointer_up on background deselects" {
  let state = apply_action(make_test_state(), SelectNodes([NodeId("1")]))
  let s0 = update_pan_start(state, screen_point(0.0, 0.0))
  let s1 = update_pointer_up(s0, "", "", false)
  inspect(s1.interaction.selected is None, content="true")
  assert_eq(s1.interaction.selected_nodes.length(), 0)
}

///|
test "pointer_interrupt drops drag without committing positions" {
  let state = apply_action(make_test_state(), SelectNodes([NodeId("2")]))
  let started = update_node_drag_start(
    state,
    NodeId("1"),
    world_point(110.0, 120.0),
  )
  let interrupted = update_pointer_interrupt({
    ..started,
    interaction: { ..started.interaction, did_move: true },
  })
  assert_eq(interrupted.nodes, state.nodes)
  assert_eq(interrupted.action_log, state.action_log)
  @debug.assert_eq(interrupted.interaction.selected_nodes, [NodeId("2")])
  assert_true(interrupted.interaction.dragging is None)
  assert_true(interrupted.interaction.panning is None)
  assert_true(interrupted.interaction.connecting is None)
  assert_eq(interrupted.interaction.pointer_down, false)
  assert_eq(interrupted.interaction.did_move, false)
}

///|
test "pointer_interrupt preserves the current viewport and commits moved pan" {
  let state = make_test_state()
  let started = update_pan_start(state, screen_point(10.0, 20.0))
  let moved = update_pan_move(started, screen_point(40.0, 65.0))
  let interrupted = update_pointer_interrupt(moved)
  assert_eq(interrupted.viewport, moved.viewport)
  assert_eq(interrupted.action_log.length(), 1)
  match interrupted.action_log[0].action() {
    SetViewport(viewport) => assert_eq(viewport, moved.viewport)
    _ => fail("expected SetViewport action")
  }
  assert_true(interrupted.interaction.panning is None)
  assert_eq(interrupted.interaction.pointer_down, false)
  assert_eq(interrupted.interaction.did_move, false)
  let repeated = update_pointer_interrupt(interrupted)
  assert_eq(repeated.action_log.length(), 1)
}

///|
test "pointer_interrupt does not commit an unmoved pan" {
  let state = make_test_state()
  let started = update_pan_start(state, screen_point(10.0, 20.0))
  let interrupted = update_pointer_interrupt(started)
  assert_eq(interrupted.viewport, state.viewport)
  assert_eq(interrupted.action_log.length(), 0)
  assert_true(interrupted.interaction.panning is None)
}

///|
test "pointer_interrupt does not select a click target" {
  let state = apply_action(make_test_state(), SelectNodes([NodeId("2")]))
  let started = update_node_drag_start(
    state,
    NodeId("1"),
    world_point(100.0, 100.0),
  )
  let interrupted = update_pointer_interrupt(started)
  @debug.assert_eq(interrupted.interaction.selected_nodes, [NodeId("2")])
  assert_eq(interrupted.action_log, state.action_log)
  assert_true(interrupted.interaction.dragging is None)
}

///|
test "pointer_interrupt drops an in-flight connection" {
  let state = make_test_state()
  let started = update_connect_start(
    state,
    NodeId("1"),
    "tick",
    world_point(0.0, 0.0),
  )
  let moved = update_connect_move(started, world_point(333.0, 444.0))
  let interrupted = update_pointer_interrupt(moved)
  assert_eq(interrupted.edges, state.edges)
  assert_eq(interrupted.action_log.length(), 0)
  assert_true(interrupted.interaction.connecting is None)
  assert_eq(interrupted.interaction.pointer_down, false)
  assert_eq(interrupted.interaction.did_move, false)
}

///|
test "connect_start records source node, source port, and cursor world position" {
  let state = make_test_state()
  let s = update_connect_start(
    state,
    NodeId("1"),
    "tick",
    world_point(250.0, 80.0),
  )
  guard! s.interaction.connecting is Some(c)
  assert_eq(c.from_node, NodeId("1"))
  inspect(c.from_port, content="tick")
  inspect(c.cursor().x(), content="250")
  inspect(c.cursor().y(), content="80")
  assert_true(s.interaction.pointer_down)
}

///|
test "connect_move updates cursor world position" {
  let state = make_test_state()
  let s0 = update_connect_start(
    state,
    NodeId("1"),
    "tick",
    world_point(0.0, 0.0),
  )
  let s1 = update_connect_move(s0, world_point(333.0, 444.0))
  guard! s1.interaction.connecting is Some(c)
  inspect(c.cursor().x(), content="333")
  inspect(c.cursor().y(), content="444")
  assert_true(s1.interaction.did_move)
}

///|
test "WorldPoint construction rejects non-finite coordinates" {
  let invalid_start = try {
    ignore(WorldPoint::from_xy(x=0.0 / 0.0, y=0.0))
    false
  } catch {
    @spatial.CoordinateError::NonFinite => true
  }
  assert_true(invalid_start)

  let invalid_move = try {
    ignore(WorldPoint::from_xy(x=1.0 / 0.0, y=20.0))
    false
  } catch {
    @spatial.CoordinateError::NonFinite => true
  }
  assert_true(invalid_move)

  let invalid_node = try {
    ignore(WorldPoint::from_xy(x=12.0, y=1.0 / 0.0))
    false
  } catch {
    @spatial.CoordinateError::NonFinite => true
  }
  assert_true(invalid_node)
}

///|
test "connect_end commits compatible typed ports" {
  let state = make_test_state()
  let s0 = update_connect_start(
    state,
    NodeId("1"),
    "tick",
    world_point(0.0, 0.0),
  )
  let s1 = update_connect_end(s0, Some(NodeId("2")), Some("in"))
  assert_eq(s1.edges.length(), 1)
  assert_eq(s1.edges[0].source, NodeId("1"))
  assert_eq(s1.edges[0].source_port, "tick")
  assert_eq(s1.edges[0].target, NodeId("2"))
  assert_eq(s1.edges[0].target_port, "in")
  assert_true(s1.interaction.connecting is None)
  assert_eq(s1.action_log.length(), 1)
}

///|
test "connect_end uses the explicit target port" {
  let nodes = make_test_state().nodes.copy()
  nodes.push(
    make_workflow_node(
      NodeId("4"),
      Custom("Any source"),
      try! WorldPoint::from_xy(x=0.0, y=0.0),
    ),
  )
  nodes.push(
    make_workflow_node(
      NodeId("5"),
      ConditionalBranch,
      try! WorldPoint::from_xy(x=0.0, y=0.0),
    ),
  )
  let state : CanvasState = { ..make_test_state(), nodes, }
  let s0 = update_connect_start(
    state,
    NodeId("4"),
    "out",
    world_point(0.0, 0.0),
  )
  let s1 = update_connect_end(s0, Some(NodeId("5")), Some("rule"))
  assert_eq(s1.edges.length(), 1)
  assert_eq(s1.edges[0].source_port, "out")
  assert_eq(s1.edges[0].target_port, "rule")
}

///|
test "connect_end rejects incompatible ports" {
  let state = make_test_state()
  let s0 = update_connect_start(
    state,
    NodeId("1"),
    "tick",
    world_point(0.0, 0.0),
  )
  let s1 = update_connect_end(s0, Some(NodeId("3")), Some("json"))
  assert_eq(s1.edges.length(), 0)
  assert_true(s1.interaction.connecting is None)
  // Rejected attempts are still logged for audit/collaboration streams.
  assert_eq(s1.action_log.length(), 1)
}

///|
test "connect_end does not create self-loops or duplicates" {
  let state = make_test_state()
  let self_loop = update_connect_end(
    update_connect_start(state, NodeId("2"), "json", world_point(0.0, 0.0)),
    Some(NodeId("2")),
    Some("in"),
  )
  assert_eq(self_loop.edges.length(), 0)

  let with_edge : CanvasState = {
    ..make_test_state(),
    edges: [
      {
        id: EdgeId::from_edge(NodeId("1"), "tick", NodeId("2"), "in"),
        source: NodeId("1"),
        source_port: "tick",
        target: NodeId("2"),
        target_port: "in",
      },
    ],
  }
  let duplicate = update_connect_end(
    update_connect_start(with_edge, NodeId("1"), "tick", world_point(0.0, 0.0)),
    Some(NodeId("2")),
    Some("in"),
  )
  assert_eq(duplicate.edges.length(), 1)
}

///|
test "workflow_add_node creates typed custom nodes through serializable action" {
  let state = make_test_state()
  let s = workflow_add_node(state, "custom", world_point(12.0, 34.0))
  assert_eq(s.nodes.length(), 4)
  assert_eq(s.next_node_id, 5)
  assert_eq(s.action_log.length(), 1)
  inspect(s.nodes[3].title, content="Custom step")
  match s.action_log[0].action() {
    WorkflowAction::AddNode(node) => assert_eq(node.id, NodeId("4"))
    _ => fail("expected AddNode action")
  }
}
