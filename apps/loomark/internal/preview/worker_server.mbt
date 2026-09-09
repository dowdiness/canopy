///|
/// /// Worker-side imperative shell around the existing PreviewEngine.
pub struct WorkerServer {
  priv engine : PreviewEngine
  priv mut generation : Int?
  priv mut last_request : Int
  priv mut pending_request : Int?
  priv mut pending_acceptance : Int?
}

///|
pub fn WorkerServer::WorkerServer() -> WorkerServer {
  let engine = PreviewEngine::PreviewEngine()
  engine.worker_server = true
  {
    engine,
    generation: None,
    last_request: -1,
    pending_request: None,
    pending_acceptance: None,
  }
}

///|
fn worker_field(json : Json, name : String) -> Json? {
  match json {
    Json::Object(fields) => fields.get(name)
    _ => None
  }
}

///|
fn worker_int(json : Json, name : String) -> Int? {
  match worker_field(json, name) {
    Some(Json::Number(value, ..)) if value.to_int().to_double() == value =>
      Some(value.to_int())
    _ => None
  }
}

///|
fn worker_error(message : String) -> Json {
  Json::object({
    "type": Json::string("error"),
    "message": Json::string(message),
  })
}

///|
/// Validate and execute one JSON request. The parser and Markdown lowering
/// remain owned by PreviewEngine; this boundary only transports detached nodes.
fn WorkerServer::dispatch(self : WorkerServer, request : Json) -> Json {
  let kind = match worker_field(request, "type") {
    Some(Json::String(value)) => value
    _ => return worker_error("missing request type")
  }
  match kind {
    "ack" => {
      let sequence = match worker_int(request, "sequence") {
        Some(value) => value
        None => return worker_error("invalid ack sequence")
      }
      let accepted = match worker_field(request, "accepted") {
        Some(Json::True) => true
        Some(Json::False) => false
        _ => return worker_error("invalid ack acceptance")
      }
      guard self.pending_request == Some(sequence) &&
        worker_int(request, "generation") == self.generation else {
        return worker_error("stale ack")
      }
      guard self.pending_acceptance is Some(acceptance) else {
        return worker_error("no candidate")
      }
      if self.engine.acknowledge(acceptance, accepted) {
        self.pending_request = None
        self.pending_acceptance = None
        Json::object({
          "type": Json::string("ack"),
          "sequence": Json::number(sequence.to_double()),
        })
      } else {
        worker_error("ack does not match pending output")
      }
    }
    "preview" => {
      guard self.pending_request is None else {
        return worker_error("output must be acknowledged before next request")
      }
      let generation = match worker_int(request, "generation") {
        Some(value) => value
        None => return worker_error("invalid generation")
      }
      let sequence = match worker_int(request, "sequence") {
        Some(value) => value
        None => return worker_error("invalid sequence")
      }
      let source = match worker_field(request, "source") {
        Some(Json::String(value)) => value
        _ => return worker_error("invalid source")
      }
      guard generation >= 0 && sequence > self.last_request else {
        return worker_error("non-monotonic sequence")
      }
      match self.generation {
        Some(current) if generation != current => {
          guard generation > current else {
            return worker_error("stale generation")
          }
          ignore(self.engine.activate_generation(generation))
          self.generation = Some(generation)
        }
        None => {
          ignore(self.engine.activate_generation(generation))
          self.generation = Some(generation)
        }
        Some(_) => ()
      }
      let change = match worker_field(request, "edit") {
        None | Some(Json::Null) => None
        Some(edit) => {
          guard worker_int(edit, "start") is Some(start) &&
            worker_int(edit, "delete_len") is Some(delete_len) &&
            worker_field(edit, "inserted") is Some(Json::String(inserted)) else {
            return worker_error("invalid edit")
          }
          Some(@text_change.ReplaceRange(start~, delete_len~, inserted~))
        }
      }
      self.last_request = sequence
      let result = match
        self.engine.catch_up_owned(generation, source, change) {
        Some(result) => result
        None => return worker_error("generation was superseded")
      }
      match result {
        Err(_) => worker_error("preview computation failed")
        Ok(output) => {
          self.last_request = sequence
          self.pending_request = Some(sequence)
          self.pending_acceptance = Some(output.acceptance.sequence)
          Json::object({
            "type": Json::string("preview"),
            "generation": Json::number(generation.to_double()),
            "sequence": Json::number(sequence.to_double()),
            "empty": Json::boolean(output.empty),
            "blocks": Json::array(output.wire_blocks),
          })
        }
      }
    }
    _ => worker_error("unknown request type")
  }
}

///|
/// Convenience JSON-string boundary for a separate Worker entry.
pub fn WorkerServer::dispatch_text(
  self : WorkerServer,
  request : String,
) -> String {
  let value = @json.parse(request) catch {
    _ => return worker_error("malformed JSON").stringify()
  }
  self.dispatch(value).stringify()
}
