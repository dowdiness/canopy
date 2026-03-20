// WebSocket client exports

///|
pub fn ws_on_open(handle : Int, ws : @editor.JsWebSocket) -> Unit {
  match editors.get(handle) {
    Some(ed) => ed.ws_on_open(ws)
    None => ()
  }
}

///|
pub fn ws_on_message(handle : Int, data : Bytes) -> Unit {
  match editors.get(handle) {
    Some(ed) => ed.ws_on_message(data)
    None => ()
  }
}

///|
pub fn ws_on_close(handle : Int) -> Unit {
  match editors.get(handle) {
    Some(ed) => ed.ws_on_close()
    None => ()
  }
}

///|
pub fn ws_broadcast_edit(handle : Int) -> Unit {
  match editors.get(handle) {
    Some(ed) => ed.ws_broadcast_edit()
    None => ()
  }
}

///|
pub fn ws_broadcast_cursor(handle : Int) -> Unit {
  match editors.get(handle) {
    Some(ed) => ed.ws_broadcast_cursor()
    None => ()
  }
}
