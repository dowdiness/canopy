///|
fn test_background_target() -> CanvasContextTarget {
  Background(insert_at=try! ScreenPoint::from_xy(x=0.0, y=0.0))
}

///|
test "workflow node catalog derives labels and descriptions from graph nodes" {
  let catalog = workflow_node_catalog()
  assert_eq(catalog.length(), 7)
  assert_eq(catalog[0].key, "timer")
  assert_eq(catalog[0].label, "Timer trigger")
  assert_eq(catalog[0].description, "Start on a schedule")
  assert_eq(catalog[6].key, "custom")
  assert_eq(catalog[6].label, "Custom step")
  assert_eq(catalog[6].description, "Reserve an integration point")
}

///|
test "workflow context disconnect uses the captured edge target" {
  let runtime = CanvasRuntime::CanvasRuntime()
  let edge = runtime.state_peek().edges[0]
  assert_true(runtime.disconnect_edge(edge.id))
  assert_eq(runtime.state_peek().edges.length(), 2)
  assert_eq(runtime.action_log_snapshot().length(), 1)

  assert_false(runtime.disconnect_edge(edge.id))
  assert_eq(runtime.state_peek().edges.length(), 2)
  assert_eq(runtime.action_log_snapshot().length(), 1)
}

///|
test "background menu stays catalog-only without a multi-selection" {
  let handle = create_canvas()
  let model = context_menu_model(handle, () => (), _s => ())
  let items = canvas_context_menu_items(model, test_background_target())
  inspect(items.length(), content="7")
  inspect(items[0].label, content="Timer trigger")
}

///|
test "background menu prepends arrange for a multi-selection" {
  let handle = create_canvas()
  let runtime = match canvas_backing(handle) {
    Some(Runtime(runtime)) => runtime
    _ => abort("expected runtime backing")
  }
  let node1 = NodeId("1")
  let node2 = NodeId("2")
  let first = contract_state_node(runtime.state_peek(), node1)
  let (one_sx, one_sy) = contract_screen_point(
    runtime.render_state().viewport,
    first.position().x(),
    first.position().y(),
  )
  ignore(runtime.pointer_down(Some(node1), one_sx, one_sy))
  runtime.pointer_up("1", "", false)
  let second = contract_state_node(runtime.state_peek(), node2)
  let (two_sx, two_sy) = contract_screen_point(
    runtime.render_state().viewport,
    second.position().x(),
    second.position().y(),
  )
  ignore(runtime.pointer_down(Some(node2), two_sx, two_sy))
  runtime.pointer_up("2", "", true)

  let model = context_menu_model(handle, () => (), _s => ())
  let items = canvas_context_menu_items(model, test_background_target())
  inspect(items.length(), content="8")
  inspect(items[0].label, content="Arrange compactly")
  inspect(items[1].label, content="Timer trigger")
}

///|
test "background menu hides arrange on a source-backed graph" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)\nmeter = scope()")
  let model = context_menu_model(handle, () => (), _s => ())
  let items = canvas_context_menu_items(model, test_background_target())
  inspect(items.length(), content="7")
  inspect(items[0].label, content="Timer trigger")
  destroy_source_graph(handle)
}
