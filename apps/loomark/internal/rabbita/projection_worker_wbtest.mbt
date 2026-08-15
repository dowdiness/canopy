///|
fn projection_worker_request(request_id : Int, command : Json) -> String {
  Json::object({
    "schema_version": Json::string("1"),
    "request_id": Json::number(request_id.to_double()),
    "command": command,
  }).stringify()
}

///|
fn projection_worker_test_stamp(
  generation : Int,
  sequence? : Int = 1,
  source_revision? : Int = sequence,
) -> ProjectionStamp {
  {
    generation,
    sequence,
    source_revision,
    causal_version: "projection-session-" + sequence.to_string(),
    block_intent: sequence,
  }
}

///|
fn projection_worker_seed_command(
  agent_id : String,
  source : String,
  generation : Int,
  demand? : ProjectionDemand = projection_all_demand(),
  sequence? : Int = 1,
  source_revision? : Int = sequence,
) -> Json {
  Json::object({
    "kind": Json::string("seed"),
    "agent_id": Json::string(agent_id),
    "source": Json::string(source),
    "stamp": projection_worker_stamp_json({
      ..projection_worker_test_stamp(generation, sequence~),
      source_revision,
    }),
    "demand": Json::object({
      "block": Json::boolean(demand.block),
      "preview": Json::boolean(demand.preview),
      "diagnostics": Json::boolean(demand.diagnostics),
    }),
  })
}

///|
fn projection_worker_advance_command(
  source : String?,
  generation? : Int = 1,
  sequence? : Int = 2,
  source_revision? : Int = sequence,
) -> Json {
  let source_effect = match source {
    Some(value) =>
      Json::object({
        "kind": Json::string("replace-source"),
        "source": Json::string(value),
      })
    None => Json::object({ "kind": Json::string("source-unchanged") })
  }
  Json::object({
    "kind": Json::string("advance"),
    "stamp": projection_worker_stamp_json(
      projection_worker_test_stamp(generation, sequence~, source_revision~),
    ),
    "source_effect": source_effect,
  })
}

///|
fn projection_worker_demand_json(
  block : Bool,
  preview : Bool,
  diagnostics : Bool,
) -> Json {
  Json::object({
    "block": Json::boolean(block),
    "preview": Json::boolean(preview),
    "diagnostics": Json::boolean(diagnostics),
  })
}

///|
fn projection_worker_demand_command(
  block : Bool,
  preview : Bool,
  diagnostics : Bool,
  generation? : Int = 1,
) -> Json {
  Json::object({
    "kind": Json::string("demand"),
    "stamp": projection_worker_stamp_json(
      projection_worker_test_stamp(generation),
    ),
    "demand": projection_worker_demand_json(block, preview, diagnostics),
  })
}

///|
fn projection_worker_command(kind : String) -> Json {
  Json::object({ "kind": Json::string(kind) })
}

///|
fn projection_worker_response(raw : String) -> Map[String, Json] {
  let parsed = try! @json.parse(raw)
  match parsed {
    Json::Object(fields) => fields
    _ => abort("projection Worker response must be an object")
  }
}

///|
fn projection_worker_response_kind(raw : String) -> String {
  match projection_worker_response(raw).get("kind") {
    Some(Json::String(value)) => value
    _ => abort("projection Worker response kind missing")
  }
}

///|
fn projection_worker_response_error(raw : String) -> String {
  match projection_worker_response(raw).get("error") {
    Some(Json::Object(error)) =>
      match error.get("kind") {
        Some(Json::String(value)) => value
        _ => abort("projection Worker error kind missing")
      }
    _ => abort("projection Worker error missing")
  }
}

///|
fn projection_worker_response_stamp_int(raw : String, name : String) -> Int {
  match projection_worker_response(raw).get("stamp") {
    Some(Json::Object(stamp)) =>
      match stamp.get(name) {
        Some(Json::Number(value, ..)) => value.to_int()
        _ => abort("projection Worker stamp field missing")
      }
    _ => abort("projection Worker stamp missing")
  }
}

///|
fn projection_worker_response_generation(raw : String) -> Int {
  projection_worker_response_stamp_int(raw, "generation")
}

///|
fn projection_worker_response_sequence(raw : String) -> Int {
  projection_worker_response_stamp_int(raw, "sequence")
}

///|
fn projection_worker_response_source_revision(raw : String) -> Int {
  projection_worker_response_stamp_int(raw, "source_revision")
}

///|
fn projection_worker_response_observables(raw : String) -> Json {
  projection_worker_response(raw)["observables"]
}

///|
test "projection Worker codec rejects malformed and incompatible requests" {
  let dispatch = new_projection_worker_dispatcher()
  assert_eq(projection_worker_response_kind(dispatch("not-json")), "error")
  assert_eq(
    projection_worker_response_error(dispatch("not-json")),
    "decode-failed",
  )
  let wrong_version = Json::object({
    "schema_version": Json::string("2"),
    "request_id": Json::number(1),
    "command": projection_worker_command("snapshot"),
  }).stringify()
  assert_eq(
    projection_worker_response_error(dispatch(wrong_version)),
    "decode-failed",
  )
  let wrong_type = Json::object({
    "schema_version": Json::string("1"),
    "request_id": Json::string("one"),
    "command": projection_worker_command("snapshot"),
  }).stringify()
  assert_eq(
    projection_worker_response_error(dispatch(wrong_type)),
    "decode-failed",
  )
}

///|
test "projection Worker Demand changes groups without advancing its stamp" {
  let dispatch = new_projection_worker_dispatcher()
  let seeded = dispatch(
    projection_worker_request(
      1,
      projection_worker_seed_command("worker-demand", "# Seed\n", 5, demand={
        block: false,
        preview: false,
        diagnostics: false,
      }),
    ),
  )
  let sequence = projection_worker_response_sequence(seeded)
  let source_revision = projection_worker_response_source_revision(seeded)
  assert_true(projection_worker_response_artifact(seeded) is Ok((1, _, None)))
  let demand_off = dispatch(
    projection_worker_request(
      2,
      projection_worker_demand_command(false, false, false, generation=5),
    ),
  )
  assert_eq(projection_worker_response_kind(demand_off), "ok")
  assert_eq(projection_worker_response_sequence(demand_off), sequence)
  assert_eq(
    projection_worker_response_source_revision(demand_off),
    source_revision,
  )
  assert_true(
    projection_worker_response_artifact(demand_off) is Ok((2, _, None)),
  )
  let preview_on = dispatch(
    projection_worker_request(
      3,
      projection_worker_demand_command(false, true, false, generation=5),
    ),
  )
  assert_eq(projection_worker_response_kind(preview_on), "ok")
  assert_eq(projection_worker_response_sequence(preview_on), sequence)
  assert_eq(
    projection_worker_response_source_revision(preview_on),
    source_revision,
  )
  assert_true(
    projection_worker_response_artifact(preview_on) is Ok((3, _, Some(_))),
  )
  let mixed = dispatch(
    projection_worker_request(
      4,
      projection_worker_demand_command(true, true, false, generation=5),
    ),
  )
  guard projection_worker_response_observables(mixed)
    is Json::Object(mixed_fields) else {
    abort("mixed demand must return observables")
  }
  assert_true(mixed_fields.contains("block"))
  assert_true(mixed_fields.contains("preview"))
  assert_false(mixed_fields.contains("diagnostics"))
  let diagnostics_only = dispatch(
    projection_worker_request(
      5,
      projection_worker_demand_command(false, false, true, generation=5),
    ),
  )
  guard projection_worker_response_observables(diagnostics_only)
    is Json::Object(diagnostic_fields) else {
    abort("diagnostics demand must return observables")
  }
  assert_false(diagnostic_fields.contains("block"))
  assert_false(diagnostic_fields.contains("preview"))
  assert_true(diagnostic_fields.contains("diagnostics"))
}

///|
test "projection Worker rejects malformed Demand" {
  let dispatch = new_projection_worker_dispatcher()
  ignore(
    dispatch(
      projection_worker_request(
        1,
        projection_worker_seed_command("worker-demand-malformed", "", 1),
      ),
    ),
  )
  let malformed = projection_worker_request(
    2,
    Json::object({
      "kind": Json::string("demand"),
      "demand": Json::object({
        "block": Json::boolean(false),
        "preview": Json::string("yes"),
        "diagnostics": Json::boolean(false),
      }),
    }),
  )
  assert_eq(
    projection_worker_response_error(dispatch(malformed)),
    "decode-failed",
  )
}

///|
test "projection Worker dispatcher preserves caller generation and adopted artifacts" {
  let dispatch = new_projection_worker_dispatcher()
  let seeded = dispatch(
    projection_worker_request(
      1,
      projection_worker_seed_command("worker-seed", "# 猫 🐈\n", 7),
    ),
  )
  assert_eq(projection_worker_response_kind(seeded), "ok")
  assert_eq(projection_worker_response_generation(seeded), 7)
  let fields = projection_worker_response(seeded)
  assert_true(fields.contains("observables"))
  assert_true(fields.contains("metrics"))
  match fields["observables"] {
    Json::Object(observables) =>
      match observables["preview"] {
        Json::Object(preview) => {
          assert_eq(preview["source"], Json::string("# 猫 🐈\n"))
          assert_true(preview.contains("artifact"))
          assert_false(preview.contains("html"))
        }
        _ => fail("projection Worker preview must be an object")
      }
    _ => fail("projection Worker observables must be an object")
  }

  let unchanged = dispatch(
    projection_worker_request(
      2,
      projection_worker_advance_command(None, generation=7, source_revision=1),
    ),
  )
  assert_eq(projection_worker_response_kind(unchanged), "ok")
  assert_eq(projection_worker_response_generation(unchanged), 7)
  assert_eq(
    projection_worker_response_observables(unchanged),
    projection_worker_response_observables(seeded),
  )
}

///|
test "projection Worker adopted output equals an independently seeded latest source" {
  let retained = new_projection_worker_dispatcher()
  ignore(
    retained(
      projection_worker_request(
        1,
        projection_worker_seed_command("retained", "# Before\n", 11),
      ),
    ),
  )
  let advanced = retained(
    projection_worker_request(
      2,
      projection_worker_advance_command(
        Some("# After\n\nTail `code`.\n"),
        generation=11,
      ),
    ),
  )

  let fresh = new_projection_worker_dispatcher()
  let expected = fresh(
    projection_worker_request(
      1,
      projection_worker_seed_command("fresh", "# After\n\nTail `code`.\n", 11),
    ),
  )
  assert_eq(
    projection_worker_response_observables(advanced),
    projection_worker_response_observables(expected),
  )
}

///|
test "projection Worker replayed Seed ReplaceProjectionSource and unchanged match in-process normalized output" {
  let source = "# Seed\n\nParagraph *強い* text.\n"
  let dispatch = new_projection_worker_dispatcher()
  let session = try! ProjectionSession::ProjectionSession(
    agent_id="in-process-parity",
    source~,
    generation=13,
  )
  defer session.dispose()
  let seeded = dispatch(
    projection_worker_request(
      1,
      projection_worker_seed_command("worker-parity", source, 13),
    ),
  )
  assert_eq(projection_worker_response_kind(seeded), "ok")
  assert_eq(projection_worker_response_generation(seeded), 13)
  assert_eq(projection_worker_response_sequence(seeded), 1)
  assert_eq(projection_worker_response_source_revision(seeded), 1)
  assert_eq(
    projection_worker_response_observables(seeded),
    normalized_projection_observables_json(
      try! session.normalized_protocol_observables(),
    ),
  )

  let replacements = [
    "# Seed\n\nParagraph *強い* text.\n\nTail `code`.\n", "> quote\n\n- first\n- second\n",
  ]
  let mut request_id = 2
  let mut expected_source_revision = 1
  for replacement in replacements {
    try! session.advance(ReplaceProjectionSource(replacement))
    expected_source_revision += 1
    let advanced = dispatch(
      projection_worker_request(
        request_id,
        projection_worker_advance_command(
          Some(replacement),
          generation=13,
          sequence=request_id,
          source_revision=expected_source_revision,
        ),
      ),
    )
    assert_eq(projection_worker_response_kind(advanced), "ok")
    assert_eq(projection_worker_response_sequence(advanced), session.sequence)
    assert_eq(
      projection_worker_response_source_revision(advanced),
      expected_source_revision,
    )
    assert_eq(
      projection_worker_response_observables(advanced),
      normalized_projection_observables_json(
        try! session.normalized_protocol_observables(),
      ),
    )
    request_id += 1

    try! session.advance(ProjectionSourceUnchanged)
    let unchanged = dispatch(
      projection_worker_request(
        request_id,
        projection_worker_advance_command(
          None,
          generation=13,
          sequence=request_id,
          source_revision=expected_source_revision,
        ),
      ),
    )
    assert_eq(projection_worker_response_kind(unchanged), "ok")
    assert_eq(projection_worker_response_sequence(unchanged), session.sequence)
    assert_eq(
      projection_worker_response_source_revision(unchanged),
      expected_source_revision,
    )
    assert_eq(
      projection_worker_response_observables(unchanged),
      normalized_projection_observables_json(
        try! session.normalized_protocol_observables(),
      ),
    )
    request_id += 1
  }
}

///|
test "projection Worker lifecycle failures are typed and disposal is terminal" {
  let dispatch = new_projection_worker_dispatcher()
  let before_seed = dispatch(
    projection_worker_request(1, projection_worker_advance_command(None)),
  )
  assert_eq(projection_worker_response_error(before_seed), "invalid-state")
  let invalid_generation = dispatch(
    projection_worker_request(
      2,
      projection_worker_seed_command("invalid", "", 0),
    ),
  )
  assert_eq(
    projection_worker_response_error(invalid_generation),
    "invalid-state",
  )
  let seeded = dispatch(
    projection_worker_request(
      3,
      projection_worker_seed_command("lifecycle", "# Seed\n", 3),
    ),
  )
  assert_eq(projection_worker_response_kind(seeded), "ok")
  let duplicate = dispatch(
    projection_worker_request(
      4,
      projection_worker_seed_command("duplicate", "# Other\n", 4),
    ),
  )
  assert_eq(projection_worker_response_error(duplicate), "invalid-state")
  let malformed_advance = dispatch(
    projection_worker_request(
      5,
      Json::object({
        "kind": Json::string("advance"),
        "source_effect": Json::object({ "kind": Json::string("replace-source") }),
      }),
    ),
  )
  assert_eq(
    projection_worker_response_error(malformed_advance),
    "decode-failed",
  )
  let disposed = dispatch(
    projection_worker_request(6, projection_worker_command("dispose")),
  )
  assert_eq(projection_worker_response_kind(disposed), "ok")
  assert_true(projection_worker_response(disposed).contains("disposed"))
  let after_dispose = dispatch(
    projection_worker_request(7, projection_worker_command("snapshot")),
  )
  assert_eq(projection_worker_response_error(after_dispose), "disposed")
  let reseed_after_dispose = dispatch(
    projection_worker_request(
      8,
      projection_worker_seed_command("reseed", "# Reopened\n", 4),
    ),
  )
  assert_eq(projection_worker_response_error(reseed_after_dispose), "disposed")
  let duplicate_dispose = dispatch(
    projection_worker_request(9, projection_worker_command("dispose")),
  )
  assert_eq(projection_worker_response_kind(duplicate_dispose), "ok")
  assert_true(
    projection_worker_response(duplicate_dispose).contains("disposed"),
  )
}

///|
test "projection Worker codec deterministically encodes Unicode and escaping" {
  let command = projection_worker_seed_command(
    "codec", "# 猫\n\n\"quoted\" \\\\ slash\n", 19,
  )
  let request = projection_worker_request(42, command)
  let dispatch_a = new_projection_worker_dispatcher()
  let dispatch_b = new_projection_worker_dispatcher()
  assert_eq(dispatch_a(request), dispatch_b(request))
}

///|
fn normalized_projection_observables_json(
  observables : NormalizedProjectionObservables,
) -> Json {
  Json::object({
    "block": normalized_block_projection_json(observables.block),
    "preview": normalized_preview_projection_json(observables.preview),
    "diagnostics": Json::array(
      observables.diagnostics.map(normalized_diagnostic_json),
    ),
  })
}

///|
test "projection Worker restart Seed preserves the host sequence frontier" {
  let dispatch = new_projection_worker_dispatcher()
  let seeded = dispatch(
    projection_worker_request(
      1,
      projection_worker_seed_command(
        "restart-frontier",
        "# Restarted\n",
        4,
        sequence=25,
      ),
    ),
  )
  assert_eq(projection_worker_response_kind(seeded), "ok")
  assert_eq(projection_worker_response_sequence(seeded), 25)
}

///|
test "projection Worker rejects an invalid initial Seed without claiming its session" {
  for
    invalid in [
      projection_worker_seed_command(
        "invalid-sequence",
        "# Invalid\n",
        1,
        sequence=0,
      ),
      projection_worker_seed_command(
        "invalid-source-revision",
        "# Invalid\n",
        1,
        source_revision=-1,
      ),
    ] {
    let dispatch = new_projection_worker_dispatcher()
    let rejected = dispatch(projection_worker_request(1, invalid))
    assert_eq(projection_worker_response_kind(rejected), "error")
    let unseeded = dispatch(
      projection_worker_request(2, projection_worker_command("snapshot")),
    )
    assert_eq(projection_worker_response_kind(unseeded), "error")
    let seeded = dispatch(
      projection_worker_request(
        3,
        projection_worker_seed_command("valid-after-rejection", "# Valid\n", 1),
      ),
    )
    assert_eq(projection_worker_response_kind(seeded), "ok")
    assert_eq(projection_worker_response_sequence(seeded), 1)
    assert_eq(projection_worker_response_source_revision(seeded), 1)
  }
}

///|
test "projection Worker rejects decoded invalid stamps without mutating its session" {
  let dispatch = new_projection_worker_dispatcher()
  let seeded = dispatch(
    projection_worker_request(
      1,
      projection_worker_seed_command("stamp-rejection", "# Seed\n", 5),
    ),
  )
  assert_eq(projection_worker_response_kind(seeded), "ok")
  let invalid_advance = dispatch(
    projection_worker_request(
      2,
      projection_worker_advance_command(
        Some("# Invalid\n"),
        generation=6,
        sequence=2,
        source_revision=2,
      ),
    ),
  )
  assert_eq(projection_worker_response_kind(invalid_advance), "error")
  let after_advance = dispatch(
    projection_worker_request(3, projection_worker_command("snapshot")),
  )
  assert_eq(projection_worker_response_kind(after_advance), "ok")
  assert_eq(projection_worker_response_sequence(after_advance), 1)
  assert_eq(projection_worker_response_source_revision(after_advance), 1)
  let sequence_gap = dispatch(
    projection_worker_request(
      4,
      projection_worker_advance_command(
        Some("# Gap\n"),
        generation=5,
        sequence=3,
        source_revision=2,
      ),
    ),
  )
  assert_eq(projection_worker_response_kind(sequence_gap), "error")
  let after_gap = dispatch(
    projection_worker_request(5, projection_worker_command("snapshot")),
  )
  assert_eq(projection_worker_response_kind(after_gap), "ok")
  assert_eq(projection_worker_response_sequence(after_gap), 1)
  assert_eq(projection_worker_response_source_revision(after_gap), 1)
  let invalid_demand = dispatch(
    projection_worker_request(
      6,
      projection_worker_demand_command(false, true, false, generation=6),
    ),
  )
  assert_eq(projection_worker_response_kind(invalid_demand), "error")
  let after_demand = dispatch(
    projection_worker_request(7, projection_worker_command("snapshot")),
  )
  assert_eq(projection_worker_response_kind(after_demand), "ok")
  assert_eq(projection_worker_response_sequence(after_demand), 1)
  assert_eq(projection_worker_response_source_revision(after_demand), 1)
}
