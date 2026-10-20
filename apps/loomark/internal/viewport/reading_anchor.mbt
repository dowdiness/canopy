///|
/// A source offset and the viewport height where the pane being read showed
/// it. Restoring it keeps that paragraph at the same height.
pub struct ReadingAnchor {
  offset : Int
  top : Double
} derive(Eq)

///|
pub extend ReadingAnchor with Eq::{equal, not_equal}

///|
/// The caret's line while it is readable, otherwise the text at the top of
/// the readable area.
fn[G : ReadingGeometry] reading_anchor(
  geometry : G,
  caret : Int,
) -> ReadingAnchor {
  let at_caret = anchor_at(geometry, caret)
  if is_readable(geometry, at_caret.top) {
    at_caret
  } else {
    anchor_at(geometry, geometry.offset_at(readable_top(geometry)))
  }
}

///|
/// `None` while the textarea is hidden.
pub fn text_reading_anchor(area : @dom.HTMLTextAreaElement) -> ReadingAnchor? {
  let text = @text_layout.TextArea(area)
  TextGeometry::measure(text).map(geometry => {
    reading_anchor(geometry, caret_offset(area))
  })
}

///|
/// `None` when `preview` shows no blocks.
pub fn preview_reading_anchor(
  area : @dom.HTMLTextAreaElement,
  preview : @dom.Element,
) -> ReadingAnchor? {
  @preview.PreviewGeometry::measure(preview).map(geometry => {
    reading_anchor(geometry, caret_offset(area))
  })
}

///|
/// A held anchor and where aligning left it: the pane cannot always scroll
/// far enough to bring the anchor to its height.
priv struct AnchorHold {
  anchor : ReadingAnchor
  mut shortfall : Double
}

///|
fn AnchorHold::AnchorHold(anchor : ReadingAnchor) -> AnchorHold {
  { anchor, shortfall: 0.0, }
}

///|
fn[G : ReadingGeometry] AnchorHold::realign(self : Self, geometry : G) -> Unit {
  align(geometry, self.anchor)
  self.shortfall = misalignment(geometry, self.anchor)
}

///|
/// A scroll that leaves the anchor elsewhere comes from the reader, find in
/// page, or assistive technology rather than from aligning.
fn[G : ReadingGeometry] AnchorHold::scrolled_away(
  self : Self,
  geometry : G,
) -> Bool {
  (misalignment(geometry, self.anchor) - self.shortfall).abs() >= 1.0
}

///|
/// Keep `anchor` in place through layout changes until the returned release
/// runs. Holds nothing while `preview` shows no blocks.
pub fn hold_preview_anchor(
  preview : @dom.Element,
  anchor : ReadingAnchor,
  scrolled_away : () -> Unit,
) -> () -> Unit {
  let hold = AnchorHold(anchor)
  fn realign() {
    if @preview.PreviewGeometry::measure(preview) is Some(geometry) {
      hold.realign(geometry)
    }
  }

  realign()
  let listener : @dom.Listener = _ => {
    if @preview.PreviewGeometry::measure(preview) is Some(geometry) &&
      hold.scrolled_away(geometry) {
      scrolled_away()
    }
  }
  preview.add_event_listener_with_options("scroll", listener, passive=true)
  let stop_layout = @preview.observe_preview_layout(preview, realign)
  let stop_fonts = on_fonts_loaded(@browser.element_document(preview), realign)
  () => {
    preview.remove_event_listener("scroll", listener)
    stop_layout()
    stop_fonts()
  }
}
