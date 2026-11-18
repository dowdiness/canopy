///|
/// A coordinate is not finite, whether supplied or produced by a calculation.
#derive(Eq, Debug)
pub(all) suberror CoordinateError {
  /// The coordinate contains NaN or positive/negative infinity.
  NonFinite
}

///|
/// A raw scale cannot represent a usable viewport scale.
#derive(Eq, Debug)
pub(all) suberror ScaleError {
  /// The scale contains NaN or positive/negative infinity.
  NonFinite
  /// The scale is zero or negative.
  NonPositive
}

///|
pub extend CoordinateError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CoordinateError with Eq::{equal, not_equal}

///|
pub extend ScaleError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ScaleError with Eq::{equal, not_equal}
