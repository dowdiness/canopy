///|
/// Firefox does not scroll a textarea's `local` background with its text, so
/// its styles shift the dot grid by this scroll offset instead.
pub fn expose_scroll_top_to_styles(
  area : @dom.HTMLTextAreaElement,
) -> () -> Unit {
  let style = area.get_style()
  fn expose() {
    style.set_property("--loomark-scroll-top", "\{area.get_scroll_top()}px")
  }
  let listener : @dom.Listener = _ => expose()
  area.add_event_listener("scroll", listener)
  expose()
  () => area.remove_event_listener("scroll", listener)
}

///|
priv suberror VisualViewportSubscription {
  FollowViewport
}

///|
/// Own scheduling and style writes for explicit browser handles.
pub fn visual_viewport_subscription(
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
      let mut previous_outer_height = @browser.window_outer_height(window)
      let mut previous_width = window.inner_width()
      fn update_viewport(_ : Double) {
        frame = None
        let scale = @browser.visual_viewport_scale(viewport)
        guard scale > 0.0 else { return }
        let height = viewport_layout_height(viewport.get_height(), scale)
        let layout_height = window.inner_height()
        let outer_height = @browser.window_outer_height(window)
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
