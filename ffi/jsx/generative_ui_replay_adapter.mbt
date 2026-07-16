///|
/// Decode and commit the concrete JSON candidate used by the GenUI replay demo.
/// The adapter owns the wire format; cognition owns validation and lifecycle
/// policy, while the JSX session owns dry-run and DOM commit effects.
const GENUI_MAX_CAPABILITIES_LENGTH : Int = 64 * 1024

///|
const GENUI_MAX_CAPABILITY_BINDINGS : Int = 256

///|
const GENUI_MAX_CAPABILITY_FIELDS : Int = 64

///|
const GENUI_MAX_CAPABILITY_SELECTION_KEYS : Int = 32

///|
const GENUI_MAX_CAPABILITY_OPERATORS : Int = 32

///|
const GENUI_MAX_CAPABILITY_AGGREGATIONS : Int = 32

///|
priv struct SessionErrorJson {
  code : String
  message : String
} derive(@json.FromJson)

///|
priv struct SessionResultJson {
  schema_version : Int
  success : Bool
  revision : Int
  mounted_ids : Array[String]
  diagnostics : Array[String]
  error : SessionErrorJson?
}

///|
priv struct RawAttributeJson {
  name : String
  value : String
} derive(@json.FromJson)

///|
priv struct RawNodeJson {
  node_type : String
  name : String?
  value : String?
  attributes : Array[RawAttributeJson]?
  children : Array[RawNodeJson]?
}

///|
priv struct BindingJson {
  name : String
  fields : Array[String]
  selection_keys : Array[String]
} derive(@json.FromJson)

///|
priv struct CapabilitiesJson {
  bindings : Array[BindingJson]
  filter_operators : Array[String]
  aggregations : Array[String]
} derive(@json.FromJson)

///|
fn[T : FromJson] require_json_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> T raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(value) => @json.from_json(value, path=path.add_key(key))
    None =>
      raise @json.JsonDecodeError(
        (path.add_key(key), "missing JSON field: " + key),
      )
  }
}

///|
fn[T : FromJson] optional_json_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> T? raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(Json::Null) => None
    Some(value) => Some(@json.from_json(value, path=path.add_key(key)))
    None => None
  }
}

///|
impl @json.FromJson for SessionResultJson with fn from_json(json, path) {
  let fields = match json {
    Json::Object(fields) => fields
    _ => raise @json.JsonDecodeError((path, "session result must be an object"))
  }
  {
    schema_version: require_json_field(fields, path, "schema_version"),
    success: require_json_field(fields, path, "success"),
    revision: require_json_field(fields, path, "revision"),
    mounted_ids: require_json_field(fields, path, "mounted_ids"),
    diagnostics: require_json_field(fields, path, "diagnostics"),
    error: optional_json_field(fields, path, "error"),
  }
}

///|
impl @json.FromJson for RawNodeJson with fn from_json(json, path) {
  let fields = match json {
    Json::Object(fields) => fields
    _ => raise @json.JsonDecodeError((path, "candidate node must be an object"))
  }
  {
    node_type: require_json_field(fields, path, "type"),
    name: optional_json_field(fields, path, "name"),
    value: optional_json_field(fields, path, "value"),
    attributes: optional_json_field(fields, path, "attributes"),
    children: optional_json_field(fields, path, "children"),
  }
}

///|
pub fn jsx_session_replay_candidate_json(
  handle : Int,
  base_revision : Int,
  chunks_input : String,
  capabilities_json : String,
) -> String {
  let revision = @cognition.GenerativeUiRevision::GenerativeUiRevision(
    base_revision,
  )
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
  let session_revision = session.baseline.revision
  guard session_revision == base_revision else {
    return render_result_json(
      false,
      session_revision,
      session.mounted_ids,
      [],
      Some(
        (
          "BaseRevisionMismatch", "candidate base revision does not match the session revision",
        ),
      ),
    )
  }
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
  guard chunks_input.length() <=
    @cognition.GENERATIVE_UI_MAX_SOURCE_LENGTH +
    @cognition.GENERATIVE_UI_MAX_CHUNKS else {
    return render_result_json(
      false,
      base_revision,
      session.mounted_ids,
      [],
      Some(("InputRejected", "replay input exceeds the generation limit")),
    )
  }
  let chunk_count = chunks_input.fold(init=1, (count, character) => {
    if character == '\u{0000}' {
      count + 1
    } else {
      count
    }
  })
  guard chunk_count <= @cognition.GENERATIVE_UI_MAX_CHUNKS else {
    return render_result_json(
      false,
      base_revision,
      session.mounted_ids,
      [],
      Some(("InputRejected", "chunk count exceeds the generation limit")),
    )
  }
  let chunks : Array[String] = [
    for part in chunks_input.split("\u0000") => part.to_owned()
  ]
  let events : Array[@cognition.GenerativeUiInput] = [
    for sequence, payload in chunks => {
      @cognition.GenerativeUiInput::chunk(
        generation_id~,
        base_revision=revision,
        sequence~,
        payload~,
      )
    }
  ]
  events.push(
    @cognition.GenerativeUiInput::finalize(
      generation_id~,
      base_revision=revision,
      sequence=chunks.length(),
    ),
  )
  let source = @cognition.GenerativeUiReplaySource::GenerativeUiReplaySource(
    events~,
  )
  let mut saw_final = false
  while source.next() is Some(input) {
    match lifecycle.dispatch(@cognition.GenerativeUiEvent::Input(input)) {
      @cognition.GenerativeUiTransition::ChunkAccepted(_) => ()
      @cognition.GenerativeUiTransition::DuplicateChunk(_) => ()
      @cognition.GenerativeUiTransition::Finalized => saw_final = true
      transition =>
        return render_result_json(
          false,
          base_revision,
          session.mounted_ids,
          [],
          Some(("InputRejected", replay_transition_message(transition))),
        )
    }
  }
  guard saw_final else {
    return render_result_json(
      false,
      base_revision,
      session.mounted_ids,
      [],
      Some(("InputRejected", "replay did not finalize")),
    )
  }
  commit_candidate_with_lifecycle(
    session, handle, revision, lifecycle, generation_id, capabilities_json,
  )
}

///|
/// Decode, capability-check, and validate the replay payload into the opaque
/// candidate consumed by the session transaction.
fn decode_validated_candidate(
  candidate_source : String,
  capabilities_json : String,
) -> Result[@cognition.GenerativeUiCandidate, (String, String, Array[String])] {
  let raw = match decode_candidate_json(candidate_source) {
    Ok(value) => value
    Err(message) => return Err(("CandidateDecodeError", message, []))
  }
  let capabilities = match decode_capabilities_json(capabilities_json) {
    Ok(value) => value
    Err(message) => return Err(("CapabilityDecodeError", message, []))
  }
  match @cognition.GenerativeUiCandidate::validate(raw~, capabilities~) {
    Ok(candidate) => Ok(candidate)
    Err(diagnostics) => {
      let messages = diagnostics.map(diagnostic => {
        "\{diagnostic.path()}: \{diagnostic.detail()}"
      })
      Err(("CandidateValidationError", "candidate rejected", messages))
    }
  }
}

///|
/// Validate and commit a candidate using the caller-owned lifecycle.
/// Transport adapters call this after their lifecycle accepted Final; the
/// session remains the only owner of dry-run, DOM apply, and revision commit.
fn commit_candidate_with_lifecycle(
  session : JsxSession,
  handle : Int,
  revision : @cognition.GenerativeUiRevision,
  lifecycle : @cognition.GenerativeUiLifecycle,
  generation_id : @cognition.GenerativeUiGenerationId,
  capabilities_json : String,
) -> String {
  match
    decode_validated_candidate(lifecycle.candidate_source(), capabilities_json) {
    Ok(candidate) =>
      commit_validated_candidate_transaction(
        session, handle, revision, lifecycle, generation_id, candidate,
      )
    Err((error_code, error_message, diagnostics)) => {
      let invalid_message = if diagnostics.is_empty() {
        error_message
      } else {
        diagnostics.join("; ")
      }
      let _ = lifecycle.dispatch(
        @cognition.GenerativeUiEvent::CandidateInvalid(
          generation_id~,
          message=invalid_message,
        ),
      )
      render_result_json(
        false,
        revision.to_int(),
        session.mounted_ids,
        diagnostics,
        Some((error_code, error_message)),
      )
    }
  }
}

///|
fn commit_validated_candidate_transaction(
  session : JsxSession,
  handle : Int,
  revision : @cognition.GenerativeUiRevision,
  lifecycle : @cognition.GenerativeUiLifecycle,
  generation_id : @cognition.GenerativeUiGenerationId,
  candidate : @cognition.GenerativeUiCandidate,
) -> String {
  let current_revision = session.baseline.revision
  let current_revision_value = @cognition.GenerativeUiRevision::GenerativeUiRevision(
    current_revision,
  )
  match
    lifecycle.dispatch(
      @cognition.GenerativeUiEvent::CandidateValid(
        generation_id~,
        current_revision=current_revision_value,
      ),
    ) {
    @cognition.GenerativeUiTransition::DryRunStarted => ()
    @cognition.GenerativeUiTransition::Rejected(
      reason=@cognition.GenerativeUiRejection::BaseRevisionMismatch(..)
    ) =>
      return render_result_json(
        false,
        current_revision,
        session.mounted_ids,
        [],
        Some(("BaseRevisionMismatch", "candidate base revision is stale")),
      )
    transition =>
      return render_result_json(
        false,
        revision.to_int(),
        session.mounted_ids,
        [],
        Some(("CandidateRejected", replay_transition_message(transition))),
      )
  }
  let result = jsx_session_commit_candidate(handle, revision, candidate)
  let result_json = @json.parse(result) catch {
    _ =>
      return render_result_json(
        false,
        revision.to_int(),
        session.mounted_ids,
        [],
        Some(("SessionError", "session returned invalid JSON")),
      )
  }
  let session_result : SessionResultJson = @json.from_json(result_json) catch {
    _ =>
      return render_result_json(
        false,
        revision.to_int(),
        session.mounted_ids,
        [],
        Some(("SessionError", "session returned invalid JSON shape")),
      )
  }
  let _ = session_result.schema_version
  let _ = session_result.mounted_ids
  let _ = session_result.diagnostics
  if session_result.success {
    let _ = lifecycle.dispatch(
      @cognition.GenerativeUiEvent::DryRunSucceeded(generation_id~),
    )
    let _ = lifecycle.dispatch(
      @cognition.GenerativeUiEvent::ApplySucceeded(
        generation_id~,
        revision=@cognition.GenerativeUiRevision::GenerativeUiRevision(
          session_result.revision,
        ),
      ),
    )
  } else {
    let (error_code, error_message) = match session_result.error {
      Some(error) => (error.code, error.message)
      None => ("SessionError", "session commit failed")
    }
    match error_code {
      "DryRunError" => {
        let _ = lifecycle.dispatch(
          @cognition.GenerativeUiEvent::DryRunFailed(
            generation_id~,
            message=error_message,
          ),
        )
      }
      "DomApplyError" => {
        let _ = lifecycle.dispatch(
          @cognition.GenerativeUiEvent::DryRunSucceeded(generation_id~),
        )
        let _ = lifecycle.dispatch(
          @cognition.GenerativeUiEvent::ApplyFailed(
            generation_id~,
            message=error_message,
          ),
        )
      }
      "BaseRevisionMismatch"
      | "CandidateLoweringError"
      | "ProjectionUnavailable"
      | "ProjectionError" => ()
      _ => ()
    }
  }
  result
}

///|
fn replay_transition_message(
  transition : @cognition.GenerativeUiTransition,
) -> String {
  match transition {
    @cognition.GenerativeUiTransition::Rejected(
      reason=@cognition.GenerativeUiRejection::InputLimitExceeded(limit~)
    ) =>
      match limit {
        @cognition.GenerativeUiInputLimit::ChunkLength =>
          "chunk length exceeds the generation limit"
        @cognition.GenerativeUiInputLimit::ChunkCount =>
          "chunk count exceeds the generation limit"
        @cognition.GenerativeUiInputLimit::SourceLength =>
          "candidate source exceeds the generation limit"
      }
    @cognition.GenerativeUiTransition::Ignored(
      reason=@cognition.GenerativeUiIgnoreReason::StaleGeneration
    ) => "stale generation input"
    _ => "generation input was not accepted"
  }
}

///|
fn decode_candidate_json(
  source : String,
) -> Result[@cognition.GenerativeUiRawNode, String] {
  let json = @json.parse(source) catch {
    _ => return Err("candidate JSON is invalid")
  }
  match validate_raw_node_limits(json, 0, 0) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  let payload : RawNodeJson = @json.from_json(json) catch {
    _ => return Err("candidate JSON has an invalid shape")
  }
  lower_raw_node(payload)
}

///|
fn validate_raw_node_limits(
  json : Json,
  depth : Int,
  nodes : Int,
) -> Result[Int, String] {
  guard depth <= @cognition.GENERATIVE_UI_MAX_DEPTH else {
    return Err("candidate nesting exceeds the validation limit")
  }
  guard nodes < @cognition.GENERATIVE_UI_MAX_NODES else {
    return Err("candidate node count exceeds the validation limit")
  }
  let next_nodes = nodes + 1
  guard json is Json::Object(fields) else {
    return Err("candidate node must be an object")
  }
  let node_type = match fields.get("type") {
    Some(Json::String(value)) => value
    _ => return Err("candidate node type is missing or invalid")
  }
  match node_type {
    "text" | "raw_html" | "expression" => {
      let attributes = match fields.get("attributes") {
        None | Some(Json::Null) => []
        Some(Json::Array(values)) => values
        _ => return Err("leaf node attributes must be an array")
      }
      guard attributes.is_empty() else {
        return Err("leaf node cannot have attributes")
      }
      let children = match fields.get("children") {
        None | Some(Json::Null) => []
        Some(Json::Array(values)) => values
        _ => return Err("leaf node children must be an array")
      }
      guard children.is_empty() else {
        return Err("leaf node cannot have children")
      }
      Ok(next_nodes)
    }
    "component" => {
      let attributes = match fields.get("attributes") {
        Some(Json::Array(values)) => values
        _ => return Err("component attributes are missing or invalid")
      }
      guard attributes.length() <= @cognition.GENERATIVE_UI_MAX_ATTRIBUTES else {
        return Err("component attribute count exceeds the validation limit")
      }
      let children = match fields.get("children") {
        Some(Json::Array(values)) => values
        _ => return Err("component children are missing or invalid")
      }
      let mut node_count = next_nodes
      for child in children {
        match validate_raw_node_limits(child, depth + 1, node_count) {
          Ok(updated_count) => node_count = updated_count
          Err(message) => return Err(message)
        }
      }
      Ok(node_count)
    }
    _ => Err("unknown candidate node type: " + node_type)
  }
}

///|
fn lower_raw_node(
  payload : RawNodeJson,
) -> Result[@cognition.GenerativeUiRawNode, String] {
  match payload.node_type {
    "text" =>
      match payload.value {
        Some(value) => Ok(@cognition.GenerativeUiRawNode::Text(value~))
        None => Err("text node value is missing or invalid")
      }
    "raw_html" =>
      match payload.value {
        Some(value) => Ok(@cognition.GenerativeUiRawNode::RawHtml(value~))
        None => Err("raw_html node value is missing or invalid")
      }
    "expression" =>
      match payload.value {
        Some(value) => Ok(@cognition.GenerativeUiRawNode::Expression(value~))
        None => Err("expression node value is missing or invalid")
      }
    "component" =>
      match (payload.name, payload.attributes, payload.children) {
        (Some(name), Some(attributes), Some(children)) => {
          let lowered_attributes = attributes.map(attr => {
            @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
              name=attr.name,
              value=attr.value,
            )
          })
          let lowered_children : Array[@cognition.GenerativeUiRawNode] = []
          for child in children {
            match lower_raw_node(child) {
              Ok(value) => lowered_children.push(value)
              Err(message) => return Err(message)
            }
          }
          Ok(
            @cognition.GenerativeUiRawNode::Component(
              name~,
              attributes=lowered_attributes,
              children=lowered_children,
            ),
          )
        }
        _ => Err("component fields are missing or invalid")
      }
    _ => Err("unknown candidate node type: " + payload.node_type)
  }
}

///|
fn validate_capability_string_array(
  values : Array[Json],
  limit : Int,
  label : String,
) -> Result[Unit, String] {
  guard values.length() <= limit else {
    return Err(label + " count exceeds the generation limit")
  }
  for value in values {
    guard value is Json::String(text) else {
      return Err(label + " must contain strings")
    }
    guard text.length() <= @cognition.GENERATIVE_UI_MAX_STRING_LENGTH else {
      return Err(label + " contains an oversized string")
    }
  }
  Ok(())
}

///|
fn validate_capability_binding(json : Json) -> Result[Unit, String] {
  guard json is Json::Object(fields) else {
    return Err("capability binding must be an object")
  }
  let name = match fields.get("name") {
    Some(Json::String(value)) => value
    _ => return Err("capability binding name is missing or invalid")
  }
  guard name.length() <= @cognition.GENERATIVE_UI_MAX_STRING_LENGTH else {
    return Err("capability binding name is oversized")
  }
  let binding_fields = match fields.get("fields") {
    Some(Json::Array(values)) => values
    _ => return Err("capability binding fields are missing or invalid")
  }
  match
    validate_capability_string_array(
      binding_fields,
      GENUI_MAX_CAPABILITY_FIELDS,
      "binding fields",
    ) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  let selection_keys = match fields.get("selection_keys") {
    Some(Json::Array(values)) => values
    _ => return Err("capability binding selection_keys are missing or invalid")
  }
  match
    validate_capability_string_array(
      selection_keys,
      GENUI_MAX_CAPABILITY_SELECTION_KEYS,
      "selection keys",
    ) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  Ok(())
}

///|
fn validate_capability_limits(json : Json) -> Result[Unit, String] {
  guard json is Json::Object(fields) else {
    return Err("capabilities must be an object")
  }
  let bindings = match fields.get("bindings") {
    Some(Json::Array(values)) => values
    _ => return Err("capability bindings are missing or invalid")
  }
  guard bindings.length() <= GENUI_MAX_CAPABILITY_BINDINGS else {
    return Err("capability bindings count exceeds the generation limit")
  }
  for binding in bindings {
    match validate_capability_binding(binding) {
      Ok(_) => ()
      Err(message) => return Err(message)
    }
  }
  let operators = match fields.get("filter_operators") {
    Some(Json::Array(values)) => values
    _ => return Err("capability filter_operators are missing or invalid")
  }
  match
    validate_capability_string_array(
      operators,
      GENUI_MAX_CAPABILITY_OPERATORS,
      "filter operators",
    ) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  let aggregations = match fields.get("aggregations") {
    Some(Json::Array(values)) => values
    _ => return Err("capability aggregations are missing or invalid")
  }
  match
    validate_capability_string_array(
      aggregations,
      GENUI_MAX_CAPABILITY_AGGREGATIONS,
      "aggregations",
    ) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  Ok(())
}

///|
fn decode_capabilities_json(
  source : String,
) -> Result[@cognition.GenerativeUiHostCapabilities, String] {
  guard source.length() <= GENUI_MAX_CAPABILITIES_LENGTH else {
    return Err("capabilities JSON exceeds the generation limit")
  }
  let json = @json.parse(source) catch {
    _ => return Err("capabilities JSON is invalid")
  }
  match validate_capability_limits(json) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  let payload : CapabilitiesJson = @json.from_json(json) catch {
    _ => return Err("capabilities JSON has an invalid shape")
  }
  let bindings = payload.bindings.map(binding => {
    @cognition.GenerativeUiBindingCapabilities::GenerativeUiBindingCapabilities(
      name=binding.name,
      fields=binding.fields,
      selection_keys=binding.selection_keys,
    )
  })
  let filter_operators = decode_filter_operators(payload.filter_operators)
  let aggregations = decode_aggregations(payload.aggregations)
  match (filter_operators, aggregations) {
    (Ok(filter_operators), Ok(aggregations)) =>
      Ok(
        @cognition.GenerativeUiHostCapabilities::GenerativeUiHostCapabilities(
          bindings~,
          filter_operators~,
          aggregations~,
        ),
      )
    (Err(message), _) => Err(message)
    (_, Err(message)) => Err(message)
  }
}

///|
fn decode_filter_operators(
  values : Array[String],
) -> Result[Array[@cognition.GenerativeUiFilterOperator], String] {
  let result : Array[@cognition.GenerativeUiFilterOperator] = []
  for value in values {
    match value {
      "eq" => result.push(@cognition.GenerativeUiFilterOperator::Equal)
      "neq" => result.push(@cognition.GenerativeUiFilterOperator::NotEqual)
      "contains" => result.push(@cognition.GenerativeUiFilterOperator::Contains)
      "gt" => result.push(@cognition.GenerativeUiFilterOperator::GreaterThan)
      "lt" => result.push(@cognition.GenerativeUiFilterOperator::LessThan)
      _ => return Err("unknown filter operator: " + value)
    }
  }
  Ok(result)
}

///|
fn decode_aggregations(
  values : Array[String],
) -> Result[Array[@cognition.GenerativeUiAggregation], String] {
  let result : Array[@cognition.GenerativeUiAggregation] = []
  for value in values {
    match value {
      "count" => result.push(@cognition.GenerativeUiAggregation::Count)
      "sum" => result.push(@cognition.GenerativeUiAggregation::Sum)
      "average" => result.push(@cognition.GenerativeUiAggregation::Average)
      "min" => result.push(@cognition.GenerativeUiAggregation::Minimum)
      "max" => result.push(@cognition.GenerativeUiAggregation::Maximum)
      _ => return Err("unknown aggregation: " + value)
    }
  }
  Ok(result)
}
