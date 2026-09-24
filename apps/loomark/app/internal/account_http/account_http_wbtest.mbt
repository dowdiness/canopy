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

///|
test "login adapter admits only Google HTTPS authorization URLs" {
  guard authorization_url(
      "{\"url\":\"https://accounts.google.com/o/oauth2/auth?client=ok\"}",
    )
    is Prepared(url) else {
    fail("Google URL should be prepared")
  }
  assert_true(url.value().has_prefix("https://accounts.google.com/"))
  assert_true(
    authorization_url("{\"url\":\"https://accounts.google.com.evil.test/\"}")
    is Unavailable,
  )
  assert_true(
    authorization_url("{\"url\":\"http://accounts.google.com/\"}")
    is Unavailable,
  )
}

///|
test "login adapter accepts browser-normalized Google host casing" {
  assert_true(
    authorization_url("{\"url\":\"https://ACCOUNTS.GOOGLE.COM/oauth2/auth\"}")
    is Prepared(_),
  )
}

///|
test "login adapter rejects hostile Google lookalike origins" {
  assert_true(
    authorization_url("{\"url\":\"https://accounts.google.com:443/\"}")
    is Unavailable,
  )
  assert_true(
    authorization_url(
      "{\"url\":\"https://accounts.google.com.evil.test/path\"}",
    )
    is Unavailable,
  )
  assert_true(
    authorization_url("{\"url\":\"https://user@accounts.google.com/path\"}")
    is Unavailable,
  )
  assert_true(
    authorization_url("{\"url\":\"//accounts.google.com/path\"}") is Unavailable,
  )
}
