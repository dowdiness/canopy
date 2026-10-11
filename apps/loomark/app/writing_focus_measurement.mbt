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
priv struct MeasuredLayout {
  width : Double
  start : (Int, Double)?
  end : (Int, Double)?
}

///|
priv struct TextLayout {
  document : @dom.Document
  window : @dom.Window
  body : @dom.HTMLElement
  text_area : @dom.HTMLTextAreaElement
  dimming_layer : @dom.HTMLElement
  element : @dom.HTMLElement
  mut rendered_lines : @writing_focus.TextLines
  mut pending_text : @writing_focus.LineReplacement?
  mut lines : Array[TextLineElement]
  retired_lines : Array[TextLineElement]
  mut measurements : MeasuredLayout?
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
  let rendered_lines = @writing_focus.TextLines("")
  let lines = rendered_lines
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
    rendered_lines,
    pending_text: None,
    lines,
    retired_lines: [],
    measurements: None,
  }
}

///|
fn TextLayout::locate_focus(
  self : TextLayout,
  refresh : GeometryRefresh,
) -> (@writing_focus.Range, Bool) raise {
  let text_changed = match refresh {
    Selection => false
    Source | Layout => self.set_source(self.text_area.get_value())
  }
  if refresh is Layout {
    self.measurements = None
  }
  let source_lines = self.source_lines()
  let focused_lines = match
    source_lines.focus_lines(
      self.text_area.get_selection_start(),
      self.text_area.get_selection_end(),
    ) {
    Ok(lines) => lines
    Err(error) => raise InvalidSelection(error)
  }
  let line_count = source_lines.lines().length()
  if focused_lines.first == 0 && focused_lines.last == line_count - 1 {
    return (
      @writing_focus.Range(0.0, @double.infinity),
      text_changed || refresh is Layout,
    )
  }
  let width = self.text_area.get_client_width()
  let (layout_changed, measured_start, measured_end) = match self.measurements {
    Some(layout) if layout.width == width => (false, layout.start, layout.end)
    _ => (true, None, None)
  }
  let unchanged_prefix_lines = match self.pending_text {
    None => line_count
    Some(replacement) => replacement.first
  }
  let (start_boundary, end_boundary) = @writing_focus.focus_boundaries(
    focused_lines, line_count, unchanged_prefix_lines, measured_start, measured_end,
  )
  let range = match (start_boundary, end_boundary) {
    (Position(start), Position(end)) => @writing_focus.Range(start, end)
    _ => {
      self.sync_text()
      if layout_changed {
        self.sync_layout(width)
      }
      let range = self.measure_range(start_boundary, end_boundary)
      // Document edges are derived from the source, not cached as line measurements.
      self.measurements = Some({
        width,
        start: if focused_lines.first == 0 {
          None
        } else {
          Some((focused_lines.first, range.start))
        },
        end: if focused_lines.last == line_count - 1 {
          None
        } else {
          Some((focused_lines.last, range.end))
        },
      })
      range
    }
  }
  (range, text_changed || layout_changed)
}

///|
fn TextLayout::remove(self : TextLayout) -> Unit {
  self.body.remove_child(self.element.as_node())
}

///|
fn TextLayout::source_lines(self : TextLayout) -> @writing_focus.TextLines {
  match self.pending_text {
    None => self.rendered_lines
    Some(replacement) => replacement.text_lines
  }
}

///|
fn TextLayout::set_source(self : TextLayout, text : String) -> Bool {
  if self.source_lines().text() == text {
    return false
  }
  // Keep one replacement relative to the DOM, including edits made while unmeasured.
  self.pending_text = self.rendered_lines.replace_text(text)
  true
}

///|
fn TextLayout::sync_text(self : TextLayout) -> Unit {
  match self.pending_text {
    None => ()
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
        if self.rendered_lines.lines()[position] != replacement.inserted[index] {
          self.lines[position].text_node.set_node_value(
            @dom_js.Nullable::from_option(Some(replacement.inserted[index])),
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
      self.rendered_lines = replacement.text_lines
      self.pending_text = None
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
fn set_style_if_changed(
  element : @dom.HTMLElement,
  property : String,
  value : String,
) -> Unit {
  let style = element.get_style()
  if style.get_property_value(property) != value {
    style.set_property(property, value)
  }
}

///|
let text_layout_properties : FixedArray[String] = [
  "font", "line-height", "font-kerning", "font-feature-settings", "font-variation-settings",
  "font-variant-ligatures", "letter-spacing", "word-spacing", "text-indent", "text-transform",
  "text-align", "direction", "unicode-bidi", "white-space", "word-break", "overflow-wrap",
  "tab-size", "padding-top", "padding-right", "padding-bottom", "padding-left",
]

///|
fn TextLayout::sync_layout(self : TextLayout, width : Double) -> Unit {
  let style = self.window.get_computed_style(self.text_area.as_element())
  let layout_style = self.element.get_style()
  for property in text_layout_properties {
    layout_style.set_property(property, style.get_property_value(property))
  }
  layout_style.set_property("width", "\{width}px")
  let padding_left = parse_css_number(style.get_property_value("padding-left"))
  let padding_right = parse_css_number(
    style.get_property_value("padding-right"),
  )
  set_style_if_changed(
    self.dimming_layer,
    "top",
    "\{self.text_area.get_offset_top()}px",
  )
  set_style_if_changed(
    self.dimming_layer,
    "left",
    "\{self.text_area.get_offset_left() + padding_left}px",
  )
  set_style_if_changed(
    self.dimming_layer,
    "width",
    "\{width - padding_left - padding_right}px",
  )
  set_style_if_changed(
    self.dimming_layer,
    "height",
    "\{self.text_area.get_client_height()}px",
  )
}

///|
fn TextLayout::measure_range(
  self : TextLayout,
  start : @writing_focus.Boundary,
  end : @writing_focus.Boundary,
) -> @writing_focus.Range raise @writing_focus.InvalidRange {
  let origin = self.element.get_bounding_client_rect().get_top()
  @writing_focus.Range(
    self.boundary_position(start, origin),
    self.boundary_position(end, origin),
  )
}

///|
fn TextLayout::boundary_position(
  self : TextLayout,
  boundary : @writing_focus.Boundary,
  origin : Double,
) -> Double {
  match boundary {
    Position(position) => position
    LineStart(line) =>
      self.lines[line].element.get_bounding_client_rect().get_top() - origin
    LineEnd(line) =>
      self.lines[line].element.get_bounding_client_rect().get_bottom() - origin
  }
}
