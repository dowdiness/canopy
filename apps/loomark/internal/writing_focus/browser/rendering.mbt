///|
priv struct OpacityAnimation {
  native : @dom.Animation
  timing : @writing_focus.FadeTiming
}

///|
priv enum ShadeContent {
  Hidden
  Visible(@writing_focus.Range, OpacityAnimation?)
}

///|
priv struct WritingShade {
  element : @dom.HTMLElement
  mut content : ShadeContent
}

///|
fn sample_writing_shade(
  window : @dom.Window,
  shade : WritingShade,
) -> (@writing_focus.Range, @writing_focus.OpacitySample)? raise {
  guard shade.content is Visible(range, animation) else { return None }
  let computed_opacity = window
    .get_computed_style(shade.element.as_element())
    .get_property_value("opacity")
  let opacity = @string.parse_double(computed_opacity.view())
  let sample : @writing_focus.OpacitySample = match animation {
    None => Still(opacity)
    Some({ native, timing, }) => {
      let playback_rate = @browser_api.animation_playback_rate(native)
      match @browser_api.animation_clock(native) {
        Pending(current_time_ms~) =>
          Animating(opacity, Pending(timing, current_time_ms~, playback_rate~))
        Running(start_time_ms~, current_time_ms~) =>
          Animating(
            opacity,
            Running(timing, start_time_ms~, current_time_ms~, playback_rate~),
          )
        Settled => Still(opacity)
      }
    }
  }
  Some((range, sample))
}

///|
fn clear_writing_shades(
  layer : @dom.HTMLElement,
  shades : ArrayView[WritingShade],
) -> Unit {
  for shade in shades {
    if shade.content is Visible(_, Some(animation)) {
      @browser_api.cancel_animation(animation.native)
    }
  }
  layer.set_inner_text("")
}

///|
fn position_writing_shade(
  element : @dom.HTMLElement,
  range : @writing_focus.Range,
  viewport_range : @writing_focus.Range,
) -> Unit {
  match @writing_focus.calculate_shade_placement(range, viewport_range) {
    Some(placement) => {
      set_style_if_changed(element, "top", "\{placement.top_in_viewport}px")
      set_style_if_changed(
        element,
        "--loomark-shade-top-in-content",
        "\{placement.top_in_content}px",
      )
      set_style_if_changed(element, "height", "\{placement.height}px")
    }
    None => {
      set_style_if_changed(element, "top", "0px")
      set_style_if_changed(element, "height", "0px")
    }
  }
}

///|
fn start_opacity_animation(
  element : @dom.HTMLElement,
  timing : @writing_focus.FadeTiming,
) -> OpacityAnimation {
  let native = @browser_api.animate_opacity(
    element,
    timing.from_opacity,
    timing.to_opacity,
    timing.duration_ms,
    timing.easing,
  )
  { native, timing, }
}

///|
fn apply_writing_fade(
  element : @dom.HTMLElement,
  fade : @writing_focus.Fade,
) -> OpacityAnimation? {
  match fade {
    SetOpacity(_) => None
    Start(timing) => Some(start_opacity_animation(element, timing))
    Continue(active) => {
      let animation = start_opacity_animation(element, active.timing())
      match active {
        Pending(_, current_time_ms~, playback_rate~) => {
          @browser_api.set_animation_playback_rate(
            animation.native,
            playback_rate,
          )
          if current_time_ms is Some(current_time) {
            @browser_api.set_animation_current_time(
              animation.native,
              current_time,
            )
          }
        }
        Running(_, start_time_ms~, playback_rate~, ..) => {
          @browser_api.set_animation_playback_rate(
            animation.native,
            playback_rate,
          )
          @browser_api.set_animation_start_time(animation.native, start_time_ms)
        }
      }
      Some(animation)
    }
  }
}

///|
fn render_writing_fades(
  document : @dom.Document,
  layer : @dom.HTMLElement,
  shades : Array[WritingShade],
  viewport_range : @writing_focus.Range,
  fades : ArrayView[(@writing_focus.Range, @writing_focus.Fade)],
) -> Unit {
  // Removing DOM nodes interrupts Chromium's native typing undo group.
  for index, (range, fade) in fades {
    let shade = match shades.get(index) {
      Some(shade) => shade
      None => {
        let element = document.create_element("div").to_html_element().unwrap()
        element.set_attribute("class", "loomark-writing-shade")
        let shade : WritingShade = { element, content: Hidden, }
        shades.push(shade)
        layer.append_child(element.as_node())
        shade
      }
    }
    match shade.content {
      Hidden => shade.element.remove_attribute("hidden")
      Visible(_, Some(animation)) =>
        @browser_api.cancel_animation(animation.native)
      Visible(_, None) => ()
    }
    set_style_if_changed(shade.element, "opacity", "\{fade.target_opacity()}")
    position_writing_shade(shade.element, range, viewport_range)
    shade.content = Visible(range, None)
  }
  for shade in shades[fades.length():] {
    match shade.content {
      Hidden => ()
      Visible(_, animation) => {
        if animation is Some(animation) {
          @browser_api.cancel_animation(animation.native)
        }
        shade.element.set_attribute("hidden", "")
        shade.content = Hidden
      }
    }
  }
  for index, (range, fade) in fades {
    let shade = shades[index]
    shade.content = Visible(range, apply_writing_fade(shade.element, fade))
  }
}
