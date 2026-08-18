///|
#warnings("-alert_unstable")
test "edge layer view renders accessible keyed paths and pending path" {
  let model : CanvasEdgeLayerState = {
    snapshot: Some({
      viewport: { x: 10.0, y: 20.0, scale: 1.5 },
      edges: [
        {
          id: "edge-1",
          path_d: "M 0 0 C 40 0, 40 10, 80 10",
          selected: true,
          aria_label: "Connection source.out → target.in",
        },
      ],
      connecting_path_d: Some("M 0 0 C 40 0, 40 10, 80 10"),
    }),
  }
  let html = canvas_edge_layer_view(model)
  let rendered = @rabbita.render_to_string(() => @rabbita.Val::constant(html))
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
test "edge layer update accepts the shared render snapshot shape" {
  let json = "{\"viewport\":{\"x\":1.0,\"y\":2.0,\"scale\":3.0},\"nodes\":[],\"edges\":[{\"id\":\"edge-1\",\"path_d\":\"M 0 0\",\"selected\":false,\"aria_label\":\"Connection source.out → target.in\"}],\"selected_nodes\":[],\"validation\":[],\"action_count\":0,\"connecting\":{\"from\":\"source\",\"from_port\":\"out\",\"cursor_x\":1.0,\"cursor_y\":2.0,\"path_d\":[\"M 0 0\"]}}"
  let parsed_snapshot = parse_canvas_edge_layer_snapshot(json)
  assert_true(parsed_snapshot is Some(_))
  let next = canvas_edge_layer_update(
    { snapshot: None },
    CanvasEdgeLayerMsg::RenderState(json),
  )
  match next.snapshot {
    Some(snapshot) => {
      assert_eq(snapshot.viewport.x, 1.0)
      assert_eq(snapshot.viewport.y, 2.0)
      assert_eq(snapshot.viewport.scale, 3.0)
      assert_eq(snapshot.edges.length(), 1)
      assert_eq(snapshot.connecting_path_d, Some("M 0 0"))
    }
    None => fail("expected the published render snapshot")
  }
}
