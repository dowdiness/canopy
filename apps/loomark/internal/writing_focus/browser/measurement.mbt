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
priv struct TextLayoutContext {
  mut geometry : @writing_focus.Layout
  mut first_observation : Bool
  mut mirror : MirrorStyle?
  mut caret : CaretMeasurement?
}

///|
/// The text area width the mirror's styles were copied at, and the width of
/// the dimming layer over its content box.
priv struct MirrorStyle {
  client_width : Double
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
fn TextLayoutContext::TextLayoutContext(
  geometry : @writing_focus.Layout,
) -> TextLayoutContext {
  { geometry, first_observation: true, mirror: None, caret: None, }
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
  mut lines : Array[TextLineElement]
  retired_lines : Array[TextLineElement]
  mut context : TextLayoutContext
  mut source_pending : Bool
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
    lines,
    retired_lines: [],
    context: TextLayoutContext(@writing_focus.Layout(rendered_lines)),
    source_pending: true,
  }
}

///|
fn TextLayout::locate_focus(
  self : TextLayout,
) -> (@writing_focus.Range, Bool) raise {
  // A notification may replace self.context during a DOM read. Read and commit
  // through the captured owner; the new context keeps its own empty cache.
  let context = self.context
  let context_changed = context.first_observation
  context.first_observation = false
  let source_pending = self.source_pending
  self.source_pending = false
  let text_changed = if source_pending {
    match context.geometry.replace_text(self.text_area.get_value()) {
      None => false
      Some(geometry) => {
        context.geometry = geometry
        true
      }
    }
  } else {
    false
  }
  let focus = match
    context.geometry.focus(
      self.text_area.get_selection_start(),
      self.text_area.get_selection_end(),
    ) {
    Document(range) => return (range, text_changed || context_changed)
    Lines(focus) => focus
  }
  let text_style = self.window.get_computed_style(self.text_area.as_element())
  // A `normal` line height parses as NaN, which never matches a measurement, so
  // every draw re-measures. Loomark sets px; only a reader's override reaches it.
  // If that slows typing, compare the computed string instead.
  let bounds = focus.bounds(
    width=self.text_area.get_client_width(),
    line_height=@browser_api.parse_css_number(
      text_style.get_property_value("line-height"),
    ),
  )
  let mut layout_synchronized = false
  let (range, geometry) = match bounds {
    Known(range) => return (range, text_changed)
    Lines(pending) => {
      layout_synchronized = pending.layout_sync is CopyStyles(_)
      let origin = self.measure_origin(context, pending.layout_sync)
      pending.between(
        self.lines[pending.lines.first].element
        .get_bounding_client_rect()
        .get_top() -
        origin,
        self.lines[pending.lines.last].element
        .get_bounding_client_rect()
        .get_bottom() -
        origin,
      )
    }
    LineStart(pending) => {
      layout_synchronized = pending.layout_sync is CopyStyles(_)
      let origin = self.measure_origin(context, pending.layout_sync)
      pending.at(
        self.lines[pending.line].element.get_bounding_client_rect().get_top() -
        origin,
      )
    }
    LineEnd(pending) => {
      layout_synchronized = pending.layout_sync is CopyStyles(_)
      let origin = self.measure_origin(context, pending.layout_sync)
      pending.at(
        self.lines[pending.line].element.get_bounding_client_rect().get_bottom() -
        origin,
      )
    }
  }
  context.geometry = geometry
  (range, text_changed || layout_synchronized)
}

///|
fn TextLayout::remove(self : TextLayout) -> Unit {
  self.body.remove_child(self.element.as_node())
}

///|
fn TextLayout::sync_text(
  self : TextLayout,
  geometry : @writing_focus.Layout,
) -> Unit {
  match geometry.edit_from(self.rendered_lines) {
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
        let before = self.rendered_lines.lines()[position]
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
      self.rendered_lines = replacement.source
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
  let padding_left = @browser_api.parse_css_number(
    style.get_property_value("padding-left"),
  )
  let padding_right = @browser_api.parse_css_number(
    style.get_property_value("padding-right"),
  )
  let (left, content_width) = @writing_focus.calculate_dimming_inline_bounds(
    self.text_area.get_offset_left(),
    width,
    padding_left,
    padding_right,
  )
  set_style_if_changed(
    self.dimming_layer,
    "top",
    "\{self.text_area.get_offset_top()}px",
  )
  set_style_if_changed(
    self.dimming_layer,
    "--loomark-text-line-height",
    style.get_property_value("line-height"),
  )
  set_style_if_changed(self.dimming_layer, "left", "\{left}px")
  set_style_if_changed(self.dimming_layer, "width", "\{content_width}px")
  set_style_if_changed(
    self.dimming_layer,
    "height",
    "\{self.text_area.get_client_height()}px",
  )
  // The caret's height follows the writing size.
  set_style_if_changed(
    self.dimming_layer,
    "font-size",
    style.get_property_value("font-size"),
  )
  { client_width: width, layer_width: content_width, }
}

///|
/// Copies the text area's styles at `width` unless this context already did.
fn TextLayout::style_mirror(
  self : TextLayout,
  context : TextLayoutContext,
  width : Double,
) -> MirrorStyle {
  match context.mirror {
    Some(mirror) if mirror.client_width == width => mirror
    _ => {
      let mirror = self.sync_layout(width)
      context.mirror = Some(mirror)
      mirror
    }
  }
}

///|
fn TextLayout::measure_origin(
  self : TextLayout,
  context : TextLayoutContext,
  layout_sync : @writing_focus.LayoutSync,
) -> Double {
  self.sync_text(context.geometry)
  match layout_sync {
    Reuse => ()
    // Measurements in this context no longer match the text area's width or
    // line height, so its styles are copied again.
    CopyStyles(width) => context.mirror = Some(self.sync_layout(width))
  }
  self.element.get_bounding_client_rect().get_top()
}

///|
/// Returns the caret's content position and what moved it since the previous
/// placement.
fn TextLayout::locate_caret(
  self : TextLayout,
  offset : Int,
) -> (@writing_focus.MeasuredCaret, @writing_focus.CaretCause) raise {
  let context = self.context
  let source = context.geometry.source()
  let position = source.position(offset)
  let history : @writing_focus.CaretHistory = match context.caret {
    None => Unmeasured
    Some(caret) if physical_equal(caret.source, source) =>
      SameText(caret.measured)
    Some(_) => OtherText
  }
  let cause = match @writing_focus.caret_measure(history, offset) {
    Cached(measured) => return (measured, Navigation)
    Measure(cause) => cause
  }
  self.sync_text(context.geometry)
  // Any styles copied for this context serve the caret; the text area keeps
  // its width until a resize replaces the context.
  let mirror = match context.mirror {
    Some(mirror) => mirror
    None => self.style_mirror(context, self.text_area.get_client_width())
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
  context.caret = Some({ source, measured, })
  (measured, cause)
}

///|
fn glyph_rects(text : @dom.Node, start : Int, end : Int) -> Array[@dom.DOMRect] {
  @browser_api.text_range_rects(text, start, end).iter().collect()
}
