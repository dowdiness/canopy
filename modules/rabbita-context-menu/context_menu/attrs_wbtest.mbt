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
