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
test "Inspector commits the captured edit once and rejects events from a replaced target" {
  let node = edge_projection_test_node("node-a", 0.0, 0.0, 100.0, 80.0, [], [])
  let snapshot = {
    ..canvas_inspector_test_snapshot(Some(node), None, None),
    selected_nodes: ["node-a"],
  }
  let initial : CanvasInspectorState = {
    projection: None,
    session: None,
    reset_generation: 0,
    terminal: false,
  }
  let populated = canvas_inspector_reconcile(initial, snapshot, true)
  let key : CanvasInspectorFieldKey = { node_id: "node-a", field: Binding, }
  let editing = canvas_inspector_update(
      populated,
      Focus(key, "node-a", populated.reset_generation, 1),
      true,
    ).state
  let unrelated = canvas_inspector_reconcile(
    editing,
    { ..snapshot, viewport: { x: 30.0, y: 20.0, scale: 1.5, }, },
    true,
  )
  let submitted = canvas_inspector_update(
    unrelated,
    Enter(key, 1, "renamed", false),
    true,
  )
  match submitted.effect {
    Submit(Rename(node_id, value), _, _) => {
      assert_eq(node_id, NodeId("node-a"))
      assert_eq(value, "renamed")
    }
    _ => fail("a viewport change must not lose the captured edit")
  }
  let duplicate = canvas_inspector_update(
    submitted.state,
    Change(key, 1, "renamed"),
    true,
  )
  assert_true(duplicate.effect is NoEffect)
  let refocused = canvas_inspector_update(
      submitted.state,
      Focus(key, "node-a", populated.reset_generation, 2),
      true,
    ).state
  let pending = canvas_inspector_update(
      refocused,
      Enter(key, 2, "newer", false),
      true,
    ).state
  let stale_completion = canvas_inspector_update(
    pending,
    Completion(1, Applied),
    true,
  )
  assert_true(stale_completion.effect is NoEffect)
  let completed = canvas_inspector_update(
    stale_completion.state,
    Completion(2, Applied),
    true,
  )
  assert_true(
    completed.effect is Finalize(_, Some(value), _, _) && value == "newer",
  )
  let other = edge_projection_test_node("node-b", 0.0, 0.0, 100.0, 80.0, [], [])
  let changed = canvas_inspector_reconcile(
    submitted.state,
    canvas_inspector_test_snapshot(Some(other), Some("node-b"), None),
    true,
  )
  let stale_focus = canvas_inspector_update(
    changed,
    Focus(key, "node-a", populated.reset_generation, 2),
    true,
  )
  let stale_edit = canvas_inspector_update(
    stale_focus.state,
    Enter(key, 2, "wrong-target", false),
    true,
  )
  assert_true(stale_edit.effect is NoEffect)
}

///|
test "Inspector cancellation allows a fresh edit but parser shutdown prevents submission" {
  let node = edge_projection_test_node("node-a", 0.0, 0.0, 100.0, 80.0, [], [])
  let populated = canvas_inspector_reconcile(
    { projection: None, session: None, reset_generation: 0, terminal: false, },
    canvas_inspector_test_snapshot(Some(node), Some("node-a"), None),
    true,
  )
  let key : CanvasInspectorFieldKey = { node_id: "node-a", field: Binding, }
  let editing = canvas_inspector_update(
      populated,
      Focus(key, "node-a", populated.reset_generation, 1),
      true,
    ).state
  let cancelled = canvas_inspector_update(editing, Escape(key, 1), true).state
  let reopened = canvas_inspector_update(
      cancelled,
      Focus(key, "node-a", populated.reset_generation, 2),
      true,
    ).state
  let fresh_edit = canvas_inspector_update(
    reopened,
    Enter(key, 2, "renamed", false),
    true,
  )
  assert_true(
    fresh_edit.effect is Submit(Rename(node_id, value), _, _) &&
    node_id == NodeId("node-a") &&
    value == "renamed",
  )
  let stopped = canvas_inspector_update(fresh_edit.state, ParserStopped, true).state
  let still_stopped = canvas_inspector_update(
      stopped,
      Focus(key, "node-a", stopped.reset_generation, 3),
      true,
    ).state
  assert_true(
    canvas_inspector_update(
      still_stopped,
      Enter(key, 3, "after-shutdown", false),
      true,
    ).effect
    is NoEffect,
  )
}
