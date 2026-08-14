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
extern "js" fn start_projection_worker_gate(
  inProcessDispatch : (String) -> String,
) -> Unit =
  #| (inProcessDispatch) => {
  #|   const params = new URLSearchParams(location.search);
  #|   if (params.get("projection-worker-gate") !== "1") return;
  #|   const root = document.documentElement;
  #|   root.dataset.loomarkProjectionWorkerGate = "pending";
  #|   let currentEpoch = 1;
  #|   let nextRequestId = 1;
  #|   let staleRejected = false;
  #|
  #|   const request = (command, requestId = nextRequestId++) => JSON.stringify({
  #|     schema_version: "1",
  #|     request_id: requestId,
  #|     command,
  #|   });
  #|   const seed = (agentId, source, generation) => ({
  #|     kind: "seed", agent_id: agentId, source, generation,
  #|   });
  #|   const advance = source => ({
  #|     kind: "advance",
  #|     source_effect: { kind: "replace-source", source },
  #|   });
  #|   const errorPayload = (requestId, kind, detail) => JSON.stringify({
  #|     schema_version: "1",
  #|     request_id: requestId,
  #|     kind: "error",
  #|     error: { kind, detail },
  #|   });
  #|   const sameStamp = (left, right) => (
  #|     left?.generation === right?.generation
  #|     && left?.sequence === right?.sequence
  #|     && left?.source_revision === right?.source_revision
  #|     && left?.causal_version === right?.causal_version
  #|     && left?.block_intent === right?.block_intent
  #|   );
  #|
  #|   const createClient = epoch => {
  #|     const worker = new Worker(
  #|       new URL("./projection-worker.js", import.meta.url),
  #|       { type: "module", name: `loomark-projection-${epoch}` },
  #|     );
  #|     const pending = new Map();
  #|     worker.addEventListener("message", event => {
  #|       const response = event.data;
  #|       if (response?.kind !== "loomark-projection-response") return;
  #|       const entry = pending.get(response.requestId);
  #|       if (!entry) return;
  #|       pending.delete(response.requestId);
  #|       clearTimeout(entry.timer);
  #|       let stampMismatch = false;
  #|       if (entry.expectedStamp) {
  #|         try {
  #|           stampMismatch = !sameStamp(
  #|             JSON.parse(response.payload).stamp,
  #|             entry.expectedStamp,
  #|           );
  #|         } catch {
  #|           stampMismatch = true;
  #|         }
  #|       }
  #|       if (response.epoch !== currentEpoch || stampMismatch) {
  #|         staleRejected = true;
  #|         entry.resolve({
  #|           ...response,
  #|           payload: errorPayload(response.requestId, "stale", "Worker epoch/stamp mismatch"),
  #|         });
  #|       } else {
  #|         entry.resolve(response);
  #|       }
  #|     });
  #|     worker.addEventListener("error", event => {
  #|       for (const [requestId, entry] of pending) {
  #|         clearTimeout(entry.timer);
  #|         entry.resolve({
  #|           epoch,
  #|           requestId,
  #|           payload: errorPayload(requestId, "terminated", event.message),
  #|         });
  #|       }
  #|       pending.clear();
  #|     });
  #|     return {
  #|       epoch,
  #|       worker,
  #|       send(payload, options = {}) {
  #|         let parsedRequestId = -1;
  #|         try { parsedRequestId = JSON.parse(payload).request_id; } catch {}
  #|         const requestId = Number.isSafeInteger(options.requestId)
  #|           ? options.requestId
  #|           : parsedRequestId;
  #|         return new Promise(resolve => {
  #|           const timer = setTimeout(() => {
  #|             pending.delete(requestId);
  #|             resolve({
  #|               epoch,
  #|               requestId,
  #|               payload: errorPayload(requestId, "timeout", "Worker response timeout"),
  #|             });
  #|           }, options.timeoutMs ?? 5000);
  #|           pending.set(requestId, {
  #|             resolve,
  #|             timer,
  #|             expectedStamp: options.expectedStamp,
  #|           });
  #|           worker.postMessage({
  #|             kind: "loomark-projection-request",
  #|             epoch,
  #|             requestId,
  #|             payload,
  #|             delayMs: options.delayMs ?? 0,
  #|             control: options.control ?? "dispatch",
  #|           });
  #|         });
  #|       },
  #|       terminate() {
  #|         worker.terminate();
  #|         for (const [requestId, entry] of pending) {
  #|           clearTimeout(entry.timer);
  #|           entry.resolve({
  #|             epoch,
  #|             requestId,
  #|             payload: errorPayload(requestId, "terminated", "Worker terminated"),
  #|           });
  #|         }
  #|         pending.clear();
  #|       },
  #|     };
  #|   };
  #|
  #|   const run = async () => {
  #|     let maxLongTaskMs = 0;
  #|     const phaseStarts = [{ name: "startup", start: performance.now() }];
  #|     const setGatePhase = name => {
  #|       phaseStarts.push({ name, start: performance.now() });
  #|     };
  #|     let maxLongTaskPhase = "none";
  #|     let inProcessMaxSliceMs = 0;
  #|     const longTaskByPhase = {};
  #|     let longTaskObserver = null;
  #|     try {
  #|       longTaskObserver = new PerformanceObserver(list => {
  #|         for (const entry of list.getEntries()) {
  #|           let entryPhase = phaseStarts[0].name;
  #|           for (const phase of phaseStarts) {
  #|             if (phase.start > entry.startTime) break;
  #|             entryPhase = phase.name;
  #|           }
  #|           longTaskByPhase[entryPhase] = Math.max(
  #|             longTaskByPhase[entryPhase] ?? 0,
  #|             entry.duration,
  #|           );
  #|           if (entry.duration > maxLongTaskMs) {
  #|             maxLongTaskMs = entry.duration;
  #|             maxLongTaskPhase = entryPhase;
  #|           }
  #|         }
  #|       });
  #|       longTaskObserver.observe({ type: "longtask" });
  #|     } catch {}
  #|     const corpus = [
  #|       ["unicode", "# 猫 🐈\n\nParagraph *強い* text.\n"],
  #|       ["recovery", "# Broken\n\n[link](\n\n```moonbit\nlet x = 1\n"],
  #|       ["containers", "> quote\n\n- first\n- second\n"],
  #|     ];
  #|     await new Promise(resolve => setTimeout(resolve, 0));
  #|     const startupFailure = await new Promise(resolve => {
  #|       const unavailable = new Worker(
  #|         new URL("./missing-projection-worker.js", import.meta.url),
  #|         { type: "module", name: "loomark-projection-unavailable" },
  #|       );
  #|       const timer = setTimeout(() => {
  #|         unavailable.terminate();
  #|         resolve("timeout");
  #|       }, 2000);
  #|       unavailable.addEventListener("error", () => {
  #|         clearTimeout(timer);
  #|         unavailable.terminate();
  #|         resolve("unavailable");
  #|       }, { once: true });
  #|     });
  #|     let parity = true;
  #|     let client = createClient(currentEpoch);
  #|     let generation = 7;
  #|     setGatePhase("parity");
  #|     await new Promise(resolve => setTimeout(resolve, 0));
  #|     const firstSeed = request(seed("worker-parity", corpus[0][1], generation));
  #|     let inProcessStarted = performance.now();
  #|     const inProcessSeed = JSON.parse(inProcessDispatch(firstSeed));
  #|     inProcessMaxSliceMs = Math.max(
  #|       inProcessMaxSliceMs,
  #|       performance.now() - inProcessStarted,
  #|     );
  #|     const workerSeed = JSON.parse((await client.send(firstSeed, {
  #|       expectedStamp: inProcessSeed.stamp,
  #|     })).payload);
  #|     parity &&= JSON.stringify(workerSeed.observables)
  #|       === JSON.stringify(inProcessSeed.observables);
  #|     for (const [, source] of corpus) {
  #|       const edited = `${source}\nTail \`code\`.\n`;
  #|       const advanceRequest = request(advance(edited));
  #|       inProcessStarted = performance.now();
  #|       const inProcessAdvanced = JSON.parse(inProcessDispatch(advanceRequest));
  #|       inProcessMaxSliceMs = Math.max(
  #|         inProcessMaxSliceMs,
  #|         performance.now() - inProcessStarted,
  #|       );
  #|       const workerAdvanced = JSON.parse((await client.send(advanceRequest, {
  #|         expectedStamp: inProcessAdvanced.stamp,
  #|       })).payload);
  #|       parity &&= JSON.stringify(workerAdvanced.observables)
  #|         === JSON.stringify(inProcessAdvanced.observables);
  #|     }
  #|     setGatePhase("worker-lifecycle");
  #|     await new Promise(resolve => setTimeout(resolve, 0));
  #|
  #|     const malformedRequestId = nextRequestId++;
  #|     const malformed = JSON.parse((await client.send("not-json", {
  #|       requestId: malformedRequestId,
  #|     })).payload).error.kind;
  #|     const collectibilityEvidence = typeof globalThis.gc === "function"
  #|       ? "gc-hook-available"
  #|       : "collectibility-unavailable";
  #|
  #|     const delayed = client.send(request({ kind: "snapshot" }), { delayMs: 100 });
  #|     currentEpoch += 1;
  #|     const restarted = createClient(currentEpoch);
  #|     generation += 1;
  #|     const restartedSeed = JSON.parse((await restarted.send(
  #|       request(seed("restart", "# Restart\n", generation)),
  #|     )).payload);
  #|     await delayed;
  #|     client.terminate();
  #|     client = restarted;
  #|     const sameEpochStale = JSON.parse((await client.send(
  #|       request({ kind: "snapshot" }),
  #|       {
  #|         control: "corrupt-stamp",
  #|         expectedStamp: restartedSeed.stamp,
  #|       },
  #|     )).payload).error.kind;
  #|
  #|     const dropped = await client.send(request({ kind: "snapshot" }), {
  #|       control: "drop-response",
  #|       timeoutMs: 100,
  #|     });
  #|     const timeout = JSON.parse(dropped.payload).error.kind;
  #|     const terminated = JSON.parse((await client.send(
  #|       request({ kind: "snapshot" }),
  #|       { control: "terminate" },
  #|     )).payload).error.kind;
  #|     client.terminate();
  #|
  #|     currentEpoch += 1;
  #|     client = createClient(currentEpoch);
  #|     generation += 1;
  #|     await client.send(request(seed("bounds", "# Initial\n", generation)));
  #|     const lowCountResponses = await Promise.all(
  #|       [100, 250, 500].map(delayMs => client.send(
  #|         request({ kind: "snapshot" }),
  #|         { delayMs, timeoutMs: 5000 },
  #|       )),
  #|     );
  #|     const lowCountDelays = lowCountResponses.every(response => (
  #|       JSON.parse(response.payload).kind === "ok"
  #|     ));
  #|     setGatePhase("large-burst");
  #|     const largeSources = [];
  #|     const largeBurst = [];
  #|     for (let index = 0; index < 20; index += 1) {
  #|       await new Promise(resolve => requestAnimationFrame(resolve));
  #|       const source = `# Large ${index}\n${"x".repeat(524288)}\n`;
  #|       largeSources.push(source);
  #|       largeBurst.push(client.send(request(advance(source)), {
  #|         delayMs: index === 0 ? 500 : 0,
  #|         timeoutMs: 10000,
  #|       }));
  #|     }
  #|     largeSources.push("# Large Latest\n");
  #|     largeBurst.push(client.send(request(advance("# Large Latest\n")), {
  #|       timeoutMs: 10000,
  #|     }));
  #|     const largeResponses = await Promise.all(largeBurst);
  #|     const largeOverflowed = largeResponses.some(response => {
  #|       try {
  #|         return JSON.parse(response.payload).error?.kind === "transport-overflow";
  #|       } catch {
  #|         return false;
  #|       }
  #|     });
  #|     client.terminate();
  #|     currentEpoch += 1;
  #|     generation += 1;
  #|     client = createClient(currentEpoch);
  #|     const largeLatest = largeSources[largeSources.length - 1];
  #|     await client.send(request(seed("large-overflow-recovery", largeLatest, generation)));
  #|     const largeSnapshot = JSON.parse((await client.send(
  #|       request({ kind: "snapshot" }),
  #|     )).payload);
  #|     const largePayloadRecovered = largeOverflowed
  #|       && largeSnapshot.observables.block.source === largeLatest;
  #|     client.terminate();
  #|     currentEpoch += 1;
  #|     generation += 1;
  #|     client = createClient(currentEpoch);
  #|     await client.send(request(seed("count-bounds", "# Initial\n", generation)));
  #|     setGatePhase("count-burst");
  #|     await new Promise(resolve => setTimeout(resolve, 0));
  #|     const burst = [];
  #|     for (let index = 0; index < 70; index += 1) {
  #|       burst.push(client.send(request(advance(`# Latest ${index}\n`)), {
  #|         delayMs: index === 0 ? 500 : 0,
  #|         timeoutMs: 10000,
  #|       }));
  #|     }
  #|     const burstResponses = await Promise.all(burst);
  #|     const overflowed = burstResponses.some(response => {
  #|       try {
  #|         return JSON.parse(response.payload).error?.kind === "transport-overflow";
  #|       } catch {
  #|         return false;
  #|       }
  #|     });
  #|     const burstTransport = largeResponses.concat(burstResponses).reduce(
  #|       (aggregate, response) => ({
  #|       highWaterCount: Math.max(
  #|         aggregate.highWaterCount,
  #|         response.transport?.highWaterCount ?? 0,
  #|       ),
  #|       highWaterEncodedBytes: Math.max(
  #|         aggregate.highWaterEncodedBytes,
  #|         response.transport?.highWaterEncodedBytes ?? 0,
  #|       ),
  #|       highWaterSourceEffectBytes: Math.max(
  #|         aggregate.highWaterSourceEffectBytes,
  #|         response.transport?.highWaterSourceEffectBytes ?? 0,
  #|       ),
  #|       supersededCount: Math.max(
  #|         aggregate.supersededCount,
  #|         response.transport?.supersededCount ?? 0,
  #|       ),
  #|       }), {
  #|         highWaterCount: 0,
  #|         highWaterEncodedBytes: 0,
  #|         highWaterSourceEffectBytes: 0,
  #|         supersededCount: 0,
  #|       },
  #|     );
  #|     client.terminate();
  #|     currentEpoch += 1;
  #|     generation += 1;
  #|     client = createClient(currentEpoch);
  #|     const recoveredSeed = JSON.parse((await client.send(request(
  #|       seed("overflow-recovery", "# Latest 69\n", generation),
  #|     ))).payload);
  #|     const snapshot = await client.send(request({ kind: "snapshot" }));
  #|     const latest = JSON.parse(snapshot.payload);
  #|     const transport = snapshot.transport ?? {};
  #|     const overflowRecovered = largePayloadRecovered && overflowed
  #|       && recoveredSeed.stamp.generation === generation;
  #|     const bounded = burstTransport.highWaterCount <= 64
  #|       && burstTransport.highWaterEncodedBytes <= 1048576
  #|       && burstTransport.highWaterSourceEffectBytes <= 1048576;
  #|     client.terminate();
  #|     await new Promise(resolve => setTimeout(resolve, 0));
  #|     longTaskObserver?.disconnect();
  #|     const workerLongTaskPhases = [
  #|       "startup",
  #|       "worker-lifecycle",
  #|       "large-burst",
  #|       "count-burst",
  #|     ];
  #|     const workerMaxLongTaskMs = workerLongTaskPhases.reduce(
  #|       (maximum, phase) => Math.max(maximum, longTaskByPhase[phase] ?? 0),
  #|       0,
  #|     );
  #|     const workerMaxLongTaskPhase = workerLongTaskPhases.reduce(
  #|       (maximum, phase) => (
  #|         (longTaskByPhase[phase] ?? 0) > (longTaskByPhase[maximum] ?? 0)
  #|           ? phase
  #|           : maximum
  #|       ),
  #|       "none",
  #|     );
  #|     const promotionRecommended = workerMaxLongTaskMs < 50;
  #|     const promotionRejection = promotionRecommended
  #|       ? "none"
  #|       : `main-thread-long-task:${workerMaxLongTaskPhase}`;
  #|
  #|     const report = {
  #|       parity,
  #|       malformed,
  #|       timeout,
  #|       startup_failure: startupFailure,
  #|       termination: terminated,
  #|       same_epoch_stale: sameEpochStale,
  #|       restart_generation: restartedSeed.stamp.generation,
  #|       stale_rejected: staleRejected,
  #|       bounded,
  #|       overflow_recovered: overflowRecovered,
  #|       large_payload_recovered: largePayloadRecovered,
  #|       latest_source: latest.observables.block.source,
  #|       high_water_count: burstTransport.highWaterCount,
  #|       low_count_delays: lowCountDelays,
  #|       high_water_encoded_bytes: burstTransport.highWaterEncodedBytes,
  #|       high_water_source_effect_bytes: burstTransport.highWaterSourceEffectBytes,
  #|       pending_count_after_catchup: transport.pendingCount ?? -1,
  #|       retained_seed_count_after_catchup: transport.retainedSeedCount ?? -1,
  #|       pending_source_effect_bytes_after_catchup:
  #|         transport.pendingSourceEffectBytes ?? -1,
  #|       retention_control_bytes: transport.retentionControlBytes ?? 0,
  #|       superseded_count: burstTransport.supersededCount,
  #|       max_long_task_ms: maxLongTaskMs,
  #|       in_process_max_slice_ms: inProcessMaxSliceMs,
  #|       worker_max_long_task_ms: workerMaxLongTaskMs,
  #|       worker_max_long_task_phase: workerMaxLongTaskPhase,
  #|       collectibility_evidence: collectibilityEvidence,
  #|       max_long_task_phase: maxLongTaskPhase,
  #|       promotion_recommended: promotionRecommended,
  #|       promotion_rejection: promotionRejection,
  #|     };
  #|     root.dataset.loomarkProjectionWorkerReport = JSON.stringify(report);
  #|     root.dataset.loomarkProjectionWorkerGate = (
  #|       parity && malformed === "decode-failed" && timeout === "timeout"
  #|       && startupFailure === "unavailable" && terminated === "terminated"
  #|       && staleRejected && sameEpochStale === "stale"
  #|       && bounded && overflowRecovered && largePayloadRecovered
  #|       && Number.isFinite(maxLongTaskMs)
  #|       && collectibilityEvidence === "collectibility-unavailable"
  #|       && report.pending_count_after_catchup === 0
  #|       && report.retained_seed_count_after_catchup === 0
  #|       && report.pending_source_effect_bytes_after_catchup === 0
  #|       && lowCountDelays
  #|       && report.retention_control_bytes > 0
  #|       && report.superseded_count > 0
  #|       && report.latest_source === "# Latest 69\n"
  #|     ) ? "complete" : "failed";
  #|   };
  #|
  #|   setTimeout(() => {
  #|     run().catch(error => {
  #|       root.dataset.loomarkProjectionWorkerReport = JSON.stringify({
  #|         error: error instanceof Error ? error.message : String(error),
  #|       });
  #|       root.dataset.loomarkProjectionWorkerGate = "error";
  #|     });
  #|   }, 0);
  #| }

///|
/// Start the page-owned Loomark application exactly once.
fn main {
  ignore(@app.mount_standalone("app", ""))
  start_warren_worker_capability_smoke()
  start_projection_worker_gate(@app.new_projection_worker_dispatcher())
}
