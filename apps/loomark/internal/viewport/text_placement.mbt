///|
/// What keeps the textarea's scroll position when it resizes.
pub(all) enum TextPlacement {
  RevealCaret
  /// Keep the anchor at its height, also when a late font rewraps the text,
  /// until a scroll leaves it elsewhere.
  HoldAnchor(ReadingAnchor)
  /// Preview is being read, so Split scrolls the textarea to follow it.
  FollowPreview
} derive(Eq)

///|
pub extend TextPlacement with Eq::{equal, not_equal}

///|
priv enum Placing {
  Revealing
  Holding(AnchorHold)
  Following
}

///|
pub struct TextPlacing {
  priv place : (TextPlacement) -> Unit
  priv disconnect : () -> Unit
}

///|
/// A new anchor is aligned at once. Revealing the caret waits for the next
/// resize, so releasing an anchor leaves the text where the reader put it.
pub fn TextPlacing::place(self : Self, placement : TextPlacement) -> Unit {
  (self.place)(placement)
}

///|
pub fn TextPlacing::disconnect(self : Self) -> Unit {
  (self.disconnect)()
}

///|
fn Placing::Placing(placement : TextPlacement) -> Placing {
  match placement {
    RevealCaret => Revealing
    HoldAnchor(anchor) => Holding(AnchorHold(anchor))
    FollowPreview => Following
  }
}

///|
/// Bind effects to a supplied node, not to a document-global selector. The
/// first resize report arrives as soon as the textarea is observed.
pub fn place_text_area(
  area : @dom.HTMLTextAreaElement,
  placement : TextPlacement,
  scrolled_away : () -> Unit,
) -> TextPlacing {
  let text = @text_layout.TextArea(area)
  let mut placing = Placing(placement)
  fn resized() {
    guard TextGeometry::measure(text) is Some(geometry) else { return }
    match placing {
      Revealing => reveal(geometry, caret_offset(area))
      Holding(hold) => hold.realign(geometry)
      Following => ()
    }
  }

  // Faces for other scripts load lazily while the reader scrolls, so a late
  // font realigns a held anchor but does not pull the reader to the caret.
  fn realign() {
    if placing is Holding(hold) && TextGeometry::measure(text) is Some(geometry) {
      hold.realign(geometry)
    }
  }

  fn place(placement : TextPlacement) {
    placing = Placing(placement)
    realign()
  }

  realign()
  let listener : @dom.Listener = _ => {
    if placing is Holding(hold) &&
      TextGeometry::measure(text) is Some(geometry) &&
      hold.scrolled_away(geometry) {
      scrolled_away()
    }
  }
  let element = area.as_element()
  element.add_event_listener_with_options("scroll", listener, passive=true)
  let stop_resize = on_resize(element, resized)
  let stop_fonts = on_fonts_loaded(@browser.element_document(element), realign)
  {
    place,
    disconnect: () => {
      element.remove_event_listener("scroll", listener)
      stop_resize()
      stop_fonts()
    },
  }
}
