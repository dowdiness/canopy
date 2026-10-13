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
pub extern "js" fn animation_pending(animation : @dom.Animation) -> Bool =
  #| animation => animation.pending

///|
pub extern "js" fn animation_play_state(animation : @dom.Animation) -> String =
  #| animation => animation.playState

///|
pub extern "js" fn animation_start_time(
  animation : @dom.Animation,
) -> @dom_js.Nullable[Double] =
  #| animation => animation.startTime

///|
pub extern "js" fn animation_current_time(
  animation : @dom.Animation,
) -> @dom_js.Nullable[Double] =
  #| animation => animation.currentTime

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
