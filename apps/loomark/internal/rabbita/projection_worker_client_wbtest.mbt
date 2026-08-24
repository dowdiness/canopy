///|
fn projection_worker_client_test_stamp(
  generation : Int,
  sequence? : Int = 1,
) -> ProjectionStamp {
  {
    generation,
    sequence,
    source_revision: sequence,
    causal_version: "projection-session-" + sequence.to_string(),
    block_intent: sequence,
  }
}

///|
test "Worker client expected stamps match dispatcher Seed and Advance" {
  let dispatch = new_projection_worker_dispatcher()
  let seeded = dispatch(
    projection_worker_request(
      1,
      projection_worker_seed_command("client-stamp", "# Seed\n", 9),
    ),
  )
  let seed_stamp = projection_worker_client_test_stamp(9)
  assert_eq(
    projection_worker_response_stamp_json_fields(seeded),
    projection_worker_stamp_json(seed_stamp),
  )
  let advanced = dispatch(
    projection_worker_request(
      2,
      projection_worker_advance_command(Some("# Next\n"), generation=9),
    ),
  )
  let advance_stamp = projection_worker_client_test_stamp(9, sequence=2)
  assert_eq(
    projection_worker_response_stamp_json_fields(advanced),
    projection_worker_stamp_json(advance_stamp),
  )
}

///|
test "Worker client decodes typed Preview artifacts and explicit failures" {
  let dispatch = new_projection_worker_dispatcher()
  let raw = dispatch(
    projection_worker_request(
      1,
      projection_worker_seed_command(
        "client-artifact", "# Heading\n\nBody\n", 3,
      ),
    ),
  )
  let decoded = projection_worker_response_artifact(raw)
  guard decoded is Ok((1, stamp, Some(preview))) else {
    fail("successful Worker response must carry a source-bound Preview")
    return
  }
  assert_eq(stamp, projection_worker_client_test_stamp(3))
  assert_eq(preview.source, "# Heading\n\nBody\n")
  assert_eq(preview.artifact.root.children.length(), 2)
  let failed = projection_worker_response_artifact(
    "{\"schema_version\":\"1\",\"request_id\":1,\"kind\":\"error\",\"error\":{\"kind\":\"timeout\",\"detail\":\"projection timed out\"}}",
  )
  assert_eq(failed, Err("projection timed out"))
}

///|
test "Worker response acceptance orders same-stamp Demand requests" {
  let stamp = projection_worker_client_test_stamp(3)
  let older_request_id = 2
  let latest_request_id = 3
  let (older_accepted, after_older) = projection_worker_claim_response(
    Some(stamp),
    Some(latest_request_id),
    stamp,
    older_request_id,
  )
  assert_false(older_accepted)
  assert_eq(after_older, Some(latest_request_id))
  let (latest_accepted, after_latest) = projection_worker_claim_response(
    Some(stamp),
    after_older,
    stamp,
    latest_request_id,
  )
  assert_true(latest_accepted)
  assert_eq(after_latest, None)
  let (duplicate_accepted, after_duplicate) = projection_worker_claim_response(
    Some(stamp),
    after_latest,
    stamp,
    latest_request_id,
  )
  assert_false(duplicate_accepted)
  assert_eq(after_duplicate, None)
}

///|
test "stale error callback is ignored without consuming the current claim" {
  let stamp = projection_worker_client_test_stamp(3)
  let (accepted, remaining) = projection_worker_claim_response(
    Some(stamp),
    Some(9),
    stamp,
    8,
  )
  assert_false(accepted)
  assert_eq(remaining, Some(9))
}

///|
fn projection_worker_response_stamp_json_fields(raw : String) -> Json {
  projection_worker_response(raw)["stamp"]
}

///|
test "projection stamps follow authority across source-equal advance and restart" {
  let owner = ProjectionStampOwner::new()
  let seeded = try! owner.next(
    source_revision=7,
    causal_version="{\"version\":1}",
    block_intent=1,
  )
  let source_equal = try! owner.next(
    source_revision=7,
    causal_version="{\"version\":2}",
    block_intent=2,
  )
  assert_eq(source_equal.source_revision, seeded.source_revision)
  assert_eq(source_equal.sequence, seeded.sequence + 1)
  assert_false(source_equal.causal_version == seeded.causal_version)
  try! owner.restart()
  let restarted = try! owner.next(
    source_revision=7,
    causal_version="{\"version\":2}",
    block_intent=2,
  )
  assert_eq(restarted.generation, seeded.generation + 1)
  assert_eq(restarted.sequence, source_equal.sequence + 1)
}

///|
test "Worker correctness counters fail before wrap or reuse" {
  try projection_worker_allocate_request_id(2147483647) catch {
    error => assert_eq(error, ProjectionWorkerCounterError::RequestIdExhausted)
  } noraise {
    _ => fail("request ID exhaustion must raise")
  }
  let owner = ProjectionStampOwner::new(
    generation=2147483647,
    sequence=2147483646,
  )
  ignore(
    try! owner.next(
      source_revision=1,
      causal_version="{\"version\":1}",
      block_intent=1,
    ),
  )
  try owner.restart() catch {
    error => assert_eq(error, ProjectionWorkerCounterError::GenerationExhausted)
  } noraise {
    _ => fail("generation exhaustion must raise")
  }
  try
    owner.next(
      source_revision=1,
      causal_version="{\"version\":2}",
      block_intent=1,
    )
  catch {
    error => assert_eq(error, ProjectionWorkerCounterError::SequenceExhausted)
  } noraise {
    _ => fail("sequence exhaustion must raise")
  }
}

///|
test "rapid authority advances accept only the latest callback token" {
  let first = projection_worker_client_test_stamp(4, sequence=8)
  let latest = projection_worker_client_test_stamp(4, sequence=9)
  assert_false(
    projection_worker_response_matches(Some(latest), Some(23), first, 22),
  )
  assert_true(
    projection_worker_response_matches(Some(latest), Some(23), latest, 23),
  )
}

///|
test "callback stamp mismatch is rejected even for the current request" {
  let expected = projection_worker_client_test_stamp(5, sequence=3)
  let mismatched = { ..expected, causal_version: "different-authority" }
  assert_false(
    projection_worker_response_matches(Some(expected), Some(17), mismatched, 17),
  )
}

///|
test "current malformed response reaches typed decode failure" {
  let expected = projection_worker_client_test_stamp(6)
  assert_true(
    projection_worker_response_matches(Some(expected), Some(1), expected, 1),
  )
  assert_eq(
    projection_worker_response_artifact("{"),
    Err("projection Worker response is not valid JSON"),
  )
}
