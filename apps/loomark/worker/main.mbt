///|
/// Worker entry for the opt-in preview transport.
#cfg(target="js")
extern "js" fn install_preview_worker(handler : (String) -> String) -> Unit =
  #|(handler => {
  #|  self.onmessage = event => {
  #|    try {
  #|      const request = typeof event.data === "string" ? event.data : JSON.stringify(event.data);
  #|      self.postMessage(handler(request));
  #|    } catch (error) {
  #|      self.postMessage(JSON.stringify({ type: "error", message: String(error) }));
  #|    }
  #|  };
  #|})

///|
fn main {
  let server = @preview.WorkerServer::WorkerServer()
  install_preview_worker(request => server.dispatch_text(request))
}
