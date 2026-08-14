///|
extern "js" fn projection_worker_client_create(epoch : Int) -> @js_value.Value =
  #| (epoch) => {
  #|   const worker = new Worker(new URL("./projection-worker.js", import.meta.url), {
  #|     type: "module",
  #|     name: `loomark-projection-${epoch}`,
  #|   });
  #|   const pending = new Map();
  #|   const errorPayload = (requestId, kind, detail) => JSON.stringify({
  #|     schema_version: "1",
  #|     request_id: requestId,
  #|     kind: "error",
  #|     error: { kind, detail },
  #|   });
  #|   const settleAll = (kind, detail) => {
  #|     for (const [requestId, entry] of pending) {
  #|       clearTimeout(entry.timer);
  #|       entry.resolve(errorPayload(requestId, kind, detail));
  #|     }
  #|     pending.clear();
  #|   };
  #|   worker.addEventListener("message", event => {
  #|     const response = event.data;
  #|     if (response?.kind !== "loomark-projection-response") return;
  #|     const entry = pending.get(response.requestId);
  #|     if (entry == null) return;
  #|     pending.delete(response.requestId);
  #|     clearTimeout(entry.timer);
  #|     if (response.epoch !== epoch) {
  #|       entry.resolve(errorPayload(response.requestId, "stale", "Worker epoch mismatch"));
  #|       return;
  #|     }
  #|     entry.resolve(response.payload);
  #|   });
  #|   worker.addEventListener("error", event => {
  #|     settleAll("terminated", event.message || "projection Worker failed");
  #|   });
  #|   return { worker, pending, epoch, errorPayload, settleAll, disposed: false };
  #| }

///|
extern "js" fn projection_worker_client_send_raw(
  handle : @js_value.Value,
  request_id : Int,
  payload : String,
  resolve : (String) -> Unit,
) -> Unit =
  #| (handle, requestId, payload, resolve) => {
  #|   if (handle.disposed) {
  #|     resolve(handle.errorPayload(requestId, "disposed", "projection Worker client disposed"));
  #|     return;
  #|   }
  #|   const timer = setTimeout(() => {
  #|     if (!handle.pending.delete(requestId)) return;
  #|     resolve(handle.errorPayload(requestId, "timeout", "projection Worker request timed out"));
  #|   }, 5000);
  #|   handle.pending.set(requestId, { resolve, timer });
  #|   handle.worker.postMessage({
  #|     kind: "loomark-projection-request",
  #|     epoch: handle.epoch,
  #|     requestId,
  #|     payload,
  #|   });
  #| }

///|
extern "js" fn projection_worker_client_dispose_raw(
  handle : @js_value.Value,
) -> Unit =
  #| handle => {
  #|   if (handle.disposed) return;
  #|   handle.disposed = true;
  #|   handle.settleAll("terminated", "projection Worker client disposed");
  #|   handle.worker.terminate();
  #| }

///|
priv struct ProjectionWorkerClient {
  handle : @js_value.Value
  agent_id : String
  mut next_request_id : Int
  mut expected_stamp : ProjectionStamp?
  mut disposed : Bool
}

///|
fn ProjectionWorkerClient::new(
  epoch : Int,
  agent_id : String,
) -> ProjectionWorkerClient {
  {
    handle: projection_worker_client_create(epoch),
    agent_id,
    next_request_id: 1,
    expected_stamp: None,
    disposed: false,
  }
}

///|
fn ProjectionWorkerClient::send(
  self : ProjectionWorkerClient,
  command : Json,
  resolve : (String) -> Unit,
) -> Int {
  let request_id = self.next_request_id
  self.next_request_id += 1
  let payload = Json::object({
    "schema_version": Json::string("1"),
    "request_id": Json::number(request_id.to_double()),
    "command": command,
  }).stringify()
  projection_worker_client_send_raw(self.handle, request_id, payload, resolve)
  request_id
}

///|
fn projection_worker_demand_command_json(demand : ProjectionDemand) -> Json {
  Json::object({
    "kind": Json::string("demand"),
    "demand": Json::object({
      "block": Json::boolean(demand.block),
      "preview": Json::boolean(demand.preview),
      "diagnostics": Json::boolean(demand.diagnostics),
    }),
  })
}

///|
fn projection_worker_client_seed_stamp(generation : Int) -> ProjectionStamp {
  {
    generation,
    sequence: 1,
    source_revision: 1,
    causal_version: "projection-session-1",
    block_intent: 1,
  }
}

///|
fn projection_worker_client_advance_stamp(
  previous : ProjectionStamp,
) -> ProjectionStamp {
  let sequence = previous.sequence + 1
  {
    ..previous,
    sequence,
    source_revision: previous.source_revision + 1,
    causal_version: "projection-session-" + sequence.to_string(),
    block_intent: previous.block_intent + 1,
  }
}

///|
fn ProjectionWorkerClient::seed(
  self : ProjectionWorkerClient,
  source : String,
  generation : Int,
  resolve : (ProjectionStamp, String) -> Unit,
) -> (Int, ProjectionStamp) {
  let stamp = projection_worker_client_seed_stamp(generation)
  self.expected_stamp = Some(stamp)
  let request_id = self.send(
    Json::object({
      "kind": Json::string("seed"),
      "agent_id": Json::string(self.agent_id),
      "source": Json::string(source),
      "generation": Json::number(generation.to_double()),
    }),
    raw => resolve(stamp, raw),
  )
  (request_id, stamp)
}

///|
fn ProjectionWorkerClient::advance(
  self : ProjectionWorkerClient,
  source : String,
  resolve : (ProjectionStamp, String) -> Unit,
) -> (Int, ProjectionStamp) raise Failure {
  guard self.expected_stamp is Some(previous) else {
    raise Failure::Failure("projection Worker Advance requires Seed")
  }
  let stamp = projection_worker_client_advance_stamp(previous)
  self.expected_stamp = Some(stamp)
  let request_id = self.send(
    Json::object({
      "kind": Json::string("advance"),
      "source_effect": Json::object({
        "kind": Json::string("replace-source"),
        "source": Json::string(source),
      }),
    }),
    raw => resolve(stamp, raw),
  )
  (request_id, stamp)
}

///|
fn ProjectionWorkerClient::demand(
  self : ProjectionWorkerClient,
  demand : ProjectionDemand,
  resolve : (ProjectionStamp, String) -> Unit,
) -> (Int, ProjectionStamp) raise Failure {
  guard self.expected_stamp is Some(stamp) else {
    raise Failure::Failure("projection Worker Demand requires Seed")
  }
  let request_id = self.send(projection_worker_demand_command_json(demand), raw => {
    resolve(stamp, raw)
  })
  (request_id, stamp)
}

///|
fn ProjectionWorkerClient::dispose(self : ProjectionWorkerClient) -> Unit {
  if !self.disposed {
    self.disposed = true
    projection_worker_client_dispose_raw(self.handle)
  }
}
