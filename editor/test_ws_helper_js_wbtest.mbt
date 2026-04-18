// Test-only: manufacture a placeholder JsWebSocket on the js target.
// `JsWebSocket` is a `#external` opaque type on js (a real JS WebSocket
// handle at runtime), so MoonBit source cannot construct one directly.
// Tests don't need a real socket — they just need a value whose
// `send` / `close` methods are callable no-ops.

///|
fn make_test_ws() -> JsWebSocket {
  js_make_fake_ws()
}

///|
extern "js" fn js_make_fake_ws() -> JsWebSocket =
  #|() => ({ send: () => {}, close: () => {} })
