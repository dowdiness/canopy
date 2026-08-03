///|
/// ARIA live-region attrs for a status element.
///
/// The element announces text changes politely and atomically while exposing a
/// stable `data-tone` hook for consumer-owned styling and tests.
pub fn Tone::attrs(self : Tone) -> @html.Attrs {
  @html.Attrs::build()
  .role("status")
  .aria_live("polite")
  .aria_atomic("true")
  .data_set("tone", self.data_value())
}
