///|
/// A pan gesture snapshot.
pub struct Pan {
  priv initial_viewport : Viewport
  priv initial_pointer : ScreenPoint
}

///|
/// Capture the viewport and pointer at the beginning of a pan gesture.
pub fn Pan::start(viewport~ : Viewport, pointer~ : ScreenPoint) -> Pan {
  { initial_viewport: viewport, initial_pointer: pointer }
}

///|
/// Compute the viewport at a pointer position from the original snapshot.
pub fn Pan::viewport_at(self : Pan, pointer : ScreenPoint) -> Viewport {
  let origin = self.initial_viewport.screen_origin()
  Viewport::validated(
    origin=ScreenPoint::from_xy(
      x=origin.x + (pointer.x - self.initial_pointer.x),
      y=origin.y + (pointer.y - self.initial_pointer.y),
    ),
    scale=self.initial_viewport.scale(),
  )
}
