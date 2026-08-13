///|
fn test_cell(runtime_id : Int, id : Int) -> @incr.CellId {
  @incr.CellId::{ runtime_id: @incr.RuntimeId(runtime_id), id }
}

///|
fn test_world(x : Double, y : Double) -> @spatial.WorldPoint {
  try! @spatial.WorldPoint::from_xy(x~, y~)
}

///|
fn test_screen(x : Double, y : Double) -> @spatial.ScreenPoint {
  try! @spatial.ScreenPoint::from_xy(x~, y~)
}

///|
fn incr_canvas_assert_close(actual : Double, expected : Double) -> Unit raise {
  assert_true(
    actual.is_close(
      expected,
      relative_tolerance=1.0e-10,
      absolute_tolerance=1.0e-10,
    ),
  )
}

///|
fn assert_incr_canvas_state_eq(
  actual : IncrCanvasState,
  expected : IncrCanvasState,
) -> Unit raise {
  assert_true(actual.viewport == expected.viewport)
  assert_true(actual.panning == expected.panning)
  assert_true(actual.dragging == expected.dragging)
  assert_true(actual.positions == expected.positions)
  assert_true(actual.selected == expected.selected)
  assert_true(Set::equal(actual.live_cells, expected.live_cells))
  assert_true(actual.active_pointer_id == expected.active_pointer_id)
}

///|
fn incr_canvas_test_viewport(
  x : Double,
  y : Double,
  scale_value : Double,
) -> @spatial.Viewport {
  let origin = test_screen(x, y)
  let scale = try! @spatial.Scale::from_double(value=scale_value)
  @spatial.Viewport::from_scale(origin~, scale~)
}

///|
test "incr canvas reconciliation preserves, adds, and removes local layout" {
  let first = test_cell(1, 1)
  let second = test_cell(1, 2)
  let removed = test_cell(1, 3)
  let existing = Map([
    (first, test_world(42.0, 9.0)),
    (removed, test_world(99.0, 99.0)),
  ])
  let next = reconcile_incr_positions([first, second], existing)
  assert_eq(next.get(first), Some(test_world(42.0, 9.0)))
  assert_true(next.get(second) is Some(_))
  assert_eq(next.get(removed), None)
  assert_eq(reconcile_incr_positions([first, second], existing), next)
}

///|
test "incr canvas reconciliation avoids retained-position overlap" {
  let first = test_cell(1, 1)
  let second = test_cell(1, 2)
  let added = test_cell(1, 3)
  let existing = Map([
    (first, incr_canvas_initial_position(0)),
    (second, incr_canvas_initial_position(1)),
  ])
  let next = reconcile_incr_positions([second, added], existing)
  assert_eq(next.get(second), Some(incr_canvas_initial_position(1)))
  assert_eq(next.get(added), Some(incr_canvas_initial_position(2)))
  let reverse = reconcile_incr_positions([added, first], existing)
  assert_eq(reverse.get(first), Some(incr_canvas_initial_position(0)))
  assert_eq(reverse.get(added), Some(incr_canvas_initial_position(1)))
}

///|
test "incr canvas sync follows live snapshot membership" {
  let runtime = @incr.Runtime()
  let source = @incr.Input(runtime, 1, label="source")
  let first = @incr.Derived(runtime, () => source.get() + 1, label="first")
  let tap = @visualizer.RecomputeTap::attach(runtime)
  ignore(first.read_or_abort())
  let first_state = sync_incr_canvas_state(
    IncrCanvasState::empty(),
    tap.snapshot(),
  )
  let first_position = first_state.positions.get(first.id())

  // The editor's causal snapshot is unchanged in this test; only the live
  // RecomputeSnapshot frontier changes.
  let second = @incr.Derived(runtime, () => source.get() + 2, label="second")
  ignore(second.read_or_abort())
  let expanded = sync_incr_canvas_state(first_state, tap.snapshot())
  assert_true(expanded.live_cells.contains(second.id()))
  assert_eq(expanded.positions.get(first.id()), first_position)
  assert_true(expanded.positions.get(second.id()) is Some(_))

  second.dispose()
  let contracted = sync_incr_canvas_state(expanded, tap.snapshot())
  assert_eq(contracted.positions.get(second.id()), None)
  assert_eq(contracted.positions.get(first.id()), first_position)
  tap.detach()
}

///|
test "incr canvas pointer movement rejects non-finite geometry" {
  let id = test_cell(2, 1)
  let point = test_world(10.0, 20.0)
  let pointer = test_world(0.0, 0.0)
  let drag = @spatial.Drag::start(
    positions=[@spatial.ItemPosition::from_id_and_point(id~, point~)],
    pointer~,
  )
  let state = {
    ..IncrCanvasState::empty(),
    positions: Map([(id, point)]),
    selected: [id],
    dragging: Some(drag),
    active_pointer_id: Some(1),
  }
  let invalid_nan = incr_canvas_pointer_move(state, 0.0 / 0.0, 0.0, Some(1))
  let invalid_infinity = incr_canvas_pointer_move(
    state,
    1.0 / 0.0,
    0.0,
    Some(1),
  )
  assert_incr_canvas_state_eq(invalid_nan, state)
  assert_incr_canvas_state_eq(invalid_infinity, state)
}

///|
test "incr canvas drag is independent of intermediate pointer moves" {
  let id = test_cell(3, 1)
  let point = test_world(10.0, 20.0)
  let pointer = test_world(4.0, 8.0)
  let drag = @spatial.Drag::start(
    positions=[@spatial.ItemPosition::from_id_and_point(id~, point~)],
    pointer~,
  )
  let state = {
    ..IncrCanvasState::empty(),
    viewport: incr_canvas_test_viewport(0.0, 0.0, 1.0),
    positions: Map([(id, point)]),
    selected: [id],
    dragging: Some(drag),
    active_pointer_id: Some(1),
  }
  let direct = incr_canvas_pointer_move(state, 20.0, 30.0, Some(1))
  let via_middle = incr_canvas_pointer_move(
    incr_canvas_pointer_move(state, 12.0, 18.0, Some(1)),
    20.0,
    30.0,
    Some(1),
  )
  assert_eq(direct.positions, via_middle.positions)
  assert_eq(direct.positions.get(id), Some(test_world(26.0, 42.0)))
}

///|
test "incr canvas pan is independent of intermediate pointer moves" {
  let start = test_screen(20.0, 30.0)
  let middle = test_screen(75.0, -10.0)
  let end = test_screen(160.0, 85.0)
  let viewport = incr_canvas_test_viewport(400.0, -120.0, 2.0)
  let state = {
    ..IncrCanvasState::empty(),
    viewport,
    panning: Some(@spatial.Pan::start(viewport~, pointer=start)),
    active_pointer_id: Some(1),
  }
  let direct = incr_canvas_pointer_move(state, end.x(), end.y(), Some(1))
  let via_middle = incr_canvas_pointer_move(
    incr_canvas_pointer_move(state, middle.x(), middle.y(), Some(1)),
    end.x(),
    end.y(),
    Some(1),
  )
  assert_eq(direct.viewport, via_middle.viewport)
}

///|
test "incr canvas pointer identity gates gestures and zero wheel is a no-op" {
  let viewport = incr_canvas_test_viewport(0.0, 0.0, 1.0)
  let state = {
    ..IncrCanvasState::empty(),
    viewport,
    active_pointer_id: Some(7),
  }
  assert_incr_canvas_state_eq(
    incr_canvas_pointer_move(state, 20.0, 30.0, Some(8)),
    state,
  )
  assert_incr_canvas_state_eq(incr_canvas_pointer_up(state, Some(8)), state)
  let released = incr_canvas_pointer_up(state, Some(7))
  assert_true(released.active_pointer_id is None)
  let lost = incr_canvas_capture_lost(state)
  assert_true(lost.active_pointer_id is None)
  assert_incr_canvas_state_eq(
    incr_canvas_capture_lost_for_pointer(state, Some(8)),
    state,
  )
  assert_incr_canvas_state_eq(
    incr_canvas_capture_lost_for_pointer(state, Some(7)),
    lost,
  )
  assert_incr_canvas_state_eq(incr_canvas_zoom(state, 0.0, 10.0, 10.0), state)
}

///|
test "incr canvas DOM claim gates pointer messages" {
  assert_true(incr_canvas_pointer_claim_matches(Some("7"), Some(7)))
  assert_false(incr_canvas_pointer_claim_matches(Some("7"), Some(8)))
  assert_false(incr_canvas_pointer_claim_matches(None, Some(7)))
  assert_false(incr_canvas_pointer_claim_matches(Some("7"), None))
}

///|
test "incr canvas pointer admission rejects unknown and secondary pointers" {
  let empty = IncrCanvasState::empty()
  assert_true(incr_canvas_pointer_admitted(empty, Some(1)))
  assert_false(incr_canvas_pointer_admitted(empty, None))
  let active = { ..empty, active_pointer_id: Some(1) }
  assert_false(incr_canvas_pointer_admitted(active, Some(2)))
  assert_false(incr_canvas_pointer_admitted(active, Some(1)))
}

///|
test "incr canvas zoom preserves the screen anchor and rejects invalid input" {
  let viewport = incr_canvas_test_viewport(100.0, -20.0, 0.75)
  let state = { ..IncrCanvasState::empty(), viewport, }
  let anchor = test_screen(310.0, 145.0)
  let world_at_anchor = try! viewport.screen_to_world(anchor)
  let changed = incr_canvas_zoom(state, -1.0, anchor.x(), anchor.y())
  let projected = try! changed.viewport.world_to_screen(world_at_anchor)
  incr_canvas_assert_close(projected.x(), anchor.x())
  incr_canvas_assert_close(projected.y(), anchor.y())
  let returned = incr_canvas_zoom(changed, 1.0, anchor.x(), anchor.y())
  incr_canvas_assert_close(
    returned.viewport.scale().to_double(),
    state.viewport.scale().to_double(),
  )
  assert_incr_canvas_state_eq(
    incr_canvas_zoom(state, 0.0 / 0.0, 0.0, 0.0),
    state,
  )
  assert_incr_canvas_state_eq(
    incr_canvas_zoom(state, 1.0, 1.0 / 0.0, 0.0),
    state,
  )
}
