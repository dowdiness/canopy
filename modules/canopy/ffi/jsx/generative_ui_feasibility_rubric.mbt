///|
priv struct FeasibilityEvidence {
  schema_version : Int
  case_id : String
  source_format : String
  binding : String
  filter_field : String
  filter_operator : @cognition.GenerativeUiFilterOperator
  filter_value : FeasibilityScalar
  projected_fields : Array[String]
  matched_stable_keys : Array[String]
  summary : FeasibilitySummary
  safe_output_sha256 : String
}

///|
fn FeasibilityEvidence::FeasibilityEvidence(
  schema_version : Int,
  case_id : String,
  source_format : String,
  binding : String,
  filter_field : String,
  filter_operator : @cognition.GenerativeUiFilterOperator,
  filter_value : FeasibilityScalar,
  projected_fields : Array[String],
  matched_stable_keys : Array[String],
  summary : FeasibilitySummary,
  safe_output_sha256 : String,
) -> FeasibilityEvidence {
  {
    schema_version,
    case_id,
    source_format,
    binding,
    filter_field,
    filter_operator,
    filter_value,
    projected_fields: projected_fields.copy(),
    matched_stable_keys: matched_stable_keys.copy(),
    summary,
    safe_output_sha256,
  }
}

///|
priv struct FeasibilityRubricExpectation {
  filter_field : String
  filter_operator : @cognition.GenerativeUiFilterOperator
  required_projected_fields : Array[String]
  matched_stable_keys : Array[String]
  summary_field : String
  summary_aggregation : @cognition.GenerativeUiAggregation
  summary_value : Double
}

///|
fn FeasibilityRubricExpectation::FeasibilityRubricExpectation(
  filter_field : String,
  filter_operator : @cognition.GenerativeUiFilterOperator,
  required_projected_fields : Array[String],
  matched_stable_keys : Array[String],
  summary_field : String,
  summary_aggregation : @cognition.GenerativeUiAggregation,
  summary_value : Double,
) -> FeasibilityRubricExpectation {
  {
    filter_field,
    filter_operator,
    required_projected_fields,
    matched_stable_keys,
    summary_field,
    summary_aggregation,
    summary_value,
  }
}

///|
priv struct FeasibilityRubricResult {
  passed : Bool
  reasons : Array[String]
}

///|
fn FeasibilityRubricResult::FeasibilityRubricResult(
  passed : Bool,
  reasons : Array[String],
) -> FeasibilityRubricResult {
  { passed, reasons }
}

///|
fn feasibility_rubric_expectation(
  case_id : String,
) -> FeasibilityRubricExpectation? {
  match case_id {
    "orders-pending-attention" =>
      Some(
        FeasibilityRubricExpectation(
          "status",
          Equal,
          ["id", "name", "amount"],
          ["ord-1002", "ord-1006"],
          "amount",
          Sum,
          2180.0,
        ),
      )
    "inventory-low-stock" =>
      Some(
        FeasibilityRubricExpectation(
          "on_hand",
          LessThan,
          ["sku", "product", "on_hand"],
          ["sku-001", "sku-002"],
          "on_hand",
          Sum,
          11.0,
        ),
      )
    "incidents-critical-resolution" =>
      Some(
        FeasibilityRubricExpectation(
          "severity",
          Equal,
          ["incident_id", "service", "resolution_minutes"],
          ["inc-001", "inc-003"],
          "resolution_minutes",
          Average,
          120.0,
        ),
      )
    _ => None
  }
}

///|
fn score_feasibility_evidence(
  evidence : FeasibilityEvidence,
) -> FeasibilityRubricResult {
  let reasons : Array[String] = []
  let expected = match feasibility_rubric_expectation(evidence.case_id) {
    Some(expected) => expected
    None => {
      reasons.push("fixture has no frozen rubric")
      return FeasibilityRubricResult(false, reasons)
    }
  }
  if evidence.filter_field != expected.filter_field ||
    evidence.filter_operator != expected.filter_operator {
    reasons.push("filter differs from the frozen rubric")
  }
  if !expected.required_projected_fields.all(field => {
      evidence.projected_fields.contains(field)
    }) {
    reasons.push("required projected fields are missing")
  }
  if evidence.matched_stable_keys != expected.matched_stable_keys {
    reasons.push("matched stable keys differ from the frozen rubric")
  }
  if evidence.summary.field != expected.summary_field ||
    evidence.summary.aggregation != expected.summary_aggregation {
    reasons.push("summary identity differs from the frozen rubric")
  }
  match evidence.summary.value {
    Numeric(value) if value == expected.summary_value => ()
    _ => reasons.push("summary value differs from the frozen rubric")
  }
  FeasibilityRubricResult(reasons.is_empty(), reasons)
}
