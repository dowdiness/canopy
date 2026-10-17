///|
/// Return the layer's left offset and width over the textarea's content box.
pub fn calculate_dimming_inline_bounds(
  offset_left : Double,
  width : Double,
  padding_left : Double,
  padding_right : Double,
) -> (Double, Double) {
  (offset_left + padding_left, width - padding_left - padding_right)
}

///|
/// A shade's box within the viewport, and its top in content coordinates,
/// which aligns its holes with the dot grid.
pub struct ShadePlacement {
  top_in_viewport : Double
  top_in_content : Double
  height : Double
}

///|
pub fn calculate_shade_placement(
  content_range : Range,
  viewport_range : Range,
) -> ShadePlacement? {
  content_range
  .intersection(viewport_range)
  .map(visible_range => {
    top_in_viewport: visible_range.start - viewport_range.start,
    top_in_content: visible_range.start,
    height: visible_range.end - visible_range.start,
  })
}
