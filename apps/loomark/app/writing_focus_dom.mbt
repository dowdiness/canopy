///|
extern "js" fn document_fonts(document : @dom.Document) -> @dom.EventTarget =
  #| document => document.fonts

///|
extern "js" fn document_timeline_time(
  document : @dom.Document,
) -> @dom_js.Nullable[Double] =
  #| document => document.timeline.currentTime

///|
extern "js" fn animate_opacity(
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
extern "js" fn cancel_opacity_animation(animation : @dom.Animation) -> Unit =
  #| animation => animation.cancel()

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
extern "js" fn animation_playback_rate(animation : @dom.Animation) -> Double =
  #| animation => animation.playbackRate

///|
extern "js" fn set_animation_start_time(
  animation : @dom.Animation,
  time : Double,
) -> Unit =
  #| (animation, time) => { animation.startTime = time; }

///|
extern "js" fn set_animation_current_time(
  animation : @dom.Animation,
  time : Double,
) -> Unit =
  #| (animation, time) => { animation.currentTime = time; }

///|
extern "js" fn set_animation_playback_rate(
  animation : @dom.Animation,
  rate : Double,
) -> Unit =
  #| (animation, rate) => { animation.playbackRate = rate; }
