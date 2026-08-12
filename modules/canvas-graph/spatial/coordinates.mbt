///|
fn finite_coordinate(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
/// A point in canvas-local screen coordinates.
pub struct ScreenPoint {
  priv x : Double
  priv y : Double
} derive(Eq, Debug)

///|
/// Construct a finite screen-space point.
pub fn ScreenPoint::from_xy(
  x~ : Double,
  y~ : Double,
) -> ScreenPoint raise CoordinateError {
  guard finite_coordinate(x) && finite_coordinate(y) else {
    raise CoordinateError::NonFinite
  }
  { x, y }
}

///|
/// Return the horizontal screen coordinate.
pub fn ScreenPoint::x(self : ScreenPoint) -> Double {
  self.x
}

///|
/// Return the vertical screen coordinate.
pub fn ScreenPoint::y(self : ScreenPoint) -> Double {
  self.y
}

///|
/// A point in canvas world coordinates.
pub struct WorldPoint {
  priv x : Double
  priv y : Double
} derive(Eq, Debug)

///|
/// Construct a finite world-space point.
pub fn WorldPoint::from_xy(
  x~ : Double,
  y~ : Double,
) -> WorldPoint raise CoordinateError {
  guard finite_coordinate(x) && finite_coordinate(y) else {
    raise CoordinateError::NonFinite
  }
  { x, y }
}

///|
/// Return the horizontal world coordinate.
pub fn WorldPoint::x(self : WorldPoint) -> Double {
  self.x
}

///|
/// Return the vertical world coordinate.
pub fn WorldPoint::y(self : WorldPoint) -> Double {
  self.y
}

///|
/// A finite, strictly positive viewport scale.
pub struct Scale {
  priv value : Double
} derive(Eq, Debug)

///|
/// Construct a finite positive scale from an untrusted number.
pub fn Scale::from_double(value~ : Double) -> Scale raise ScaleError {
  guard finite_coordinate(value) else { raise ScaleError::NonFinite }
  guard value > 0.0 else { raise ScaleError::NonPositive }
  { value, }
}

///|
/// Return the underlying scale value at an intentional numeric boundary.
pub fn Scale::to_double(self : Scale) -> Double {
  self.value
}
