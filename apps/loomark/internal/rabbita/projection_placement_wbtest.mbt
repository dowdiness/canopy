///|
test "projection placement retains synchronous production after failed promotion" {
  assert_eq(projection_placement_from_query(None), ProjectionSynchronous)
  assert_eq(projection_placement_from_query(Some("")), ProjectionSynchronous)
  assert_eq(projection_placement_from_query(Some("unknown")), ProjectionSynchronous)
  assert_eq(projection_placement_from_query(Some("worker")), ProjectionWorker)
}

///|
test "projection placement admits only explicit comparison modes" {
  assert_eq(
    projection_placement_from_query(Some("in-process")),
    ProjectionInProcess,
  )
  assert_eq(
    projection_placement_from_query(Some("synchronous")),
    ProjectionSynchronous,
  )
}

///|
test "projection benchmark instrumentation requires an exact private opt-in" {
  assert_false(projection_benchmark_enabled_from_query(None))
  assert_false(projection_benchmark_enabled_from_query(Some("")))
  assert_false(projection_benchmark_enabled_from_query(Some("true")))
  assert_true(projection_benchmark_enabled_from_query(Some("1")))
}

///|
test "in-process projection client emits the Worker envelope synchronously" {
  let client = ProjectionInProcessClient::new("in-process-test")
  let stamp = projection_worker_client_test_stamp(3)
  let received : @ref.Ref[(Int, ProjectionStamp, String)?] = @ref.Ref(None)
  let request_id = client.seed(
    "# Title\n",
    stamp,
    projection_all_demand(),
    (request_id, callback_stamp, raw) => {
      received.val = Some((request_id, callback_stamp, raw))
    },
  )
  assert_eq(request_id, 1)
  guard received.val is Some((1, callback_stamp, raw)) else {
    fail("in-process projection response missing")
  }
  assert_eq(callback_stamp, stamp)
  guard projection_worker_response_artifact(raw)
    is Ok((1, response_stamp, Some(_))) else {
    fail("in-process projection response must carry a typed artifact")
  }
  assert_eq(response_stamp, stamp)
  client.dispose()
}
