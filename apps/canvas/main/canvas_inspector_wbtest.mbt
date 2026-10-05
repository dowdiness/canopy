///|
fn canvas_inspector_test_snapshot(
  node : NodeJson?,
  selected : String?,
  inspector : InspectorNodeJson?,
) -> CanvasRenderLayerSnapshot {
  {
    viewport: { x: 0.0, y: 0.0, scale: 1.0, },
    nodes: match node {
      Some(value) => [value]
      None => []
    },
    edges: [],
    selected,
    selected_nodes: match selected {
      Some(value) => [value]
      None => []
    },
    inspector,
    connecting: None,
    input_compatibility: [],
    validation: [],
  }
}

///|
test "Inspector source fallback and sessions target captured identity" {
  let node = edge_projection_test_node("node-a", 0.0, 0.0, 100.0, 80.0, [], [])
  let snapshot = {
    ..canvas_inspector_test_snapshot(Some(node), None, None),
    selected_nodes: ["node-a"],
  }
  let projection = canvas_inspector_projection(true, snapshot)
  assert_true(projection is Some(value) && value.summary.id == "node-a")
  let initial : CanvasInspectorState = {
    projection: None,
    session: None,
    reset_generation: 0,
    terminal: false,
  }
  let populated = canvas_inspector_reconcile(initial, snapshot, true)
  let key : CanvasInspectorFieldKey = { node_id: "node-a", field: Binding, }
  let (editing, _) = canvas_inspector_update(
    populated,
    Focus(key, "node-a", populated.reset_generation, 1),
    true,
    _ => (),
    _ => (),
  )
  assert_true(editing.session is Some(session) && session.phase == Editing)
  let requests : Array[CanvasSourceMessage] = []
  let (submitted, _) = canvas_inspector_update(
    editing,
    Enter(key, 1, "renamed", false),
    true,
    message => requests.push(message),
    _ => (),
  )
  assert_true(submitted.session is Some(session) && session.phase == Submitted)
  let (duplicate, _) = canvas_inspector_update(
    submitted,
    Change(key, 1, "renamed"),
    true,
    message => requests.push(message),
    _ => (),
  )
  assert_true(duplicate == submitted)
  let (rejected, _) = canvas_inspector_update(
    submitted,
    Completion(1, Rejected),
    true,
    _ => (),
    _ => (),
  )
  assert_true(rejected.session is None)
  let other = edge_projection_test_node("node-b", 0.0, 0.0, 100.0, 80.0, [], [])
  let changed = canvas_inspector_reconcile(
    submitted,
    canvas_inspector_test_snapshot(Some(other), Some("node-b"), None),
    true,
  )
  assert_true(changed.session is None)
  assert_eq(changed.reset_generation, submitted.reset_generation + 1)
  let (stale_focus, _) = canvas_inspector_update(
    changed,
    Focus(key, "node-a", submitted.reset_generation, 2),
    true,
    _ => (),
    _ => (),
  )
  assert_true(stale_focus.session is None)
}

///|
test "Inspector cancellation permits a new session and terminal blocks edits" {
  let node = edge_projection_test_node("node-a", 0.0, 0.0, 100.0, 80.0, [], [])
  let populated = canvas_inspector_reconcile(
    { projection: None, session: None, reset_generation: 0, terminal: false, },
    canvas_inspector_test_snapshot(Some(node), Some("node-a"), None),
    true,
  )
  let key : CanvasInspectorFieldKey = { node_id: "node-a", field: Binding, }
  let (editing, _) = canvas_inspector_update(
    populated,
    Focus(key, "node-a", populated.reset_generation, 1),
    true,
    _ => (),
    _ => (),
  )
  let (cancelled, _) = canvas_inspector_update(
    editing,
    Escape(key, 1),
    true,
    _ => (),
    _ => (),
  )
  assert_true(cancelled.session is Some(session) && session.phase == Cancelled)
  let (reopened, _) = canvas_inspector_update(
    cancelled,
    Focus(key, "node-a", populated.reset_generation, 2),
    true,
    _ => (),
    _ => (),
  )
  assert_true(
    reopened.session is Some(session) &&
    session.id == 2 &&
    session.phase == Editing,
  )
  let (stopped, _) = canvas_inspector_update(
    reopened,
    ParserStopped,
    true,
    _ => (),
    _ => (),
  )
  assert_true(stopped.terminal && stopped.session is None)
  let (still_stopped, _) = canvas_inspector_update(
    stopped,
    Focus(key, "node-a", stopped.reset_generation, 3),
    true,
    _ => (),
    _ => (),
  )
  assert_true(still_stopped.session is None)
}

///|
test "unrelated Inspector snapshots preserve field session" {
  let node = edge_projection_test_node("node-a", 0.0, 0.0, 100.0, 80.0, [], [])
  let base = canvas_inspector_test_snapshot(Some(node), Some("node-a"), None)
  let initial : CanvasInspectorState = {
    projection: None,
    session: None,
    reset_generation: 0,
    terminal: false,
  }
  let populated = canvas_inspector_reconcile(initial, base, true)
  let key : CanvasInspectorFieldKey = { node_id: "node-a", field: Binding, }
  let (editing, _) = canvas_inspector_update(
    populated,
    Focus(key, "node-a", populated.reset_generation, 1),
    true,
    _ => (),
    _ => (),
  )
  let unrelated = canvas_inspector_reconcile(
    editing,
    { ..base, viewport: { x: 30.0, y: 20.0, scale: 1.5, }, },
    true,
  )
  assert_true(unrelated.session == editing.session)
  assert_eq(unrelated.reset_generation, editing.reset_generation)
}
