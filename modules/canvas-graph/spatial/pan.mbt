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
  match self.try_viewport_at(pointer) {
    Some(viewport) => viewport
    None => abort("pan origin must be finite")
  }
}

///|
/// Compute a viewport without aborting when the translated origin is invalid.
pub fn Pan::try_viewport_at(self : Pan, pointer : ScreenPoint) -> Viewport? {
  let origin = self.initial_viewport.screen_origin()
  Viewport::try_from_scale(
    origin=ScreenPoint::from_xy(
      x=origin.x + (pointer.x - self.initial_pointer.x),
      y=origin.y + (pointer.y - self.initial_pointer.y),
    ),
    scale=self.initial_viewport.scale(),
  )
}
