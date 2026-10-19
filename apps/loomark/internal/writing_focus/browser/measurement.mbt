///|
priv struct TextLineElement {
  element : @dom.HTMLElement
  text_node : @dom.Node
}

///|
fn TextLineElement::TextLineElement(
  document : @dom.Document,
  text : String,
) -> TextLineElement {
  let element = document.create_element("div").to_html_element().unwrap()
  let text_node = document.create_text_node(text).as_node()
  element.append_child(text_node)
  { element, text_node, }
}

///|
/// The text area width and line height the mirror's styles were copied at,
/// and the width of the dimming layer over its content box.
priv struct MirrorStyle {
  client_width : Double
  /// The computed line height; a reader's text-spacing override changes it
  /// without resizing the text area.
  line_height : String
  layer_width : Double
}

///|
priv suberror MirrorMeasurement {
  UnrenderedGlyph
}

///|
/// A caret measured against one source text; scrolling and repeated selection
/// events reuse it without reading layout.
priv struct CaretMeasurement {
  source : @writing_focus.TextLines
  measured : @writing_focus.MeasuredCaret
}

///|
/// The focused range measured for one source text and group of lines; caret
/// moves within the group and scrolling reuse it without reading layout.
priv struct FocusMeasurement {
  source : @writing_focus.TextLines
  lines : @writing_focus.LineRange
  range : @writing_focus.Range
}

///|
/// A hidden per-line copy of the text area. Each frame first brings its text
/// and styles up to date, then measures the focused lines and the caret.
priv struct TextLayout {
  document : @dom.Document
  window : @dom.Window
  body : @dom.HTMLElement
  text_area : @dom.HTMLTextAreaElement
  dimming_layer : @dom.HTMLElement
  element : @dom.HTMLElement
  mut source : @writing_focus.TextLines
  mut lines : Array[TextLineElement]
  retired_lines : Array[TextLineElement]
  /// `None` until styles are copied, and again after a reflow.
  mut mirror : MirrorStyle?
  /// Measurements hold for the copied styles they were read with.
  mut focus : FocusMeasurement?
  mut caret : CaretMeasurement?
}

///|
fn TextLayout::TextLayout(
  document : @dom.Document,
  window : @dom.Window,
  text_area : @dom.HTMLTextAreaElement,
  dimming_layer : @dom.HTMLElement,
) -> TextLayout {
  let body = document.get_body().unwrap()
  let element = document.create_element("div").to_html_element().unwrap()
  element.set_attribute("class", "loomark-writing-measure")
  element.set_attribute("aria-hidden", "true")
  element.set_inert(true)
  let source = @writing_focus.TextLines("")
  let lines = source
    .lines()
    .map(text => {
      let line = TextLineElement(document, text)
      element.append_child(line.element.as_node())
      line
    })
  body.append_child(element.as_node())
  {
    document,
    window,
    body,
    text_area,
    dimming_layer,
    element,
    source,
    lines,
    retired_lines: [],
    mirror: None,
    focus: None,
    caret: None,
  }
}

///|
/// Copies styles again on the next sync, after the text may have reflowed.
fn TextLayout::reset(self : TextLayout) -> Unit {
  self.mirror = None
}

///|
/// Brings the mirror up to date and reports whether its text or styles
/// changed, which moves every measured position.
fn TextLayout::sync(self : TextLayout) -> (MirrorStyle, Bool) {
  let text_changed = self.sync_text()
  let width = self.text_area.get_client_width()
  let line_height = self.window
    .get_computed_style(self.text_area.as_element())
    .get_property_value("line-height")
  match self.mirror {
    Some(mirror) if mirror.client_width == width &&
      mirror.line_height == line_height => (mirror, text_changed)
    _ => {
      let mirror = self.sync_layout(width)
      self.mirror = Some(mirror)
      self.focus = None
      self.caret = None
      (mirror, true)
    }
  }
}

///|
fn TextLayout::locate_focus(self : TextLayout) -> @writing_focus.Range raise {
  let source = self.source
  let lines = source.focus_lines(
    self.text_area.get_selection_start(),
    self.text_area.get_selection_end(),
  )
  match self.focus {
    Some(focus) if physical_equal(focus.source, source) &&
      focus.lines.first == lines.first &&
      focus.lines.last == lines.last => focus.range
    _ => {
      let origin = self.element.get_bounding_client_rect().get_top()
      let range = source.focus_range(
        lines,
        top=self.lines[lines.first].element.get_bounding_client_rect().get_top() -
          origin,
        bottom=self.lines[lines.last].element
          .get_bounding_client_rect()
          .get_bottom() -
          origin,
      )
      self.focus = Some({ source, lines, range, })
      range
    }
  }
}

///|
fn TextLayout::remove(self : TextLayout) -> Unit {
  self.body.remove_child(self.element.as_node())
}

///|
fn TextLayout::sync_text(self : TextLayout) -> Bool {
  match self.source.replace_text(self.text_area.get_value()) {
    None => false
    Some(replacement) => {
      let document = self.document
      let inserted_count = replacement.inserted.length()
      let retained_count = if replacement.removed < inserted_count {
        replacement.removed
      } else {
        inserted_count
      }
      for index in 0..<retained_count {
        let position = replacement.first + index
        let before = self.source.lines()[position]
        let after = replacement.inserted[index]
        if before != after {
          // Replacing only the changed span lets Chromium reuse the line's
          // shaping; replacing the whole value reshapes every character.
          let change = @writing_focus.TextChange(before, after)
          @browser_api.replace_text_data(
            self.lines[position].text_node,
            change.start,
            change.old_end - change.start,
            after.unsafe_substring(start=change.start, end=change.new_end),
          )
        }
      }
      let additions = replacement.inserted[retained_count:].map(text => {
        TextLineElement(document, text)
      })
      if inserted_count > replacement.removed {
        let fragment = document.create_document_fragment()
        for line in additions {
          fragment.append_child(line.element.as_node())
        }
        let following = self.lines
          .get(replacement.first + replacement.removed)
          .map(line => line.element.as_node())
        self.element
        .as_node()
        .insert_before(
          fragment.to_node(),
          @dom_js.Nullable::from_option(following),
        )
      } else {
        // Keep these nodes attached until blur to preserve the textarea's native Undo.
        for index in inserted_count..<replacement.removed {
          let line = self.lines[replacement.first + index]
          line.element.set_attribute("hidden", "")
          line.text_node.set_node_value(@dom_js.Nullable::from_option(Some("")))
          self.retired_lines.push(line)
        }
      }
      if inserted_count != replacement.removed {
        let previous = self.lines
        self.lines = Array::makei(
          previous.length() - replacement.removed + inserted_count,
          index => {
            if index < replacement.first + retained_count {
              previous[index]
            } else if index < replacement.first + inserted_count {
              additions[index - replacement.first - retained_count]
            } else {
              previous[index - inserted_count + replacement.removed]
            }
          },
        )
      }
      self.source = replacement.source
      true
    }
  }
}

///|
fn TextLayout::release_retired_lines(self : TextLayout) -> Unit {
  for line in self.retired_lines {
    self.element.remove_child(line.element.as_node())
  }
  self.retired_lines.clear()
}

///|
/// Font longhands, not the `font` shorthand: Chromium serializes the computed
/// shorthand as "" when a longhand such as font-kerning has no shorthand form,
/// which left the mirror in the page font and misplaced every wrapped line.
let text_layout_properties : FixedArray[String] = [
  "font-family", "font-size", "font-weight", "font-style", "font-stretch", "font-variant-caps",
  "font-variant-east-asian", "font-variant-numeric", "font-variant-position", "font-optical-sizing",
  "font-synthesis", "font-size-adjust", "line-height", "font-kerning", "font-feature-settings",
  "font-variation-settings", "font-variant-ligatures", "letter-spacing", "word-spacing",
  "text-indent", "text-transform", "text-align", "direction", "unicode-bidi", "white-space",
  "word-break", "overflow-wrap", "tab-size", "padding-top", "padding-right", "padding-bottom",
  "padding-left",
]

///|
fn TextLayout::sync_layout(self : TextLayout, width : Double) -> MirrorStyle {
  let style = self.window.get_computed_style(self.text_area.as_element())
  let layout_style = self.element.get_style()
  for property in text_layout_properties {
    layout_style.set_property(property, style.get_property_value(property))
  }
  layout_style.set_property("width", "\{width}px")
  let (left, content_width) = @writing_focus.calculate_dimming_inline_bounds(
    self.text_area.get_offset_left(),
    width,
    @browser_api.parse_css_number(style.get_property_value("padding-left")),
    @browser_api.parse_css_number(style.get_property_value("padding-right")),
  )
  let line_height = style.get_property_value("line-height")
  let layer_style = self.dimming_layer.get_style()
  layer_style.set_property("--loomark-text-line-height", line_height)
  layer_style.set_property("left", "\{left}px")
  layer_style.set_property("width", "\{content_width}px")
  // After a style change, Chromium answers the first line query in the hidden
  // mirror from its previous layout, so spend that query here.
  self.lines[0].element.get_bounding_client_rect() |> ignore
  { client_width: width, line_height, layer_width: content_width, }
}

///|
/// Returns the caret's content position and what moved it since the previous
/// placement.
fn TextLayout::locate_caret(
  self : TextLayout,
  mirror : MirrorStyle,
  offset : Int,
) -> (@writing_focus.MeasuredCaret, @writing_focus.CaretCause) raise {
  let source = self.source
  let position = source.position(offset)
  let history : @writing_focus.CaretHistory = match self.caret {
    None => Unmeasured
    Some(caret) if physical_equal(caret.source, source) =>
      SameText(caret.measured)
    Some(_) => OtherText
  }
  let cause = match @writing_focus.caret_measure(history, offset) {
    Cached(measured) => return (measured, Navigation)
    Measure(cause) => cause
  }
  let line = self.lines[position.line]
  let (x, y) = match
    @writing_focus.caret_glyph(source.lines()[position.line], position.column) {
    EmptyLine => {
      let box = line.element.get_bounding_client_rect()
      (box.get_left(), box.get_top() + box.get_height() / 2)
    }
    // A rendered glyph always has a box; a wrapped one has one per line.
    Before(start~, end~) => {
      guard glyph_rects(line.text_node, start, end) is [glyph, ..] else {
        raise UnrenderedGlyph
      }
      (glyph.get_left(), glyph.get_top() + glyph.get_height() / 2)
    }
    After(start~, end~) => {
      guard glyph_rects(line.text_node, start, end) is [.., glyph] else {
        raise UnrenderedGlyph
      }
      (glyph.get_right(), glyph.get_top() + glyph.get_height() / 2)
    }
  }
  let measured : @writing_focus.MeasuredCaret = {
    offset,
    x: @writing_focus.drawn_caret_x(
      x - line.element.get_bounding_client_rect().get_left(),
      layer_width=mirror.layer_width,
      half_width=CARET_WIDTH / 2.0,
    ),
    y: y - self.element.get_bounding_client_rect().get_top(),
  }
  self.caret = Some({ source, measured, })
  (measured, cause)
}

///|
fn glyph_rects(text : @dom.Node, start : Int, end : Int) -> Array[@dom.DOMRect] {
  @browser_api.text_range_rects(text, start, end).iter().collect()
}
