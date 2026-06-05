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
