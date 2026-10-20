///|
/// How a pane places source offsets on screen and scrolls them. Heights are
/// viewport coordinates.
priv trait ReadingGeometry {
  /// Top of the line showing `offset`.
  fn top_of(Self, Int) -> Double
  /// The source offset shown at height `top`.
  fn offset_at(Self, Double) -> Int
  /// Zero where offsets sit at points rather than on lines.
  fn line_height(Self) -> Double
  /// Top and bottom of the area clear of overlaid controls.
  fn readable(Self) -> (Double, Double)
  fn scroll_by(Self, Double) -> Unit
}

///|
fn[G : ReadingGeometry] readable_top(geometry : G) -> Double {
  geometry.readable().0
}

///|
/// Where a line asked to sit at `top` lands inside the readable area.
fn[G : ReadingGeometry] fitted(geometry : G, top : Double) -> Double {
  let (readable_top, readable_bottom) = geometry.readable()
  fitted_top(top, geometry.line_height(), readable_top, readable_bottom)
}

///|
fn[G : ReadingGeometry] is_readable(geometry : G, top : Double) -> Bool {
  fitted(geometry, top) == top
}

///|
fn[G : ReadingGeometry] anchor_at(geometry : G, offset : Int) -> ReadingAnchor {
  { offset, top: geometry.top_of(offset), }
}

///|
fn[G : ReadingGeometry] misalignment(
  geometry : G,
  anchor : ReadingAnchor,
) -> Double {
  geometry.top_of(anchor.offset) - fitted(geometry, anchor.top)
}

///|
fn[G : ReadingGeometry] align(geometry : G, anchor : ReadingAnchor) -> Unit {
  let delta = misalignment(geometry, anchor)
  if delta.abs() >= 0.5 {
    geometry.scroll_by(delta)
  }
}

///|
fn[G : ReadingGeometry] reveal(geometry : G, offset : Int) -> Unit {
  align(geometry, anchor_at(geometry, offset))
}

///|
impl ReadingGeometry for @preview.PreviewGeometry with fn top_of(self, offset) {
  self.top_of(offset)
}

///|
impl ReadingGeometry for @preview.PreviewGeometry with fn offset_at(self, top) {
  self.offset_at(top)
}

///|
/// Preview places an offset at a point inside its block.
impl ReadingGeometry for @preview.PreviewGeometry with fn line_height(_) {
  0.0
}

///|
impl ReadingGeometry for @preview.PreviewGeometry with fn readable(self) {
  self.readable()
}

///|
impl ReadingGeometry for @preview.PreviewGeometry with fn scroll_by(self, delta) {
  self.scroll_by(delta)
}

///|
fn on_resize(element : @dom.Element, resized : () -> Unit) -> () -> Unit {
  let observer = @dom.ResizeObserver::new((_, _) => resized())
  @browser.observe_border_box(observer, element)
  () => observer.disconnect()
}

///|
/// A face that arrives late rewraps the text.
fn on_fonts_loaded(document : @dom.Document, loaded : () -> Unit) -> () -> Unit {
  let fonts = @browser.document_fonts(document)
  let listener : @dom.Listener = _ => loaded()
  fonts.add_event_listener("loadingdone", listener)
  () => fonts.remove_event_listener("loadingdone", listener)
}
