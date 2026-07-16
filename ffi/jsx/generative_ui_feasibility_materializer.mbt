///|
/// A frozen dataset scalar. String spelling is preserved for display and hash
/// stability; numbers remain numeric for filters and aggregations.
priv enum FeasibilityScalar {
  Text(String)
  Number(Double)
  Boolean(Bool)
  Null
}

///|
priv struct FeasibilityDatasetRow {
  stable_key : String
  values : Array[(String, FeasibilityScalar)]
}

///|
fn FeasibilityDatasetRow::FeasibilityDatasetRow(
  stable_key : String,
  values : Array[(String, FeasibilityScalar)],
) -> FeasibilityDatasetRow {
  { stable_key, values }
}

///|
priv struct FeasibilityDataset {
  schema_version : Int
  case_id : String
  source_format : String
  binding : String
  selection_key : String
  fields : Array[String]
  rows : Array[FeasibilityDatasetRow]
  task_value : FeasibilityScalar
}

///|
fn FeasibilityDataset::FeasibilityDataset(
  schema_version : Int,
  case_id : String,
  source_format : String,
  binding : String,
  selection_key : String,
  fields : Array[String],
  rows : Array[FeasibilityDatasetRow],
  task_value : FeasibilityScalar,
) -> FeasibilityDataset {
  {
    schema_version,
    case_id,
    source_format,
    binding,
    selection_key,
    fields,
    rows,
    task_value,
  }
}

///|
const GENUI_MAX_FEASIBILITY_DATASET_LENGTH : Int = 1024 * 1024

///|
const GENUI_MAX_FEASIBILITY_ROWS : Int = 4096

///|
fn feasibility_exact_object(
  json : Json,
  keys : Array[String],
  label : String,
) -> Result[Map[String, Json], String] {
  guard json is Json::Object(fields) else {
    return Err(label + " must be an object")
  }
  guard fields.length() == keys.length() &&
    keys.all(key => fields.contains(key)) else {
    return Err(label + " has an invalid property set")
  }
  Ok(fields)
}

///|
fn feasibility_json_string_field(
  fields : Map[String, Json],
  key : String,
) -> Result[String, String] {
  match fields.get(key) {
    Some(Json::String(value)) if !value.is_empty() => Ok(value)
    _ => Err(key + " must be a non-empty string")
  }
}

///|
fn feasibility_json_string_array(
  json : Json,
  label : String,
) -> Result[Array[String], String] {
  guard json is Json::Array(values) else {
    return Err(label + " must be an array")
  }
  guard !values.is_empty() && values.length() <= GENUI_MAX_CAPABILITY_FIELDS else {
    return Err(label + " has an invalid count")
  }
  let result : Array[String] = []
  let seen : Set[String] = Set([])
  for value in values {
    guard value is Json::String(text) && !text.is_empty() else {
      return Err(label + " must contain non-empty strings")
    }
    guard seen.add_and_check(text) else {
      return Err(label + " contains a duplicate")
    }
    result.push(text)
  }
  Ok(result)
}

///|
fn feasibility_decode_scalar(json : Json) -> Result[FeasibilityScalar, String] {
  match json {
    Json::String(value) => Ok(Text(value))
    Json::Number(value, ..) => {
      guard !value.is_nan() && !value.is_inf() else {
        return Err("number must be finite")
      }
      Ok(Number(value))
    }
    Json::True => Ok(Boolean(true))
    Json::False => Ok(Boolean(false))
    Json::Null => Ok(Null)
    _ => Err("dataset scalars must be string, number, boolean, or null")
  }
}

///|
fn feasibility_decode_row(
  json : Json,
  fields : Array[String],
  selection_key : String,
) -> Result[FeasibilityDatasetRow, String] {
  let object = match
    feasibility_exact_object(json, ["stable_key", "values"], "dataset row") {
    Ok(object) => object
    Err(message) => return Err(message)
  }
  let stable_key = match feasibility_json_string_field(object, "stable_key") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let pairs = match object.get("values") {
    Some(Json::Array(values)) => values
    _ => return Err("row values must be an array")
  }
  guard pairs.length() == fields.length() else {
    return Err("row values must cover every declared field")
  }
  let values : Array[(String, FeasibilityScalar)] = []
  let seen : Set[String] = Set([])
  for index, pair in pairs {
    guard pair is Json::Array(items) && items.length() == 2 else {
      return Err("row value must be a two-element field/scalar pair")
    }
    guard items[0] is Json::String(name) && !name.is_empty() else {
      return Err("row field name must be a non-empty string")
    }
    guard seen.add_and_check(name) else {
      return Err("row contains a duplicate field")
    }
    guard name == fields[index] else {
      return Err("row field order differs from the dataset declaration")
    }
    let scalar = match feasibility_decode_scalar(items[1]) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    values.push((name, scalar))
  }
  let selection = values.iter().find_first(pair => pair.0 == selection_key)
  guard selection is Some((_, Text(value))) && value == stable_key else {
    return Err("row selection value must equal its stable key")
  }
  Ok(FeasibilityDatasetRow(stable_key, values))
}

///|
fn decode_feasibility_dataset(
  source : String,
) -> Result[FeasibilityDataset, String] {
  guard source.length() <= GENUI_MAX_FEASIBILITY_DATASET_LENGTH else {
    return Err("dataset JSON exceeds the feasibility limit")
  }
  let json = @json.parse(source) catch {
    _ => return Err("dataset JSON is invalid")
  }
  let object = match
    feasibility_exact_object(
      json,
      [
        "schema_version", "case_id", "source_format", "binding", "selection_key",
        "fields", "rows", "task_value",
      ],
      "dataset",
    ) {
    Ok(object) => object
    Err(message) => return Err(message)
  }
  let schema_version = match object.get("schema_version") {
    Some(Json::Number(value, ..)) if value == 1.0 => 1
    _ => return Err("dataset schema_version must be 1")
  }
  let case_id = match feasibility_json_string_field(object, "case_id") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let source_format = match
    feasibility_json_string_field(object, "source_format") {
    Ok("json-array" | "json-nested-items" | "restricted-csv" as value) => value
    Ok(_) => return Err("dataset source_format is unsupported")
    Err(message) => return Err(message)
  }
  let binding = match feasibility_json_string_field(object, "binding") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let selection_key = match
    feasibility_json_string_field(object, "selection_key") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let fields = match object.get("fields") {
    Some(value) =>
      match feasibility_json_string_array(value, "dataset fields") {
        Ok(fields) => fields
        Err(message) => return Err(message)
      }
    None => return Err("dataset fields are missing")
  }
  guard fields.contains(selection_key) else {
    return Err("dataset fields must contain the selection key")
  }
  let row_values = match object.get("rows") {
    Some(Json::Array(values)) => values
    _ => return Err("dataset rows must be an array")
  }
  guard row_values.length() <= GENUI_MAX_FEASIBILITY_ROWS else {
    return Err("dataset row count exceeds the feasibility limit")
  }
  let rows : Array[FeasibilityDatasetRow] = []
  let stable_keys : Set[String] = Set([])
  for row_json in row_values {
    let row = match feasibility_decode_row(row_json, fields, selection_key) {
      Ok(row) => row
      Err(message) => return Err(message)
    }
    guard stable_keys.add_and_check(row.stable_key) else {
      return Err("dataset contains a duplicate stable key")
    }
    rows.push(row)
  }
  let task_value = match object.get("task_value") {
    Some(value) =>
      match feasibility_decode_scalar(value) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
    None => return Err("dataset task_value is missing")
  }
  Ok(
    FeasibilityDataset(
      schema_version, case_id, source_format, binding, selection_key, fields, rows,
      task_value,
    ),
  )
}

///|
priv enum FeasibilitySummaryValue {
  Numeric(Double)
  Empty
}

///|
priv struct FeasibilitySummary {
  field : String
  aggregation : @cognition.GenerativeUiAggregation
  value : FeasibilitySummaryValue
}

///|
fn FeasibilitySummary::FeasibilitySummary(
  field : String,
  aggregation : @cognition.GenerativeUiAggregation,
  value : FeasibilitySummaryValue,
) -> FeasibilitySummary {
  { field, aggregation, value }
}

///|
priv enum FeasibilitySafeNode {
  Stack(Array[FeasibilitySafeNode])
  Panel(Array[FeasibilitySafeNode])
  Text(String)
} derive(Debug)

///|
priv struct MaterializedFeasibilityCandidate {
  candidate : @cognition.GenerativeUiCandidate
  safe_output_json : String
  safe_output_sha256 : String
  matched_stable_keys : Array[String]
  projected_fields : Array[String]
  summary : FeasibilitySummary
}

///|
fn MaterializedFeasibilityCandidate::MaterializedFeasibilityCandidate(
  candidate : @cognition.GenerativeUiCandidate,
  safe_output_json : String,
  safe_output_sha256 : String,
  matched_stable_keys : Array[String],
  projected_fields : Array[String],
  summary : FeasibilitySummary,
) -> MaterializedFeasibilityCandidate {
  {
    candidate,
    safe_output_json,
    safe_output_sha256,
    matched_stable_keys,
    projected_fields,
    summary,
  }
}

///|
fn feasibility_scalar_text(value : FeasibilityScalar) -> String {
  match value {
    Text(value) => value
    Number(value) => value.to_string()
    Boolean(value) => if value { "true" } else { "false" }
    Null => "null"
  }
}

///|
fn feasibility_scalar_json(value : FeasibilityScalar) -> String {
  match value {
    Text(value) => Json::string(value).stringify()
    Number(value) => Json::number(value).stringify()
    Boolean(value) => Json::boolean(value).stringify()
    Null => "null"
  }
}

///|
fn feasibility_row_value(
  row : FeasibilityDatasetRow,
  field : String,
) -> FeasibilityScalar? {
  for pair in row.values {
    let (name, value) = pair
    if name == field {
      return Some(value)
    }
  }
  None
}

///|
fn feasibility_scalar_equal(
  left : FeasibilityScalar,
  right : FeasibilityScalar,
) -> Bool {
  match (left, right) {
    (Text(left), Text(right)) => left == right
    (Number(left), Number(right)) => left == right
    (Boolean(left), Boolean(right)) => left == right
    (Null, Null) => true
    _ => false
  }
}

///|
fn feasibility_filter_matches(
  row : FeasibilityDatasetRow,
  field : String,
  operator : @cognition.GenerativeUiFilterOperator,
  task_value : FeasibilityScalar,
) -> Bool {
  match feasibility_row_value(row, field) {
    None => false
    Some(value) =>
      match operator {
        Equal => feasibility_scalar_equal(value, task_value)
        NotEqual => !feasibility_scalar_equal(value, task_value)
        Contains =>
          match (value, task_value) {
            (Text(value), Text(fragment)) =>
              value.to_lower().contains(fragment.to_lower())
            _ => false
          }
        GreaterThan =>
          match (value, task_value) {
            (Number(value), Number(limit)) => value > limit
            _ => false
          }
        LessThan =>
          match (value, task_value) {
            (Number(value), Number(limit)) => value < limit
            _ => false
          }
      }
  }
}

///|
fn feasibility_summary_value(
  rows : Array[FeasibilityDatasetRow],
  field : String,
  aggregation : @cognition.GenerativeUiAggregation,
) -> Result[FeasibilitySummaryValue, String] {
  guard aggregation != Count else {
    return Ok(Numeric(Double::from_int(rows.length())))
  }
  let values : Array[Double] = []
  for row in rows {
    match feasibility_row_value(row, field) {
      Some(Number(value)) => values.push(value)
      _ => return Err("summary field is missing or non-numeric: " + field)
    }
  }
  if values.is_empty() {
    return Ok(Empty)
  }
  let value = match aggregation {
    Count => Double::from_int(values.length())
    Sum => values.fold(init=0.0, (total, value) => total + value)
    Average =>
      values.fold(init=0.0, (total, value) => total + value) /
      Double::from_int(values.length())
    Minimum =>
      values.fold(init=values[0], (left, right) => Double::min(left, right))
    Maximum =>
      values.fold(init=values[0], (left, right) => Double::max(left, right))
  }
  if value.is_nan() || value.is_inf() {
    Err("summary result is not finite")
  } else {
    Ok(Numeric(value))
  }
}

///|
fn feasibility_aggregation_name(
  aggregation : @cognition.GenerativeUiAggregation,
) -> String {
  match aggregation {
    Count => "count"
    Sum => "sum"
    Average => "average"
    Minimum => "minimum"
    Maximum => "maximum"
  }
}

///|
fn feasibility_summary_text(summary : FeasibilitySummary) -> String {
  let value = match summary.value {
    Numeric(value) => value.to_string()
    Empty => "null"
  }
  feasibility_aggregation_name(summary.aggregation) +
  " " +
  summary.field +
  ": " +
  value
}

///|
fn feasibility_materialize_table(
  binding : @cognition.GenerativeUiDataBinding,
  selection_key : @cognition.GenerativeUiSelectionKey?,
  children : Array[@cognition.GenerativeUiCandidateNode],
  dataset : FeasibilityDataset,
) -> Result[
  (Array[FeasibilitySafeNode], Array[String], Array[String], FeasibilitySummary),
  String,
] {
  guard binding.to_string() == dataset.binding else {
    return Err("candidate binding does not match the frozen dataset")
  }
  guard selection_key is Some(selection_key) else {
    return Err("candidate table requires a selection key")
  }
  guard selection_key.to_string() == dataset.selection_key else {
    return Err("candidate selection key does not match the frozen dataset")
  }
  guard children.length() >= 4 && children.length() <= 6 else {
    return Err(
      "candidate table must contain two to four columns, one filter, and one summary",
    )
  }
  let column_count = children.length() - 2
  let column_fields : Set[String] = Set([])
  for index in 0..<column_count {
    guard children[index]
      is @cognition.GenerativeUiCandidateNode::Column(field~, ..) else {
      return Err("candidate table columns must precede the filter and summary")
    }
    guard column_fields.add_and_check(field.to_string()) else {
      return Err("candidate table contains a duplicate column field")
    }
  }
  guard children[column_count]
    is @cognition.GenerativeUiCandidateNode::Filter(_) else {
    return Err("candidate table filter must follow its columns")
  }
  guard children[column_count + 1]
    is @cognition.GenerativeUiCandidateNode::Summary(_) else {
    return Err("candidate table summary must follow its filter")
  }
  let columns : Array[(String, String)] = [
    for child in children if child
    is @cognition.GenerativeUiCandidateNode::Column(field~, label~) => {
      (
        field.to_string(),
        match label {
          Some(label) => label
          None => field.to_string()
        },
      )
    }
  ]
  let filters : Array[(String, @cognition.GenerativeUiFilterOperator)] = [
    for child in children if child
    is @cognition.GenerativeUiCandidateNode::Filter(field~, operator~) => {
      (field.to_string(), operator)
    }
  ]
  let summaries : Array[(String, @cognition.GenerativeUiAggregation)] = [
    for child in children if child
    is @cognition.GenerativeUiCandidateNode::Summary(field~, aggregation~) => {
      (field.to_string(), aggregation)
    }
  ]
  guard filters.length() == 1 else {
    return Err("candidate table must contain one filter")
  }
  guard summaries.length() == 1 else {
    return Err("candidate table must contain one summary")
  }
  let (filter_field, filter_operator) = filters[0]
  let matched_rows = dataset.rows.filter(row => {
    feasibility_filter_matches(
      row,
      filter_field,
      filter_operator,
      dataset.task_value,
    )
  })
  let safe_rows : Array[FeasibilitySafeNode] = matched_rows.map(row => {
    Panel(
      columns.map(column => {
        let (field, label) = column
        let value = feasibility_row_value(row, field).unwrap()
        Text(label + ": " + feasibility_scalar_text(value))
      }),
    )
  })
  let (summary_field, summary_aggregation) = summaries[0]
  let summary_value = match
    feasibility_summary_value(matched_rows, summary_field, summary_aggregation) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let summary = FeasibilitySummary(
    summary_field, summary_aggregation, summary_value,
  )
  let materialized = safe_rows.copy()
  materialized.push(Text(feasibility_summary_text(summary)))
  Ok(
    (
      materialized,
      matched_rows.map(row => row.stable_key),
      columns.map(column => column.0),
      summary,
    ),
  )
}

///|
fn feasibility_materialize_node(
  node : @cognition.GenerativeUiCandidateNode,
  dataset : FeasibilityDataset,
) -> Result[
  (
    Array[FeasibilitySafeNode],
    Array[String],
    Array[String],
    FeasibilitySummary?,
  ),
  String,
] {
  match node {
    Stack(children~) | Panel(children~) => {
      let materialized_children : Array[FeasibilitySafeNode] = []
      let matched_stable_keys : Array[String] = []
      let projected_fields : Array[String] = []
      let mut summary : FeasibilitySummary? = None
      for child in children {
        let child_result = feasibility_materialize_node(child, dataset)
        let (nodes, keys, fields, child_summary) = match child_result {
          Ok(result) => result
          Err(message) => return Err(message)
        }
        materialized_children.append(nodes)
        matched_stable_keys.append(keys)
        projected_fields.append(fields)
        match child_summary {
          Some(value) => summary = Some(value)
          None => ()
        }
      }
      let container = if node is Stack(_) {
        Stack(materialized_children)
      } else {
        Panel(materialized_children)
      }
      Ok(([container], matched_stable_keys, projected_fields, summary))
    }
    Text(value~) => Ok(([Text(value)], [], [], None))
    Table(binding~, selection_key~, children~) => {
      let table_result = feasibility_materialize_table(
        binding, selection_key, children, dataset,
      )
      let (nodes, keys, fields, summary) = match table_result {
        Ok(result) => result
        Err(message) => return Err(message)
      }
      Ok((nodes, keys, fields, Some(summary)))
    }
    Column(_) | Filter(_) | Summary(_) =>
      Err("table-only component appears outside a table")
  }
}

///|
fn feasibility_safe_node_to_raw(
  node : FeasibilitySafeNode,
) -> @cognition.GenerativeUiRawNode {
  match node {
    Stack(children) =>
      @cognition.GenerativeUiRawNode::Component(
        name="stack",
        attributes=[],
        children=children.map(feasibility_safe_node_to_raw),
      )
    Panel(children) =>
      @cognition.GenerativeUiRawNode::Component(
        name="panel",
        attributes=[],
        children=children.map(feasibility_safe_node_to_raw),
      )
    Text(value) =>
      @cognition.GenerativeUiRawNode::Component(
        name="text",
        attributes=[@cognition.GenerativeUiRawAttribute(name="value", value~)],
        children=[],
      )
  }
}

///|
fn feasibility_safe_node_json(node : FeasibilitySafeNode) -> String {
  let builder = StringBuilder(size_hint=128)
  match node {
    Stack(children) => {
      builder.write_string("{\"type\":\"stack\",\"children\":[")
      for index, child in children {
        if index > 0 {
          builder.write_char(',')
        }
        builder.write_string(feasibility_safe_node_json(child))
      }
      builder.write_string("]}")
    }
    Panel(children) => {
      builder.write_string("{\"type\":\"panel\",\"children\":[")
      for index, child in children {
        if index > 0 {
          builder.write_char(',')
        }
        builder.write_string(feasibility_safe_node_json(child))
      }
      builder.write_string("]}")
    }
    Text(value) =>
      builder
      ..write_string("{\"type\":\"text\",\"value\":")
      ..write_string(Json::string(value).stringify())
      .write_char('}')
  }
  builder.to_string()
}

///|
fn materialize_feasibility_candidate(
  candidate : @cognition.GenerativeUiCandidate,
  dataset : FeasibilityDataset,
) -> Result[MaterializedFeasibilityCandidate, String] {
  let root = candidate.root()
  guard root is @cognition.GenerativeUiCandidateNode::Stack(children~) &&
    children.length() == 2 else {
    return Err("candidate root must be a Stack with one title and one table")
  }
  guard children[0] is @cognition.GenerativeUiCandidateNode::Text(_) else {
    return Err("candidate Stack must begin with a title")
  }
  guard children[1]
    is @cognition.GenerativeUiCandidateNode::Table(children=_, ..) else {
    return Err("candidate Stack must end with a table")
  }
  let materialized = feasibility_materialize_node(root, dataset)
  let (nodes, matched_stable_keys, projected_fields, summary) = match
    materialized {
    Ok(result) => result
    Err(message) => return Err(message)
  }
  guard nodes.length() == 1 else {
    return Err("candidate root materialized to more than one node")
  }
  guard summary is Some(summary) else {
    return Err("candidate does not contain a summary")
  }
  let safe_node = nodes[0]
  let raw = feasibility_safe_node_to_raw(safe_node)
  let capabilities = @cognition.GenerativeUiHostCapabilities(
    bindings=[],
    filter_operators=[],
    aggregations=[],
  )
  let safe_candidate = match
    @cognition.GenerativeUiCandidate::validate(raw~, capabilities~) {
    Ok(candidate) => candidate
    Err(_) => return Err("materialized safe output failed validation")
  }
  let safe_output_json = feasibility_safe_node_json(safe_node)
  let safe_output_sha256 = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(safe_output_json)),
  )
  Ok(
    MaterializedFeasibilityCandidate(
      safe_candidate, safe_output_json, safe_output_sha256, matched_stable_keys,
      projected_fields, summary,
    ),
  )
}
