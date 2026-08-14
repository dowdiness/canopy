///|
test "Worker client expected stamps match dispatcher Seed and Advance" {
  let dispatch = new_projection_worker_dispatcher()
  let seeded = dispatch(
    projection_worker_request(
      1,
      projection_worker_seed_command("client-stamp", "# Seed\n", 9),
    ),
  )
  let seed_stamp = projection_worker_client_seed_stamp(9)
  assert_eq(
    projection_worker_response_stamp_json_fields(seeded),
    projection_worker_stamp_json(seed_stamp),
  )
  let advanced = dispatch(
    projection_worker_request(
      2,
      projection_worker_advance_command(Some("# Next\n")),
    ),
  )
  let advance_stamp = projection_worker_client_advance_stamp(seed_stamp)
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
  guard decoded is Ok((stamp, Some(artifact))) else {
    fail("successful Worker response must carry a typed Preview artifact")
    return
  }
  assert_eq(stamp, projection_worker_client_seed_stamp(3))
  assert_eq(artifact.root.children.length(), 2)
  let failed = projection_worker_response_artifact(
    "{\"schema_version\":\"1\",\"request_id\":1,\"kind\":\"error\",\"error\":{\"kind\":\"timeout\",\"detail\":\"projection timed out\"}}",
  )
  assert_eq(failed, Err("projection timed out"))
}

///|
fn projection_worker_response_stamp_json_fields(raw : String) -> Json {
  projection_worker_response(raw)["stamp"]
}
