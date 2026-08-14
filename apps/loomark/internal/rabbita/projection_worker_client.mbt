///|
extern "js" fn projection_worker_client_create(epoch : Int) -> @js_value.Value =
  #| (epoch) => {
  #|   const worker = new Worker(new URL("./projection-worker.js", globalThis.location.href), {
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
  resolve : (Int, String) -> Unit,
) -> Int {
  let request_id = self.next_request_id
  self.next_request_id += 1
  let payload = Json::object({
    "schema_version": Json::string("1"),
    "request_id": Json::number(request_id.to_double()),
    "command": command,
  }).stringify()
  projection_worker_client_send_raw(self.handle, request_id, payload, raw => {
    resolve(request_id, raw)
  })
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
  demand : ProjectionDemand,
  resolve : (Int, ProjectionStamp, String) -> Unit,
) -> (Int, ProjectionStamp) {
  let stamp = projection_worker_client_seed_stamp(generation)
  self.expected_stamp = Some(stamp)
  let request_id = self.send(
    Json::object({
      "kind": Json::string("seed"),
      "agent_id": Json::string(self.agent_id),
      "source": Json::string(source),
      "generation": Json::number(generation.to_double()),
      "demand": Json::object({
        "block": Json::boolean(demand.block),
        "preview": Json::boolean(demand.preview),
        "diagnostics": Json::boolean(demand.diagnostics),
      }),
    }),
    (request_id, raw) => resolve(request_id, stamp, raw),
  )
  (request_id, stamp)
}

///|
fn ProjectionWorkerClient::advance(
  self : ProjectionWorkerClient,
  source : String,
  resolve : (Int, ProjectionStamp, String) -> Unit,
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
    (request_id, raw) => resolve(request_id, stamp, raw),
  )
  (request_id, stamp)
}

///|
fn ProjectionWorkerClient::demand(
  self : ProjectionWorkerClient,
  demand : ProjectionDemand,
  resolve : (Int, ProjectionStamp, String) -> Unit,
) -> (Int, ProjectionStamp) raise Failure {
  guard self.expected_stamp is Some(stamp) else {
    raise Failure::Failure("projection Worker Demand requires Seed")
  }
  let request_id = self.send(projection_worker_demand_command_json(demand), (
    request_id,
    raw,
  ) => resolve(request_id, stamp, raw))
  (request_id, stamp)
}

///|
fn ProjectionWorkerClient::dispose(self : ProjectionWorkerClient) -> Unit {
  if !self.disposed {
    self.disposed = true
    projection_worker_client_dispose_raw(self.handle)
  }
}

///|
fn projection_worker_response_stamp(
  fields : Map[String, Json],
) -> ProjectionStamp? {
  guard projection_worker_decode_int(fields, "generation") is Some(generation) &&
    projection_worker_decode_int(fields, "sequence") is Some(sequence) &&
    projection_worker_decode_int(fields, "source_revision")
    is Some(source_revision) &&
    projection_worker_decode_string(fields, "causal_version")
    is Some(causal_version) &&
    projection_worker_decode_int(fields, "block_intent") is Some(block_intent) else {
    return None
  }
  Some({ generation, sequence, source_revision, causal_version, block_intent })
}

///|
fn projection_worker_response_matches(
  expected_stamp : ProjectionStamp?,
  expected_request_id : Int?,
  callback_stamp : ProjectionStamp,
  callback_request_id : Int,
) -> Bool {
  expected_stamp == Some(callback_stamp) &&
  expected_request_id == Some(callback_request_id)
}

///|
fn projection_worker_response_artifact(
  raw : String,
) -> Result[(ProjectionStamp, ProjectionPreviewArtifact?), String] {
  let parsed = @json.parse(raw) catch {
    _ => return Err("projection Worker response is not valid JSON")
  }
  guard parsed is Json::Object(fields) else {
    return Err("projection Worker response must be an object")
  }
  guard projection_worker_decode_string(fields, "schema_version") == Some("1") else {
    return Err("projection Worker response has unsupported schema_version")
  }
  match projection_worker_decode_string(fields, "kind") {
    Some("error") => {
      let detail = match fields.get("error") {
        Some(Json::Object(error)) =>
          match projection_worker_decode_string(error, "detail") {
            Some(detail) => detail
            None =>
              projection_worker_decode_string(error, "kind").unwrap_or(
                "unknown projection Worker error",
              )
          }
        _ => "malformed projection Worker error"
      }
      Err(detail)
    }
    Some("ok") => {
      guard fields.get("stamp") is Some(Json::Object(stamp_fields)) &&
        projection_worker_response_stamp(stamp_fields) is Some(stamp) else {
        return Err("projection Worker response is missing its stamp")
      }
      let artifact = match fields.get("observables") {
        Some(Json::Object(observables)) =>
          match observables.get("preview") {
            Some(Json::Object(preview)) =>
              match preview.get("artifact") {
                Some(encoded) =>
                  match projection_preview_artifact_from_json(encoded) {
                    Ok(value) => Some(value)
                    Err(detail) => return Err(detail)
                  }
                None => None
              }
            _ => None
          }
        _ => None
      }
      Ok((stamp, artifact))
    }
    _ => Err("projection Worker response has unknown kind")
  }
}

///|
priv struct ProjectionWorkerRuntime {
  mut client : ProjectionWorkerClient
  agent_id : String
  mut epoch : Int
  mut seeded : Bool
  mut source : String
  mut demand : ProjectionDemand
  mut expected_stamp : ProjectionStamp?
  mut expected_request_id : Int?
  mut restart_count : Int
  mut disposed : Bool
}

///|
fn ProjectionWorkerRuntime::new(agent_id : String) -> ProjectionWorkerRuntime {
  {
    client: ProjectionWorkerClient::new(1, agent_id),
    agent_id,
    epoch: 1,
    seeded: false,
    source: "",
    demand: { block: false, preview: false, diagnostics: false },
    expected_stamp: None,
    expected_request_id: None,
    restart_count: 0,
    disposed: false,
  }
}

///|
fn ProjectionWorkerRuntime::accepts(
  self : ProjectionWorkerRuntime,
  request_id : Int,
  stamp : ProjectionStamp,
) -> Bool {
  !self.disposed &&
  projection_worker_response_matches(
    self.expected_stamp,
    self.expected_request_id,
    stamp,
    request_id,
  )
}

///|
fn ProjectionWorkerRuntime::sync(
  self : ProjectionWorkerRuntime,
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  guard !self.disposed else { return @rabbita_runtime.none }
  let source = model.document.source()
  let demand = projection_demand_for_model(model)
  let seed = !self.seeded
  let source_changed = self.seeded && source != self.source
  let demand_changed = self.seeded && demand != self.demand
  guard seed || source_changed || demand_changed else {
    return @rabbita_runtime.none
  }
  self.seeded = true
  self.source = source
  self.demand = demand
  @cmd.custom_cmd(scheduler => {
    let resolve = (request_id, stamp, raw) => {
      scheduler.add(
        emit(Lifecycle(ProjectionWorkerResolved(request_id, stamp, raw))),
      )
    }
    if seed {
      let (request_id, stamp) = self.client.seed(
        source,
        self.epoch,
        demand,
        resolve,
      )
      self.expected_stamp = Some(stamp)
      self.expected_request_id = Some(request_id)
    } else {
      if source_changed {
        let (request_id, stamp) = self.client.advance(source, resolve) catch {
          _ => {
            self.restart()
            return
          }
        }
        self.expected_stamp = Some(stamp)
        self.expected_request_id = Some(request_id)
      }
      if demand_changed {
        let (request_id, _) = self.client.demand(demand, resolve) catch {
          _ => return
        }
        self.expected_request_id = Some(request_id)
      }
    }
  })
}

///|
fn ProjectionWorkerRuntime::restart(self : ProjectionWorkerRuntime) -> Unit {
  self.client.dispose()
  if self.restart_count >= 1 {
    self.disposed = true
    return
  }
  self.restart_count += 1
  self.epoch += 1
  self.client = ProjectionWorkerClient::new(self.epoch, self.agent_id)
  self.seeded = false
  self.source = ""
  self.expected_stamp = None
  self.expected_request_id = None
}

///|
fn ProjectionWorkerRuntime::mark_healthy(
  self : ProjectionWorkerRuntime,
) -> Unit {
  self.restart_count = 0
}

///|
fn ProjectionWorkerRuntime::dispose(self : ProjectionWorkerRuntime) -> Unit {
  if !self.disposed {
    self.disposed = true
    self.client.dispose()
  }
}
