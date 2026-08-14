///|
extern "js" fn install_projection_worker_transport(
  dispatch : (String) -> String,
) -> Unit =
  #| (dispatch) => {
  #|   const MAX_COUNT = 64;
  #|   const MAX_BYTES = 1048576;
  #|   const encoder = new TextEncoder();
  #|   const queue = [];
  #|   let queuedBytes = 0;
  #|   let queuedSourceEffectBytes = 0;
  #|   let highCount = 0;
  #|   let highBytes = 0;
  #|   let highSourceEffectBytes = 0;
  #|   const retentionControl = { payload: "positive-retention-control" };
  #|   let processing = false;
  #|   let disposed = false;
  #|   let seedCount = 0;
  #|   let advanceCount = 0;
  #|   let supersededCount = 0;
  #|
  #|   const terminal = (request, kind, detail) => self.postMessage({
  #|     kind: "loomark-projection-response",
  #|     epoch: request.epoch,
  #|     requestId: request.requestId,
  #|     payload: JSON.stringify({
  #|       schema_version: "1",
  #|       request_id: request.requestId,
  #|       kind: "error",
  #|       error: { kind, detail },
  #|     }),
  #|     transport: metrics(),
  #|   });
  #|
  #|   const metrics = () => ({
  #|     pendingCount: queue.length,
  #|     pendingEncodedBytes: queuedBytes,
  #|     pendingSourceEffectBytes: queuedSourceEffectBytes,
  #|     highWaterCount: highCount,
  #|     highWaterEncodedBytes: highBytes,
  #|     highWaterSourceEffectBytes: highSourceEffectBytes,
  #|     retainedSeedCount: 0,
  #|     retainedSeedBytes: 0,
  #|     seedCount,
  #|     advanceCount,
  #|     supersededCount,
  #|     retentionControlBytes: encoder.encode(retentionControl.payload).length,
  #|   });
  #|
  #|   const inspectPayload = payload => {
  #|     try {
  #|       const request = JSON.parse(payload);
  #|       const command = request?.command;
  #|       if (command?.kind === "seed") {
  #|         seedCount += 1;
  #|       } else if (command?.kind === "advance") {
  #|         advanceCount += 1;
  #|       }
  #|       return request;
  #|     } catch {
  #|       return null;
  #|     }
  #|   };
  #|
  #|
  #|   const run = async () => {
  #|     if (processing || disposed) return;
  #|     processing = true;
  #|     while (queue.length > 0 && !disposed) {
  #|       const item = queue.shift();
  #|       queuedBytes -= item.bytes;
  #|       queuedSourceEffectBytes -= item.sourceEffectBytes;
  #|       if (item.delayMs > 0) {
  #|         await new Promise(resolve => setTimeout(resolve, item.delayMs));
  #|       }
  #|       if (item.control === "terminate") {
  #|         terminal(item, "terminated", "Worker terminated during active work");
  #|         disposed = true;
  #|         self.close();
  #|         break;
  #|       }
  #|       const started = performance.now();
  #|       let payload = dispatch(item.payload);
  #|       if (item.control === "corrupt-stamp") {
  #|         const decoded = JSON.parse(payload);
  #|         decoded.stamp.causal_version += "-corrupt";
  #|         payload = JSON.stringify(decoded);
  #|       }
  #|       const elapsedMs = performance.now() - started;
  #|       if (item.control !== "drop-response") {
  #|         self.postMessage({
  #|           kind: "loomark-projection-response",
  #|           epoch: item.epoch,
  #|           requestId: item.requestId,
  #|           payload,
  #|           elapsedMs,
  #|           transport: metrics(),
  #|         });
  #|       }
  #|     }
  #|     processing = false;
  #|   };
  #|
  #|   self.addEventListener("message", event => {
  #|     const request = event.data;
  #|     if (request?.kind !== "loomark-projection-request") return;
  #|     if (
  #|       !Number.isSafeInteger(request.epoch)
  #|       || !Number.isSafeInteger(request.requestId)
  #|       || typeof request.payload !== "string"
  #|     ) {
  #|       terminal({ epoch: -1, requestId: -1 }, "decode-failed", "invalid Worker envelope");
  #|       return;
  #|     }
  #|     const decoded = inspectPayload(request.payload);
  #|     const bytes = encoder.encode(request.payload).length;
  #|     const sourceEffectBytes = (() => {
  #|       const command = decoded?.command;
  #|       if (command?.kind === "seed") {
  #|         return encoder.encode(command.source).length;
  #|       }
  #|       if (
  #|         command?.kind === "advance"
  #|         && command.source_effect?.kind === "replace-source"
  #|       ) {
  #|         return encoder.encode(command.source_effect.source).length;
  #|       }
  #|       return 0;
  #|     })();
  #|     const item = {
  #|       epoch: request.epoch,
  #|       requestId: request.requestId,
  #|       payload: request.payload,
  #|       delayMs: Math.max(0, request.delayMs ?? 0),
  #|       control: request.control ?? "dispatch",
  #|       bytes,
  #|       sourceEffectBytes,
  #|     };
  #|     if (bytes > MAX_BYTES || sourceEffectBytes > MAX_BYTES) {
  #|       terminal(item, "transport-overflow", "single payload exceeds byte limits");
  #|       return;
  #|     }
  #|     if (
  #|       queue.length + 1 > MAX_COUNT
  #|       || queuedBytes + bytes > MAX_BYTES
  #|       || queuedSourceEffectBytes + sourceEffectBytes > MAX_BYTES
  #|     ) {
  #|       for (const dropped of queue.splice(0)) {
  #|         supersededCount += 1;
  #|         terminal(dropped, "stale", "superseded by transport overflow");
  #|       }
  #|       queuedBytes = 0;
  #|       queuedSourceEffectBytes = 0;
  #|       supersededCount += 1;
  #|       terminal(item, "transport-overflow", "restart with latest authority Seed");
  #|       return;
  #|     }
  #|     queue.push(item);
  #|     queuedBytes += bytes;
  #|     queuedSourceEffectBytes += sourceEffectBytes;
  #|     highCount = Math.max(highCount, queue.length);
  #|     highBytes = Math.max(highBytes, queuedBytes);
  #|     highSourceEffectBytes = Math.max(
  #|       highSourceEffectBytes,
  #|       queuedSourceEffectBytes,
  #|     );
  #|     void run();
  #|   });
  #| }

///|
fn main {
  install_projection_worker_transport(@app.new_projection_worker_dispatcher())
}
