///|
test "canvas instances allocate one monotonic handle space" {
  let runtime_handle = create_canvas()
  let source_handle = create_source_graph("osc = sine(freq: 440Hz)")
  let next_runtime_handle = create_canvas()
  inspect(source_handle == runtime_handle + 1, content="true")
  inspect(next_runtime_handle == source_handle + 1, content="true")
  match canvas_backing(runtime_handle) {
    Some(Runtime(_)) => ()
    _ => abort("expected runtime backing")
  }
  match canvas_backing(source_handle) {
    Some(Source(_)) => ()
    _ => abort("expected source backing")
  }
  match canvas_backing(next_runtime_handle) {
    Some(Runtime(_)) => ()
    _ => abort("expected next runtime backing")
  }
  destroy_source_graph(source_handle)
}

///|
test "source destroy clears only its unified backing slot" {
  let runtime_handle = create_canvas()
  let source_handle = create_source_graph("osc = sine(freq: 440Hz)")
  inspect(try_destroy_source_graph(runtime_handle), content="false")
  match canvas_backing(runtime_handle) {
    Some(Runtime(_)) => ()
    _ => abort("runtime slot was changed by source destroy")
  }
  inspect(try_destroy_source_graph(source_handle), content="true")
  inspect(canvas_backing(source_handle) is None, content="true")
  match canvas_backing(runtime_handle) {
    Some(Runtime(_)) => ()
    _ => abort("runtime slot did not survive source destroy")
  }
}

///|
test "cross-backing operations reject without registry reinterpretation" {
  let runtime_handle = create_canvas()
  let source_handle = create_source_graph("osc = sine(freq: 440Hz)")
  let source_before = get_source_graph_source(source_handle)
  add_node(source_handle, "timer", 0.0, 0.0)
  assert_eq(get_source_graph_source(source_handle), source_before)
  inspect(get_render_state(source_handle), content="")
  inspect(get_action_log(source_handle), content="[]")
  inspect(
    operation_result_applied(apply_source_graph_operation(runtime_handle, "{}")),
    content="false",
  )
  inspect(get_source_graph_source(runtime_handle), content="")
  inspect(get_source_graph_action_log(runtime_handle), content="[]")
  destroy_source_graph(source_handle)
}

///|
test "source-backed node identity survives other backing allocation" {
  let source_handle = create_source_graph("osc = sine(freq: 440Hz)")
  let before = handle_token(source_handle, "osc")
  let runtime_handle = create_canvas()
  let after = handle_token(source_handle, "osc")
  assert_eq(before, after)
  match canvas_backing(runtime_handle) {
    Some(Runtime(_)) => ()
    _ => abort("expected runtime backing")
  }
  destroy_source_graph(source_handle)
}
