///|
fn assert_close(actual : Double, expected : Double) -> Unit raise {
  assert_true(
    actual.is_close(
      expected,
      relative_tolerance=1.0e-10,
      absolute_tolerance=1.0e-10,
    ),
  )
}

///|
fn viewport_for_test(
  origin_x : Double,
  origin_y : Double,
  scale : Double,
) -> Viewport {
  Viewport::validated(
    origin=ScreenPoint::from_xy(x=origin_x, y=origin_y),
    scale~,
  )
}

///|
test "finite viewport scales are accepted" {
  for scale in [0.1, 0.25, 1.0, 4.0, 8.0] {
    let viewport = viewport_for_test(12.0, -7.0, scale)
    assert_close(viewport.scale(), scale)
  }
}

///|
test "viewport constructor raises typed errors for invalid scales" {
  let origin = ScreenPoint::from_xy(x=12.0, y=-7.0)
  let zero = try {
    ignore(Viewport::from_scale(origin~, scale=0.0))
    None
  } catch {
    ViewportError::InvalidScale => Some(())
    _ => fail("unexpected viewport error")
  }
  let negative = try {
    ignore(Viewport::from_scale(origin~, scale=-1.0))
    None
  } catch {
    ViewportError::InvalidScale => Some(())
    _ => fail("unexpected viewport error")
  }
  let nan = try {
    ignore(Viewport::from_scale(origin~, scale=0.0 / 0.0))
    None
  } catch {
    ViewportError::InvalidScale => Some(())
    _ => fail("unexpected viewport error")
  }
  assert_true(zero is Some(_))
  assert_true(negative is Some(_))
  assert_true(nan is Some(_))
  assert_eq(
    Viewport::from_scale(origin~, scale=2.0),
    Viewport::validated(origin~, scale=2.0),
  )
}

///|
test "viewport constructor raises for non-finite origins" {
  let nan_x = ScreenPoint::from_xy(x=0.0 / 0.0, y=0.0)
  let infinite_y = ScreenPoint::from_xy(x=0.0, y=1.0 / 0.0)
  assert_true(!nan_x.is_finite())
  assert_true(!infinite_y.is_finite())
  let nan_result = try {
    ignore(Viewport::from_scale(origin=nan_x, scale=1.0))
    None
  } catch {
    ViewportError::InvalidOrigin => Some(())
    _ => fail("unexpected viewport error")
  }
  let infinite_result = try {
    ignore(Viewport::from_scale(origin=infinite_y, scale=1.0))
    None
  } catch {
    ViewportError::InvalidOrigin => Some(())
    _ => fail("unexpected viewport error")
  }
  assert_true(nan_result is Some(_))
  assert_true(infinite_result is Some(_))
}

///|
test "anchored scale rejects non-finite anchors and origins" {
  let viewport = viewport_for_test(0.0, 0.0, 1.0e-308)
  let invalid_anchor = try {
    ignore(
      viewport.with_scale_around(
        anchor=ScreenPoint::from_xy(x=0.0 / 0.0, y=0.0),
        absolute_scale=1.0,
      ),
    )
    None
  } catch {
    ViewportTransformError::InvalidAnchor => Some(())
    _ => fail("unexpected viewport transform error")
  }
  let overflowing_origin = try {
    ignore(
      viewport.with_scale_around(
        anchor=ScreenPoint::from_xy(x=1.0e308, y=0.0),
        absolute_scale=1.0,
      ),
    )
    None
  } catch {
    ViewportTransformError::InvalidViewport(ViewportError::InvalidOrigin) =>
      Some(())
    _ => fail("unexpected viewport transform error")
  }
  assert_true(invalid_anchor is Some(_))
  assert_true(overflowing_origin is Some(_))
}

///|
test "viewport round trip law holds for finite points and scales" {
  let viewports = [
    viewport_for_test(-80.0, 45.0, 0.25),
    viewport_for_test(0.0, 0.0, 1.0),
    viewport_for_test(120.0, -33.0, 3.5),
  ]
  let points = [
    WorldPoint::from_xy(x=-100.0, y=50.0),
    WorldPoint::from_xy(x=0.0, y=0.0),
    WorldPoint::from_xy(x=12.5, y=-8.25),
  ]
  for viewport in viewports {
    for world in points {
      let screen = viewport.world_to_screen(world)
      let round_trip = viewport.screen_to_world(screen)
      assert_close(round_trip.x, world.x)
      assert_close(round_trip.y, world.y)
    }
  }
}

///|
test "viewport scale law preserves the screen anchor" {
  let viewport = viewport_for_test(100.0, -20.0, 0.75)
  let anchor = ScreenPoint::from_xy(x=310.0, y=145.0)
  let world_at_anchor = viewport.screen_to_world(anchor)
  for scale in [0.2, 0.5, 1.0, 2.0, 7.5] {
    let changed = viewport.with_scale_around(anchor~, absolute_scale=scale)
    let projected = changed.world_to_screen(world_at_anchor)
    assert_close(projected.x, anchor.x)
    assert_close(projected.y, anchor.y)
    assert_close(changed.scale(), scale)
  }
  let zero_scale = try {
    ignore(viewport.with_scale_around(anchor~, absolute_scale=0.0))
    None
  } catch {
    ViewportTransformError::InvalidViewport(ViewportError::InvalidScale) =>
      Some(())
    _ => fail("unexpected viewport transform error")
  }
  let infinite_scale = try {
    ignore(viewport.with_scale_around(anchor~, absolute_scale=1.0 / 0.0))
    None
  } catch {
    ViewportTransformError::InvalidViewport(ViewportError::InvalidScale) =>
      Some(())
    _ => fail("unexpected viewport transform error")
  }
  assert_true(zero_scale is Some(_))
  assert_true(infinite_scale is Some(_))
}

///|
test "pan at is path independent from its snapshot" {
  let start = ScreenPoint::from_xy(x=20.0, y=30.0)
  let mid = ScreenPoint::from_xy(x=75.0, y=-10.0)
  let end = ScreenPoint::from_xy(x=160.0, y=85.0)
  let pan = Pan::start(
    viewport=viewport_for_test(400.0, -120.0, 2.0),
    pointer=start,
  )
  let mid_viewport = pan.viewport_at(mid)
  let direct = pan.viewport_at(end)
  let repeated = pan.viewport_at(end)
  assert_close(mid_viewport.screen_origin().x, 455.0)
  assert_close(mid_viewport.screen_origin().y, -160.0)
  assert_close(direct.screen_origin().x, 540.0)
  assert_close(direct.screen_origin().y, -65.0)
  assert_close(repeated.screen_origin().x, direct.screen_origin().x)
  assert_close(repeated.screen_origin().y, direct.screen_origin().y)
  assert_close(repeated.scale(), direct.scale())
}

///|
test "pan rejects a non-finite translated origin" {
  let pan = Pan::start(
    viewport=viewport_for_test(0.0, 0.0, 1.0),
    pointer=ScreenPoint::from_xy(x=-1.0e308, y=0.0),
  )
  let result = try {
    ignore(pan.viewport_at(ScreenPoint::from_xy(x=1.0e308, y=0.0)))
    None
  } catch {
    PanError::InvalidViewport(ViewportError::InvalidOrigin) => Some(())
    _ => fail("unexpected pan error")
  }
  assert_true(result is Some(_))
}

///|
test "checked gesture starts reject non-finite snapshots" {
  let viewport = viewport_for_test(0.0, 0.0, 1.0)
  let invalid_pan = try {
    ignore(
      Pan::start(viewport~, pointer=ScreenPoint::from_xy(x=0.0 / 0.0, y=0.0)),
    )
    None
  } catch {
    PanStartError::InvalidPointer => Some(())
  }
  assert_true(invalid_pan is Some(_))
  let invalid_positions : Array[ItemPosition[String]] = [
    ItemPosition::from_id_and_point(
      id="invalid",
      point=WorldPoint::from_xy(x=1.0 / 0.0, y=0.0),
    ),
  ]
  let invalid_drag = try {
    ignore(
      Drag::start(
        positions=ReadOnlyArray::from_array(invalid_positions[:]),
        pointer=WorldPoint::from_xy(x=0.0, y=0.0),
      ),
    )
    None
  } catch {
    DragStartError::InvalidPosition => Some(())
    _ => fail("unexpected drag start error")
  }
  let empty_positions : ReadOnlyArray[ItemPosition[String]] = []
  let invalid_pointer_drag = try {
    ignore(
      Drag::start(
        positions=empty_positions,
        pointer=WorldPoint::from_xy(x=0.0 / 0.0, y=0.0),
      ),
    )
    None
  } catch {
    DragStartError::InvalidPointer => Some(())
    _ => fail("unexpected drag start error")
  }
  assert_true(invalid_drag is Some(_))
  assert_true(invalid_pointer_drag is Some(_))
}

///|
test "drag snapshots initial positions and is path independent" {
  let positions = [
    ItemPosition::from_id_and_point(
      id="first",
      point=WorldPoint::from_xy(x=10.0, y=20.0),
    ),
    ItemPosition::from_id_and_point(
      id="second",
      point=WorldPoint::from_xy(x=40.0, y=55.0),
    ),
  ]
  let drag = Drag::start(
    positions=ReadOnlyArray::from_array(positions[:]),
    pointer=WorldPoint::from_xy(x=4.0, y=8.0),
  )
  positions[0] = ItemPosition::from_id_and_point(
    id="changed",
    point=WorldPoint::from_xy(x=999.0, y=999.0),
  )
  let mid = drag.positions_at(WorldPoint::from_xy(x=12.0, y=18.0))
  let direct = drag.positions_at(WorldPoint::from_xy(x=20.0, y=30.0))
  let repeated = drag.positions_at(WorldPoint::from_xy(x=20.0, y=30.0))
  assert_eq(mid[0].id, "first")
  assert_close(mid[0].point.x, 18.0)
  assert_close(mid[0].point.y, 30.0)
  assert_eq(direct[0].id, "first")
  assert_close(direct[0].point.x, 26.0)
  assert_close(direct[0].point.y, 42.0)
  assert_eq(direct[1].id, "second")
  assert_close(direct[1].point.x, 56.0)
  assert_close(direct[1].point.y, 77.0)
  assert_eq(repeated[0].id, direct[0].id)
  assert_close(repeated[0].point.x, direct[0].point.x)
  assert_close(repeated[0].point.y, direct[0].point.y)
}

///|
test "drag preserves relative positions" {
  let drag = Drag::start(
    positions=[
      ItemPosition::from_id_and_point(
        id=1,
        point=WorldPoint::from_xy(x=-10.0, y=5.0),
      ),
      ItemPosition::from_id_and_point(
        id=2,
        point=WorldPoint::from_xy(x=13.0, y=41.0),
      ),
    ],
    pointer=WorldPoint::from_xy(x=-20.0, y=-5.0),
  )
  let initial = drag.positions_at(WorldPoint::from_xy(x=-20.0, y=-5.0))
  let moved = drag.positions_at(WorldPoint::from_xy(x=80.0, y=95.0))
  assert_close(
    initial[1].point.x - initial[0].point.x,
    moved[1].point.x - moved[0].point.x,
  )
  assert_close(
    initial[1].point.y - initial[0].point.y,
    moved[1].point.y - moved[0].point.y,
  )
  assert_eq(moved[0].id, 1)
  assert_eq(moved[1].id, 2)
}

///|
test "drag preserves initial positions at large magnitudes" {
  let pointer = WorldPoint::from_xy(x=1.0e16, y=-1.0e16)
  let initial = ItemPosition::from_id_and_point(
    id="large",
    point=WorldPoint::from_xy(x=1.0e16 + 2.0, y=-1.0e16 - 2.0),
  )
  let drag = Drag::start(positions=[initial], pointer~)
  let result = drag.positions_at(pointer)
  assert_close(result[0].point.x, initial.point.x)
  assert_close(result[0].point.y, initial.point.y)
}

///|
test "checked drag movement rejects non-finite input and overflow" {
  let drag = Drag::start(
    positions=[
      ItemPosition::from_id_and_point(
        id="item",
        point=WorldPoint::from_xy(x=0.0, y=0.0),
      ),
    ],
    pointer=WorldPoint::from_xy(x=0.0, y=0.0),
  )
  let invalid_pointer = try {
    ignore(drag.positions_at(WorldPoint::from_xy(x=0.0 / 0.0, y=0.0)))
    None
  } catch {
    DragError::InvalidPointer => Some(())
    _ => fail("unexpected drag error")
  }
  assert_true(invalid_pointer is Some(_))

  let overflowing = Drag::start(
    positions=[
      ItemPosition::from_id_and_point(
        id="item",
        point=WorldPoint::from_xy(x=1.0e308, y=0.0),
      ),
    ],
    pointer=WorldPoint::from_xy(x=-1.0e308, y=0.0),
  )
  let overflow = try {
    ignore(overflowing.positions_at(WorldPoint::from_xy(x=1.0e308, y=0.0)))
    None
  } catch {
    DragError::PositionOverflow => Some(())
    _ => fail("unexpected drag error")
  }
  assert_true(overflow is Some(_))
}

///|
test "positive world and screen directions agree" {
  let viewport = viewport_for_test(-30.0, 70.0, 2.5)
  let world_origin = viewport.world_to_screen(WorldPoint::from_xy(x=0.0, y=0.0))
  let world_right = viewport.world_to_screen(WorldPoint::from_xy(x=1.0, y=0.0))
  let world_down = viewport.world_to_screen(WorldPoint::from_xy(x=0.0, y=1.0))
  assert_true(world_right.x > world_origin.x)
  assert_true(world_down.y > world_origin.y)
  let screen_origin = ScreenPoint::from_xy(x=100.0, y=100.0)
  let screen_right = ScreenPoint::from_xy(x=110.0, y=100.0)
  let screen_down = ScreenPoint::from_xy(x=100.0, y=110.0)
  let world_screen_origin = viewport.screen_to_world(screen_origin)
  let world_screen_right = viewport.screen_to_world(screen_right)
  let world_screen_down = viewport.screen_to_world(screen_down)
  assert_true(world_screen_right.x > world_screen_origin.x)
  assert_true(world_screen_down.y > world_screen_origin.y)
}

///|
test "validated viewport construction remains trusted-only" {
  let viewport = viewport_for_test(0.0, 0.0, 1.0)
  assert_eq(viewport.scale(), 1.0)
}

///|
test "panic validated viewport rejects zero scale" {
  ignore(viewport_for_test(0.0, 0.0, 0.0))
}

///|
test "panic validated viewport rejects negative scale" {
  ignore(viewport_for_test(0.0, 0.0, -1.0))
}

///|
test "panic validated viewport rejects NaN scale" {
  ignore(viewport_for_test(0.0, 0.0, 0.0 / 0.0))
}

///|
test "panic validated viewport rejects infinite scale" {
  ignore(viewport_for_test(0.0, 0.0, 1.0 / 0.0))
}
