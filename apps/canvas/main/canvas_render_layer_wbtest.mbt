///|
#warnings("-alert_unstable")
test "render layer view renders accessible keyed paths and pending path" {
  let model : CanvasRenderLayerState = {
    snapshot: Some({
      viewport: { x: 10.0, y: 20.0, scale: 1.5 },
      nodes: [],
      edges: [
        {
          id: "edge-1",
          path_d: "M 0 0 C 40 0, 40 10, 80 10",
          selected: true,
          aria_label: "Connection source.out → target.in",
        },
      ],
      selected_nodes: [],
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
test "render layer update accepts the shared render snapshot shape" {
  let json = "{\"viewport\":{\"x\":1.0,\"y\":2.0,\"scale\":3.0},\"nodes\":[],\"edges\":[{\"id\":\"edge-1\",\"path_d\":\"M 0 0\",\"selected\":false,\"aria_label\":\"Connection source.out → target.in\"}],\"selected_nodes\":[],\"input_compatibility\":[],\"validation\":[],\"action_count\":0,\"connecting\":{\"from\":\"source\",\"from_port\":\"out\",\"cursor_x\":1.0,\"cursor_y\":2.0,\"path_d\":[\"M 0 0\"]}}"
  let parsed_snapshot = parse_canvas_render_layer_snapshot(json)
  assert_true(parsed_snapshot is Some(_))
  let next = canvas_render_layer_update(
    { snapshot: None },
    CanvasRenderLayerMsg::RenderState(json),
  )
  match next.snapshot {
    Some(snapshot) => {
      assert_eq(snapshot.viewport.x, 1.0)
      assert_eq(snapshot.viewport.y, 2.0)
      assert_eq(snapshot.viewport.scale, 3.0)
      assert_eq(snapshot.edges.length(), 1)
      match snapshot.connecting {
        Some(connecting) => assert_eq(connecting.path_d, Some("M 0 0"))
        None => fail("expected the published connection")
      }
    }
    None => fail("expected the published render snapshot")
  }
}

///|
test "render layer update keeps the last valid snapshot on malformed JSON" {
  let current : CanvasRenderLayerState = {
    snapshot: Some({
      viewport: { x: 1.0, y: 2.0, scale: 1.0 },
      nodes: [],
      edges: [],
      selected_nodes: [],
      connecting: None,
      input_compatibility: [],
      validation: [],
    }),
  }
  let next = canvas_render_layer_update(
    current,
    CanvasRenderLayerMsg::RenderState("{broken"),
  )
  assert_true(next == current)
}
