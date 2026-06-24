///|
fn contract_runtime_operations(
  runtime : CanvasRuntime,
) -> Array[GraphOperation] {
  ok_operation_log(runtime.action_log_json())
}

///|
fn contract_source_graph(handle : Int) -> SourceBackedGraph {
  match source_graph_by_handle(handle) {
    Some(graph) => graph
    None => abort("expected source graph handle")
  }
}

///|
fn contract_state_node(state : CanvasState, id : NodeId) -> CanvasNode {
  match @graph_model.find_node(state.nodes, id) {
    Some(node) => node
    None => abort("missing canvas state node: " + id.to_string())
  }
}

///|
fn contract_render_node(render : RenderStateJson, id : String) -> NodeJson {
  match render.nodes.search_by(fn(node) { node.id == id }) {
    Some(index) => render.nodes[index]
    None => abort("missing render node: " + id)
  }
}

///|
fn contract_assert_close(actual : Double, expected : Double) -> Unit raise {
  assert_true((actual - expected).abs() < 1.0e-9)
}

///|
fn contract_screen_point(
  viewport : Viewport,
  world_x : Double,
  world_y : Double,
) -> (Double, Double) {
  (world_x * viewport.scale + viewport.x, world_y * viewport.scale + viewport.y)
}

///|
fn contract_expect_move_nodes(
  operation : GraphOperation,
  expected : Array[NodePosition],
) -> Unit raise {
  match operation.action() {
    MoveNodes(positions) => @debug.assert_eq(positions, expected)
    _ => fail("expected MoveNodes action")
  }
}

///|
fn contract_expect_select_nodes(
  operation : GraphOperation,
  expected : Array[NodeId],
) -> Unit raise {
  match operation.action() {
    SelectNodes(nodes) => @debug.assert_eq(nodes, expected)
    _ => fail("expected SelectNodes action")
  }
}

///|
test "runtime contract: pointermove previews before one durable MoveNodes commit" {
  let runtime = CanvasRuntime::CanvasRuntime()
  let node_id = NodeId("1")
  let before_node = contract_state_node(runtime.state_peek(), node_id)
  let (start_sx, start_sy) = contract_screen_point(
    runtime.render_state().viewport,
    before_node.x,
    before_node.y,
  )
  runtime.pointer_down(Some(node_id), start_sx, start_sy)

  let (mid_sx, mid_sy) = contract_screen_point(
    runtime.render_state().viewport,
    -410.0,
    -110.0,
  )
  runtime.pointer_move(mid_sx, mid_sy)
  let during_node = contract_state_node(runtime.state_peek(), node_id)
  contract_assert_close(during_node.x, before_node.x)
  contract_assert_close(during_node.y, before_node.y)
  assert_eq(contract_runtime_operations(runtime).length(), 0)
  let mid_preview = contract_render_node(runtime.render_state(), "1")
  contract_assert_close(mid_preview.x, -410.0)
  contract_assert_close(mid_preview.y, -110.0)

  let (final_sx, final_sy) = contract_screen_point(
    runtime.render_state().viewport,
    -390.0,
    -95.0,
  )
  runtime.pointer_move(final_sx, final_sy)
  assert_eq(contract_runtime_operations(runtime).length(), 0)
  let final_preview = contract_render_node(runtime.render_state(), "1")
  contract_assert_close(final_preview.x, -390.0)
  contract_assert_close(final_preview.y, -95.0)

  runtime.pointer_up("1", "", false)
  let after_node = contract_state_node(runtime.state_peek(), node_id)
  contract_assert_close(after_node.x, -390.0)
  contract_assert_close(after_node.y, -95.0)
  let operations = contract_runtime_operations(runtime)
  assert_eq(operations.length(), 1)
  contract_expect_move_nodes(operations[0], [{ node_id, x: -390.0, y: -95.0 }])
}

///|
test "runtime contract: panning logs viewport only on pointerup" {
  let runtime = CanvasRuntime::CanvasRuntime()
  let before = runtime.render_state().viewport
  runtime.pointer_down(None, 10.0, 20.0)
  runtime.pointer_move(30.0, 55.0)
  let during = runtime.render_state()
  contract_assert_close(during.viewport.x, before.x + 20.0)
  contract_assert_close(during.viewport.y, before.y + 35.0)
  assert_eq(during.action_count, 0)
  assert_eq(contract_runtime_operations(runtime).length(), 0)

  runtime.pointer_move(40.0, 65.0)
  runtime.pointer_up("", "", false)
  let after = runtime.render_state()
  let operations = contract_runtime_operations(runtime)
  assert_eq(after.action_count, 1)
  assert_eq(operations.length(), 1)
  match operations[0].action() {
    SetViewport(viewport) => @debug.assert_eq(viewport, after.viewport)
    _ => fail("expected SetViewport action")
  }
}

///|
test "runtime contract: zoom logs one viewport operation immediately" {
  let runtime = CanvasRuntime::CanvasRuntime()
  runtime.zoom(-1.0, 500.0, 400.0)
  let after = runtime.render_state()
  let operations = contract_runtime_operations(runtime)
  assert_eq(after.action_count, 1)
  assert_eq(operations.length(), 1)
  match operations[0].action() {
    SetViewport(viewport) => @debug.assert_eq(viewport, after.viewport)
    _ => fail("expected SetViewport action")
  }
}

///|
test "runtime contract: click selection is pointerup-only and additive" {
  let runtime = CanvasRuntime::CanvasRuntime()
  let node1 = NodeId("1")
  let first_node = contract_state_node(runtime.state_peek(), node1)
  let (one_sx, one_sy) = contract_screen_point(
    runtime.render_state().viewport,
    first_node.x,
    first_node.y,
  )
  runtime.pointer_down(Some(node1), one_sx, one_sy)
  assert_eq(runtime.render_state().selected_nodes.length(), 0)
  assert_eq(contract_runtime_operations(runtime).length(), 0)

  runtime.pointer_up("1", "", false)
  @debug.assert_eq(runtime.render_state().selected_nodes, ["1"])
  let first_operations = contract_runtime_operations(runtime)
  assert_eq(first_operations.length(), 1)
  contract_expect_select_nodes(first_operations[0], [node1])

  let node2 = NodeId("2")
  let second_node = contract_state_node(runtime.state_peek(), node2)
  let (two_sx, two_sy) = contract_screen_point(
    runtime.render_state().viewport,
    second_node.x,
    second_node.y,
  )
  runtime.pointer_down(Some(node2), two_sx, two_sy)
  runtime.pointer_up("2", "", true)
  @debug.assert_eq(runtime.render_state().selected_nodes, ["1", "2"])
  let second_operations = contract_runtime_operations(runtime)
  assert_eq(second_operations.length(), 2)
  contract_expect_select_nodes(second_operations[1], [node1, node2])

  runtime.pointer_down(Some(node1), one_sx, one_sy)
  runtime.pointer_up("1", "", true)
  @debug.assert_eq(runtime.render_state().selected_nodes, ["2"])
  let third_operations = contract_runtime_operations(runtime)
  assert_eq(third_operations.length(), 3)
  contract_expect_select_nodes(third_operations[2], [node2])
}

///|
test "source-backed runtime contract: pointermove previews before one local MoveNodes commit" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)\nmeter = scope()")
  let graph = contract_source_graph(handle)
  let osc = handle_token(handle, "osc")
  let before = source_graph_base_canvas_state(graph)
  let before_node = contract_state_node(before, osc)
  let (start_sx, start_sy) = contract_screen_point(
    before.viewport,
    before_node.x,
    before_node.y,
  )
  source_graph_pointer_down(handle, osc.to_string(), start_sx, start_sy)

  let (mid_sx, mid_sy) = contract_screen_point(before.viewport, 80.0, 40.0)
  source_graph_pointer_move(handle, mid_sx, mid_sy)
  let durable_during = contract_state_node(
    source_graph_base_canvas_state(graph),
    osc,
  )
  contract_assert_close(durable_during.x, before_node.x)
  contract_assert_close(durable_during.y, before_node.y)
  assert_eq(ok_operation_log(get_source_graph_action_log(handle)).length(), 0)
  let mid_preview = contract_state_node(source_graph_canvas_state(graph), osc)
  contract_assert_close(mid_preview.x, 80.0)
  contract_assert_close(mid_preview.y, 40.0)

  let (final_sx, final_sy) = contract_screen_point(before.viewport, 90.0, 60.0)
  source_graph_pointer_move(handle, final_sx, final_sy)
  assert_eq(ok_operation_log(get_source_graph_action_log(handle)).length(), 0)
  let final_preview = contract_state_node(source_graph_canvas_state(graph), osc)
  contract_assert_close(final_preview.x, 90.0)
  contract_assert_close(final_preview.y, 60.0)

  source_graph_pointer_up(handle, osc.to_string(), "", false)
  let after_node = contract_state_node(
    source_graph_base_canvas_state(graph),
    osc,
  )
  contract_assert_close(after_node.x, 90.0)
  contract_assert_close(after_node.y, 60.0)
  let operations = ok_operation_log(get_source_graph_action_log(handle))
  assert_eq(operations.length(), 1)
  contract_expect_move_nodes(operations[0], [{ node_id: osc, x: 90.0, y: 60.0 }])
  destroy_source_graph(handle)
}

///|
test "source-backed runtime contract: panning logs viewport only on pointerup" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)\nmeter = scope()")
  let graph = contract_source_graph(handle)
  let before = source_graph_base_canvas_state(graph).viewport
  source_graph_pointer_down(handle, "", 10.0, 20.0)
  source_graph_pointer_move(handle, 30.0, 55.0)
  let during = source_graph_base_canvas_state(graph)
  contract_assert_close(during.viewport.x, before.x + 20.0)
  contract_assert_close(during.viewport.y, before.y + 35.0)
  assert_eq(ok_operation_log(get_source_graph_action_log(handle)).length(), 0)

  source_graph_pointer_move(handle, 40.0, 65.0)
  source_graph_pointer_up(handle, "", "", false)
  let after = source_graph_base_canvas_state(graph)
  let operations = ok_operation_log(get_source_graph_action_log(handle))
  assert_eq(operations.length(), 1)
  match operations[0].action() {
    SetViewport(viewport) => @debug.assert_eq(viewport, after.viewport)
    _ => fail("expected SetViewport action")
  }
  destroy_source_graph(handle)
}
