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
suberror ProjectionWorkerCounterError {
  RequestIdExhausted
  SequenceExhausted
  GenerationExhausted
} derive(Eq, Debug)

///|
fn projection_worker_allocate_request_id(
  next_request_id : Int,
) -> (Int, Int) raise ProjectionWorkerCounterError {
  guard next_request_id > 0 && checked_next(next_request_id) is Some(next) else {
    raise ProjectionWorkerCounterError::RequestIdExhausted
  }
  (next_request_id, next)
}

///|
priv struct ProjectionStampOwner {
  mut generation : Int
  mut sequence : Int
}

///|
fn ProjectionStampOwner::new(
  generation? : Int = 1,
  sequence? : Int = 0,
) -> ProjectionStampOwner {
  { generation, sequence }
}

///|
fn ProjectionStampOwner::next(
  self : Self,
  source_revision~ : Int,
  causal_version~ : String,
  block_intent~ : Int,
) -> ProjectionStamp raise ProjectionWorkerCounterError {
  guard checked_next(self.sequence) is Some(sequence) else {
    raise ProjectionWorkerCounterError::SequenceExhausted
  }
  self.sequence = sequence
  {
    generation: self.generation,
    sequence,
    source_revision,
    causal_version,
    block_intent,
  }
}

///|
fn ProjectionStampOwner::restart(
  self : Self,
) -> Unit raise ProjectionWorkerCounterError {
  guard checked_next(self.generation) is Some(generation) else {
    raise ProjectionWorkerCounterError::GenerationExhausted
  }
  self.generation = generation
}

///|
priv struct ProjectionWorkerClient {
  handle : @js_value.Value
  agent_id : String
  mut next_request_id : Int
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
    disposed: false,
  }
}

///|
fn ProjectionWorkerClient::send(
  self : ProjectionWorkerClient,
  command : Json,
  resolve : (Int, String) -> Unit,
) -> Int raise ProjectionWorkerCounterError {
  let (request_id, next_request_id) = projection_worker_allocate_request_id(
    self.next_request_id,
  )
  self.next_request_id = next_request_id
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
fn projection_worker_demand_command_json(
  stamp : ProjectionStamp,
  demand : ProjectionDemand,
) -> Json {
  Json::object({
    "kind": Json::string("demand"),
    "stamp": projection_worker_stamp_json(stamp),
    "demand": Json::object({
      "block": Json::boolean(demand.block),
      "preview": Json::boolean(demand.preview),
      "diagnostics": Json::boolean(demand.diagnostics),
    }),
  })
}

///|
fn ProjectionWorkerClient::seed(
  self : ProjectionWorkerClient,
  source : String,
  stamp : ProjectionStamp,
  demand : ProjectionDemand,
  resolve : (Int, ProjectionStamp, String) -> Unit,
) -> Int raise {
  self.send(
    Json::object({
      "kind": Json::string("seed"),
      "agent_id": Json::string(self.agent_id),
      "source": Json::string(source),
      "stamp": projection_worker_stamp_json(stamp),
      "demand": Json::object({
        "block": Json::boolean(demand.block),
        "preview": Json::boolean(demand.preview),
        "diagnostics": Json::boolean(demand.diagnostics),
      }),
    }),
    (request_id, raw) => resolve(request_id, stamp, raw),
  )
}

///|
fn ProjectionWorkerClient::advance(
  self : ProjectionWorkerClient,
  stamp : ProjectionStamp,
  effect : ProjectionSourceEffect,
  resolve : (Int, ProjectionStamp, String) -> Unit,
) -> Int raise {
  self.send(
    Json::object({
      "kind": Json::string("advance"),
      "stamp": projection_worker_stamp_json(stamp),
      "source_effect": projection_source_effect_json(effect),
    }),
    (request_id, raw) => resolve(request_id, stamp, raw),
  )
}

///|
fn ProjectionWorkerClient::demand(
  self : ProjectionWorkerClient,
  stamp : ProjectionStamp,
  demand : ProjectionDemand,
  resolve : (Int, ProjectionStamp, String) -> Unit,
) -> Int raise {
  self.send(projection_worker_demand_command_json(stamp, demand), (
    request_id,
    raw,
  ) => resolve(request_id, stamp, raw))
}

///|
fn ProjectionWorkerClient::dispose(self : ProjectionWorkerClient) -> Unit {
  if !self.disposed {
    self.disposed = true
    projection_worker_client_dispose_raw(self.handle)
  }
}

///|
/// Main-thread transport for the private placement comparison. It retains the
/// same dispatcher session and envelope as the dedicated Worker client.
#warnings("-unused_value")
priv struct ProjectionInProcessClient {
  dispatch : (String) -> String
  agent_id : String
  mut next_request_id : Int
  mut disposed : Bool
}

///|
#warnings("-unused_value")
fn ProjectionInProcessClient::new(
  agent_id : String,
) -> ProjectionInProcessClient {
  {
    dispatch: new_projection_worker_dispatcher(),
    agent_id,
    next_request_id: 1,
    disposed: false,
  }
}

///|
#warnings("-unused_value")
fn ProjectionInProcessClient::send(
  self : ProjectionInProcessClient,
  command : Json,
  resolve : (Int, String) -> Unit,
) -> Int raise {
  guard !self.disposed else {
    raise Failure::Failure("in-process projection client disposed")
  }
  let (request_id, next_request_id) = projection_worker_allocate_request_id(
    self.next_request_id,
  )
  self.next_request_id = next_request_id
  let payload = Json::object({
    "schema_version": Json::string("1"),
    "request_id": Json::number(request_id.to_double()),
    "command": command,
  }).stringify()
  resolve(request_id, (self.dispatch)(payload))
  request_id
}

///|
#warnings("-unused_value")
fn ProjectionInProcessClient::seed(
  self : ProjectionInProcessClient,
  source : String,
  stamp : ProjectionStamp,
  demand : ProjectionDemand,
  resolve : (Int, ProjectionStamp, String) -> Unit,
) -> Int raise {
  self.send(
    Json::object({
      "kind": Json::string("seed"),
      "agent_id": Json::string(self.agent_id),
      "source": Json::string(source),
      "stamp": projection_worker_stamp_json(stamp),
      "demand": Json::object({
        "block": Json::boolean(demand.block),
        "preview": Json::boolean(demand.preview),
        "diagnostics": Json::boolean(demand.diagnostics),
      }),
    }),
    (request_id, raw) => resolve(request_id, stamp, raw),
  )
}

///|
#warnings("-unused_value")
fn ProjectionInProcessClient::advance(
  self : ProjectionInProcessClient,
  stamp : ProjectionStamp,
  effect : ProjectionSourceEffect,
  resolve : (Int, ProjectionStamp, String) -> Unit,
) -> Int raise {
  self.send(
    Json::object({
      "kind": Json::string("advance"),
      "stamp": projection_worker_stamp_json(stamp),
      "source_effect": projection_source_effect_json(effect),
    }),
    (request_id, raw) => resolve(request_id, stamp, raw),
  )
}

///|
#warnings("-unused_value")
fn ProjectionInProcessClient::demand(
  self : ProjectionInProcessClient,
  stamp : ProjectionStamp,
  demand : ProjectionDemand,
  resolve : (Int, ProjectionStamp, String) -> Unit,
) -> Int raise {
  self.send(projection_worker_demand_command_json(stamp, demand), (
    request_id,
    raw,
  ) => resolve(request_id, stamp, raw))
}

///|
#warnings("-unused_value")
fn ProjectionInProcessClient::dispose(self : ProjectionInProcessClient) -> Unit {
  self.disposed = true
}

///|
priv enum ProjectionClient {
  DedicatedWorker(ProjectionWorkerClient)
  MainThread(ProjectionInProcessClient)
}

///|
fn ProjectionClient::seed(
  self : ProjectionClient,
  source : String,
  stamp : ProjectionStamp,
  demand : ProjectionDemand,
  resolve : (Int, ProjectionStamp, String) -> Unit,
) -> Int raise {
  match self {
    DedicatedWorker(client) => client.seed(source, stamp, demand, resolve)
    MainThread(client) => client.seed(source, stamp, demand, resolve)
  }
}

///|
fn ProjectionClient::advance(
  self : ProjectionClient,
  stamp : ProjectionStamp,
  effect : ProjectionSourceEffect,
  resolve : (Int, ProjectionStamp, String) -> Unit,
) -> Int raise {
  match self {
    DedicatedWorker(client) => client.advance(stamp, effect, resolve)
    MainThread(client) => client.advance(stamp, effect, resolve)
  }
}

///|
fn ProjectionClient::demand(
  self : ProjectionClient,
  stamp : ProjectionStamp,
  demand : ProjectionDemand,
  resolve : (Int, ProjectionStamp, String) -> Unit,
) -> Int raise {
  match self {
    DedicatedWorker(client) => client.demand(stamp, demand, resolve)
    MainThread(client) => client.demand(stamp, demand, resolve)
  }
}

///|
fn ProjectionClient::dispose(self : ProjectionClient) -> Unit {
  match self {
    DedicatedWorker(client) => client.dispose()
    MainThread(client) => client.dispose()
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
fn projection_worker_claim_response(
  expected_stamp : ProjectionStamp?,
  expected_request_id : Int?,
  callback_stamp : ProjectionStamp,
  callback_request_id : Int,
) -> (Bool, Int?) {
  if projection_worker_response_matches(
      expected_stamp, expected_request_id, callback_stamp, callback_request_id,
    ) {
    (true, None)
  } else {
    (false, expected_request_id)
  }
}

///|
fn projection_worker_response_artifact(
  raw : String,
) -> Result[(Int, ProjectionStamp, ProjectionPreviewArtifact?), String] {
  let parsed = @json.parse(raw) catch {
    _ => return Err("projection Worker response is not valid JSON")
  }
  guard parsed is Json::Object(fields) else {
    return Err("projection Worker response must be an object")
  }
  guard projection_worker_decode_string(fields, "schema_version") == Some("1") else {
    return Err("projection Worker response has unsupported schema_version")
  }
  guard projection_worker_decode_int(fields, "request_id") is Some(request_id) else {
    return Err("projection Worker response is missing its request ID")
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
      Ok((request_id, stamp, artifact))
    }
    _ => Err("projection Worker response has unknown kind")
  }
}

///|
priv struct ProjectionWorkerRuntime {
  mut client : ProjectionClient
  agent_id : String
  in_process : Bool
  stamp_owner : ProjectionStampOwner
  mut current_stamp : ProjectionStamp?
  mut seeded : Bool
  mut source : String
  mut source_revision : Int
  mut causal_version : String
  mut demand : ProjectionDemand
  mut expected_request_id : Int?
  mut restart_count : Int
  mut disposed : Bool
}

///|
fn ProjectionWorkerRuntime::new(agent_id : String) -> ProjectionWorkerRuntime {
  {
    client: DedicatedWorker(ProjectionWorkerClient::new(1, agent_id)),
    agent_id,
    in_process: false,
    stamp_owner: ProjectionStampOwner::new(),
    current_stamp: None,
    seeded: false,
    source: "",
    source_revision: 0,
    causal_version: "",
    demand: { block: false, preview: false, diagnostics: false },
    expected_request_id: None,
    restart_count: 0,
    disposed: false,
  }
}

///|
#warnings("-unused_value")
fn ProjectionWorkerRuntime::new_in_process(
  agent_id : String,
) -> ProjectionWorkerRuntime {
  {
    client: MainThread(ProjectionInProcessClient::new(agent_id)),
    agent_id,
    in_process: true,
    stamp_owner: ProjectionStampOwner::new(),
    current_stamp: None,
    seeded: false,
    source: "",
    source_revision: 0,
    causal_version: "",
    demand: { block: false, preview: false, diagnostics: false },
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
  guard !self.disposed else { return false }
  let (accepted, next_request_id) = projection_worker_claim_response(
    self.current_stamp,
    self.expected_request_id,
    stamp,
    request_id,
  )
  self.expected_request_id = next_request_id
  accepted
}

///|
fn ProjectionWorkerRuntime::sync(
  self : ProjectionWorkerRuntime,
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  guard !self.disposed else { return @rabbita_runtime.none }
  let source = model.document.source()
  let source_revision = model.source_revision
  let causal_version = model.document_version.to_json_string()
  let demand = projection_demand_for_model(model)
  let seed = !self.seeded
  let authority_changed = self.seeded &&
    (
      source_revision != self.source_revision ||
      causal_version != self.causal_version
    )
  let demand_changed = self.seeded && demand != self.demand
  let source_effect = if source == self.source {
    ProjectionSourceUnchanged
  } else {
    ReplaceProjectionSource(source)
  }
  guard seed || authority_changed || demand_changed else {
    return @rabbita_runtime.none
  }
  self.seeded = true
  self.source = source
  self.source_revision = source_revision
  self.causal_version = causal_version
  self.demand = demand
  self.expected_request_id = None
  @cmd.custom_cmd(scheduler => {
    let resolve = (request_id, stamp, raw) => {
      scheduler.add(
        emit(Lifecycle(ProjectionWorkerResolved(request_id, stamp, raw))),
      )
    }
    if seed {
      let stamp = self.stamp_owner.next(
        source_revision~,
        causal_version~,
        block_intent=model.committed_change_count,
      ) catch {
        _ => {
          self.disposed = true
          scheduler.add(
            emit(Lifecycle(Fatal("projection Worker stamp exhausted"))),
          )
          return
        }
      }
      let request_id = self.client.seed(source, stamp, demand, resolve) catch {
        error => {
          self.disposed = true
          scheduler.add(emit(Lifecycle(Fatal(error.to_string()))))
          return
        }
      }
      self.current_stamp = Some(stamp)
      self.expected_request_id = Some(request_id)
    } else {
      if authority_changed {
        let stamp = self.stamp_owner.next(
          source_revision~,
          causal_version~,
          block_intent=model.committed_change_count,
        ) catch {
          _ => {
            self.disposed = true
            scheduler.add(
              emit(Lifecycle(Fatal("projection Worker stamp exhausted"))),
            )
            return
          }
        }
        let effect = source_effect
        let request_id = self.client.advance(stamp, effect, resolve) catch {
          error => {
            self.disposed = true
            scheduler.add(emit(Lifecycle(Fatal(error.to_string()))))
            return
          }
        }
        self.current_stamp = Some(stamp)
        self.expected_request_id = Some(request_id)
      }
      if demand_changed {
        guard self.current_stamp is Some(stamp) else { return }
        let request_id = self.client.demand(stamp, demand, resolve) catch {
          error => {
            self.disposed = true
            scheduler.add(emit(Lifecycle(Fatal(error.to_string()))))
            return
          }
        }
        self.expected_request_id = Some(request_id)
      }
    }
  })
}

///|
fn ProjectionWorkerRuntime::restart(
  self : ProjectionWorkerRuntime,
) -> Unit raise ProjectionWorkerCounterError {
  self.client.dispose()
  self.expected_request_id = None
  self.current_stamp = None
  if self.restart_count >= 1 {
    self.disposed = true
    return
  }
  self.restart_count += 1
  self.stamp_owner.restart()
  self.client = if self.in_process {
    MainThread(ProjectionInProcessClient::new(self.agent_id))
  } else {
    DedicatedWorker(
      ProjectionWorkerClient::new(self.stamp_owner.generation, self.agent_id),
    )
  }
  self.seeded = false
  self.source = ""
}

///|

///|
fn ProjectionWorkerRuntime::recover(
  self : ProjectionWorkerRuntime,
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
  detail : String,
) -> (DriverModel, @cmd.Cmd) {
  self.restart() catch {
    _ => {
      self.disposed = true
      return (
        { ..projection_failed_model(model, detail), fatal: true },
        @rabbita_runtime.none,
      )
    }
  }
  let next = projection_failed_model(model, detail)
  (next, self.sync(next, emit))
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
