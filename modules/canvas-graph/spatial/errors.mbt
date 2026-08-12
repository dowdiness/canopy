///|
/// A raw coordinate was not finite.
pub(all) suberror CoordinateError {
  /// The coordinate contains NaN or positive/negative infinity.
  NonFinite
} derive(Eq, Debug)

///|
/// A raw scale cannot represent a usable viewport scale.
pub(all) suberror ScaleError {
  /// The scale contains NaN or positive/negative infinity.
  NonFinite
  /// The scale is zero or negative.
  NonPositive
} derive(Eq, Debug)

///|
/// A finite viewport transform produced a non-finite coordinate.
pub(all) suberror ViewportTransformError {
  /// Arithmetic overflowed while producing a transformed coordinate.
  CoordinateOverflow
} derive(Eq, Debug)

///|
/// A finite pan snapshot produced a non-finite viewport origin.
pub(all) suberror PanError {
  /// Arithmetic overflowed while translating the viewport origin.
  OriginOverflow
} derive(Eq, Debug)

///|
/// A finite drag snapshot produced a non-finite item position.
pub(all) suberror DragError {
  /// Arithmetic overflowed while translating an item position.
  PositionOverflow
} derive(Eq, Debug)
