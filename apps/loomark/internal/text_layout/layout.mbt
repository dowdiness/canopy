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
/// Document-owned measuring surface. It retains no textarea or feature
/// session: every measurement supplies the currently rendered textarea.
priv struct TextMirror {
  document : @dom.Document
  element : @dom.HTMLElement
  mut source : @text_lines.TextLines
  mut lines : Array[TextLineElement]
  retired_lines : Array[TextLineElement]
  mut signature : Array[String]
  mut metrics : TextMetrics?
  mut reflow_revision : Int
}

///|
/// Retain the mirror across feature disconnects: removing even unrelated DOM
/// nodes can end Chromium's native textarea undo transaction.
let document_mirror : Ref[TextMirror?] = Ref(None)

///|
fn TextMirror::in_document(document : @dom.Document) -> TextMirror {
  match document_mirror.val {
    Some(mirror) if physical_equal(mirror.document, document) => mirror
    _ => {
      let element = document.create_element("div").to_html_element().unwrap()
      element.set_attribute("class", "loomark-writing-measure")
      element.set_attribute("aria-hidden", "true")
      element.set_inert(true)
      let line = TextLineElement(document, "")
      element.append_child(line.element.as_node())
      document.get_body().unwrap().append_child(element.as_node())
      let mirror = {
        document,
        element,
        source: @text_lines.TextLines(""),
        lines: [line],
        retired_lines: [],
        signature: [],
        metrics: None,
        reflow_revision: 0,
      }
      // These listeners share the document's lifetime with the surface. No
      // feature disconnect can remove nodes during another feature's edit.
      document.add_event_listener("focusout", _ => {
        mirror.release_retired_lines()
      })
      @browser.document_fonts(document).add_event_listener("loadingdone", _ => {
        mirror.metrics = None
      })
      document_mirror.val = Some(mirror)
      mirror
    }
  }
}

///|
/// Font longhands are necessary: Chromium can serialize `font` as empty.
let text_layout_properties : FixedArray[String] = [
  "font-family", "font-size", "font-weight", "font-style", "font-stretch", "font-variant-caps",
  "font-variant-east-asian", "font-variant-numeric", "font-variant-position", "font-optical-sizing",
  "font-synthesis", "font-size-adjust", "line-height", "font-kerning", "font-feature-settings",
  "font-variation-settings", "font-variant-ligatures", "letter-spacing", "word-spacing",
  "text-indent", "text-transform", "text-align", "direction", "unicode-bidi", "white-space",
  "word-break", "overflow-wrap", "tab-size", "padding-top", "padding-right", "padding-bottom",
  "padding-left", "box-sizing", "width", "border-left-style", "border-left-width",
  "border-right-style", "border-right-width", "scrollbar-width", "scrollbar-gutter",
]

///|
/// Synchronize before querying geometry. Compare all copied style values, not
/// rounded clientWidth: fractional widths and text-spacing overrides reflow text.
fn TextMirror::measure(
  self : TextMirror,
  text_area : @dom.HTMLTextAreaElement,
  style : @dom.CSSStyleDeclaration,
  lang : String,
) -> MeasuredText {
  self.sync_text(text_area.get_value())
  let area = text_area.as_element()
  let overflow = match style.get_property_value("overflow-y") {
    "scroll" => "scroll"
    "auto" if area.get_scroll_height() > area.get_client_height() => "scroll"
    _ => "hidden"
  }
  let signature = text_layout_properties
    .iter()
    .map(property => style.get_property_value(property))
    .collect()
  signature.push(overflow)
  signature.push(lang)
  signature.push(style.get_property_value("scroll-padding-bottom"))
  let metrics = match self.metrics {
    Some(metrics) if signature == self.signature => metrics
    _ => {
      let copied = self.element.get_style()
      for index, property in text_layout_properties {
        copied.set_property(property, signature[index])
      }
      copied.set_property("overflow-y", overflow)
      self.element.set_attribute("lang", lang)
      self.signature = signature
      let pixels = property => {
        @browser.parse_css_number(style.get_property_value(property))
      }
      let metrics = {
        line_height: pixels("line-height"),
        padding_top: pixels("padding-top"),
        scroll_padding_bottom: pixels("scroll-padding-bottom"),
        padding_left: pixels("padding-left"),
        content_width: area.get_client_width() -
        pixels("padding-left") -
        pixels("padding-right"),
      }
      self.metrics = Some(metrics)
      self.reflow_revision += 1
      // After a style change, Chromium answers the first line query in the hidden
      // mirror from its previous layout, so spend that query here.
      self.lines[0].element.get_bounding_client_rect() |> ignore
      metrics
    }
  }
  { source: self.source, metrics, reflow_revision: self.reflow_revision, }
}

///|
fn TextMirror::sync_text(self : TextMirror, text : String) -> Unit {
  match self.source.replace_text(text) {
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
        let before = self.source.lines()[position]
        let after = replacement.inserted[index]
        if before != after {
          // Replace only the changed span so Chromium can reuse line shaping.
          let change = @text_lines.TextChange(before, after)
          @browser.replace_text_data(
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
        // Keep removed lines attached until blur to preserve native Undo.
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
    }
  }
}

///|
fn TextMirror::release_retired_lines(self : TextMirror) -> Unit {
  for line in self.retired_lines {
    self.element.remove_child(line.element.as_node())
  }
  self.retired_lines.clear()
}

///|
fn TextMirror::line_bounds(
  self : TextMirror,
  first : Int,
  last : Int,
) -> (Double, Double) {
  let origin = self.element.get_bounding_client_rect().get_top()
  (
    self.lines[first].element.get_bounding_client_rect().get_top() - origin,
    self.lines[last].element.get_bounding_client_rect().get_bottom() - origin,
  )
}

///|
fn TextMirror::glyph_rects(
  self : TextMirror,
  line : Int,
  start : Int,
  end : Int,
) -> Array[@dom.DOMRect] {
  @browser.text_range_rects(self.lines[line].text_node, start, end)
  .iter()
  .collect()
}

///|
fn TextMirror::line_rect(self : TextMirror, line : Int) -> @dom.DOMRect {
  self.lines[line].element.get_bounding_client_rect()
}

///|
fn TextMirror::top(self : TextMirror) -> Double {
  self.element.get_bounding_client_rect().get_top()
}

///|
/// Visual line containing a UTF-16 offset, relative to the textarea's inner
/// border edge. Empty logical lines have their own line box, including at EOF.
fn TextMirror::line_top(
  self : TextMirror,
  offset : Int,
  line_height : Double,
) -> Double {
  let position = self.source.position(offset)
  let line = self.line_rect(position.line)
  let text = self.source.lines()[position.line]
  if text.is_empty() {
    return line.get_top() - self.top()
  }
  let index = position.column.clamp(min=0, max=text.length() - 1)
  let middle = @browser.document_text_middle(
    self.document,
    self.lines[position.line].text_node,
    index,
    index + 1,
  )
  line_box_top(middle, line.get_top(), line_height) - self.top()
}
