///|
/// Observe one native Element (including SVG). Pass a typed DOM handle with
/// `@js.any(element)`. Notifications report content-box width and height in CSS
/// pixels, using native ResizeObserver delivery, including its initial report.
/// No synchronous callback, frame scheduling, or application policy is added.
///
/// Each call owns an independent observation. The returned function disconnects
/// it and is safe to call repeatedly. Invalid targets and unavailable browser
/// APIs raise `@js.JsError`; no observer is installed on failure.
pub fn observe(
  target : @js.Any,
  callback : (Double, Double) -> Unit,
) -> (() -> Unit) raise @js.JsError {
  @js.try_sync(() => @js.any(observe_native(target, callback))).cast()
}

///|
extern "js" fn observe_native(
  target : @js.Any,
  callback : (Double, Double) -> Unit,
) -> () -> Unit =
  #| (target, callback) => {
  #|   const observer = new ResizeObserver(entries => {
  #|     for (const entry of entries) {
  #|       callback(entry.contentRect.width, entry.contentRect.height);
  #|     }
  #|   });
  #|   observer.observe(target);
  #|   return () => observer.disconnect();
  #| }
