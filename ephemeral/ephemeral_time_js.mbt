///|
/// Wall-clock milliseconds for expiry checks (JS target).
fn now_ms() -> UInt64 {
  js_now_ms().reinterpret_as_uint64()
}

///|
extern "js" fn js_now_ms() -> Int64 =
  #|() => {
  #|  return BigInt(Date.now());
  #|}
