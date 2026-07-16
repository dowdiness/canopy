///|
priv struct FeasibilityPreparationError {
  classification : String
  message : String
}

///|
fn FeasibilityPreparationError::FeasibilityPreparationError(
  classification : String,
  message : String,
) -> FeasibilityPreparationError {
  { classification, message }
}

///|
priv struct PreparedFeasibilityCandidate {
  candidate : @cognition.GenerativeUiCandidate
  safe_output_json : String
  safe_output_sha256 : String
  evidence_json : String
  rubric : FeasibilityRubricResult
}

///|
fn PreparedFeasibilityCandidate::PreparedFeasibilityCandidate(
  candidate : @cognition.GenerativeUiCandidate,
  safe_output_json : String,
  safe_output_sha256 : String,
  evidence_json : String,
  rubric : FeasibilityRubricResult,
) -> PreparedFeasibilityCandidate {
  { candidate, safe_output_json, safe_output_sha256, evidence_json, rubric }
}

///|
fn feasibility_json_string(value : String) -> String {
  Json::string(value).stringify()
}

///|
fn feasibility_string_array_json(values : Array[String]) -> String {
  values.map(value => feasibility_json_string(value)).join(",")
}

///|
fn feasibility_filter_operator_name(
  operator : @cognition.GenerativeUiFilterOperator,
) -> String {
  match operator {
    Equal => "equals"
    NotEqual => "not_equals"
    Contains => "contains"
    GreaterThan => "greater_than"
    LessThan => "less_than"
  }
}

///|
fn feasibility_capabilities_match_dataset(
  capabilities_json : String,
  dataset : FeasibilityDataset,
) -> Bool {
  let json = @json.parse(capabilities_json) catch { _ => return false }
  let payload : CapabilitiesJson = @json.from_json(json) catch {
    _ => return false
  }
  guard payload.bindings.length() == 1 else { return false }
  let binding = payload.bindings[0]
  binding.name == dataset.binding &&
  binding.fields == dataset.fields &&
  binding.selection_keys == [dataset.selection_key]
}

///|
fn feasibility_candidate_filter(
  candidate : @cognition.GenerativeUiCandidate,
) -> (String, @cognition.GenerativeUiFilterOperator)? {
  guard candidate.root() is Stack(children~) else { return None }
  guard children.length() == 2 else { return None }
  guard children[1] is Table(children=table_children, ..) else { return None }
  guard table_children.length() >= 2 else { return None }
  match table_children[table_children.length() - 2] {
    Filter(field~, operator~) => Some((field.to_string(), operator))
    _ => None
  }
}

///|
fn feasibility_evidence_json(evidence : FeasibilityEvidence) -> String {
  let builder = StringBuilder()
  builder
  ..write_string("{\"schema_version\":")
  ..write_string(evidence.schema_version.to_string())
  ..write_string(",\"case_id\":")
  ..write_string(feasibility_json_string(evidence.case_id))
  ..write_string(",\"source_format\":")
  ..write_string(feasibility_json_string(evidence.source_format))
  ..write_string(",\"binding\":")
  ..write_string(feasibility_json_string(evidence.binding))
  ..write_string(",\"filter\":{\"field\":")
  ..write_string(feasibility_json_string(evidence.filter_field))
  ..write_string(",\"operator\":")
  ..write_string(
    feasibility_json_string(
      feasibility_filter_operator_name(evidence.filter_operator),
    ),
  )
  ..write_string(",\"value\":")
  ..write_string(feasibility_scalar_json(evidence.filter_value))
  ..write_string("},\"projected_fields\":[")
  ..write_string(feasibility_string_array_json(evidence.projected_fields))
  ..write_string("],\"matched_stable_keys\":[")
  ..write_string(feasibility_string_array_json(evidence.matched_stable_keys))
  ..write_string("],\"summary\":{\"field\":")
  ..write_string(feasibility_json_string(evidence.summary.field))
  ..write_string(",\"aggregation\":")
  ..write_string(
    feasibility_json_string(
      feasibility_aggregation_name(evidence.summary.aggregation),
    ),
  )
  .write_string(",\"value\":")
  match evidence.summary.value {
    Numeric(value) => builder.write_string(value.to_string())
    Empty => builder.write_string("null")
  }
  builder
  ..write_string("},\"safe_output_sha256\":")
  ..write_string(feasibility_json_string(evidence.safe_output_sha256))
  .write_char('}')
  builder.to_string()
}

///|
fn feasibility_rubric_json(rubric : FeasibilityRubricResult) -> String {
  let builder = StringBuilder()
  builder
  ..write_string("{\"passed\":")
  ..write_string(if rubric.passed { "true" } else { "false" })
  ..write_string(",\"reasons\":[")
  ..write_string(feasibility_string_array_json(rubric.reasons))
  .write_string("]}")
  builder.to_string()
}

///|
fn prepare_feasibility_candidate(
  candidate_json~ : String,
  capabilities_json~ : String,
  dataset_json~ : String,
) -> Result[PreparedFeasibilityCandidate, FeasibilityPreparationError] {
  let candidate = match
    decode_validated_candidate(candidate_json, capabilities_json) {
    Ok(candidate) => candidate
    Err(("CandidateDecodeError", message, _)) =>
      return Err(FeasibilityPreparationError("candidate_decode_error", message))
    Err(("CapabilityDecodeError", message, _)) =>
      return Err(
        FeasibilityPreparationError("capability_decode_error", message),
      )
    Err((_, message, _)) =>
      return Err(
        FeasibilityPreparationError("candidate_validation_error", message),
      )
  }
  let dataset = match decode_feasibility_dataset(dataset_json) {
    Ok(dataset) => dataset
    Err(message) =>
      return Err(FeasibilityPreparationError("dataset_decode_error", message))
  }
  guard feasibility_capabilities_match_dataset(capabilities_json, dataset) else {
    return Err(
      FeasibilityPreparationError(
        "capability_decode_error", "capabilities differ from the normalized dataset",
      ),
    )
  }
  let materialized = match
    materialize_feasibility_candidate(candidate, dataset) {
    Ok(materialized) => materialized
    Err(message) =>
      return Err(FeasibilityPreparationError("materialization_error", message))
  }
  let (filter_field, filter_operator) = match
    feasibility_candidate_filter(candidate) {
    Some(filter) => filter
    None =>
      return Err(
        FeasibilityPreparationError(
          "materialization_error", "candidate filter topology is invalid",
        ),
      )
  }
  let evidence = FeasibilityEvidence(
    dataset.schema_version,
    dataset.case_id,
    dataset.source_format,
    dataset.binding,
    filter_field,
    filter_operator,
    dataset.task_value,
    materialized.projected_fields,
    materialized.matched_stable_keys,
    materialized.summary,
    materialized.safe_output_sha256,
  )
  let evidence_json = feasibility_evidence_json(evidence)
  let rubric = score_feasibility_evidence(evidence)
  Ok(
    PreparedFeasibilityCandidate(
      materialized.candidate,
      materialized.safe_output_json,
      materialized.safe_output_sha256,
      evidence_json,
      rubric,
    ),
  )
}

///|
fn feasibility_error_json(error : FeasibilityPreparationError) -> String {
  "{\"schema_version\":1,\"classification\":" +
  feasibility_json_string(error.classification) +
  ",\"message\":" +
  feasibility_json_string(error.message) +
  ",\"evidence\":null,\"rubric\":null,\"safe_output\":null,\"safe_output_sha256\":null,\"session\":null}"
}

///|
fn feasibility_prepared_json(
  prepared : PreparedFeasibilityCandidate,
  classification : String,
  session_json : String,
) -> String {
  "{\"schema_version\":1,\"classification\":" +
  feasibility_json_string(classification) +
  ",\"evidence\":" +
  prepared.evidence_json +
  ",\"rubric\":" +
  feasibility_rubric_json(prepared.rubric) +
  ",\"safe_output\":" +
  prepared.safe_output_json +
  ",\"safe_output_sha256\":" +
  feasibility_json_string(prepared.safe_output_sha256) +
  ",\"session\":" +
  session_json +
  "}"
}

///|
fn feasibility_session_classification(session_json : String) -> String {
  let json = @json.parse(session_json) catch { _ => return "commit_failure" }
  guard json is Json::Object(fields) else { return "commit_failure" }
  match fields.get("success") {
    Some(Json::True) => "success"
    Some(Json::False) =>
      match fields.get("error") {
        Some(Json::Object(error_fields)) =>
          match error_fields.get("code") {
            Some(Json::String("BaseRevisionMismatch")) => "replay_mismatch"
            _ => "commit_failure"
          }
        _ => "commit_failure"
      }
    _ => "commit_failure"
  }
}

///|
fn feasibility_commit_session(
  handle : Int,
  base_revision : Int,
  prepared : PreparedFeasibilityCandidate,
) -> String {
  let session = match session_registry.get(handle) {
    Some(session) => session
    None => {
      let error = if disposed_session_handles.contains(handle) {
        ("DisposedSession", "session handle has been disposed")
      } else {
        ("InvalidSession", "unknown session handle")
      }
      return render_result_json(false, 0, [], [], Some(error))
    }
  }
  let revision = @cognition.GenerativeUiRevision::GenerativeUiRevision(
    base_revision,
  )
  let lifecycle = @cognition.GenerativeUiLifecycle::GenerativeUiLifecycle()
  let generation_id = match
    lifecycle.dispatch(
      @cognition.GenerativeUiEvent::Start(base_revision=revision),
    ) {
    @cognition.GenerativeUiTransition::Started(generation_id~) => generation_id
    _ =>
      return render_result_json(
        false,
        base_revision,
        session.mounted_ids,
        [],
        Some(("ReplayError", "failed to start generation")),
      )
  }
  let finalized = lifecycle.dispatch(
    @cognition.GenerativeUiEvent::Input(
      @cognition.GenerativeUiInput::finalize(
        generation_id~,
        base_revision=revision,
        sequence=0,
      ),
    ),
  )
  guard finalized is @cognition.GenerativeUiTransition::Finalized else {
    return render_result_json(
      false,
      base_revision,
      session.mounted_ids,
      [],
      Some(("ReplayError", "failed to finalize generation")),
    )
  }
  commit_validated_candidate_transaction(
    session,
    handle,
    revision,
    lifecycle,
    generation_id,
    prepared.candidate,
  )
}

///|
pub fn __jsx_evaluate_feasibility_candidate_json(
  candidate_json : String,
  capabilities_json : String,
  dataset_json : String,
) -> String {
  match
    prepare_feasibility_candidate(
      candidate_json~,
      capabilities_json~,
      dataset_json~,
    ) {
    Ok(prepared) => {
      let classification = if prepared.rubric.passed {
        "success"
      } else {
        "rubric_failure"
      }
      feasibility_prepared_json(prepared, classification, "null")
    }
    Err(error) => feasibility_error_json(error)
  }
}

///|
pub fn __jsx_commit_feasibility_candidate_json(
  handle : Int,
  base_revision : Int,
  candidate_json : String,
  capabilities_json : String,
  dataset_json : String,
) -> String {
  match
    prepare_feasibility_candidate(
      candidate_json~,
      capabilities_json~,
      dataset_json~,
    ) {
    Err(error) => feasibility_error_json(error)
    Ok(prepared) => {
      guard prepared.rubric.passed else {
        return feasibility_prepared_json(prepared, "rubric_failure", "null")
      }
      let session_json = feasibility_commit_session(
        handle, base_revision, prepared,
      )
      feasibility_prepared_json(
        prepared,
        feasibility_session_classification(session_json),
        session_json,
      )
    }
  }
}
