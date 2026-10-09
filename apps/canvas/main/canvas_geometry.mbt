///|
fn canvas_relative_screen_point(
  client_x : Double,
  client_y : Double,
  left : Double,
  top : Double,
) -> ScreenPoint? {
  let point = ScreenPoint::from_xy(x=client_x - left, y=client_y - top) catch {
    @spatial.CoordinateError::NonFinite => return None
  }
  Some(point)
}

///|
fn canvas_library_screen_point(width : Double, height : Double) -> ScreenPoint? {
  let screen = ScreenPoint::from_xy(x=width * 0.52, y=height * 0.48) catch {
    @spatial.CoordinateError::NonFinite => return None
  }
  Some(screen)
}

///|
fn context_menu_anchor(
  client_x : Double,
  client_y : Double,
) -> @context_menu.Point? {
  let anchor_x = Float::from_double(client_x)
  let anchor_y = Float::from_double(client_y)
  if anchor_x.is_nan() ||
    anchor_x.is_inf() ||
    anchor_y.is_nan() ||
    anchor_y.is_inf() {
    None
  } else {
    Some(@context_menu.Point(x=anchor_x, y=anchor_y))
  }
}
