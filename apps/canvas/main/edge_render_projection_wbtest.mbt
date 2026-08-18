///|
fn edge_projection_test_node(
  id : String,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  inputs : Array[PortDef],
  outputs : Array[PortDef],
) -> NodeJson {
  {
    id,
    x,
    y,
    w,
    h,
    kind: Workflow(Custom(id)),
    title: id,
    subtitle: id,
    inputs,
    outputs,
    configured: true,
    params: [],
  }
}

///|
fn edge_projection_test_edge(
  id : String,
  source : String,
  source_port : String,
  target : String,
  target_port : String,
) -> Edge {
  {
    id: EdgeId(id),
    source: NodeId(source),
    source_port,
    target: NodeId(target),
    target_port,
  }
}

///|
fn edge_projection_test_connecting(
  from : String,
  from_port : String,
  cursor_x : Double,
  cursor_y : Double,
) -> ConnectingJson {
  { from, from_port, cursor_x, cursor_y, path_d: None }
}

///|
fn edge_projection_test_required(
  projection : EdgeRenderProjection?,
) -> EdgeRenderProjection {
  match projection {
    Some(value) => value
    None => abort("expected edge projection")
  }
}

///|
test "edge projection derives anchors and exact horizontal cubic paths" {
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
  let edge = edge_projection_test_edge(
    "edge",
    "source",
    "out",
    "target",
    "in",
  )
  let nodes = [source, target]
  let node_index = edge_render_node_index(nodes)
  let projected = edge_projection_test_required(
    project_edge_render(node_index, edge, None),
  )
  assert_eq(projected.path_d, "M 110 60 C 205 60, 205 80, 300 80")
  assert_eq(projected.aria_label, "Connection source.out → target.in")
  assert_true(!projected.selected)

  let nearby_target = { ..target, x: 130.0 }
  let nearby = edge_projection_test_required(
    project_edge_render(
      edge_render_node_index([source, nearby_target]),
      edge,
      None,
    ),
  )
  assert_eq(nearby.path_d, "M 110 60 C 150 60, 90 80, 130 80")
}

///|
test "edge projection captures selection and omits missing graph targets" {
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
  let edge = edge_projection_test_edge(
    "edge",
    "source",
    "out",
    "target",
    "in",
  )
  let selected = edge_projection_test_required(
    project_edge_render(
      edge_render_node_index([source, target]),
      edge,
      Some(edge.id),
    ),
  )
  assert_true(selected.selected)

  let missing_source = { ..edge, source: NodeId("missing") }
  let node_index = edge_render_node_index([source, target])
  assert_true(project_edge_render(node_index, missing_source, None) is None)
  let missing_target = { ..edge, target: NodeId("missing") }
  assert_true(project_edge_render(node_index, missing_target, None) is None)
  let missing_port = { ..edge, target_port: "missing" }
  assert_true(project_edge_render(node_index, missing_port, None) is None)
}

///|
test "edge projection rejects anchor and control-point overflow" {
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
  let edge = edge_projection_test_edge(
    "edge",
    "source",
    "out",
    "target",
    "in",
  )

  let overflowing_anchor = { ..source, x: 1.0e308, w: 1.0e308 }
  assert_true(
    project_edge_render(
      edge_render_node_index([overflowing_anchor, target]),
      edge,
      None,
    ) is None,
  )

  let far_source = { ..source, x: 1.0e308, w: 0.0 }
  let far_target = { ..target, x: -1.0e308, w: 0.0 }
  assert_true(
    project_edge_render(
      edge_render_node_index([far_source, far_target]),
      edge,
      None,
    ) is None,
  )
}

///|
test "pending edge projection follows the same source anchor and rejects invalid input" {
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
  let nodes = [source, target]
  let node_index = edge_render_node_index(nodes)
  let connecting = edge_projection_test_connecting("source", "out", 300.0, 80.0)
  assert_eq(
    project_pending_path(node_index, Some(connecting)),
    Some("M 110 60 C 205 60, 205 80, 300 80"),
  )
  assert_true(
    project_pending_path(
      node_index,
      Some({ ..connecting, from: "missing" }),
    ) is None,
  )
  assert_true(
    project_pending_path(
      node_index,
      Some({ ..connecting, from_port: "missing" }),
    ) is None,
  )
  assert_true(
    project_pending_path(
      node_index,
      Some({ ..connecting, cursor_x: 1.0 / 0.0 }),
    ) is None,
  )
  assert_true(project_pending_path(node_index, None) is None)
}

///|
test "workflow and source-backed render paths serialize the shared edge projection" {
  let handle = create_source_graph(
    "osc = sine(freq: 440Hz)\nmeter = scope(input: osc)",
  )
  let graph = match source_graph_by_handle(handle) {
    Some(graph) => graph
    None => abort("expected source graph")
  }
  let state = source_graph_base_canvas_state(graph)
  assert_true(state.edges.length() > 0)
  let workflow_render = render_state_json(state, [], graph.selected_edge)
  let edge = workflow_render.edges[0]
  let source_render = source_render_state_string(graph, state, [])
  assert_true(source_render.contains("\"path_d\":\"" + edge.path_d + "\""))
  assert_true(source_render.contains(edge.aria_label))
  destroy_source_graph(handle)
}
