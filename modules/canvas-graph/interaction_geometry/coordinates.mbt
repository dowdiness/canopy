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
