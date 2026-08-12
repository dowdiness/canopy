///|
/// A pan gesture snapshot.
pub struct Pan {
  priv initial_viewport : Viewport
  priv initial_pointer : ScreenPoint
}

///|
/// Capture the viewport and pointer at the beginning of a pan gesture.
/// The caller must provide a finite pointer; use `try_start` for untrusted input.
pub fn Pan::start(viewport~ : Viewport, pointer~ : ScreenPoint) -> Pan {
  { initial_viewport: viewport, initial_pointer: pointer }
}

///|
/// Capture a pan gesture without accepting a non-finite start pointer.
pub fn Pan::try_start(viewport~ : Viewport, pointer~ : ScreenPoint) -> Pan? {
  if pointer.is_finite() {
    Some({ initial_viewport: viewport, initial_pointer: pointer })
  } else {
    None
  }
}

///|
/// Compute the viewport at a finite pointer position from the original snapshot.
/// Use `try_viewport_at` for untrusted pointer input.
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
