///|
/// A live browser VisualViewport handle. Values are read on demand; this package
/// does not resize elements, schedule frames, or impose a zoom policy.
#external
pub type VisualViewport

///|
/// The current window's visual viewport, or None outside a browser, in an
/// inactive document, or when the browser does not provide the API.
/// In an iframe, this describes that frame, not the top-level window.
pub fn current() -> VisualViewport? {
  let window = @js.global().get("window")
  guard !window.is_nullish() else { return None }
  let viewport = window.get("visualViewport")
  if viewport.is_nullish() {
    None
  } else {
    Some(viewport.cast())
  }
}

///|
/// Visible viewport height in CSS pixels.
pub extern "js" fn VisualViewport::height(self : VisualViewport) -> Double =
  #| viewport => viewport.height

///|
/// Offset from the layout viewport's top edge in CSS pixels.
pub extern "js" fn VisualViewport::offset_top(self : VisualViewport) -> Double =
  #| viewport => viewport.offsetTop

///|
/// Pinch-zoom scale relative to the initial containing block.
pub extern "js" fn VisualViewport::scale(self : VisualViewport) -> Double =
  #| viewport => viewport.scale

///|
/// Listen to native resize and scroll events. No initial callback is emitted;
/// read current geometry when installing if an initial update is needed.
/// Events are not throttled. The returned function removes both listeners and
/// is safe to call repeatedly. Each call owns an independent registration.
pub extern "js" fn VisualViewport::on_change(
  self : VisualViewport,
  callback : () -> Unit,
) -> () -> Unit =
  #| (viewport, callback) => {
  #|   const listener = () => callback();
  #|   viewport.addEventListener('resize', listener);
  #|   viewport.addEventListener('scroll', listener);
  #|   return () => {
  #|     viewport.removeEventListener('resize', listener);
  #|     viewport.removeEventListener('scroll', listener);
  #|   };
  #| }
