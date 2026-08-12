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
/// Construct a viewport with a finite origin and positive finite scale.
///
/// This constructor aborts for invalid input. Use `try_from_scale` when values
/// come from an untrusted boundary.
pub fn Viewport::validated(origin~ : ScreenPoint, scale~ : Double) -> Viewport {
  match Viewport::try_from_scale(origin~, scale~) {
    Some(viewport) => viewport
    None =>
      abort(
        "viewport origin must be finite and scale must be finite and positive",
      )
  }
}

///|
/// Construct a viewport from untrusted input without aborting.
pub fn Viewport::try_from_scale(
  origin~ : ScreenPoint,
  scale~ : Double,
) -> Viewport? {
  if origin.is_finite() && valid_scale(scale) {
    Some({ origin, scale })
  } else {
    None
  }
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
///
/// This method aborts for invalid input. Use `try_with_scale_around` when values
/// come from an untrusted boundary.
pub fn Viewport::with_scale_around(
  self : Viewport,
  anchor~ : ScreenPoint,
  absolute_scale~ : Double,
) -> Viewport {
  match self.try_with_scale_around(anchor~, absolute_scale~) {
    Some(viewport) => viewport
    None =>
      abort(
        "viewport anchor/origin must be finite and scale must be finite and positive",
      )
  }
}

///|
/// Change scale around an anchor without aborting on invalid input.
pub fn Viewport::try_with_scale_around(
  self : Viewport,
  anchor~ : ScreenPoint,
  absolute_scale~ : Double,
) -> Viewport? {
  if !anchor.is_finite() || !valid_scale(absolute_scale) {
    None
  } else {
    let world_anchor = self.screen_to_world(anchor)
    let origin = ScreenPoint::from_xy(
      x=anchor.x - world_anchor.x * absolute_scale,
      y=anchor.y - world_anchor.y * absolute_scale,
    )
    Viewport::try_from_scale(origin~, scale=absolute_scale)
  }
}
