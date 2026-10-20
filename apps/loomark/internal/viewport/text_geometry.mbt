///|
let mirrored_text_properties : FixedArray[String] = [
  "font-family", "font-size", "font-weight", "font-style", "font-stretch", "font-variant",
  "line-height", "letter-spacing", "word-spacing", "tab-size", "text-indent", "text-transform",
  "text-align", "direction", "word-break", "padding-top", "padding-right", "padding-bottom",
  "padding-left", "box-sizing", "width", "border-left-style", "border-left-width",
  "border-right-style", "border-right-width", "scrollbar-width", "scrollbar-gutter",
]

///|
/// A hidden element that wraps text the way the textarea does, so line
/// positions can be read from it.
priv struct TextMirror {
  document : @dom.Document
  element : @dom.HTMLElement
  text_node : @dom.Node
  mut text : String
}

///|
/// One mirror stays in the document once created: removing any node ends the
/// textarea's native typing undo group in Chromium. Keeping its text spares a
/// new layout on every scroll, and a closed shadow root keeps that copy out of
/// page queries.
let document_mirror : Ref[TextMirror?] = Ref(None)

///|
fn TextMirror::in_document(document : @dom.Document) -> TextMirror? {
  match document_mirror.val {
    Some(mirror) if physical_equal(mirror.document, document) &&
      mirror.element.get_is_connected() => Some(mirror)
    _ => {
      document_mirror.val = TextMirror::attach(document)
      document_mirror.val
    }
  }
}

///|
fn TextMirror::attach(document : @dom.Document) -> TextMirror? {
  guard document.get_body() is Some(body) else { return None }
  let host = document.create_element("div").to_html_element().unwrap()
  host.set_attribute("aria-hidden", "true")
  host.set_inert(true)
  let host_style = host.get_style()
  host_style.set_property("position", "fixed")
  host_style.set_property("visibility", "hidden")
  host_style.set_property("pointer-events", "none")
  host_style.set_property("top", "0")
  host_style.set_property("left", "0")
  let element = document.create_element("div").to_html_element().unwrap()
  let style = element.get_style()
  style.set_property("white-space", "pre-wrap")
  style.set_property("overflow-wrap", "break-word")
  let text_node = document.create_text_node("").as_node()
  element.append_child(text_node) |> ignore
  let shadow = @browser.attach_closed_shadow(host.as_element())
  shadow.append_child(element.as_node()) |> ignore
  body.append_child(host.as_node()) |> ignore
  Some({ document, element, text_node, text: "", })
}

///|
/// The mirror takes the textarea's own box rather than its rounded client
/// width: half a pixel of extra room keeps lines from wrapping, and the
/// difference accumulates through a long text.
fn TextMirror::lay_out_like(
  self : Self,
  area : @dom.HTMLTextAreaElement,
  style : @dom.CSSStyleDeclaration,
) -> Unit {
  let mirror_style = self.element.get_style()
  for property in mirrored_text_properties {
    mirror_style.set_property(property, style.get_property_value(property))
  }
  let element = area.as_element()
  let scrolls = match style.get_property_value("overflow-y") {
    "scroll" => true
    "auto" => element.get_scroll_height() > element.get_client_height()
    _ => false
  }
  mirror_style.set_property(
    "overflow-y",
    if scrolls {
      "scroll"
    } else {
      "hidden"
    },
  )
  // Line breaking follows the content language.
  let lang = element
    .closest("[lang]")
    .bind(owner => owner.get_attribute("lang"))
  if self.element.get_attribute("lang") != lang {
    match lang {
      Some(lang) => self.element.set_attribute("lang", lang)
      None => self.element.remove_attribute("lang")
    }
  }
  let text = area.get_value()
  if text != self.text {
    self.text = text
    self.text_node.set_node_value(@dom_js.Nullable::from_option(Some(text)))
  }
}

///|
/// Height of the middle of the character at `index` below the mirror's top.
fn TextMirror::glyph_middle(self : Self, index : Int) -> Double {
  @browser.document_text_middle(self.document, self.text_node, index, index + 1) -
  self.element.get_bounding_client_rect().get_top()
}

///|
/// A measurement stays current while the textarea scrolls; measure again after
/// its text, style, or width changes.
priv struct TextGeometry {
  area : @dom.HTMLTextAreaElement
  mirror : TextMirror
  line_height : Double
  padding_top : Double
  scroll_padding_bottom : Double
}

///|
/// `None` while the textarea is hidden.
fn TextGeometry::measure(area : @dom.HTMLTextAreaElement) -> TextGeometry? {
  guard area.get_client_height() > 0.0 else { return None }
  let document = @browser.element_document(area.as_element())
  guard TextMirror::in_document(document) is Some(mirror) else { return None }
  let style = @browser.document_window(document).get_computed_style(
    area.as_element(),
  )
  mirror.lay_out_like(area, style)
  let pixels = property => {
    @browser.parse_css_number(style.get_property_value(property))
  }
  Some({
    area,
    mirror,
    line_height: pixels("line-height"),
    padding_top: pixels("padding-top"),
    scroll_padding_bottom: pixels("scroll-padding-bottom"),
  })
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
/// Distance from the textarea's border edge to the line showing `offset` when
/// the textarea is scrolled to its top. Offsets are UTF-16 code units.
fn TextGeometry::unscrolled_line_top(self : Self, offset : Int) -> Double {
  match line_reference(self.mirror.text, offset) {
    Some((index, lines_below)) =>
      line_box_top(
        self.mirror.glyph_middle(index),
        self.padding_top,
        self.line_height,
      ) +
      lines_below.to_double() * self.line_height
    None => self.padding_top
  }
}

///|
extend TextGeometry with ReadingGeometry::{top_of}

///|
impl ReadingGeometry for TextGeometry with fn top_of(self, offset) {
  let area = self.area.as_element()
  area.get_bounding_client_rect().get_top() +
  area.get_client_top() +
  self.unscrolled_line_top(offset) -
  area.get_scroll_top()
}

///|
/// Empty lines show no text to keep in place, so the search moves past them.
impl ReadingGeometry for TextGeometry with fn offset_at(self, top) {
  let text = self.mirror.text
  let mut low = 0
  let mut high = text.length()
  while low < high {
    let middle = (low + high) / 2
    if self.top_of(middle) >= top {
      high = middle
    } else {
      low = middle + 1
    }
  }
  while low < text.length() && text.code_unit_at(low) == '\n' {
    low += 1
  }
  low
}

///|
impl ReadingGeometry for TextGeometry with fn line_height(self) {
  self.line_height
}

///|
/// The textarea's scroll padding keeps lines clear of the overlaid controls;
/// its larger bottom padding only lets the text scroll past its end.
impl ReadingGeometry for TextGeometry with fn readable(self) {
  let area = self.area.as_element()
  let top = area.get_bounding_client_rect().get_top() + area.get_client_top()
  (
    top + self.padding_top,
    top + area.get_client_height() - self.scroll_padding_bottom,
  )
}

///|
impl ReadingGeometry for TextGeometry with fn scroll_by(self, delta) {
  let area = self.area.as_element()
  area.set_scroll_top(area.get_scroll_top() + delta)
}
