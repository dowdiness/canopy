///|
/// A viewport maps world coordinates into canvas-local screen coordinates.
pub struct Viewport {
  priv origin : ScreenPoint
  priv scale : Double
} derive(Eq, Debug)

///|
fn valid_scale(scale : Double) -> Bool {
  finite_coordinate(scale) && scale > 0.0
}

///|
/// Construct a viewport from an untrusted origin and scale.
pub fn Viewport::from_scale(
  origin~ : ScreenPoint,
  scale~ : Double,
) -> Viewport raise ViewportError {
  guard origin.is_finite() else { raise ViewportError::InvalidOrigin }
  guard valid_scale(scale) else { raise ViewportError::InvalidScale }
  { origin, scale }
}

///|
/// Construct a viewport from trusted finite values.
///
/// Use `from_scale` when the values may be invalid.
pub fn Viewport::validated(origin~ : ScreenPoint, scale~ : Double) -> Viewport {
  try! Viewport::from_scale(origin~, scale~)
}

///|
/// Return the screen-space origin of the world coordinate system.
pub fn Viewport::screen_origin(self : Viewport) -> ScreenPoint {
  self.origin
}

///|
/// Return the viewport's absolute scale.
pub fn Viewport::scale(self : Viewport) -> Double {
  self.scale
}

///|
/// Convert a canvas-local screen point into world coordinates.
pub fn Viewport::screen_to_world(
  self : Viewport,
  screen : ScreenPoint,
) -> WorldPoint {
  WorldPoint::from_xy(
    x=(screen.x - self.origin.x) / self.scale,
    y=(screen.y - self.origin.y) / self.scale,
  )
}

///|
/// Convert a world point into canvas-local screen coordinates.
pub fn Viewport::world_to_screen(
  self : Viewport,
  world : WorldPoint,
) -> ScreenPoint {
  ScreenPoint::from_xy(
    x=self.origin.x + world.x * self.scale,
    y=self.origin.y + world.y * self.scale,
  )
}

///|
/// Return a viewport with an absolute scale while keeping `anchor` fixed.
pub fn Viewport::with_scale_around(
  self : Viewport,
  anchor~ : ScreenPoint,
  absolute_scale~ : Double,
) -> Viewport raise ViewportTransformError {
  guard anchor.is_finite() else { raise ViewportTransformError::InvalidAnchor }
  guard valid_scale(absolute_scale) else {
    raise ViewportTransformError::InvalidViewport(ViewportError::InvalidScale)
  }
  let world_anchor = self.screen_to_world(anchor)
  let origin = ScreenPoint::from_xy(
    x=anchor.x - world_anchor.x * absolute_scale,
    y=anchor.y - world_anchor.y * absolute_scale,
  )
  Viewport::from_scale(origin~, scale=absolute_scale) catch {
    error => raise ViewportTransformError::InvalidViewport(error)
  }
}
