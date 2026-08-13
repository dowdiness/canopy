///|
fn screen_point(x : Double, y : Double) -> ScreenPoint {
  try! ScreenPoint::from_xy(x~, y~)
}

///|
fn world_point(x : Double, y : Double) -> WorldPoint {
  try! WorldPoint::from_xy(x~, y~)
}

///|
fn scale(value : Double) -> Scale {
  try! Scale::from_double(value~)
}

///|
fn viewport_for_test(
  origin_x : Double,
  origin_y : Double,
  scale_value : Double,
) -> Viewport {
  Viewport::from_scale(
    origin=screen_point(origin_x, origin_y),
    scale=scale(scale_value),
  )
}

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
test "finite coordinate constructors expose only validated values" {
  let screen = screen_point(12.5, -7.25)
  let world = world_point(-3.0, 4.0)
  assert_eq(screen.x(), 12.5)
  assert_eq(screen.y(), -7.25)
  assert_eq(world.x(), -3.0)
  assert_eq(world.y(), 4.0)
}

///|
test "coordinate constructors reject non-finite values" {
  for invalid in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    let screen_result = try {
      ignore(ScreenPoint::from_xy(x=invalid, y=0.0))
      false
    } catch {
      CoordinateError::NonFinite => true
    }
    let world_result = try {
      ignore(WorldPoint::from_xy(x=0.0, y=invalid))
      false
    } catch {
      CoordinateError::NonFinite => true
    }
    assert_true(screen_result)
    assert_true(world_result)
  }
}

///|
test "scale accepts finite positive values and rejects invalid values" {
  for value in [0.1, 1.0, 8.0, 1.0e308] {
    assert_eq(scale(value).to_double(), value)
  }
  let invalid_values = [0.0, -1.0, 0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0]
  for value in invalid_values {
    let rejected = try {
      ignore(Scale::from_double(value~))
      false
    } catch {
      ScaleError::NonFinite | ScaleError::NonPositive => true
    }
    assert_true(rejected)
  }
}

///|
test "viewport construction accepts typed geometry" {
  let viewport = viewport_for_test(12.0, -7.0, 2.5)
  assert_eq(viewport.screen_origin().x(), 12.0)
  assert_eq(viewport.screen_origin().y(), -7.0)
  assert_eq(viewport.scale().to_double(), 2.5)
}

///|
test "viewport round trip law holds for finite points and scales" {
  let viewports = [
    viewport_for_test(-80.0, 45.0, 0.25),
    viewport_for_test(0.0, 0.0, 1.0),
    viewport_for_test(120.0, -33.0, 3.5),
  ]
  let points = [
    world_point(-100.0, 50.0),
    world_point(0.0, 0.0),
    world_point(12.5, -8.25),
  ]
  for viewport in viewports {
    for world in points {
      let screen = try! viewport.world_to_screen(world)
      let round_trip = try! viewport.screen_to_world(screen)
      assert_close(round_trip.x(), world.x())
      assert_close(round_trip.y(), world.y())
    }
  }
}

///|
test "viewport scale law preserves the screen anchor" {
  let viewport = viewport_for_test(100.0, -20.0, 0.75)
  let anchor = screen_point(310.0, 145.0)
  let world_at_anchor = try! viewport.screen_to_world(anchor)
  for scale_value in [0.2, 0.5, 1.0, 2.0, 7.5] {
    let changed = viewport.with_scale_around(
      anchor~,
      absolute_scale=scale(scale_value),
    )
    let projected = try! changed.world_to_screen(world_at_anchor)
    assert_close(projected.x(), anchor.x())
    assert_close(projected.y(), anchor.y())
    assert_close(changed.scale().to_double(), scale_value)
  }
}

///|
test "viewport transforms reject arithmetic overflow" {
  let inverse_overflow = viewport_for_test(0.0, 0.0, 1.0e-308)
  let screen_result = try {
    ignore(inverse_overflow.screen_to_world(screen_point(1.0e308, 0.0)))
    false
  } catch {
    CoordinateError::NonFinite => true
  }
  let forward_overflow = viewport_for_test(0.0, 0.0, 1.0e308)
  let world_result = try {
    ignore(forward_overflow.world_to_screen(world_point(1.0e308, 0.0)))
    false
  } catch {
    CoordinateError::NonFinite => true
  }
  assert_true(screen_result)
  assert_true(world_result)
}

///|
test "anchored scale rejects an overflowing derived origin" {
  let viewport = viewport_for_test(0.0, 0.0, 1.0)
  let result = try {
    ignore(
      viewport.with_scale_around(
        anchor=screen_point(1.0e308, 0.0),
        absolute_scale=scale(1.0e308),
      ),
    )
    false
  } catch {
    CoordinateError::NonFinite => true
  }
  assert_true(result)
}

///|
test "pan snapshot is path independent and rejects origin overflow" {
  let pan = Pan::start(
    viewport=viewport_for_test(400.0, -120.0, 2.0),
    pointer=screen_point(20.0, 30.0),
  )
  let mid = try! pan.viewport_at(screen_point(75.0, -10.0))
  let direct = try! pan.viewport_at(screen_point(160.0, 85.0))
  let repeated = try! pan.viewport_at(screen_point(160.0, 85.0))
  assert_close(mid.screen_origin().x(), 455.0)
  assert_close(mid.screen_origin().y(), -160.0)
  assert_close(direct.screen_origin().x(), 540.0)
  assert_close(direct.screen_origin().y(), -65.0)
  assert_eq(repeated, direct)

  let overflowing_pan = Pan::start(
    viewport=viewport_for_test(0.0, 0.0, 1.0),
    pointer=screen_point(-1.0e308, 0.0),
  )
  let result = try {
    ignore(overflowing_pan.viewport_at(screen_point(1.0e308, 0.0)))
    false
  } catch {
    CoordinateError::NonFinite => true
  }
  assert_true(result)
}

///|
test "drag snapshot is path independent and preserves source arrays" {
  let positions = [
    ItemPosition::from_id_and_point(id="first", point=world_point(10.0, 20.0)),
    ItemPosition::from_id_and_point(id="second", point=world_point(40.0, 55.0)),
  ]
  let drag = Drag::start(
    positions=ReadOnlyArray::from_array(positions[:]),
    pointer=world_point(4.0, 8.0),
  )
  positions[0] = ItemPosition::from_id_and_point(
    id="changed",
    point=world_point(999.0, 999.0),
  )
  let direct = try! drag.positions_at(world_point(20.0, 30.0))
  let repeated = try! drag.positions_at(world_point(20.0, 30.0))
  assert_eq(direct[0].id, "first")
  assert_eq(direct[1].id, "second")
  assert_close(direct[0].point.x(), 26.0)
  assert_close(direct[0].point.y(), 42.0)
  assert_close(direct[1].point.x(), 56.0)
  assert_close(direct[1].point.y(), 77.0)
  assert_eq(repeated, direct)
}

///|
test "drag movement rejects position overflow" {
  let drag = Drag::start(
    positions=[
      ItemPosition::from_id_and_point(
        id="item",
        point=world_point(1.0e308, 0.0),
      ),
    ],
    pointer=world_point(-1.0e308, 0.0),
  )
  let result = try {
    ignore(drag.positions_at(world_point(1.0e308, 0.0)))
    false
  } catch {
    CoordinateError::NonFinite => true
  }
  assert_true(result)
}

///|
test "positive world and screen directions agree" {
  let viewport = viewport_for_test(-30.0, 70.0, 2.5)
  let world_origin = try! viewport.world_to_screen(world_point(0.0, 0.0))
  let world_right = try! viewport.world_to_screen(world_point(1.0, 0.0))
  let world_down = try! viewport.world_to_screen(world_point(0.0, 1.0))
  assert_true(world_right.x() > world_origin.x())
  assert_true(world_down.y() > world_origin.y())
  let screen_origin = screen_point(100.0, 100.0)
  let screen_right = screen_point(110.0, 100.0)
  let screen_down = screen_point(100.0, 110.0)
  let world_screen_origin = try! viewport.screen_to_world(screen_origin)
  let world_screen_right = try! viewport.screen_to_world(screen_right)
  let world_screen_down = try! viewport.screen_to_world(screen_down)
  assert_true(world_screen_right.x() > world_screen_origin.x())
  assert_true(world_screen_down.y() > world_screen_origin.y())
}
