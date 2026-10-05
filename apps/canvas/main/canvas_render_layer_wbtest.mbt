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
