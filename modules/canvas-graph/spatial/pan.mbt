///|
/// A pan gesture snapshot.
pub struct Pan {
  priv initial_viewport : Viewport
  priv initial_pointer : ScreenPoint
}

///|
/// Capture the viewport and pointer at the beginning of a pan gesture.
pub fn Pan::start(
  viewport~ : Viewport,
  pointer~ : ScreenPoint,
) -> Pan raise PanStartError {
  guard pointer.is_finite() else { raise PanStartError::InvalidPointer }
  { initial_viewport: viewport, initial_pointer: pointer }
}

///|
/// Compute the viewport at a pointer position from the original snapshot.
pub fn Pan::viewport_at(
  self : Pan,
  pointer : ScreenPoint,
) -> Viewport raise PanError {
  guard pointer.is_finite() else { raise PanError::InvalidPointer }
  let origin = self.initial_viewport.screen_origin()
  let next_origin = ScreenPoint::from_xy(
    x=origin.x + (pointer.x - self.initial_pointer.x),
    y=origin.y + (pointer.y - self.initial_pointer.y),
  )
  Viewport::from_scale(origin=next_origin, scale=self.initial_viewport.scale()) catch {
    error => raise PanError::InvalidViewport(error)
  }
}
