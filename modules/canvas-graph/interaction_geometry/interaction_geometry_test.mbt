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
fn viewport_json_with_coordinates(
  x : Double,
  y : Double,
  scale : Double,
) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["x"] = x.to_json()
  fields["y"] = y.to_json()
  fields["scale"] = scale.to_json()
  Json::object(fields)
}

///|
fn viewport_json(scale : Double) -> Json {
  viewport_json_with_coordinates(12.0, -7.0, scale)
}

///|
fn assert_rejects_viewport_json(json : Json) -> Unit raise {
  let rejected = try {
    let _ : Viewport = @json.from_json(json)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "viewport JSON preserves the existing wire shape" {
  let viewport = viewport_for_test(12.0, -7.0, 2.5)
  inspect(
    viewport.to_json().stringify(),
    content="{\"x\":12,\"y\":-7,\"scale\":2.5}",
  )
  let decoded : Viewport = @json.from_json(viewport.to_json())
  assert_eq(decoded, viewport)
}

///|
test "viewport JSON rejects non-positive and non-finite scales" {
  assert_rejects_viewport_json(viewport_json(0.0))
  assert_rejects_viewport_json(viewport_json(-1.0))
  assert_rejects_viewport_json(viewport_json(0.0 / 0.0))
  assert_rejects_viewport_json(viewport_json(1.0 / 0.0))
}

///|
test "viewport JSON rejects non-finite coordinates" {
  assert_rejects_viewport_json(
    viewport_json_with_coordinates(1.0 / 0.0, -7.0, 1.0),
  )
  assert_rejects_viewport_json(
    viewport_json_with_coordinates(12.0, 0.0 / 0.0, 1.0),
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
test "checked viewport constructor rejects invalid scales" {
  let origin = ScreenPoint::from_xy(x=12.0, y=-7.0)
  assert_eq(Viewport::try_from_scale(origin~, scale=0.0), None)
  assert_eq(Viewport::try_from_scale(origin~, scale=-1.0), None)
  assert_eq(Viewport::try_from_scale(origin~, scale=0.0 / 0.0), None)
  assert_eq(
    Viewport::try_from_scale(origin~, scale=2.0),
    Some(Viewport::validated(origin~, scale=2.0)),
  )
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
  assert_eq(viewport.try_with_scale_around(anchor~, absolute_scale=0.0), None)
  assert_eq(
    viewport.try_with_scale_around(anchor~, absolute_scale=1.0 / 0.0),
    None,
  )
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
test "map_drag_positions_at translates a borrowed sliced snapshot" {
  let positions = [
    ItemPosition::from_id_and_point(
      id="skip",
      point=WorldPoint::from_xy(x=-100.0, y=-100.0),
    ),
    ItemPosition::from_id_and_point(
      id="first",
      point=WorldPoint::from_xy(x=10.0, y=20.0),
    ),
    ItemPosition::from_id_and_point(
      id="second",
      point=WorldPoint::from_xy(x=40.0, y=55.0),
    ),
  ]
  let moved = map_drag_positions_at(
    positions=positions[1:3],
    initial_pointer=WorldPoint::from_xy(x=4.0, y=8.0),
    current_pointer=WorldPoint::from_xy(x=12.0, y=18.0),
    to_point=item => (item.point.x, item.point.y),
    map_result=(item, x, y) => {
      ItemPosition::from_id_and_point(
        id=item.id,
        point=WorldPoint::from_xy(x~, y~),
      )
    },
  )
  assert_eq(moved.length(), 2)
  assert_eq(moved[0].id, "first")
  assert_close(moved[0].point.x, 18.0)
  assert_close(moved[0].point.y, 30.0)
  assert_eq(moved[1].id, "second")
  assert_close(moved[1].point.x, 48.0)
  assert_close(moved[1].point.y, 65.0)
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
test "panic viewport rejects zero scale" {
  ignore(viewport_for_test(0.0, 0.0, 0.0))
}

///|
test "panic viewport rejects negative scale" {
  ignore(viewport_for_test(0.0, 0.0, -1.0))
}

///|
test "panic viewport rejects non-finite scale" {
  ignore(viewport_for_test(0.0, 0.0, 0.0 / 0.0))
}

///|
test "panic viewport rejects positive infinity scale" {
  ignore(viewport_for_test(0.0, 0.0, 1.0 / 0.0))
}

///|
test "panic viewport rejects positive infinity update scale" {
  let viewport = viewport_for_test(0.0, 0.0, 1.0)
  ignore(
    viewport.with_scale_around(
      anchor=ScreenPoint::from_xy(x=10.0, y=20.0),
      absolute_scale=1.0 / 0.0,
    ),
  )
}
