///|
priv enum ProjectionWorkerCommand {
  WorkerSeed(String, String, ProjectionStamp, ProjectionDemand)
  WorkerAdvance(ProjectionStamp, ProjectionSourceEffect)
  WorkerDemand(ProjectionStamp, ProjectionDemand)
  WorkerSnapshot
  WorkerDispose
}

///|
fn projection_worker_decode_int(
  fields : Map[String, Json],
  name : String,
) -> Int? {
  match fields.get(name) {
    Some(Json::Number(value, ..)) => {
      let integer = value.to_int()
      if value == integer.to_double() {
        Some(integer)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn projection_worker_decode_string(
  fields : Map[String, Json],
  name : String,
) -> String? {
  match fields.get(name) {
    Some(Json::String(value)) => Some(value)
    _ => None
  }
}

///|
fn projection_worker_decode_bool(
  fields : Map[String, Json],
  name : String,
) -> Bool? {
  match fields.get(name) {
    Some(Json::True) => Some(true)
    Some(Json::False) => Some(false)
    _ => None
  }
}

///|
fn projection_worker_decode_demand(
  fields : Map[String, Json],
) -> ProjectionDemand? {
  guard projection_worker_decode_bool(fields, "block") is Some(block) &&
    projection_worker_decode_bool(fields, "preview") is Some(preview) &&
    projection_worker_decode_bool(fields, "diagnostics") is Some(diagnostics) else {
    return None
  }
  Some({ block, preview, diagnostics })
}

///|
fn projection_worker_decode_stamp(
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
fn projection_worker_decode_request(
  raw : String,
) -> Result[(Int, ProjectionWorkerCommand), String] {
  let parsed = @json.parse(raw) catch {
    _ => return Err("request is not valid JSON")
  }
  guard parsed is Json::Object(fields) else {
    return Err("request must be an object")
  }
  guard projection_worker_decode_string(fields, "schema_version") == Some("1") else {
    return Err("unsupported schema_version")
  }
  guard projection_worker_decode_int(fields, "request_id") is Some(request_id) &&
    request_id >= 0 else {
    return Err("request_id must be a non-negative integer")
  }
  guard fields.get("command") is Some(Json::Object(command)) else {
    return Err("command must be an object")
  }
  guard projection_worker_decode_string(command, "kind") is Some(kind) else {
    return Err("command kind is missing")
  }
  match kind {
    "seed" => {
      guard projection_worker_decode_string(command, "agent_id")
        is Some(agent_id) else {
        return Err("seed agent_id is missing")
      }
      guard projection_worker_decode_string(command, "source") is Some(source) else {
        return Err("seed source is missing")
      }
      guard command.get("stamp") is Some(Json::Object(stamp_fields)) &&
        projection_worker_decode_stamp(stamp_fields) is Some(stamp) else {
        return Err("seed stamp is missing or malformed")
      }
      guard command.get("demand") is Some(Json::Object(demand)) &&
        projection_worker_decode_demand(demand) is Some(decoded_demand) else {
        return Err(
          "seed demand must contain boolean block, preview, and diagnostics",
        )
      }
      Ok((request_id, WorkerSeed(agent_id, source, stamp, decoded_demand)))
    }
    "advance" => {
      guard command.get("stamp") is Some(Json::Object(stamp_fields)) &&
        projection_worker_decode_stamp(stamp_fields) is Some(stamp) else {
        return Err("advance stamp is missing or malformed")
      }
      guard command.get("source_effect") is Some(Json::Object(effect)) else {
        return Err("advance source_effect must be an object")
      }
      guard projection_worker_decode_string(effect, "kind") is Some(effect_kind) else {
        return Err("source_effect kind is missing")
      }
      match effect_kind {
        "replace-source" => {
          guard projection_worker_decode_string(effect, "source")
            is Some(source) else {
            return Err("replacement source is missing")
          }
          Ok(
            (request_id, WorkerAdvance(stamp, ReplaceProjectionSource(source))),
          )
        }
        "source-unchanged" =>
          Ok((request_id, WorkerAdvance(stamp, ProjectionSourceUnchanged)))
        _ => Err("unknown source_effect kind")
      }
    }
    "demand" => {
      guard command.get("stamp") is Some(Json::Object(stamp_fields)) &&
        projection_worker_decode_stamp(stamp_fields) is Some(stamp) else {
        return Err("demand stamp is missing or malformed")
      }
      guard command.get("demand") is Some(Json::Object(demand)) &&
        projection_worker_decode_demand(demand) is Some(decoded) else {
        return Err(
          "demand must contain boolean block, preview, and diagnostics",
        )
      }
      Ok((request_id, WorkerDemand(stamp, decoded)))
    }
    "snapshot" => Ok((request_id, WorkerSnapshot))
    "dispose" => Ok((request_id, WorkerDispose))
    _ => Err("unknown command kind")
  }
}

///|
fn projection_worker_range_json(range : (Int, Int)) -> Json {
  Json::array([
    Json::number(range.0.to_double()),
    Json::number(range.1.to_double()),
  ])
}

///|
fn projection_worker_optional_range_json(range : (Int, Int)?) -> Json {
  match range {
    Some(value) => projection_worker_range_json(value)
    None => Json::null()
  }
}

///|
fn projection_worker_optional_string_json(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn normalized_block_kind_json(kind : NormalizedBlockKind) -> Json {
  match kind {
    NormalizedParagraph => Json::object({ "kind": Json::string("paragraph") })
    NormalizedHeading(level) =>
      Json::object({
        "kind": Json::string("heading"),
        "level": Json::number(level.to_double()),
      })
    NormalizedUnorderedListItem =>
      Json::object({ "kind": Json::string("unordered-list-item") })
    NormalizedOrderedListItem(start, delimiter) =>
      Json::object({
        "kind": Json::string("ordered-list-item"),
        "start": Json::number(start.to_double()),
        "delimiter": Json::string(delimiter),
      })
    NormalizedCodeBlock(info) =>
      Json::object({
        "kind": Json::string("code-block"),
        "info": Json::string(info),
      })
  }
}

///|
fn normalized_block_json(block : NormalizedBlock) -> Json {
  Json::object({
    "key": Json::string(block.key),
    "kind": normalized_block_kind_json(block.kind),
    "source_range": projection_worker_range_json(block.source_range),
    "text_range": projection_worker_range_json(block.text_range),
    "marker_range": projection_worker_optional_range_json(block.marker_range),
    "fence_open_range": projection_worker_optional_range_json(
      block.fence_open_range,
    ),
    "fence_close_range": projection_worker_optional_range_json(
      block.fence_close_range,
    ),
    "text": Json::string(block.text),
  })
}

///|
fn normalized_role_json(role : NormalizedRoleSpan) -> Json {
  Json::object({
    "start": Json::number(role.start.to_double()),
    "end": Json::number(role.end.to_double()),
    "role": Json::string(role.role),
  })
}

///|
fn normalized_resolver_evidence_json(
  evidence : NormalizedResolverEvidence,
) -> Json {
  Json::object({
    "key": Json::string(evidence.key),
    "source_start": Json::number(evidence.source_start.to_double()),
    "source_end": Json::number(evidence.source_end.to_double()),
  })
}

///|
fn normalized_block_projection_json(
  projection : NormalizedBlockProjection,
) -> Json {
  Json::object({
    "source": Json::string(projection.source),
    "blocks": Json::array(projection.blocks.map(normalized_block_json)),
    "node_keys": Json::array(projection.node_keys.map(Json::string)),
    "roles": Json::array(projection.roles.map(normalized_role_json)),
    "resolver_evidence": Json::array(
      projection.resolver_evidence.map(normalized_resolver_evidence_json),
    ),
  })
}

///|
fn normalized_preview_projection_json(
  projection : NormalizedPreviewProjection,
) -> Json {
  Json::object({
    "source": Json::string(projection.source),
    "artifact": projection_preview_artifact_json(projection.artifact),
  })
}

///|
fn normalized_diagnostic_label_json(label : NormalizedDiagnosticLabel) -> Json {
  Json::object({
    "source": Json::string(label.source),
    "start": Json::number(label.start.to_double()),
    "end": Json::number(label.end.to_double()),
    "style": Json::string(label.style),
    "message": projection_worker_optional_string_json(label.message),
  })
}

///|
fn normalized_diagnostic_json(diagnostic : NormalizedDiagnostic) -> Json {
  Json::object({
    "origin": Json::string(diagnostic.origin),
    "severity": Json::string(diagnostic.severity),
    "message": Json::string(diagnostic.message),
    "code": projection_worker_optional_string_json(diagnostic.code),
    "labels": Json::array(
      diagnostic.labels.map(normalized_diagnostic_label_json),
    ),
    "notes": Json::array(diagnostic.notes.map(Json::string)),
  })
}

///|
fn projection_worker_stamp_json(stamp : ProjectionStamp) -> Json {
  Json::object({
    "generation": Json::number(stamp.generation.to_double()),
    "sequence": Json::number(stamp.sequence.to_double()),
    "source_revision": Json::number(stamp.source_revision.to_double()),
    "causal_version": Json::string(stamp.causal_version),
    "block_intent": Json::number(stamp.block_intent.to_double()),
  })
}

///|
fn projection_worker_metrics_json(session : ProjectionSession) -> Json {
  Json::object({
    "pending_advance_count": Json::number(
      session.adapter.queued_advance_count().to_double(),
    ),
    "pending_encoded_bytes": Json::number(
      session.adapter.queued_encoded_bytes().to_double(),
    ),
    "pending_source_effect_bytes": Json::number(
      session.adapter.queued_source_effect_bytes().to_double(),
    ),
    "generation": Json::number(session.stamp().generation.to_double()),
    "sequence": Json::number(session.stamp().sequence.to_double()),
  })
}

///|
fn projection_worker_error_response(
  request_id : Int,
  kind : String,
  detail : String,
) -> String {
  Json::object({
    "schema_version": Json::string("1"),
    "request_id": Json::number(request_id.to_double()),
    "kind": Json::string("error"),
    "error": Json::object({
      "kind": Json::string(kind),
      "detail": Json::string(detail),
    }),
  }).stringify()
}

///|
fn projection_worker_observables_json(
  session : ProjectionSession,
) -> Json raise Failure {
  let artifacts = session.adapter.adopted_artifacts()
  let fields : Map[String, Json] = Map([])
  if session.demand.block {
    guard artifacts.get(Block) is Some(BlockArtifact(block)) else {
      raise Failure::Failure("demanded Block artifact is unavailable")
    }
    fields["block"] = normalized_block_projection_json(block)
  }
  if session.demand.preview {
    guard artifacts.get(Preview) is Some(PreviewArtifact(preview)) else {
      raise Failure::Failure("demanded Preview artifact is unavailable")
    }
    fields["preview"] = normalized_preview_projection_json(preview)
  }
  if session.demand.diagnostics {
    guard artifacts.get(Diagnostics) is Some(DiagnosticsArtifact(diagnostics)) else {
      raise Failure::Failure("demanded Diagnostics artifact is unavailable")
    }
    fields["diagnostics"] = Json::array(
      diagnostics.map(normalized_diagnostic_json),
    )
  }
  Json::object(fields)
}

///|
fn projection_worker_ok_response(
  request_id : Int,
  session : ProjectionSession,
) -> String raise {
  Json::object({
    "schema_version": Json::string("1"),
    "request_id": Json::number(request_id.to_double()),
    "kind": Json::string("ok"),
    "stamp": projection_worker_stamp_json(session.stamp()),
    "observables": projection_worker_observables_json(session),
    "metrics": projection_worker_metrics_json(session),
  }).stringify()
}

///|
fn projection_worker_disposed_response(request_id : Int) -> String {
  Json::object({
    "schema_version": Json::string("1"),
    "request_id": Json::number(request_id.to_double()),
    "kind": Json::string("ok"),
    "disposed": Json::boolean(true),
  }).stringify()
}

///|
pub fn new_projection_worker_dispatcher() -> (String) -> String {
  let session : @ref.Ref[ProjectionSession?] = @ref.Ref(None)
  let disposed : @ref.Ref[Bool] = @ref.Ref(false)
  raw => {
    let decoded = projection_worker_decode_request(raw)
    guard decoded is Ok((request_id, command)) else {
      let detail = match decoded {
        Err(value) => value
        _ => "invalid request"
      }
      return projection_worker_error_response(-1, "decode-failed", detail)
    }
    match command {
      WorkerSeed(agent_id, source, stamp, demand) => {
        guard !disposed.val else {
          return projection_worker_error_response(
            request_id, "disposed", "dispatcher is disposed",
          )
        }
        guard session.val is None && stamp.generation > 0 else {
          return projection_worker_error_response(
            request_id, "invalid-state", "Seed requires an empty dispatcher and positive generation",
          )
        }
        let created = ProjectionSession::ProjectionSession(
          agent_id~,
          source~,
          stamp~,
          demand~,
        ) catch {
          error =>
            return projection_worker_error_response(
              request_id,
              "execution-failed",
              error.to_string(),
            )
        }
        session.val = Some(created)
        projection_worker_ok_response(request_id, created) catch {
          error =>
            projection_worker_error_response(
              request_id,
              "execution-failed",
              error.to_string(),
            )
        }
      }
      WorkerAdvance(stamp, effect) => {
        guard !disposed.val else {
          return projection_worker_error_response(
            request_id, "disposed", "dispatcher is disposed",
          )
        }
        guard session.val is Some(active) else {
          return projection_worker_error_response(
            request_id, "invalid-state", "Advance requires Seed",
          )
        }
        active.advance(effect, stamp~) catch {
          error =>
            return projection_worker_error_response(
              request_id,
              "execution-failed",
              error.to_string(),
            )
        }
        projection_worker_ok_response(request_id, active) catch {
          error =>
            projection_worker_error_response(
              request_id,
              "execution-failed",
              error.to_string(),
            )
        }
      }
      WorkerDemand(stamp, demand) => {
        guard !disposed.val else {
          return projection_worker_error_response(
            request_id, "disposed", "dispatcher is disposed",
          )
        }
        guard session.val is Some(active) else {
          return projection_worker_error_response(
            request_id, "invalid-state", "Demand requires Seed",
          )
        }
        active.demand(demand, stamp~) catch {
          error =>
            return projection_worker_error_response(
              request_id,
              "execution-failed",
              error.to_string(),
            )
        }
        projection_worker_ok_response(request_id, active) catch {
          error =>
            projection_worker_error_response(
              request_id,
              "execution-failed",
              error.to_string(),
            )
        }
      }
      WorkerSnapshot => {
        guard !disposed.val else {
          return projection_worker_error_response(
            request_id, "disposed", "dispatcher is disposed",
          )
        }
        guard session.val is Some(active) else {
          return projection_worker_error_response(
            request_id, "invalid-state", "Snapshot requires Seed",
          )
        }
        projection_worker_ok_response(request_id, active) catch {
          error =>
            projection_worker_error_response(
              request_id,
              "execution-failed",
              error.to_string(),
            )
        }
      }
      WorkerDispose => {
        if session.val is Some(active) {
          active.dispose()
          session.val = None
        }
        disposed.val = true
        projection_worker_disposed_response(request_id)
      }
    }
  }
}
