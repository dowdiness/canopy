// Whitebox tests for RecoveryContext state machine.

///|
fn make_empty_sync_message() -> @text.SyncMessage raise {
  @text.SyncMessage::from_json_string("{\"runs\":[],\"heads\":[]}")
}

///|
test "RecoveryContext: new creates initial state" {
  let msg = make_empty_sync_message()
  let ctx = RecoveryContext::new("alice", msg, 1)
  inspect(ctx.peer_id, content="alice")
  inspect(ctx.retries, content="0")
  inspect(ctx.request_id, content="1")
  inspect(ctx.deferred.length(), content="0")
}

///|
test "RecoveryContext: advance_retry doubles backoff" {
  let msg = make_empty_sync_message()
  let ctx = RecoveryContext::new("alice", msg, 1)
  ctx.advance_retry(2)
  inspect(ctx.retries, content="1")
  inspect(500 << ctx.retries, content="1000")
  inspect(ctx.request_id, content="2")
  ctx.advance_retry(3)
  inspect(ctx.retries, content="2")
  inspect(500 << ctx.retries, content="2000")
  inspect(ctx.request_id, content="3")
}

///|
test "RecoveryContext: is_exhausted after 3 retries" {
  let msg = make_empty_sync_message()
  let ctx = RecoveryContext::new("alice", msg, 1)
  inspect(ctx.is_exhausted(), content="false")
  ctx.advance_retry(2)
  inspect(ctx.is_exhausted(), content="false")
  ctx.advance_retry(3)
  inspect(ctx.is_exhausted(), content="false")
  ctx.advance_retry(4)
  inspect(ctx.is_exhausted(), content="true")
}

///|
test "RecoveryContext: buffer_message adds to deferred" {
  let msg = make_empty_sync_message()
  let ctx = RecoveryContext::new("alice", msg, 1)
  let msg2 = make_empty_sync_message()
  ctx.buffer_message(msg2)
  inspect(ctx.deferred.length(), content="1")
}

///|
test "RecoveryContext: buffer caps at 32" {
  let msg = make_empty_sync_message()
  let ctx = RecoveryContext::new("alice", msg, 1)
  for i = 0; i < 40; i = i + 1 {
    ctx.buffer_message(make_empty_sync_message())
  }
  inspect(ctx.deferred.length(), content="32")
}

///|
test "RecoveryContext: matches_request_id" {
  let msg = make_empty_sync_message()
  let ctx = RecoveryContext::new("alice", msg, 42)
  inspect(ctx.matches_request_id("42"), content="true")
  inspect(ctx.matches_request_id("99"), content="false")
}
