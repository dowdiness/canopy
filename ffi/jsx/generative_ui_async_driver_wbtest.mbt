///|
/// Package-level coverage for the deterministic async driver shell.
fn async_driver_int(value : @js.Any, key : String) -> Int {
  value.get(key).cast()
}

///|
async test "property: async driver disposal rejects late input without affecting another session" {
  let handle_a = 1
  let handle_b = 2
  let driver_a = @js.parse(__jsx_async_driver_new(handle_a, 1))
  let driver_b = @js.parse(__jsx_async_driver_new(handle_b, 1))
  let driver_handle_a = async_driver_int(driver_a, "driver_handle")
  let driver_handle_b = async_driver_int(driver_b, "driver_handle")
  let generation_a = async_driver_int(driver_a, "generation_id")
  let generation_b = async_driver_int(driver_b, "generation_id")
  assert_true(handle_a != handle_b)
  assert_true(driver_handle_a != driver_handle_b)
  assert_true(generation_a == generation_b)

  __jsx_async_driver_queue_chunk(
    driver_handle_a, generation_a, 1, 0, "<div>late</div>",
  )
  __jsx_async_driver_dispose(driver_handle_a)
  let late = @js.parse(
    @js_async.run_promise(_ => __jsx_async_driver_resolve_next(driver_handle_a)),
  )
  assert_eq(late.get("kind").cast(), "driver_error")

  __jsx_async_driver_queue_chunk(
    driver_handle_b, generation_b, 1, 0, "<div>active</div>",
  )
  let active_chunk = @js.parse(
    @js_async.run_promise(_ => __jsx_async_driver_resolve_next(driver_handle_b)),
  )
  assert_eq(active_chunk.get("kind").cast(), "chunk_accepted")
  assert_eq(active_chunk.get("sequence").cast(), 0)
  __jsx_async_driver_queue_final(driver_handle_b, generation_b, 1, 1)
  let active_final = @js.parse(
    @js_async.run_promise(_ => __jsx_async_driver_resolve_next(driver_handle_b)),
  )
  assert_eq(active_final.get("kind").cast(), "finalized")
  let stats = @js.parse(__jsx_async_driver_stats(driver_handle_b))
  assert_false(stats.get("abort_observed").cast())
  assert_eq(stats.get("commit_count").cast(), 0)

  __jsx_async_driver_dispose(driver_handle_b)
}

///|
async test "disposed settled continuation cannot dispatch late input" {
  let session_handle = 4
  let driver = @js.parse(__jsx_async_driver_new(session_handle, 1))
  let driver_handle = async_driver_int(driver, "driver_handle")
  let generation_id = async_driver_int(driver, "generation_id")
  __jsx_async_driver_queue_chunk(
    driver_handle, generation_id, 1, 0, "<div>late</div>",
  )
  let waiter = __jsx_async_driver_resolve_next(driver_handle)
  __jsx_async_driver_dispose(driver_handle)
  let late = @js.parse(@js_async.run_promise(_ => waiter))
  assert_eq(late.get("kind").cast(), "driver_error")
  assert_eq(late.get("reason").cast(), "async driver is disposed")
}

///|
async test "provider promise rejection is classified through Promise::wait" {
  let session_handle = 3
  let driver = @js.parse(__jsx_async_driver_new(session_handle, 1))
  let driver_handle = async_driver_int(driver, "driver_handle")
  let generation_id = async_driver_int(driver, "generation_id")
  let provider = @js.parse(
    __jsx_async_driver_provider_new(driver_handle, generation_id, 1, 0),
  )
  let provider_handle = async_driver_int(provider, "provider_handle")
  let waiter = __jsx_async_driver_provider_wait(provider_handle)
  __jsx_async_driver_provider_reject(provider_handle, "quota", "provider quota")
  let result = @js.parse(@js_async.run_promise(_ => waiter))
  assert_eq(result.get("kind").cast(), "provider_failed")
  assert_eq(result.get("code").cast(), "quota")
  assert_eq(result.get("reason").cast(), "provider quota")
  __jsx_async_driver_dispose(driver_handle)
}
