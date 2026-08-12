///|
fn finite_coordinate(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
/// A point in canvas-local screen coordinates.
pub struct ScreenPoint {
  x : Double
  y : Double
} derive(Eq, Debug)

///|
/// Construct a screen-space point.
pub fn ScreenPoint::from_xy(x~ : Double, y~ : Double) -> ScreenPoint {
  { x, y }
}

///|
/// Return whether both screen coordinates are finite.
pub fn ScreenPoint::is_finite(self : ScreenPoint) -> Bool {
  finite_coordinate(self.x) && finite_coordinate(self.y)
}

///|
/// A point in canvas world coordinates.
pub struct WorldPoint {
  x : Double
  y : Double
} derive(Eq, Debug)

///|
/// Construct a world-space point.
pub fn WorldPoint::from_xy(x~ : Double, y~ : Double) -> WorldPoint {
  { x, y }
}

///|
/// Return whether both world coordinates are finite.
pub fn WorldPoint::is_finite(self : WorldPoint) -> Bool {
  finite_coordinate(self.x) && finite_coordinate(self.y)
}
