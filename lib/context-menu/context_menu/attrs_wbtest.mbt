///|
#cfg(target="js")
extern "js" fn test_mouse_event(
  client_x : Double,
  client_y : Double,
) -> @dom.MouseEvent = "(clientX, clientY) => ({ clientX, clientY })"

///|
#cfg(target="js")
test "mouse event points preserve fractional client coordinates" {
  let point = Point::from_mouse_event(test_mouse_event(12.5, 34.25))
  inspect(point.x, content="12.5")
  inspect(point.y, content="34.25")
}

///|
test "close focus id is preserved across open and close" {
  let model = Model::new(id="test-menu").with_close_focus_id("canvas-root")
  guard model.close_focus_id is Some("canvas-root") else {
    fail("expected close focus id to be stored")
  }
  let opened = model.open(anchor=Point(x=1.0F, y=2.0F), item_count=2)
  guard opened.close_focus_id is Some("canvas-root") else {
    fail("expected close focus id to survive open")
  }
  guard opened.close().close_focus_id is Some("canvas-root") else {
    fail("expected close focus id to survive close")
  }
}

///|
test "positioning defaults clamp to viewport" {
  let positioning = Positioning::default()
  inspect(positioning.offset_x, content="0")
  inspect(positioning.offset_y, content="0")
  inspect(positioning.viewport_margin, content="8")
  guard positioning.collision is ClampToViewport else {
    fail("expected default positioning to clamp to viewport")
  }
}

///|
test "positioning constructor preserves offsets and collision strategy" {
  let positioning = Positioning(
    offset_x=4.5F,
    offset_y=6.25F,
    viewport_margin=12.0F,
    collision=NoCollisionHandling,
  )
  inspect(positioning.offset_x, content="4.5")
  inspect(positioning.offset_y, content="6.25")
  inspect(positioning.viewport_margin, content="12")
  guard positioning.collision is NoCollisionHandling else {
    fail("expected explicit collision strategy")
  }
}
