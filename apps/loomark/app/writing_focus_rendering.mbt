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
  let sample = match animation {
    None => @writing_focus.OpacitySample::Still(opacity)
    Some(animation) => {
      let current_time = animation_current_time(animation.native).to_option()
      let rate = animation_playback_rate(animation.native)
      if animation_pending(animation.native) {
        @writing_focus.OpacitySample::Animating(
          opacity,
          @writing_focus.ActiveFade::Pending(
            animation.timing,
            current_time_ms=current_time,
            playback_rate=rate,
          ),
        )
      } else {
        match animation_play_state(animation.native) {
          "running" => {
            let start_time = animation_start_time(animation.native).to_option()
            match (start_time, current_time) {
              (Some(start), Some(current)) =>
                @writing_focus.OpacitySample::Animating(
                  opacity,
                  @writing_focus.ActiveFade::Running(
                    animation.timing,
                    start_time_ms=start,
                    current_time_ms=current,
                    playback_rate=rate,
                  ),
                )
              _ => raise InvalidAnimationClock
            }
          }
          "idle" | "finished" | "paused" =>
            @writing_focus.OpacitySample::Still(opacity)
          state => raise UnsupportedAnimationState(state)
        }
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
      cancel_opacity_animation(animation.native)
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
  match @writing_focus.calculate_visible_range(range, viewport_range) {
    Some(visible) => {
      set_style_if_changed(element, "top", "\{visible.start}px")
      set_style_if_changed(
        element,
        "height",
        "\{visible.end - visible.start}px",
      )
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
  let native = animate_opacity(
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
          set_animation_playback_rate(animation.native, playback_rate)
          if current_time_ms is Some(current_time) {
            set_animation_current_time(animation.native, current_time)
          }
        }
        Running(_, start_time_ms~, playback_rate~, ..) => {
          set_animation_playback_rate(animation.native, playback_rate)
          set_animation_start_time(animation.native, start_time_ms)
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
      Visible(_, Some(animation)) => cancel_opacity_animation(animation.native)
      Visible(_, None) => ()
    }
    let target_opacity = match fade {
      SetOpacity(opacity) => opacity
      Start(timing) => timing.to_opacity
      Continue(active) => active.timing().to_opacity
    }
    set_style_if_changed(shade.element, "opacity", "\{target_opacity}")
    position_writing_shade(shade.element, range, viewport_range)
    shade.content = Visible(range, None)
  }
  for shade in shades[fades.length():] {
    match shade.content {
      Hidden => ()
      Visible(_, animation) => {
        if animation is Some(animation) {
          cancel_opacity_animation(animation.native)
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
