///|
pub extern "js" fn animate_opacity(
  element : @dom.HTMLElement,
  from : Double,
  to : Double,
  duration_ms : Double,
  easing : String,
) -> @dom.Animation =
  #| (element, from, to, duration, easing) => element.animate(
  #|   [{ opacity: from }, { opacity: to }], { duration, easing }
  #| )

///|
pub extern "js" fn cancel_animation(animation : @dom.Animation) -> Unit =
  #| animation => animation.cancel()

///|
/// An animation's clock, parsed from its pending flag, play state and times.
pub enum AnimationClock {
  /// Waiting to start; the current time is unresolved until it is set.
  Pending(current_time_ms~ : Double?)
  Running(start_time_ms~ : Double, current_time_ms~ : Double)
  /// Idle, paused or finished: the animation no longer advances.
  Settled
}

///|
pub suberror InvalidAnimationClock {
  UnresolvedRunningTime
  UnknownPlayState(String)
}

///|
extern "js" fn animation_pending(animation : @dom.Animation) -> Bool =
  #| animation => animation.pending

///|
extern "js" fn animation_play_state(animation : @dom.Animation) -> String =
  #| animation => animation.playState

///|
extern "js" fn animation_start_time(
  animation : @dom.Animation,
) -> @dom_js.Nullable[Double] =
  #| animation => animation.startTime

///|
extern "js" fn animation_current_time(
  animation : @dom.Animation,
) -> @dom_js.Nullable[Double] =
  #| animation => animation.currentTime

///|
/// A running animation on the document timeline always has resolved times.
pub fn animation_clock(
  animation : @dom.Animation,
) -> AnimationClock raise InvalidAnimationClock {
  let current_time_ms = animation_current_time(animation).to_option()
  if animation_pending(animation) {
    return Pending(current_time_ms~)
  }
  match animation_play_state(animation) {
    "running" =>
      match (animation_start_time(animation).to_option(), current_time_ms) {
        (Some(start_time_ms), Some(current_time_ms)) =>
          Running(start_time_ms~, current_time_ms~)
        _ => raise UnresolvedRunningTime
      }
    "idle" | "paused" | "finished" => Settled
    state => raise UnknownPlayState(state)
  }
}

///|
pub extern "js" fn animation_playback_rate(
  animation : @dom.Animation,
) -> Double =
  #| animation => animation.playbackRate

///|
pub extern "js" fn set_animation_start_time(
  animation : @dom.Animation,
  time : Double,
) -> Unit =
  #| (animation, time) => { animation.startTime = time; }

///|
pub extern "js" fn set_animation_current_time(
  animation : @dom.Animation,
  time : Double,
) -> Unit =
  #| (animation, time) => { animation.currentTime = time; }

///|
pub extern "js" fn set_animation_playback_rate(
  animation : @dom.Animation,
  rate : Double,
) -> Unit =
  #| (animation, rate) => { animation.playbackRate = rate; }

///|
/// Plays a cancelled animation from its start.
pub extern "js" fn play_animation(animation : @dom.Animation) -> Unit =
  #| animation => animation.play()

///|
pub(all) struct OpacityKeyframe {
  offset : Double
  opacity : Double
  /// The easing from this keyframe to the next.
  easing : String
}

///|
extern "js" fn idle_animation(
  element : @dom.HTMLElement,
  keyframes : @js.Any,
  duration_ms : Double,
  iterations : Double,
) -> @dom.Animation =
  #| (element, keyframes, duration, iterations) => new Animation(
  #|   new KeyframeEffect(element, keyframes, { duration, iterations }),
  #|   element.ownerDocument.timeline
  #| )

///|
/// An opacity animation that waits, idle, until it is played.
pub fn idle_opacity_animation(
  element : @dom.HTMLElement,
  keyframes : ArrayView[OpacityKeyframe],
  duration_ms~ : Double,
  iterations~ : Double,
) -> @dom.Animation {
  let frames = @js.array()
  for keyframe in keyframes {
    let frame = @js.object()
    frame.set("offset", @js.any(keyframe.offset))
    frame.set("opacity", @js.any(keyframe.opacity))
    frame.set("easing", @js.any(keyframe.easing))
    frames.call("push", [frame]) |> ignore
  }
  idle_animation(element, frames, duration_ms, iterations)
}
