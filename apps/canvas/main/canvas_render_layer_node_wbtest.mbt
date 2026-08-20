///|
#warnings("-alert_unstable")
test "render layer view renders keyed nodes, handles, edges, and connection state" {
  let source = edge_projection_test_node(
    "source",
    10.0,
    20.0,
    100.0,
    80.0,
    [],
    [@graph_model.port("out", "out", Any)],
  )
  let target = edge_projection_test_node(
    "target",
    300.0,
    40.0,
    100.0,
    80.0,
    [@graph_model.port("in", "in", Any)],
    [],
  )
  let model : CanvasRenderLayerState = {
    snapshot: Some({
      viewport: { x: 10.0, y: 20.0, scale: 1.5 },
      nodes: [source, target],
      edges: [],
      selected_nodes: ["target"],
      connecting: Some({
        from: "source",
        from_port: "out",
        cursor_x: 200.0,
        cursor_y: 80.0,
        path_d: Some("M 0 0 C 40 0, 40 10, 80 10"),
      }),
      input_compatibility: [
        { node_id: "target", port_id: "in", compatible: true },
      ],
      validation: [
        { severity: "error", message: "broken", node_id: Some("target") },
      ],
    }),
  }
  let html = canvas_render_layer_view(model)
  let rendered = @rabbita.render_to_string(() => @rabbita.Val::constant(html))
  assert_true(rendered.contains("id=\"edges\""))
  assert_true(rendered.contains("id=\"world\""))
  assert_true(rendered.contains("data-node-id=\"source\""))
  assert_true(rendered.contains("data-node-id=\"target\""))
  assert_true(
    rendered.contains("class=\"canvas-node workflow-node connecting-source\""),
  )
  assert_true(
    rendered.contains("class=\"canvas-node workflow-node selected invalid\""),
  )
  assert_true(rendered.contains("data-handle=\"input\""))
  assert_true(rendered.contains("data-port-id=\"in\""))
  assert_true(rendered.contains("data-port-label=\"in\""))
  assert_true(rendered.contains("data-handle=\"output\""))
  assert_true(rendered.contains("style=\"top:50%\""))
  assert_true(rendered.contains("title=\"Input in: Any\""))
  assert_true(rendered.contains("aria-label=\"target input in: Any\""))
  assert_true(rendered.contains("class=\"handle input compatible-target\""))
  assert_true(rendered.contains("class=\"edge-pending\""))
}
