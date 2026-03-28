///|
fn make_test_state() -> CanvasState {
  {
    viewport: { x: 0.0, y: 0.0, scale: 1.0 },
    nodes: [
      {
        id: NodeId(1),
        x: 100.0,
        y: 100.0,
        w: 200.0,
        h: 100.0,
        kind: NodeKind::Shape("#8250df"),
      },
      {
        id: NodeId(2),
        x: 400.0,
        y: 200.0,
        w: 150.0,
        h: 80.0,
        kind: NodeKind::Text("hello"),
      },
    ],
    interaction: {
      dragging: None,
      panning: None,
      selected: None,
      pointer_down: false,
      did_move: false,
    },
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
  // Move pointer to (160, 140) → delta (60, 40)
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
  // Second move uses original start_pan (0,0), not the intermediate position
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
test "zoom out (delta > 0) decreases scale" {
  let state = make_test_state()
  // cursor at (500, 400), scroll down → zoom out
  let s = update_zoom(state, 1.0, 500.0, 400.0)
  assert_true(s.viewport.scale < 1.0)
}

///|
test "zoom in (delta < 0) increases scale" {
  let state = make_test_state()
  let s = update_zoom(state, -1.0, 500.0, 400.0)
  assert_true(s.viewport.scale > 1.0)
}

///|
test "zoom clamps to min 0.1" {
  let state = { ..make_test_state(), viewport: { x: 0.0, y: 0.0, scale: 0.11 } }
  let s = update_zoom(state, 1.0, 0.0, 0.0)
  assert_eq(s.viewport.scale, 0.1)
}

///|
test "zoom clamps to max 8.0" {
  let state = { ..make_test_state(), viewport: { x: 0.0, y: 0.0, scale: 7.5 } }
  let s = update_zoom(state, -1.0, 0.0, 0.0)
  assert_eq(s.viewport.scale, 8.0)
}

///|
test "zoom keeps cursor world position fixed" {
  // World point under cursor before and after zoom must be identical.
  let state = make_test_state() // pan=(0,0), scale=1.0
  let cx = 300.0
  let cy = 200.0
  // world point under cursor before: (cx - pan.x) / scale = (300-0)/1 = 300
  let world_x_before = (cx - state.viewport.x) / state.viewport.scale
  let s = update_zoom(state, 1.0, cx, cy) // zoom out
  let world_x_after = (cx - s.viewport.x) / s.viewport.scale
  // Allow tiny float error
  assert_true((world_x_before - world_x_after).abs() < 1.0e-9)
}

///|
test "node_drag_start records offset from cursor to node origin" {
  let state = make_test_state()
  // Node 1 is at (100, 100). Grab it at world (110, 120).
  // offset = node_pos - cursor = (100-110, 100-120) = (-10, -20)
  let s = update_node_drag_start(state, NodeId(1), 110.0, 120.0)
  guard s.interaction.dragging is Some(d)
  assert_eq(d.node_id, NodeId(1))
  inspect(d.offset_x, content="-10")
  inspect(d.offset_y, content="-20")
  assert_true(s.interaction.pointer_down)
  assert_eq(s.interaction.did_move, false)
}

///|
test "node_drag_start is no-op for unknown node id" {
  let state = make_test_state()
  let s = update_node_drag_start(state, NodeId(99), 0.0, 0.0)
  assert_true(s.interaction.dragging is None)
}

///|
test "node_drag_move updates node position" {
  let state = make_test_state()
  let s0 = update_node_drag_start(state, NodeId(1), 110.0, 120.0)
  // offset = (-10, -20). Move cursor to (200, 300).
  // new node pos = cursor + offset = (200 + -10, 300 + -20) = (190, 280)
  let s1 = update_node_drag_move(s0, 200.0, 300.0)
  let node = s1.nodes[0]
  assert_eq(node.id, NodeId(1))
  inspect(node.x, content="190")
  inspect(node.y, content="280")
  assert_true(s1.interaction.did_move)
}

///|
test "node_drag_move does not affect other nodes" {
  let state = make_test_state()
  let s0 = update_node_drag_start(state, NodeId(1), 110.0, 120.0)
  let s1 = update_node_drag_move(s0, 200.0, 300.0)
  // Node 2 is unchanged
  inspect(s1.nodes[1].x, content="400")
  inspect(s1.nodes[1].y, content="200")
}

///|
test "node_drag_move is no-op when not dragging" {
  let state = make_test_state()
  let s = update_node_drag_move(state, 999.0, 999.0)
  inspect(s.nodes[0].x, content="100")
  inspect(s.nodes[0].y, content="100")
}

///|
test "pointer_up clears panning state" {
  let state = make_test_state()
  let s0 = update_pan_start(state, 0.0, 0.0)
  let s1 = update_pointer_up(s0, 0)
  inspect(s1.interaction.panning, content="None")
  inspect(s1.interaction.pointer_down, content="false")
}

///|
test "pointer_up clears dragging state" {
  let state = make_test_state()
  let s0 = update_node_drag_start(state, NodeId(1), 0.0, 0.0)
  let s1 = update_pointer_up(s0, 1)
  inspect(s1.interaction.dragging, content="None")
  inspect(s1.interaction.pointer_down, content="false")
}

///|
test "pointer_up on node without movement selects it" {
  let state = make_test_state()
  // pointerdown on node 1, no movement → did_move stays false
  let s0 = update_node_drag_start(state, NodeId(1), 100.0, 100.0)
  let s1 = update_pointer_up(s0, 1)
  inspect(s1.interaction.selected, content="Some(NodeId(1))")
}

///|
test "pointer_up after drag movement does not change selection" {
  let state : CanvasState = {
    ..make_test_state(),
    interaction: { ..make_test_state().interaction, selected: Some(NodeId(2)) },
  }
  let s0 = update_node_drag_start(state, NodeId(1), 100.0, 100.0)
  let s1 = update_node_drag_move(s0, 200.0, 200.0) // sets did_move = true
  let s2 = update_pointer_up(s1, 1)
  // Selection unchanged because movement occurred (it was a drag, not a click)
  inspect(s2.interaction.selected, content="Some(NodeId(2))")
}

///|
test "pointer_up on background deselects" {
  let state : CanvasState = {
    ..make_test_state(),
    interaction: { ..make_test_state().interaction, selected: Some(NodeId(1)) },
  }
  let s0 = update_pan_start(state, 0.0, 0.0)
  let s1 = update_pointer_up(s0, 0)
  inspect(s1.interaction.selected, content="None")
}

///|
test "pointer_up after pan movement preserves selection" {
  let state : CanvasState = {
    ..make_test_state(),
    interaction: { ..make_test_state().interaction, selected: Some(NodeId(1)) },
  }
  let s0 = update_pan_start(state, 0.0, 0.0)
  let s1 = update_pan_move(s0, 40.0, 20.0)
  let s2 = update_pointer_up(s1, 0)
  inspect(s2.interaction.selected, content="Some(NodeId(1))")
}

///|
test "get_render_state returns correct JSON shape" {
  // create_canvas returns handle 0 on first call in test process
  let handle = create_canvas()
  let json_str = get_render_state(handle)
  // Run `moon test --update` on first run to capture actual snapshot.
  inspect(
    json_str,
    content=(
      #|{"viewport":{"x":520,"y":300,"scale":1},"nodes":[{"id":1,"x":-320,"y":-160,"w":200,"h":120,"kind":["Shape","#8250df"]},{"id":2,"x":-60,"y":-160,"w":200,"h":120,"kind":["Shape","#c792ea"]},{"id":3,"x":200,"y":-160,"w":200,"h":120,"kind":["Shape","#82aaff"]},{"id":4,"x":-320,"y":20,"w":200,"h":60,"kind":["Text","Canopy Canvas"]},{"id":5,"x":-60,"y":20,"w":200,"h":60,"kind":["Text","Pan · Zoom · Drag"]},{"id":6,"x":200,"y":20,"w":200,"h":60,"kind":["Text","∞"]}]}
    ),
  )
}
