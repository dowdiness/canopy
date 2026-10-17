///|
/// Keeps the other Split pane showing what the reading pane shows at its top.
pub struct SplitFollowing {
  priv resync : () -> Unit
  priv disconnect : () -> Unit
}

///|
/// Follow again after a change neither pane reports, such as a new Preview
/// rendering.
pub fn SplitFollowing::resync(self : Self) -> Unit {
  (self.resync)()
}

///|
pub fn SplitFollowing::disconnect(self : Self) -> Unit {
  (self.disconnect)()
}

///|
pub fn follow_text_in_preview(
  area : @dom.HTMLTextAreaElement,
  preview : @dom.Element,
) -> SplitFollowing {
  connect_split(area, preview, reading=area.as_element(), following=preview, (
    text,
    rendered,
  ) => follow(text, rendered))
}

///|
pub fn follow_preview_in_text(
  preview : @dom.Element,
  area : @dom.HTMLTextAreaElement,
) -> SplitFollowing {
  connect_split(area, preview, reading=preview, following=area.as_element(), (
    text,
    rendered,
  ) => follow(rendered, text))
}

///|
/// Show the text at the top of `reading` at the same depth below the top of
/// `following`.
fn[R : ReadingGeometry, F : ReadingGeometry] follow(
  reading : R,
  following : F,
) -> Unit {
  let top = readable_top(reading)
  let offset = reading.offset_at(top)
  let depth = reading.top_of(offset) - top
  align(following, { offset, top: readable_top(following) + depth, })
}

///|
/// A pane that does not scroll has no end to reach.
fn scrolled_to_end(pane : @dom.Element) -> Bool {
  let top = pane.get_scroll_top()
  top > 0.0 && top + pane.get_client_height() >= pane.get_scroll_height() - 0.5
}

///|
fn connect_split(
  area : @dom.HTMLTextAreaElement,
  preview : @dom.Element,
  reading~ : @dom.Element,
  following~ : @dom.Element,
  follow_reading : (TextGeometry, @preview.PreviewGeometry) -> Unit,
) -> SplitFollowing {
  fn resync() {
    // The last text of the following pane can sit lower than the text it
    // follows, which would leave the end of the document out of view.
    if scrolled_to_end(reading) {
      following.set_scroll_top(following.get_scroll_height())
    } else if TextGeometry::measure(area) is Some(text) &&
      @preview.PreviewGeometry::measure(preview) is Some(rendered) {
      follow_reading(text, rendered)
    }
  }

  let listener : @dom.Listener = _ => resync()
  reading.add_event_listener_with_options("scroll", listener, passive=true)
  let stop_text_resize = on_resize(area.as_element(), resync)
  let stop_preview_layout = @preview.observe_preview_layout(preview, resync)
  let stop_fonts = on_fonts_loaded(@browser.element_document(preview), resync)
  resync()
  {
    resync,
    disconnect: () => {
      reading.remove_event_listener("scroll", listener)
      stop_text_resize()
      stop_preview_layout()
      stop_fonts()
    },
  }
}
