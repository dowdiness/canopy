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
