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
fn projection_worker_response_stamp_json_fields(raw : String) -> Json {
  projection_worker_response(raw)["stamp"]
}
