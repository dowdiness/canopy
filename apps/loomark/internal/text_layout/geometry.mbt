///|
/// Glyphs sit inside their line by half the leading; taller fallback glyphs
/// reach out of it, but their middle stays within it.
fn line_box_top(
  middle : Double,
  padding_top : Double,
  line_height : Double,
) -> Double {
  padding_top + ((middle - padding_top) / line_height).floor() * line_height
}

///|
pub struct CaretPosition {
  x : Double
  y : Double
}

///|
/// Convert a measured glyph edge and vertical box into content coordinates.
/// The shell chooses and reads the glyph; this calculation knows no DOMRect.
fn caret_position(
  edge : Double,
  top : Double,
  height : Double,
  origin_left : Double,
  origin_top : Double,
) -> CaretPosition {
  { x: edge - origin_left, y: top + height / 2 - origin_top, }
}
