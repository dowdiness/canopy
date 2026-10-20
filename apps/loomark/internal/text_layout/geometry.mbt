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
