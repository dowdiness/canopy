///|
/// Reading-position policy over the shared textarea layout.
priv struct TextGeometry {
  area : @dom.HTMLTextAreaElement
  layout : @text_layout.MeasuredText
}

///|
/// `None` while the textarea is hidden.
fn TextGeometry::measure(area : @dom.HTMLTextAreaElement) -> TextGeometry? {
  guard area.get_client_height() > 0.0 else { return None }
  Some({ area, layout: @text_layout.measure(area), })
}

///|
/// The selection endpoint the user is moving, where the caret is drawn.
fn caret_offset(area : @dom.HTMLTextAreaElement) -> Int {
  if area.get_selection_direction() == "backward" {
    area.get_selection_start()
  } else {
    area.get_selection_end()
  }
}

///|
impl ReadingGeometry for TextGeometry with fn top_of(self, offset) {
  // Preview may still describe text from before a deletion. A reading
  // position beyond the current source corresponds to its new end.
  let offset = offset.clamp(min=0, max=self.area.get_value().length())
  let area = self.area.as_element()
  area.get_bounding_client_rect().get_top() +
  area.get_client_top() +
  @text_layout.measure_line_top(self.area, offset) -
  area.get_scroll_top()
}

///|
/// Empty lines show no text to keep in place, so the search moves past them.
impl ReadingGeometry for TextGeometry with fn offset_at(self, top) {
  let text = self.layout.source.text()
  let area = self.area.as_element()
  let origin = area.get_bounding_client_rect().get_top() +
    area.get_client_top() -
    area.get_scroll_top()
  let mut low = @text_layout.measure_offset_at(self.area, top - origin)
  while low < text.length() && text.code_unit_at(low) == '\n' {
    low += 1
  }
  low
}

///|
impl ReadingGeometry for TextGeometry with fn line_height(self) {
  self.layout.metrics.line_height
}

///|
/// The textarea's scroll padding keeps lines clear of the overlaid controls;
/// its larger bottom padding only lets the text scroll past its end.
impl ReadingGeometry for TextGeometry with fn readable(self) {
  let area = self.area.as_element()
  let top = area.get_bounding_client_rect().get_top() + area.get_client_top()
  (
    top + self.layout.metrics.padding_top,
    top + area.get_client_height() - self.layout.metrics.scroll_padding_bottom,
  )
}

///|
impl ReadingGeometry for TextGeometry with fn scroll_by(self, delta) {
  let area = self.area.as_element()
  area.set_scroll_top(area.get_scroll_top() + delta)
}
