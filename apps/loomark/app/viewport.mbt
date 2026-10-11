///|
let caret_layout_properties : FixedArray[String] = [
  "font-family", "font-size", "font-weight", "font-style", "font-stretch", "font-variant",
  "line-height", "letter-spacing", "word-spacing", "tab-size", "text-indent", "text-transform",
  "text-align", "direction", "word-break", "padding-top", "padding-right", "padding-bottom",
  "padding-left",
]

///|
priv struct CaretLayout {
  element : @dom.HTMLElement
  before_caret : @dom.Node
  caret : @dom.Element
  after_caret : @dom.Node
  window : @dom.Window
}

///|
fn CaretLayout::CaretLayout(document : @dom.Document) -> CaretLayout {
  let element = document.create_element("div").to_html_element().unwrap()
  element.set_attribute("aria-hidden", "true")
  element.set_inert(true)
  let style = element.get_style()
  style.set_property("position", "fixed")
  style.set_property("visibility", "hidden")
  style.set_property("pointer-events", "none")
  style.set_property("top", "0")
  style.set_property("left", "0")
  style.set_property("box-sizing", "border-box")
  style.set_property("white-space", "pre-wrap")
  style.set_property("overflow-wrap", "break-word")
  let before_caret = document.create_text_node("").as_node()
  let caret = document.create_element("span")
  let after_caret = document.create_text_node("").as_node()
  caret.append_child(after_caret)
  element.append_child(before_caret)
  element.append_child(caret.as_node())
  {
    element,
    before_caret,
    caret,
    after_caret,
    window: document_window(document),
  }
}

///|
fn CaretLayout::measure(
  self : CaretLayout,
  area : @dom.HTMLTextAreaElement,
  measured : (Double, Double, Double, Double, Double, Double) -> Unit,
) -> Unit {
  guard area.get_client_height() > 0.0 else { return }
  let style = self.window.get_computed_style(area.as_element())
  let layout_style = self.element.get_style()
  for property in caret_layout_properties {
    layout_style.set_property(property, style.get_property_value(property))
  }
  layout_style.set_property("width", "\{area.get_client_width()}px")
  let endpoint = if area.get_selection_direction() == "backward" {
    area.get_selection_start()
  } else {
    area.get_selection_end()
  }
  let text = area.get_value()
  // Browser selection offsets are UTF-16 code units, including split surrogates.
  self.before_caret.set_node_value(
    @dom_js.Nullable::from_option(
      Some(text.unsafe_substring(start=0, end=endpoint)),
    ),
  )
  let remainder = text.unsafe_substring(start=endpoint, end=text.length())
  self.after_caret.set_node_value(
    @dom_js.Nullable::from_option(
      Some(if remainder.is_empty() { "." } else { remainder }),
    ),
  )
  let top = self.caret
    .get_client_rects()
    .item(0.0)
    .to_option()
    .unwrap()
    .get_top() -
    self.element.get_bounding_client_rect().get_top()
  measured(
    top,
    parse_css_number(style.get_property_value("line-height")),
    area.get_scroll_top(),
    area.get_client_height(),
    parse_css_number(style.get_property_value("padding-top")),
    parse_css_number(style.get_property_value("padding-bottom")),
  )
}

///|
/// Bind effects to a supplied node, not to a document-global selector.
fn observe_text_area_resize(
  area : @dom.HTMLTextAreaElement,
) -> (() -> Unit) raise @js.JsError {
  let apply_measurement = (
    top,
    line_height,
    scroll_top,
    height,
    padding_top,
    padding_bottom,
  ) => {
    let next = caret_scroll_top(
      top, line_height, scroll_top, height, padding_top, padding_bottom,
    )
    if next != scroll_top {
      area.set_scroll_top(next)
    }
  }
  @js.try_sync(() => {
    let document = element_document(area.as_element())
    let body = document.get_body().unwrap()
    let layout = CaretLayout(document)
    let observer = @dom.ResizeObserver::new((_, _) => {
      layout.measure(area, apply_measurement)
    })
    observer.observe(area.as_element())
    body.append_child(layout.element.as_node())
    @js.any(() => {
      observer.disconnect()
      body.remove_child(layout.element.as_node())
    })
  }).cast()
}

///|
priv suberror VisualViewportSubscription {
  FollowViewport
}

///|
/// Own scheduling and style writes for explicit browser handles.
fn visual_viewport_subscription(
  window : @dom.Window,
  viewport : @dom.VisualViewport,
  root : @dom.HTMLElement,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.visual-viewport",
    @sub.Scope::Local,
    VisualViewportSubscription::FollowViewport,
    (_, _) => {
      let style = root.get_style()
      let mut frame : Double? = None
      let mut top = 0.0
      let mut baseline_height = window.inner_height()
      let mut previous_outer_height = window_outer_height(window)
      let mut previous_width = window.inner_width()
      fn update_viewport(_ : Double) {
        frame = None
        let scale = visual_viewport_scale(viewport)
        guard scale > 0.0 else { return }
        let height = viewport_layout_height(viewport.get_height(), scale)
        let layout_height = window.inner_height()
        let outer_height = window_outer_height(window)
        let width = window.inner_width()
        baseline_height = viewport_baseline_height(
          baseline_height, previous_outer_height, previous_width, layout_height,
          outer_height, width,
        )
        previous_outer_height = outer_height
        previous_width = width
        top = viewport_layout_top(
          viewport.get_offset_top(),
          scale,
          top,
          layout_height,
          height,
        )
        style.set_property("--loomark-viewport-height", "\{height}px")
        style.set_property("--loomark-viewport-top", "\{top}px")
        if bottom_bar_obscured(height, layout_height, baseline_height) {
          root.set_attribute("data-loomark-bottom-obscured", "")
        } else {
          root.remove_attribute("data-loomark-bottom-obscured")
        }
      }
      fn schedule_update() {
        if frame is None {
          frame = Some(window.request_animation_frame(update_viewport))
        }
      }
      let listener : @dom.Listener = _ => schedule_update()
      viewport.add_event_listener("resize", listener)
      viewport.add_event_listener("scroll", listener)
      window.add_event_listener("resize", listener)
      frame = Some(window.request_animation_frame(update_viewport))
      Some({
        unload: _ => {
          viewport.remove_event_listener("resize", listener)
          viewport.remove_event_listener("scroll", listener)
          window.remove_event_listener("resize", listener)
          if frame is Some(frame) {
            window.cancel_animation_frame(frame)
          }
          style.remove_property("--loomark-viewport-height") |> ignore
          style.remove_property("--loomark-viewport-top") |> ignore
          root.remove_attribute("data-loomark-bottom-obscured")
        },
        update_tagger: _ => (),
      })
    },
  )
}
