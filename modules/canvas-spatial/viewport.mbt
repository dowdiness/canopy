///|
/// A viewport maps world coordinates into canvas-local screen coordinates.
pub struct Viewport {
  priv origin : ScreenPoint
  priv scale : Scale
} derive(Eq, Debug)

///|
/// Construct a viewport from already-validated geometry.
pub fn Viewport::from_scale(origin~ : ScreenPoint, scale~ : Scale) -> Viewport {
  { origin, scale }
}

///|
/// Return the screen-space origin of the world coordinate system.
pub fn Viewport::screen_origin(self : Viewport) -> ScreenPoint {
  self.origin
}

///|
/// Return the viewport's validated scale.
pub fn Viewport::scale(self : Viewport) -> Scale {
  self.scale
}

///|
/// Convert a canvas-local screen point into world coordinates.
pub fn Viewport::screen_to_world(
  self : Viewport,
  screen : ScreenPoint,
) -> WorldPoint raise CoordinateError {
  let x = (screen.x() - self.origin.x()) / self.scale.to_double()
  let y = (screen.y() - self.origin.y()) / self.scale.to_double()
  WorldPoint::from_xy(x~, y~)
}

///|
/// Convert a world point into canvas-local screen coordinates.
pub fn Viewport::world_to_screen(
  self : Viewport,
  world : WorldPoint,
) -> ScreenPoint raise CoordinateError {
  let x = self.origin.x() + world.x() * self.scale.to_double()
  let y = self.origin.y() + world.y() * self.scale.to_double()
  ScreenPoint::from_xy(x~, y~)
}

///|
/// Return a viewport with an absolute scale while keeping `anchor` fixed.
pub fn Viewport::with_scale_around(
  self : Viewport,
  anchor~ : ScreenPoint,
  absolute_scale~ : Scale,
) -> Viewport raise CoordinateError {
  let world_anchor = self.screen_to_world(anchor)
  let x = anchor.x() - world_anchor.x() * absolute_scale.to_double()
  let y = anchor.y() - world_anchor.y() * absolute_scale.to_double()
  let next_origin = ScreenPoint::from_xy(x~, y~)
  Viewport::from_scale(origin=next_origin, scale=absolute_scale)
}
