///|
#external
pub type JsWebSocket

///|
pub fn JsWebSocket::send_bytes(self : JsWebSocket, data : Bytes) -> Unit {
  js_ws_send(self, data)
}

///|
pub fn JsWebSocket::close(self : JsWebSocket) -> Unit {
  js_ws_close(self)
}

///|
extern "js" fn js_ws_send(ws : JsWebSocket, data : Bytes) -> Unit =
  #|(ws, data) => {
  #|  ws.send(data);
  #|}

///|
extern "js" fn js_ws_close(ws : JsWebSocket) -> Unit =
  #|(ws) => {
  #|  ws.close();
  #|}
