///|
test "keyboard delete admission matches key and modifier rules" {
  assert_true(canvas_delete_key_admitted("Delete", false, false, false, false))
  assert_true(
    canvas_delete_key_admitted("Backspace", false, false, false, false),
  )
  assert_true(!canvas_delete_key_admitted("Delete", true, false, false, false))
  assert_true(!canvas_delete_key_admitted("Delete", false, true, false, false))
  assert_true(!canvas_delete_key_admitted("Delete", false, false, true, false))
  assert_true(!canvas_delete_key_admitted("Delete", false, false, false, true))
  assert_true(!canvas_delete_key_admitted("Enter", false, false, false, false))
}

///|
test "keyboard deletion retains the admitted nodes when selection changes" {
  let handle = create_canvas()
  let runtime = test_context_runtime(handle)
  test_select_node(runtime, NodeId("2"))
  let captured = canvas_delete_target(Runtime(runtime)).unwrap()
  test_select_node(runtime, NodeId("3"))
  let actions_before = runtime.action_log_snapshot().length()
  canvas_keyboard_update(
    {
      handle,
      on_change: () => (),
      send_source: _ => (),
      can_mutate: () => true,
    },
    captured,
  )
  let state = runtime.state_peek()
  assert_true(@graph_model.find_node(state.nodes, NodeId("2")) is None)
  assert_true(@graph_model.find_node(state.nodes, NodeId("3")) is Some(_))
  assert_eq(runtime.action_log_snapshot().length(), actions_before + 1)
}

///|
test "keyboard deletion captures edges ahead of nodes and ignores empty selection" {
  let handle = create_source_graph(
    "osc = sine(freq: 440Hz)\nmeter = scope(input: osc)",
  )
  defer destroy_source_graph(handle)
  let graph = source_graph_by_handle(handle).unwrap()
  let edge = source_graph_base_canvas_state(graph).edges[0].id
  let node = handle_token(handle, "osc")
  graph.interaction = { ..graph.interaction, selected_nodes: [node], }
  graph.select_edge(edge)
  let captured = canvas_delete_target(Source(graph)).unwrap()
  assert_true(captured is Disconnect(actual) && actual == edge)
  graph.clear_selected_edge()
  assert_true(
    canvas_delete_target(Source(graph)) is Some(DeleteNodes(nodes)) &&
    nodes == [node],
  )
  graph.interaction = { ..graph.interaction, selected_nodes: [], }
  assert_true(canvas_delete_target(Source(graph)) is None)
}
