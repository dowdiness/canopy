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
  let model = context_menu_model(handle, false, () => (), _s => ())
  let items = canvas_context_menu_items(model, test_background_target())
  inspect(items.length(), content="7")
  inspect(items[0].label, content="Timer trigger")
}
