///|
const DIMMING_DURATION_MS : Double = 220.0

///|
const REVEAL_DURATION_MS : Double = 160.0

///|
const DIMMING_EASING : String = "cubic-bezier(0.215, 0.61, 0.355, 1)"

///|
const REVEAL_EASING : String = "cubic-bezier(0.23, 1, 0.32, 1)"

///|
pub(all) struct FadeTiming {
  from_opacity : Double
  to_opacity : Double
  duration_ms : Double
  easing : String
}

///|
pub(all) enum ActiveFade {
  Pending(FadeTiming, current_time_ms~ : Double?, playback_rate~ : Double)
  Running(
    FadeTiming,
    start_time_ms~ : Double,
    current_time_ms~ : Double,
    playback_rate~ : Double
  )
}

///|
pub enum Fade {
  Continue(ActiveFade)
  Start(FadeTiming)
  SetOpacity(Double)
}

///|
pub fn ActiveFade::timing(self : ActiveFade) -> FadeTiming {
  match self {
    Pending(timing, ..) | Running(timing, ..) => timing
  }
}

///|
fn ActiveFade::elapsed_ms(
  self : ActiveFade,
  timeline_time_ms : Double?,
) -> Double? {
  match self {
    Pending(_, current_time_ms~, ..) => current_time_ms
    Running(_, start_time_ms~, current_time_ms~, playback_rate~) =>
      Some(
        match timeline_time_ms {
          Some(now) => (now - start_time_ms) * playback_rate
          None => current_time_ms
        },
      )
  }
}

///|
pub fn calculate_fade(
  current_opacity : Double,
  target_opacity : Double,
  previous : ActiveFade?,
  timeline_time_ms : Double?,
  animate~ : Bool,
) -> Fade {
  guard animate else { return SetOpacity(target_opacity) }
  match previous {
    Some(active) if active.timing().to_opacity == target_opacity =>
      match active.elapsed_ms(timeline_time_ms) {
        Some(elapsed) if elapsed >= active.timing().duration_ms =>
          SetOpacity(target_opacity)
        _ => Continue(active)
      }
    _ if current_opacity == target_opacity => SetOpacity(target_opacity)
    _ => {
      let dimming = target_opacity > current_opacity
      Start({
        from_opacity: current_opacity,
        to_opacity: target_opacity,
        duration_ms: if dimming {
          DIMMING_DURATION_MS
        } else {
          REVEAL_DURATION_MS
        },
        easing: if dimming {
          DIMMING_EASING
        } else {
          REVEAL_EASING
        },
      })
    }
  }
}
