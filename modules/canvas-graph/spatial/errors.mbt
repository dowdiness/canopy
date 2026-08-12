///|
/// Invalid viewport construction input.
pub(all) suberror ViewportError {
  /// The viewport origin is not finite.
  InvalidOrigin
  /// The viewport scale is not finite or is not positive.
  InvalidScale
} derive(Eq, Debug)

///|
/// Invalid input or derived state during an anchored viewport transform.
pub(all) suberror ViewportTransformError {
  /// The zoom anchor is not finite.
  InvalidAnchor
  /// The transformed viewport would violate its invariants.
  InvalidViewport(ViewportError)
} derive(Eq, Debug)

///|
/// Invalid input when capturing a pan gesture.
pub(all) suberror PanStartError {
  /// The initial screen pointer is not finite.
  InvalidPointer
} derive(Eq, Debug)

///|
/// Invalid input or derived state while evaluating a pan gesture.
pub(all) suberror PanError {
  /// The current screen pointer is not finite.
  InvalidPointer
  /// The translated viewport would violate its invariants.
  InvalidViewport(ViewportError)
} derive(Eq, Debug)

///|
/// Invalid input when capturing a drag gesture.
pub(all) suberror DragStartError {
  /// The initial world pointer is not finite.
  InvalidPointer
  /// A drag snapshot contains a non-finite item position.
  InvalidPosition
} derive(Eq, Debug)

///|
/// Invalid input or derived state while evaluating a drag gesture.
pub(all) suberror DragError {
  /// The current world pointer is not finite.
  InvalidPointer
  /// Moving the finite snapshot produced a non-finite item position.
  PositionOverflow
} derive(Eq, Debug)
