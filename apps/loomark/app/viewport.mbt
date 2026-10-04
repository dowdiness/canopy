///|
/// Measurement is an action: it reads live selection/style/layout and briefly
/// attaches a mirror. The callback receives only numeric geometry; it never
/// needs to look up a node. No text, selection, or focus is changed here.
extern "js" fn measure_caret(
  area : @dom.HTMLTextAreaElement,
  measured : (Double, Double, Double, Double, Double, Double) -> Unit,
) =
  #| (area, measured) => {
  #|   const document = area.ownerDocument;
  #|   if (area.clientHeight === 0) return;
  #|   const style = document.defaultView.getComputedStyle(area);
  #|   const mirror = document.createElement('div');
  #|   mirror.setAttribute('aria-hidden', 'true');
  #|   for (const property of [
  #|     'fontFamily', 'fontSize', 'fontWeight', 'fontStyle', 'fontStretch',
  #|     'fontVariant', 'lineHeight', 'letterSpacing', 'wordSpacing', 'tabSize',
  #|     'textIndent', 'textTransform', 'textAlign', 'direction', 'wordBreak',
  #|     'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft'
  #|   ]) mirror.style[property] = style[property];
  #|   Object.assign(mirror.style, {
  #|     position: 'fixed', visibility: 'hidden', pointerEvents: 'none',
  #|     top: '0', left: '0', width: `${area.clientWidth}px`,
  #|     boxSizing: 'border-box', whiteSpace: 'pre-wrap', overflowWrap: 'break-word'
  #|   });
  #|   const endpoint = area.selectionDirection === 'backward'
  #|     ? area.selectionStart : area.selectionEnd;
  #|   mirror.textContent = area.value.slice(0, endpoint);
  #|   const marker = document.createElement('span');
  #|   marker.textContent = area.value.slice(endpoint) || '.';
  #|   mirror.append(marker);
  #|   document.body.append(mirror);
  #|   try {
  #|     const top = marker.getClientRects()[0].top - mirror.getBoundingClientRect().top;
  #|     measured(
  #|       top, top + parseFloat(style.lineHeight),
  #|       area.scrollTop, area.clientHeight,
  #|       parseFloat(style.paddingTop), parseFloat(style.paddingBottom)
  #|     );
  #|   } finally {
  #|     mirror.remove();
  #|   }
  #| }

///|
/// Bind effects to a supplied node, not to a document-global selector.
fn observe_text_area_resize(
  area : @dom.HTMLTextAreaElement,
) -> (() -> Unit) raise @js.JsError {
  let apply_measurement = (
    top,
    bottom,
    scroll_top,
    height,
    padding_top,
    padding_bottom,
  ) => {
    let next = caret_scroll_top(
      top, bottom, scroll_top, height, padding_top, padding_bottom,
    )
    if next != scroll_top {
      area.set_scroll_top(next)
    }
  }
  @resize_observer.observe(@js.any(area), (_, _) => {
    measure_caret(area, apply_measurement)
  })
}

///|
priv suberror VisualViewportSubscription {
  FollowViewport
}

///|
/// Own scheduling and style writes for explicit browser handles.
fn visual_viewport_subscription(
  window : @dom.Window,
  viewport : @visual_viewport.VisualViewport,
  root : @dom.HTMLElement,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.visual-viewport",
    @sub.Scope::Local,
    VisualViewportSubscription::FollowViewport,
    (_, _) => {
      let style = root.get_style()
      let mut frame : Double? = None
      fn update_viewport(_ : Double) {
        frame = None
        // Freeze layout while pinching: zoom must not reflow or chase the page.
        guard follows_visual_viewport(viewport.scale()) else { return }
        let height = viewport.height()
        let top = viewport.offset_top()
        style.set_property("--loomark-viewport-height", "\{height}px")
        style.set_property("--loomark-viewport-top", "\{top}px")
        if bottom_bar_obscured(height, window.inner_height()) {
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
      let stop = viewport.on_change(schedule_update)
      let listener : @dom.Listener = _ => schedule_update()
      window.add_event_listener("resize", listener)
      frame = Some(window.request_animation_frame(update_viewport))
      Some({
        unload: _ => {
          stop()
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
