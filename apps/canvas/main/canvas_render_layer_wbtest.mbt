///|
#warnings("-alert_unstable")
test "render layer view renders accessible keyed paths and pending path" {
  let model : CanvasRenderLayerState = {
    snapshot: Some({
      viewport: { x: 10.0, y: 20.0, scale: 1.5, },
      nodes: [],
      edges: [
        {
          id: "edge-1",
          path_d: "M 0 0 C 40 0, 40 10, 80 10",
          selected: true,
          aria_label: "Connection source.out → target.in",
        },
      ],
      selected: None,
      selected_nodes: [],
      inspector: None,
      connecting: Some({
        from: "source",
        from_port: "out",
        cursor_x: 80.0,
        cursor_y: 10.0,
        path_d: Some("M 0 0 C 40 0, 40 10, 80 10"),
      }),
      input_compatibility: [],
      validation: [],
    }),
  }
  let html = canvas_render_layer_view(model)
  let rendered = @rabbita_testing.server_side_render(() => html)
  assert_true(rendered.contains("<svg"))
  assert_true(rendered.contains("id=\"edges\""))
  assert_true(rendered.contains("transform:translate(10px, 20px) scale(1.5)"))
  assert_true(rendered.contains("data-edge-id=\"edge-1\""))
  assert_true(rendered.contains("role=\"button\""))
  assert_true(rendered.contains("tabindex=\"0\""))
  assert_true(
    rendered.contains("aria-label=\"Connection source.out → target.in\""),
  )
  assert_true(rendered.contains("class=\"edge selected\""))
  assert_true(rendered.contains("class=\"edge-pending\""))
}

///|
test "render snapshot decode includes selected node and Inspector projection" {
  let json = "{\"viewport\":{\"x\":1.0,\"y\":2.0,\"scale\":3.0},\"nodes\":[],\"edges\":[],\"selected\":\"node-a\",\"selected_nodes\":[\"node-a\"],\"inspector\":{\"id\":\"node-a\",\"title\":\"Mixer\",\"subtitle\":\"mix\",\"configured\":true,\"input_count\":2,\"output_count\":1,\"source\":\"selected\"},\"input_compatibility\":[],\"validation\":[],\"action_count\":0}"
  match parse_canvas_render_layer_snapshot(json) {
    Some(snapshot) => {
      assert_eq(snapshot.selected, Some("node-a"))
      match snapshot.inspector {
        Some(inspector) => {
          assert_eq(inspector.id, "node-a")
          assert_eq(inspector.input_count, 2)
          assert_eq(inspector.source, "selected")
        }
        None => fail("expected the published Inspector projection")
      }
    }
    None => fail("expected a valid published render snapshot")
  }
  assert_true(parse_canvas_render_layer_snapshot("{broken") is None)
}
