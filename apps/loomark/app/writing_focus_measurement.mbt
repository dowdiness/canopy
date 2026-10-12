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
    context: {
      geometry: @writing_focus.Layout(rendered_lines),
      first_observation: true,
    },
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
  let bounds = focus.bounds(self.text_area.get_client_width())
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
fn TextLayout::measure_origin(
  self : TextLayout,
  context : TextLayoutContext,
  layout_sync : @writing_focus.LayoutSync,
) -> Double {
  self.sync_text(context.geometry)
  match layout_sync {
    Reuse => ()
    CopyStyles(width) => self.sync_layout(width)
  }
  self.element.get_bounding_client_rect().get_top()
}
