///|
/// A coordinate is not finite, whether supplied or produced by a calculation.
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
pub extend CoordinateError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CoordinateError with Eq::{equal, not_equal}

///|
pub extend ScaleError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ScaleError with Eq::{equal, not_equal}
