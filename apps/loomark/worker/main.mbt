///|
extern "js" fn install_warren_worker_capability() -> Unit =
  #| () => {
  #|   self.addEventListener("message", event => {
  #|     const request = event.data;
  #|     if (
  #|       request?.kind !== "loomark-warren-capability-probe"
  #|       || request.token !== "loomark-warren-multi-entry"
  #|     ) return;
  #|     self.postMessage({
  #|       kind: "loomark-warren-capability-ready",
  #|       token: "loomark-warren-multi-entry",
  #|     });
  #|     self.close();
  #|   }, { once: true });
  #| }

///|
fn main {
  install_warren_worker_capability()
}
