///|
/// Shell connection to one rendered textarea. Resolve ancestry once; attribute
/// values may change between frames, but replacing the node needs a new connection.
/// This owns no mirror and exposes no deferred geometry result.
pub struct TextArea {
  element : @dom.HTMLTextAreaElement
  priv ancestors : ArrayView[@dom.Element]
}

///|
pub fn TextArea::TextArea(element : @dom.HTMLTextAreaElement) -> TextArea {
  let ancestors : Array[@dom.Element] = []
  for current = Some(element.as_element())
      current is Some(node)
      current = node.get_parent_element() {
    ancestors.push(node)
  }
  { element, ancestors: ancestors[:], }
}

///|
fn TextArea::language(self : TextArea) -> String {
  for node in self.ancestors {
    if node.get_attribute("lang") is Some(lang) {
      return lang
    }
  }
  ""
}

///|
/// Immutable dimensions, with no cache-invalidation meaning attached to identity.
pub struct TextMetrics {
  line_height : Double
  padding_top : Double
  scroll_padding_bottom : Double
  padding_left : Double
  content_width : Double
}

///|
/// Values captured by a measurement. No DOM handles or deferred geometry reads.
/// `reflow_revision` changes when styles or loaded fonts change, independently
/// of source edits; it is scoped to the textarea's document.
pub struct MeasuredText {
  source : @text_lines.TextLines
  metrics : TextMetrics
  reflow_revision : Int
}

///|
fn prepare(area : TextArea) -> (TextMirror, MeasuredText) {
  let document = @browser.element_document(area.element.as_element())
  let mirror = TextMirror::in_document(document)
  let style = @browser.document_window(document).get_computed_style(
    area.element.as_element(),
  )
  (mirror, mirror.measure(area.element, style, area.language()))
}

///|
pub fn measure(area : TextArea) -> MeasuredText {
  let (_, measured) = prepare(area)
  measured
}

///|
/// Positions are relative to the textarea's inner border edge, before scrolling.
/// Each query synchronizes and reads the mirror before returning plain values.
pub fn measure_line_top(area : TextArea, offset : Int) -> Double {
  let (mirror, measured) = prepare(area)
  mirror.line_top(offset, measured.metrics.line_height)
}

///|
pub fn measure_line_bounds(
  area : TextArea,
  first : Int,
  last : Int,
) -> (Double, Double) {
  let (mirror, _) = prepare(area)
  mirror.line_bounds(first, last)
}

///|
/// First UTF-16 offset whose visual line starts at or below `top`, or EOF.
/// The whole search uses one synchronization; no live query object escapes.
pub fn measure_offset_at(area : TextArea, top : Double) -> Int {
  let (mirror, measured) = prepare(area)
  let mut low = 0
  let mut high = measured.source.text().length()
  while low < high {
    let middle = (low + high) / 2
    if mirror.line_top(middle, measured.metrics.line_height) >= top {
      high = middle
    } else {
      low = middle + 1
    }
  }
  low
}

///|
pub suberror MeasurementError {
  UnrenderedGlyph
}

///|
/// The caret edge and glyph centre, in the same coordinates as measure_line_bounds.
/// Clipping and animation of the drawn caret belong to its presentation.
pub fn measure_caret(
  area : TextArea,
  offset : Int,
) -> CaretPosition raise MeasurementError {
  let (mirror, measured) = prepare(area)
  let position = measured.source.position(offset)
  let line = mirror.line_rect(position.line)
  let (edge, top, height) = match
    @text_lines.caret_glyph(
      measured.source.lines()[position.line],
      position.column,
    ) {
    EmptyLine => (line.get_left(), line.get_top(), line.get_height())
    Before(start~, end~) => {
      guard mirror.glyph_rects(position.line, start, end) is [glyph, ..] else {
        raise UnrenderedGlyph
      }
      (glyph.get_left(), glyph.get_top(), glyph.get_height())
    }
    After(start~, end~) => {
      guard mirror.glyph_rects(position.line, start, end) is [.., glyph] else {
        raise UnrenderedGlyph
      }
      (glyph.get_right(), glyph.get_top(), glyph.get_height())
    }
  }
  let origin = mirror.element.get_bounding_client_rect()
  caret_position(edge, top, height, origin.get_left(), origin.get_top())
}
