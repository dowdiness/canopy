///|
test "incr canvas render assigns duplicate endpoint ordinals without index-only keys" {
  let endpoint = "edge:cell_7_1->cell_7_2"
  assert_eq(incr_canvas_edge_key(endpoint, 0), endpoint)
  assert_eq(incr_canvas_edge_key(endpoint, 1), endpoint + "#1")
}

///|
test "incr runtime snapshot characterizes dependency endpoint uniqueness" {
  let runtime = @incr.Runtime()
  let source = @incr.Input(runtime, 1, label="source")
  let derived = @incr.Derived(
    runtime,
    () => source.get() + source.get(),
    label="derived",
  )
  let tap = @visualizer.RecomputeTap::attach(runtime)
  ignore(derived.read_or_abort())
  let snapshot = tap.snapshot()
  let seen : Set[String] = Set([])
  for edge in snapshot.edges {
    let key = incr_canvas_edge_endpoint_key(edge)
    assert_false(seen.contains(key))
    seen.add(key)
  }
  match incr_canvas_status(snapshot, derived.id()) {
    @visualizer.VisualNodeStatus::Changed => ()
    _ => fail("expected the derived cell to be changed")
  }
  match incr_canvas_status(snapshot, source.id()) {
    @visualizer.VisualNodeStatus::Neutral => ()
    _ => fail("expected the source cell to be neutral")
  }
  tap.detach()
}

///|
test "incr canvas renderer omits only invalid node and edge projections" {
  let runtime = @incr.Runtime()
  let source = @incr.Input(runtime, 1, label="source")
  let derived = @incr.Derived(runtime, () => source.get() + 1, label="derived")
  let tap = @visualizer.RecomputeTap::attach(runtime)
  ignore(derived.read_or_abort())
  let snapshot = tap.snapshot()
  let state = reconcile_incr_canvas(IncrCanvasState::empty(), snapshot)
  let invalid = test_world(1.0e308, 0.0)
  let invalid_positions = state.positions.copy()
  assert_true(snapshot.nodes.length() > 0)
  let first = snapshot.nodes[0]
  invalid_positions[first.id] = invalid
  let invalid_state = {
    ..state,
    viewport: incr_canvas_test_viewport(1.0e308, 0.0, 1.0),
    positions: invalid_positions,
  }
  assert_true(incr_canvas_node_view(invalid_state, snapshot, first) is None)
  assert_true(snapshot.edges.length() > 0)
  let edge = snapshot.edges[0]
  let edge_positions = state.positions.copy()
  edge_positions[edge.from] = invalid
  let edge_state = {
    ..state,
    viewport: incr_canvas_test_viewport(1.0e308, 0.0, 1.0),
    positions: edge_positions,
  }
  assert_true(incr_canvas_edge_view(edge_state, edge) is None)
  tap.detach()
}
