///|
/// Native no-op stub for JsWebSocket (non-JS targets).
/// Methods intentionally do nothing — real WebSocket is JS-only.
pub struct JsWebSocket(Int)

///|
/// No-op: native target cannot send WebSocket data.
pub fn JsWebSocket::send_bytes(self : JsWebSocket, _data : Bytes) -> Unit {
  ignore(self)
}

///|
/// No-op: native target has no WebSocket to close.
pub fn JsWebSocket::close(self : JsWebSocket) -> Unit {
  ignore(self)
}
