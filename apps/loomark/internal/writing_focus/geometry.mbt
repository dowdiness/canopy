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
pub fn calculate_visible_range(
  content_range : Range,
  viewport_range : Range,
) -> Range? {
  content_range
  .intersection(viewport_range)
  .map(visible_range => {
    start: visible_range.start - viewport_range.start,
    end: visible_range.end - viewport_range.start,
  })
}
