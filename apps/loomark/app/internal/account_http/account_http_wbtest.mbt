///|
test "account response is parsed once into its domain identity" {
  guard account_result(200, "{\"id\":\"account\",\"name\":\"Writer\"}")
    is @sync.Resolved(id, "Writer") else {
    fail("resolved account")
  }
  assert_eq(id.value(), "account")
}

///|
test "account response distinguishes signed out from unavailable" {
  assert_true(account_result(401, "") is @sync.SignedOut)
  assert_true(account_result(503, "") is @sync.AccountUnavailable)
  assert_true(
    account_result(200, "{\"id\":\"\",\"name\":\"Writer\"}")
    is @sync.AccountUnavailable,
  )
}
