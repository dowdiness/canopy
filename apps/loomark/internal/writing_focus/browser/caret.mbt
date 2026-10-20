///|
/// Like VS Code, continuous typing keeps the caret solid without touching its
/// animation; the blink resumes once input pauses this long.
const CARET_REST_MS : Int = 500

///|
/// The widest bar that still clears the side bearings of tight pairs such as
/// 本 and L at 17px. The bar is centred on the caret edge, and its styles read
/// this width from `--loomark-caret-width`.
const CARET_WIDTH : Double = 1.5

///|
/// How a placed caret reaches its position.
priv enum CaretMotion {
  /// Straight to the position, with the text.
  Jump
  /// A short transition, for navigation through unchanged text.
  Glide
}

///|
/// Breathes like ephe: holds, then eases out and back in over 384 ms each on a
/// sine curve, so the caret never flashes.
let caret_blink : FixedArray[@browser_api.OpacityKeyframe] = [
  { offset: 0.0, opacity: 1.0, easing: "linear", },
  { offset: 0.18, opacity: 1.0, easing: "cubic-bezier(0.37, 0, 0.63, 1)", },
  { offset: 0.5, opacity: 0.0, easing: "cubic-bezier(0.37, 0, 0.63, 1)", },
  { offset: 0.82, opacity: 1.0, easing: "linear", },
  { offset: 1.0, opacity: 1.0, easing: "linear", },
]

///|
const CARET_BLINK_MS : Double = 1200.0

///|
/// Like VS Code's smooth blinking, the blink settles solid after about ten
/// seconds so an idle editor stops producing frames.
const CARET_BLINK_ITERATIONS : Double = 8.0

///|
/// A caret on screen. While `resting` holds a timer, the caret stays solid and
/// the timer plays the blink; otherwise the blink is breathing.
priv struct ShownCaret {
  mut at : @writing_focus.Caret
  mut resting : Int?
}

///|
priv enum CaretPresence {
  Hidden
  Shown(ShownCaret)
}

///|
priv struct WritingCaret {
  element : @dom.HTMLElement
  window : @dom.Window
  blink : @dom.Animation
  mut presence : CaretPresence
}

///|
fn WritingCaret::WritingCaret(
  document : @dom.Document,
  window : @dom.Window,
  layer : @dom.HTMLElement,
) -> WritingCaret {
  let element = document.create_element("div").to_html_element().unwrap()
  element.set_attribute("class", "loomark-writing-caret")
  element.set_attribute("hidden", "")
  element.get_style().set_property("--loomark-caret-width", "\{CARET_WIDTH}px")
  layer.append_child(element.as_node())
  let blink = @browser_api.idle_opacity_animation(
    element,
    caret_blink[:],
    duration_ms=CARET_BLINK_MS,
    iterations=CARET_BLINK_ITERATIONS,
  )
  { element, window, blink, presence: Hidden, }
}

///|
/// Cancels the blink on the first move only; later moves just postpone the
/// timer that plays it again.
fn WritingCaret::hold(self : WritingCaret, shown : ShownCaret) -> Unit {
  match shown.resting {
    Some(timer) => self.window.clear_timeout(timer)
    None => @browser_api.cancel_animation(self.blink)
  }
  shown.resting = Some(
    self.window.set_timeout(
      () => {
        shown.resting = None
        @browser_api.play_animation(self.blink)
      },
      CARET_REST_MS,
    ),
  )
}

///|
fn WritingCaret::hide(self : WritingCaret, shown : ShownCaret) -> Unit {
  match shown.resting {
    Some(timer) => self.window.clear_timeout(timer)
    None => @browser_api.cancel_animation(self.blink)
  }
  self.element.set_attribute("hidden", "")
  self.presence = Hidden
}

///|
fn WritingCaret::release(self : WritingCaret) -> Unit {
  match self.presence {
    Hidden => ()
    Shown(shown) => self.hide(shown)
  }
}

///|
fn WritingCaret::place(
  self : WritingCaret,
  at : @writing_focus.Caret,
  motion~ : CaretMotion,
) -> Unit {
  self.element.set_attribute(
    "data-motion",
    match motion {
      Jump => "jump"
      Glide => "glide"
    },
  )
  self.element
  .get_style()
  .set_property("transform", "translate(\{at.x}px, \{at.y - at.scroll_top}px)")
}

///|
/// A newly shown caret appears in place, solid until the rest timer.
fn render_writing_caret(
  caret : WritingCaret,
  next : (@writing_focus.Caret, @writing_focus.CaretCause)?,
) -> Unit {
  match (caret.presence, next) {
    (Hidden, None) => ()
    (Shown(shown), None) => caret.hide(shown)
    (Hidden, Some((at, _))) => {
      caret.place(at, motion=Jump)
      caret.element.remove_attribute("hidden")
      let shown : ShownCaret = { at, resting: None, }
      caret.presence = Shown(shown)
      caret.hold(shown)
    }
    (Shown(shown), Some((at, cause))) =>
      match @writing_focus.caret_move(shown.at, at, cause) {
        Still => ()
        Scroll => {
          caret.place(at, motion=Jump)
          shown.at = at
        }
        Jump => {
          caret.place(at, motion=Jump)
          shown.at = at
          caret.hold(shown)
        }
        Glide => {
          caret.place(at, motion=Glide)
          shown.at = at
          caret.hold(shown)
        }
      }
  }
}
