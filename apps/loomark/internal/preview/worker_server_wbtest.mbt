///|
test "worker server requires acknowledgement and transports detached blocks" {
  let server = WorkerServer::WorkerServer()
  let first = server.dispatch_text(
    "{\"type\":\"preview\",\"generation\":1,\"sequence\":0,\"source\":\"Alpha.\\n\\nBeta.\\n\"}",
  )
  assert_true(first.contains("\"blocks\""))
  assert_true(first.contains("\"node\""))
  let blocked = server.dispatch_text(
    "{\"type\":\"preview\",\"generation\":1,\"sequence\":1,\"source\":\"Later.\"}",
  )
  assert_true(blocked.contains("acknowledged"))
  ignore(
    server.dispatch_text(
      "{\"type\":\"ack\",\"generation\":1,\"sequence\":0,\"accepted\":true}",
    ),
  )
  let second = server.dispatch_text(
    "{\"type\":\"preview\",\"generation\":1,\"sequence\":1,\"source\":\"Alpha.\\n\\nChanged.\\n\"}",
  )
  assert_true(second.contains("\"blocks\""))
}

///|
test "worker server rejects malformed JSON and stale acknowledgements" {
  let server = WorkerServer::WorkerServer()
  assert_true(server.dispatch_text("not-json").contains("malformed"))
  assert_true(
    server
    .dispatch_text("{\"type\":\"ack\",\"sequence\":99,\"accepted\":true}")
    .contains("stale ack"),
  )
}
