// Test-only: construct a placeholder JsWebSocket on non-js targets.
// Pairs with test_ws_helper_js.mbt so wbtests can share a single
// `make_test_ws()` helper regardless of target.

///|
fn make_test_ws() -> JsWebSocket {
  JsWebSocket(0)
}
