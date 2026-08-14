///|
extern "js" fn start_warren_worker_capability_smoke() -> Unit =
  #| () => {
  #|   const root = document.documentElement;
  #|   root.dataset.loomarkWarrenWorkerCapability = "pending";
  #|   const worker = new Worker(
  #|     new URL("./capability-worker.js", import.meta.url),
  #|     { type: "module", name: "loomark-warren-capability" },
  #|   );
  #|   const token = "loomark-warren-multi-entry";
  #|   worker.addEventListener("message", event => {
  #|     const response = event.data;
  #|     if (
  #|       response?.kind === "loomark-warren-capability-ready"
  #|       && response.token === token
  #|     ) {
  #|       worker.terminate();
  #|       root.dataset.loomarkWarrenWorkerCapability = "complete";
  #|     } else {
  #|       worker.terminate();
  #|       root.dataset.loomarkWarrenWorkerCapability = "invalid-response";
  #|     }
  #|   }, { once: true });
  #|   worker.addEventListener("error", () => {
  #|     worker.terminate();
  #|     root.dataset.loomarkWarrenWorkerCapability = "error";
  #|   }, { once: true });
  #|   worker.postMessage({
  #|     kind: "loomark-warren-capability-probe",
  #|     token,
  #|   });
  #| }

///|
/// Start the page-owned Loomark application exactly once.
fn main {
  ignore(@app.mount_standalone("app", ""))
  start_warren_worker_capability_smoke()
}
