///|
fn feasibility_test_json_string(value : String) -> String {
  Json::string(value).stringify()
}

///|
fn feasibility_test_json_field(json : Json, key : String) -> Json raise {
  match json {
    Object(fields) =>
      match fields.get(key) {
        Some(value) => value
        None => fail("missing JSON field: " + key)
      }
    _ => fail("expected JSON object")
  }
}

///|
fn feasibility_test_attribute(name : String, value : String) -> String {
  "{\"name\":" +
  feasibility_test_json_string(name) +
  ",\"value\":" +
  feasibility_test_json_string(value) +
  "}"
}

///|
fn feasibility_test_component(
  name : String,
  attributes : Array[(String, String)],
  children : Array[String],
) -> String {
  let encoded_attributes = attributes.map(pair => {
    let (attribute_name, value) = pair
    feasibility_test_attribute(attribute_name, value)
  })
  "{\"type\":\"component\",\"name\":" +
  feasibility_test_json_string(name) +
  ",\"attributes\":[" +
  encoded_attributes.join(",") +
  "],\"children\":[" +
  children.join(",") +
  "]}"
}

///|
fn feasibility_test_text(value : String) -> String {
  feasibility_test_component("text", [("value", value)], [])
}

///|
fn feasibility_test_column(field : String, label : String) -> String {
  feasibility_test_component("column", [("field", field), ("label", label)], [])
}

///|
fn feasibility_test_filter(field : String, operator : String) -> String {
  feasibility_test_component(
    "filter",
    [("field", field), ("operator", operator)],
    [],
  )
}

///|
fn feasibility_test_summary(field : String, aggregation : String) -> String {
  feasibility_test_component(
    "summary",
    [("field", field), ("aggregation", aggregation)],
    [],
  )
}

///|
fn feasibility_test_table(
  binding : String,
  selection_key : String,
  children : Array[String],
) -> String {
  feasibility_test_component(
    "table",
    [("data", binding), ("selection", selection_key)],
    children,
  )
}

///|
fn feasibility_test_candidate(
  title : String,
  binding : String,
  selection_key : String,
  columns : Array[(String, String)],
  filter_field : String,
  operator : String,
  summary_field : String,
  aggregation : String,
) -> String {
  let table_children = columns.map(pair => {
    let (field, label) = pair
    feasibility_test_column(field, label)
  })
  table_children.push(feasibility_test_filter(filter_field, operator))
  table_children.push(feasibility_test_summary(summary_field, aggregation))
  feasibility_test_component("stack", [], [
    feasibility_test_text(title),
    feasibility_test_table(binding, selection_key, table_children),
  ])
}

///|
fn feasibility_test_capabilities(
  binding : String,
  fields : Array[String],
  selection_key : String,
  operators : Array[String],
  aggregations : Array[String],
) -> String {
  let encoded_fields = fields.map(feasibility_test_json_string)
  let encoded_operators = operators.map(feasibility_test_json_string)
  let encoded_aggregations = aggregations.map(feasibility_test_json_string)
  "{\"bindings\":[{\"name\":" +
  feasibility_test_json_string(binding) +
  ",\"fields\":[" +
  encoded_fields.join(",") +
  "],\"selection_keys\":[" +
  feasibility_test_json_string(selection_key) +
  "]}],\"filter_operators\":[" +
  encoded_operators.join(",") +
  "],\"aggregations\":[" +
  encoded_aggregations.join(",") +
  "]}"
}

///|
fn feasibility_test_prepare(
  candidate_json : String,
  capabilities_json : String,
  dataset_json : String,
) -> PreparedFeasibilityCandidate raise {
  match
    prepare_feasibility_candidate(
      candidate_json~,
      capabilities_json~,
      dataset_json~,
    ) {
    Ok(prepared) => prepared
    Err(error) => fail("unexpected preparation error: \{error.message}")
  }
}

///|
fn feasibility_test_assert_error(
  candidate_json : String,
  capabilities_json : String,
  dataset_json : String,
  classification : String,
) -> Unit raise {
  match
    prepare_feasibility_candidate(
      candidate_json~,
      capabilities_json~,
      dataset_json~,
    ) {
    Ok(_) => fail("preparation unexpectedly succeeded")
    Err(error) => assert_eq(error.classification, classification)
  }
}

///|
const ORDERS_DATASET_JSON = "{\"schema_version\":1,\"case_id\":\"orders-pending-attention\",\"source_format\":\"json-array\",\"binding\":\"orders\",\"selection_key\":\"id\",\"fields\":[\"id\",\"name\",\"status\",\"amount\"],\"rows\":[{\"stable_key\":\"ord-1001\",\"values\":[[\"id\",\"ord-1001\"],[\"name\",\"Acme renewal\"],[\"status\",\"paid\"],[\"amount\",1280.5]]},{\"stable_key\":\"ord-1002\",\"values\":[[\"id\",\"ord-1002\"],[\"name\",\"Northstar onboarding\"],[\"status\",\"pending\"],[\"amount\",640]]},{\"stable_key\":\"ord-1003\",\"values\":[[\"id\",\"ord-1003\"],[\"name\",\"Cedar support plan\"],[\"status\",\"paid\"],[\"amount\",315.75]]},{\"stable_key\":\"ord-1004\",\"values\":[[\"id\",\"ord-1004\"],[\"name\",\"Lumen migration\"],[\"status\",\"review\"],[\"amount\",2180]]},{\"stable_key\":\"ord-1005\",\"values\":[[\"id\",\"ord-1005\"],[\"name\",\"Harbor analytics\"],[\"status\",\"paid\"],[\"amount\",890.25]]},{\"stable_key\":\"ord-1006\",\"values\":[[\"id\",\"ord-1006\"],[\"name\",\"Vertex renewal\"],[\"status\",\"pending\"],[\"amount\",1540]]}],\"task_value\":\"pending\"}"

///|
const INVENTORY_DATASET_JSON = "{\"schema_version\":1,\"case_id\":\"inventory-low-stock\",\"source_format\":\"json-nested-items\",\"binding\":\"inventory\",\"selection_key\":\"sku\",\"fields\":[\"sku\",\"product\",\"category\",\"on_hand\"],\"rows\":[{\"stable_key\":\"sku-001\",\"values\":[[\"sku\",\"sku-001\"],[\"product\",\"Flux capacitor\"],[\"category\",\"components\"],[\"on_hand\",4]]},{\"stable_key\":\"sku-002\",\"values\":[[\"sku\",\"sku-002\"],[\"product\",\"Quantum relay\"],[\"category\",\"components\"],[\"on_hand\",7]]},{\"stable_key\":\"sku-003\",\"values\":[[\"sku\",\"sku-003\"],[\"product\",\"Sensor array\"],[\"category\",\"instruments\"],[\"on_hand\",14]]},{\"stable_key\":\"sku-004\",\"values\":[[\"sku\",\"sku-004\"],[\"product\",\"Thermal coupler\"],[\"category\",\"components\"],[\"on_hand\",22]]}],\"task_value\":10}"

///|
const INCIDENTS_DATASET_JSON = "{\"schema_version\":1,\"case_id\":\"incidents-critical-resolution\",\"source_format\":\"restricted-csv\",\"binding\":\"incidents\",\"selection_key\":\"incident_id\",\"fields\":[\"incident_id\",\"service\",\"severity\",\"resolution_minutes\"],\"rows\":[{\"stable_key\":\"inc-001\",\"values\":[[\"incident_id\",\"inc-001\"],[\"service\",\"auth-api\"],[\"severity\",\"critical\"],[\"resolution_minutes\",90]]},{\"stable_key\":\"inc-002\",\"values\":[[\"incident_id\",\"inc-002\"],[\"service\",\"billing-worker\"],[\"severity\",\"high\"],[\"resolution_minutes\",45]]},{\"stable_key\":\"inc-003\",\"values\":[[\"incident_id\",\"inc-003\"],[\"service\",\"search-api\"],[\"severity\",\"critical\"],[\"resolution_minutes\",150]]},{\"stable_key\":\"inc-004\",\"values\":[[\"incident_id\",\"inc-004\"],[\"service\",\"analytics\"],[\"severity\",\"medium\"],[\"resolution_minutes\",60]]}],\"task_value\":\"critical\"}"

///|
fn feasibility_test_orders_capabilities() -> String {
  feasibility_test_capabilities(
    "orders",
    ["id", "name", "status", "amount"],
    "id",
    ["eq", "lt"],
    ["count", "sum", "average", "min", "max"],
  )
}

///|
fn feasibility_test_inventory_capabilities() -> String {
  feasibility_test_capabilities(
    "inventory",
    ["sku", "product", "category", "on_hand"],
    "sku",
    ["eq", "lt"],
    ["count", "sum", "average", "min", "max"],
  )
}

///|
fn feasibility_test_incidents_capabilities() -> String {
  feasibility_test_capabilities(
    "incidents",
    ["incident_id", "service", "severity", "resolution_minutes"],
    "incident_id",
    ["eq", "lt"],
    ["count", "sum", "average", "min", "max"],
  )
}

///|
fn feasibility_test_orders_candidate() -> String {
  feasibility_test_candidate(
    "Pending orders requiring attention",
    "orders",
    "id",
    [("id", "Order"), ("name", "Customer"), ("amount", "Amount")],
    "status",
    "eq",
    "amount",
    "sum",
  )
}

///|
fn feasibility_test_inventory_candidate() -> String {
  feasibility_test_candidate(
    "Inventory below reorder threshold",
    "inventory",
    "sku",
    [("sku", "SKU"), ("product", "Product"), ("on_hand", "On hand")],
    "on_hand",
    "lt",
    "on_hand",
    "sum",
  )
}

///|
fn feasibility_test_incidents_candidate() -> String {
  feasibility_test_candidate(
    "Critical incident resolution",
    "incidents",
    "incident_id",
    [
      ("incident_id", "Incident"),
      ("service", "Service"),
      ("resolution_minutes", "Resolution minutes"),
    ],
    "severity",
    "eq",
    "resolution_minutes",
    "average",
  )
}

///|
test "recorded orders materializes exact generic evidence and safe output" {
  let prepared = feasibility_test_prepare(
    feasibility_test_orders_candidate(),
    feasibility_test_orders_capabilities(),
    ORDERS_DATASET_JSON,
  )
  assert_true(prepared.rubric.passed)
  assert_eq(
    prepared.safe_output_json,
    "{\"type\":\"stack\",\"children\":[{\"type\":\"text\",\"value\":\"Pending orders requiring attention\"},{\"type\":\"panel\",\"children\":[{\"type\":\"text\",\"value\":\"Order: ord-1002\"},{\"type\":\"text\",\"value\":\"Customer: Northstar onboarding\"},{\"type\":\"text\",\"value\":\"Amount: 640\"}]},{\"type\":\"panel\",\"children\":[{\"type\":\"text\",\"value\":\"Order: ord-1006\"},{\"type\":\"text\",\"value\":\"Customer: Vertex renewal\"},{\"type\":\"text\",\"value\":\"Amount: 1540\"}]},{\"type\":\"text\",\"value\":\"sum amount: 2180\"}]}",
  )
  assert_eq(
    prepared.safe_output_sha256,
    "b38921f65f7f8c3ecb366702b6dc7a4e703d99a6dbcdc16e43353a4a11be46e7",
  )
  assert_eq(
    prepared.evidence_json,
    "{\"schema_version\":1,\"case_id\":\"orders-pending-attention\",\"source_format\":\"json-array\",\"binding\":\"orders\",\"filter\":{\"field\":\"status\",\"operator\":\"equals\",\"value\":\"pending\"},\"projected_fields\":[\"id\",\"name\",\"amount\"],\"matched_stable_keys\":[\"ord-1002\",\"ord-1006\"],\"summary\":{\"field\":\"amount\",\"aggregation\":\"sum\",\"value\":2180},\"safe_output_sha256\":\"b38921f65f7f8c3ecb366702b6dc7a4e703d99a6dbcdc16e43353a4a11be46e7\"}",
  )
}

///|
test "recorded inventory and incidents preserve source and projection order" {
  let inventory = feasibility_test_prepare(
    feasibility_test_inventory_candidate(),
    feasibility_test_inventory_capabilities(),
    INVENTORY_DATASET_JSON,
  )
  assert_true(inventory.rubric.passed)
  assert_eq(
    inventory.safe_output_sha256,
    "b65291b9a34fdf7987d7b1acb8bb7c6107c2617c4e063f56c5a52f0cdb28db3e",
  )
  assert_eq(
    inventory.evidence_json,
    "{\"schema_version\":1,\"case_id\":\"inventory-low-stock\",\"source_format\":\"json-nested-items\",\"binding\":\"inventory\",\"filter\":{\"field\":\"on_hand\",\"operator\":\"less_than\",\"value\":10},\"projected_fields\":[\"sku\",\"product\",\"on_hand\"],\"matched_stable_keys\":[\"sku-001\",\"sku-002\"],\"summary\":{\"field\":\"on_hand\",\"aggregation\":\"sum\",\"value\":11},\"safe_output_sha256\":\"b65291b9a34fdf7987d7b1acb8bb7c6107c2617c4e063f56c5a52f0cdb28db3e\"}",
  )
  let incidents = feasibility_test_prepare(
    feasibility_test_incidents_candidate(),
    feasibility_test_incidents_capabilities(),
    INCIDENTS_DATASET_JSON,
  )
  assert_true(incidents.rubric.passed)
  assert_eq(
    incidents.safe_output_sha256,
    "2c2e3d0fbb0db55022166f79607c7bce44a1b8bd39bac811b20e9bee86e3809f",
  )
  assert_eq(
    incidents.evidence_json,
    "{\"schema_version\":1,\"case_id\":\"incidents-critical-resolution\",\"source_format\":\"restricted-csv\",\"binding\":\"incidents\",\"filter\":{\"field\":\"severity\",\"operator\":\"equals\",\"value\":\"critical\"},\"projected_fields\":[\"incident_id\",\"service\",\"resolution_minutes\"],\"matched_stable_keys\":[\"inc-001\",\"inc-003\"],\"summary\":{\"field\":\"resolution_minutes\",\"aggregation\":\"average\",\"value\":120},\"safe_output_sha256\":\"2c2e3d0fbb0db55022166f79607c7bce44a1b8bd39bac811b20e9bee86e3809f\"}",
  )
}

///|
fn feasibility_test_operator_dataset(task_value : String) -> String {
  "{\"schema_version\":1,\"case_id\":\"operator-test\",\"source_format\":\"json-array\",\"binding\":\"records\",\"selection_key\":\"id\",\"fields\":[\"id\",\"text\",\"num\",\"flag\"],\"rows\":[{\"stable_key\":\"a\",\"values\":[[\"id\",\"a\"],[\"text\",\"Alpha Beta\"],[\"num\",1e0],[\"flag\",true]]},{\"stable_key\":\"b\",\"values\":[[\"id\",\"b\"],[\"text\",\"beta\"],[\"num\",2],[\"flag\",false]]},{\"stable_key\":\"c\",\"values\":[[\"id\",\"c\"],[\"text\",\"Gamma\"],[\"num\",3.00],[\"flag\",true]]}],\"task_value\":" +
  task_value +
  "}"
}

///|
fn feasibility_test_operator_capabilities() -> String {
  feasibility_test_capabilities(
    "records",
    ["id", "text", "num", "flag"],
    "id",
    ["eq", "neq", "contains", "gt", "lt"],
    ["count", "sum", "average", "min", "max"],
  )
}

///|
fn feasibility_test_operator_candidate(
  field : String,
  operator : String,
  aggregation : String,
) -> String {
  feasibility_test_candidate(
    "Operator <proof> & evidence",
    "records",
    "id",
    [("id", "ID"), ("num", "Number")],
    field,
    operator,
    "num",
    aggregation,
  )
}

///|
test "all filter operators preserve exact scalar semantics and source order" {
  let cases : Array[(String, String, String, String)] = [
    ("flag", "eq", "true", "[\"a\",\"c\"]"),
    ("flag", "neq", "true", "[\"b\"]"),
    ("text", "contains", "\"BETA\"", "[\"a\",\"b\"]"),
    ("num", "gt", "2", "[\"c\"]"),
    ("num", "lt", "2", "[\"a\"]"),
  ]
  for item in cases {
    let (field, operator, task_value, expected_keys) = item
    let prepared = feasibility_test_prepare(
      feasibility_test_operator_candidate(field, operator, "count"),
      feasibility_test_operator_capabilities(),
      feasibility_test_operator_dataset(task_value),
    )
    let evidence = @json.parse(prepared.evidence_json)
    assert_eq(
      feasibility_test_json_field(evidence, "matched_stable_keys").stringify(),
      expected_keys,
    )
  }
}

///|
test "count accepts a non-numeric summary field" {
  let candidate = feasibility_test_candidate(
    "Count records",
    "records",
    "id",
    [("id", "ID"), ("text", "Text")],
    "flag",
    "eq",
    "text",
    "count",
  )
  let prepared = feasibility_test_prepare(
    candidate,
    feasibility_test_operator_capabilities(),
    feasibility_test_operator_dataset("true"),
  )
  let evidence = @json.parse(prepared.evidence_json)
  let summary = feasibility_test_json_field(evidence, "summary")
  assert_eq(
    feasibility_test_json_field(summary, "value").stringify(),
    "2",
  )
}

///|
test "all aggregations normalize number spelling and empty numeric sets" {
  let cases : Array[(String, String)] = [
    ("count", "2"),
    ("sum", "4"),
    ("average", "2"),
    ("min", "1"),
    ("max", "3"),
  ]
  for item in cases {
    let (aggregation, expected_value) = item
    let prepared = feasibility_test_prepare(
      feasibility_test_operator_candidate("flag", "eq", aggregation),
      feasibility_test_operator_capabilities(),
      feasibility_test_operator_dataset("true"),
    )
    let evidence = @json.parse(prepared.evidence_json)
    let summary = feasibility_test_json_field(evidence, "summary")
    assert_eq(
      feasibility_test_json_field(summary, "value").stringify(),
      expected_value,
    )
    assert_false(prepared.safe_output_json.contains("1e0"))
    assert_false(prepared.safe_output_json.contains("3.00"))
  }
  let empty = feasibility_test_prepare(
    feasibility_test_operator_candidate("text", "eq", "sum"),
    feasibility_test_operator_capabilities(),
    feasibility_test_operator_dataset("\"missing\""),
  )
  let empty_evidence = @json.parse(empty.evidence_json)
  let empty_summary = feasibility_test_json_field(empty_evidence, "summary")
  assert_eq(
    feasibility_test_json_field(empty_summary, "value").stringify(),
    "null",
  )
}

///|
test "non-finite inputs and aggregate overflow fail before evidence" {
  let candidate = feasibility_test_operator_candidate("flag", "eq", "sum")
  let capabilities = feasibility_test_operator_capabilities()
  let non_finite = feasibility_test_operator_dataset("true").replace_all(
    old="1e0",
    new="1e309",
  )
  feasibility_test_assert_error(
    candidate, capabilities, non_finite, "dataset_decode_error",
  )
  let overflow = feasibility_test_operator_dataset("true")
    .replace_all(old="1e0", new="1e308")
    .replace_all(old="3.00", new="1e308")
  feasibility_test_assert_error(
    candidate, capabilities, overflow, "materialization_error",
  )
}

///|
test "normalized dataset rejects schema identity order and capability drift" {
  let candidate = feasibility_test_orders_candidate()
  let capabilities = feasibility_test_orders_capabilities()
  let cases = [
    ORDERS_DATASET_JSON.replace_all(
      old="\"schema_version\":1",
      new="\"schema_version\":2",
    ),
    ORDERS_DATASET_JSON.replace_all(
      old="\"task_value\":\"pending\"",
      new="\"extra\":true,\"task_value\":\"pending\"",
    ),
    ORDERS_DATASET_JSON.replace_all(
      old="\"stable_key\":\"ord-1001\"",
      new="\"stable_key\":\"\"",
    ),
    ORDERS_DATASET_JSON.replace_all(
      old="\"stable_key\":\"ord-1002\"",
      new="\"stable_key\":\"ord-1001\"",
    ),
    ORDERS_DATASET_JSON.replace_all(
      old="[\"id\",\"ord-1001\"]",
      new="[\"id\",\"wrong\"]",
    ),
    ORDERS_DATASET_JSON.replace_all(
      old="[\"status\",\"paid\"],[\"amount\",1280.5]",
      new="[\"amount\",1280.5],[\"status\",\"paid\"]",
    ),
    ORDERS_DATASET_JSON.replace_all(
      old="[\"amount\",1280.5]",
      new="[\"status\",\"paid\"]",
    ),
  ]
  for dataset in cases {
    feasibility_test_assert_error(
      candidate, capabilities, dataset, "dataset_decode_error",
    )
  }
  feasibility_test_assert_error(
    candidate,
    feasibility_test_capabilities(
      "orders",
      ["id", "name", "amount", "status"],
      "id",
      ["eq", "lt"],
      ["count", "sum", "average", "min", "max"],
    ),
    ORDERS_DATASET_JSON,
    "capability_decode_error",
  )
}

///|
test "candidate decode validation and direct topology fail closed" {
  let capabilities = feasibility_test_orders_capabilities()
  feasibility_test_assert_error(
    "not json",
    capabilities,
    ORDERS_DATASET_JSON,
    "candidate_decode_error",
  )
  feasibility_test_assert_error(
    feasibility_test_orders_candidate(),
    "{}",
    ORDERS_DATASET_JSON,
    "capability_decode_error",
  )
  let disallowed_field = feasibility_test_candidate(
    "Unsafe",
    "orders",
    "id",
    [("missing", "Missing"), ("name", "Name")],
    "status",
    "eq",
    "amount",
    "sum",
  )
  feasibility_test_assert_error(
    disallowed_field,
    capabilities,
    ORDERS_DATASET_JSON,
    "candidate_validation_error",
  )
  let title = feasibility_test_text("Title")
  let columns = [
    feasibility_test_column("id", "ID"),
    feasibility_test_column("name", "Name"),
  ]
  let filter = feasibility_test_filter("status", "eq")
  let summary = feasibility_test_summary("amount", "sum")
  let table = feasibility_test_table(
    "orders",
    "id",
    columns + [filter, summary],
  )
  let cases = [
    feasibility_test_component("panel", [], [title, table]),
    feasibility_test_component("stack", [], [table]),
    feasibility_test_component("stack", [], [table, title]),
    feasibility_test_component("stack", [], [
      title,
      table,
      feasibility_test_text("extra"),
    ]),
    feasibility_test_component("stack", [], [
      title,
      feasibility_test_table("orders", "id", [columns[0], filter, summary]),
    ]),
    feasibility_test_component("stack", [], [
      title,
      feasibility_test_table("orders", "id", [
        columns[0],
        columns[0],
        filter,
        summary,
      ]),
    ]),
    feasibility_test_component("stack", [], [
      title,
      feasibility_test_table(
        "orders",
        "id",
        columns + [filter, filter, summary],
      ),
    ]),
    feasibility_test_component("stack", [], [
      title,
      feasibility_test_table("orders", "id", columns + [summary, filter]),
    ]),
  ]
  for malformed in cases {
    feasibility_test_assert_error(
      malformed,
      capabilities,
      ORDERS_DATASET_JSON,
      "materialization_error",
    )
  }
}

///|
test "duplicate projected columns fail the frozen topology" {
  let duplicate = feasibility_test_candidate(
    "Pending orders",
    "orders",
    "id",
    [("id", "Order"), ("id", "Duplicate")],
    "status",
    "eq",
    "amount",
    "sum",
  )
  feasibility_test_assert_error(
    duplicate,
    feasibility_test_orders_capabilities(),
    ORDERS_DATASET_JSON,
    "materialization_error",
  )
}

///|
test "task-wrong candidates materialize generically but fail the separate rubric" {
  let candidate = feasibility_test_candidate(
    "Pending orders",
    "orders",
    "id",
    [("id", "Order"), ("name", "Customer")],
    "status",
    "contains",
    "amount",
    "sum",
  )
  let capabilities = feasibility_test_capabilities(
    "orders",
    ["id", "name", "status", "amount"],
    "id",
    ["eq", "contains"],
    ["sum"],
  )
  let prepared = feasibility_test_prepare(
    candidate,
    capabilities,
    ORDERS_DATASET_JSON,
  )
  assert_false(prepared.rubric.passed)
  assert_true(prepared.evidence_json.contains("matched_stable_keys"))
}

///|
test "evaluate-only and commit share preparation while rubric gates session effects" {
  install_session_test_document()
  let candidate = feasibility_test_orders_candidate()
  let capabilities = feasibility_test_orders_capabilities()
  let evaluated = @js.parse(
    __jsx_evaluate_feasibility_candidate_json(
      candidate,
      capabilities,
      ORDERS_DATASET_JSON,
    ),
  )
  assert_true(evaluated.get("session").is_nullish())
  assert_eq(evaluated.get("classification").to_str(), "success")
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let committed = @js.parse(
    __jsx_commit_feasibility_candidate_json(
      handle,
      1,
      candidate,
      capabilities,
      ORDERS_DATASET_JSON,
    ),
  )
  assert_eq(
    committed.get("classification").to_str(),
    evaluated.get("classification").to_str(),
  )
  assert_eq(
    committed.get("evidence").stringify(),
    evaluated.get("evidence").stringify(),
  )
  assert_eq(
    committed.get("rubric").stringify(),
    evaluated.get("rubric").stringify(),
  )
  assert_eq(
    committed.get("safe_output_sha256").to_str(),
    evaluated.get("safe_output_sha256").to_str(),
  )
  assert_true(committed.get("session").get("success").cast())
  assert_eq(committed.get("session").get("revision").cast(), 2)
  let wrong = feasibility_test_candidate(
    "Wrong",
    "orders",
    "id",
    [("id", "Order"), ("name", "Customer")],
    "status",
    "eq",
    "amount",
    "sum",
  )
  let blocked = @js.parse(
    __jsx_commit_feasibility_candidate_json(
      handle,
      2,
      wrong,
      capabilities,
      ORDERS_DATASET_JSON,
    ),
  )
  assert_eq(blocked.get("classification").to_str(), "rubric_failure")
  assert_true(blocked.get("session").is_nullish())
  assert_eq(session_registry.get(handle).unwrap().baseline.revision, 2)
  let stale = @js.parse(
    __jsx_commit_feasibility_candidate_json(
      handle,
      1,
      candidate,
      capabilities,
      ORDERS_DATASET_JSON,
    ),
  )
  assert_eq(stale.get("classification").to_str(), "replay_mismatch")
  assert_false(stale.get("session").get("success").cast())
  assert_eq(stale.get("session").get("error").get("code").to_str(), "BaseRevisionMismatch")
  let missing_session = @js.parse(
    __jsx_commit_feasibility_candidate_json(
      handle + 1000,
      1,
      candidate,
      capabilities,
      ORDERS_DATASET_JSON,
    ),
  )
  assert_eq(missing_session.get("classification").to_str(), "commit_failure")
  assert_false(missing_session.get("session").get("success").cast())
  jsx_session_dispose(handle)
}
