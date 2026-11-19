///|
/// The device clock, in milliseconds since the epoch.
pub extern "js" fn now() -> Double =
  #| () => Date.now()
