///|
let caret_mirror_properties : FixedArray[String] = [
  "font-family", "font-size", "font-weight", "font-style", "font-stretch", "font-variant",
  "line-height", "letter-spacing", "word-spacing", "tab-size", "text-indent", "text-transform",
  "text-align", "direction", "word-break", "padding-top", "padding-right", "padding-bottom",
  "padding-left",
]

///|
/// Measurement is an action. Mirror lifetime and typed DOM calls stay in
/// MoonBit; the callback receives numeric geometry, never a live node.
fn measure_caret(
  area : @dom.HTMLTextAreaElement,
  measured : (Double, Double, Double, Double, Double, Double) -> Unit,
) -> Unit {
  guard area.get_client_height() > 0.0 else { return }
  let document = element_document(area.as_element())
  guard document.get_body() is Some(body) else { return }
  let style = document_window(document).get_computed_style(area.as_element())
  let mirror = document.create_element("div").to_html_element().unwrap()
  mirror.set_attribute("aria-hidden", "true")
  let mirror_style = mirror.get_style()
  for property in caret_mirror_properties {
    mirror_style.set_property(property, style.get_property_value(property))
  }
  mirror_style.set_property("position", "fixed")
  mirror_style.set_property("visibility", "hidden")
  mirror_style.set_property("pointer-events", "none")
  mirror_style.set_property("top", "0")
  mirror_style.set_property("left", "0")
  mirror_style.set_property("width", "\{area.get_client_width()}px")
  mirror_style.set_property("box-sizing", "border-box")
  mirror_style.set_property("white-space", "pre-wrap")
  mirror_style.set_property("overflow-wrap", "break-word")
  let endpoint = if area.get_selection_direction() == "backward" {
    area.get_selection_start()
  } else {
    area.get_selection_end()
  }
  let text = area.get_value()
  // Browser selection offsets are UTF-16 code units, including split surrogates.
  mirror.append_child(
    document
    .create_text_node(text.unsafe_substring(start=0, end=endpoint))
    .as_node(),
  )
  let marker = document.create_element("span")
  let remainder = text.unsafe_substring(start=endpoint, end=text.length())
  marker.append_child(
    document
    .create_text_node(if remainder.is_empty() { "." } else { remainder })
    .as_node(),
  )
  mirror.append_child(marker.as_node())
  body.append_child(mirror.as_node())
  defer body.remove_child(mirror.as_node())
  let top = marker.get_client_rects().item(0.0).to_option().unwrap().get_top() -
    mirror.get_bounding_client_rect().get_top()
  measured(
    top,
    css_pixels(style, "line-height"),
    area.get_scroll_top(),
    area.get_client_height(),
    css_pixels(style, "padding-top"),
    css_pixels(style, "padding-bottom"),
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
    let observer = @dom.ResizeObserver::new((_, _) => {
      measure_caret(area, apply_measurement)
    })
    observer.observe(area.as_element())
    @js.any(() => observer.disconnect())
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
