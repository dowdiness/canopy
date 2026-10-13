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
test "authorization response decoding returns validated URLs or unavailable" {
  assert_true(
    parse_authorization_url(
      "{\"url\":\"https://accounts.google.com/o/oauth2/auth?client=ok\"}",
    )
    is Some(_),
  )
  assert_true(parse_authorization_url("{}") is None)
  assert_true(parse_authorization_url("not JSON") is None)
}

///|
test "Google authorization URL parser validates HTTPS origin" {
  assert_true(
    GoogleAuthorizationUrl::parse(
      "https://accounts.google.com/o/oauth2/auth?client=ok",
    )
    is Some(_),
  )
  assert_true(
    GoogleAuthorizationUrl::parse("https://ACCOUNTS.GOOGLE.COM/oauth2/auth")
    is Some(_),
  )
  assert_true(
    GoogleAuthorizationUrl::parse("http://accounts.google.com/") is None,
  )
}

///|
test "Google authorization URL parser rejects hostile lookalike origins" {
  assert_true(
    GoogleAuthorizationUrl::parse("https://accounts.google.com:443/") is None,
  )
  assert_true(
    GoogleAuthorizationUrl::parse("https://accounts.google.com.evil.test/path")
    is None,
  )
  assert_true(
    GoogleAuthorizationUrl::parse("https://user@accounts.google.com/path")
    is None,
  )
  assert_true(
    GoogleAuthorizationUrl::parse("//accounts.google.com/path") is None,
  )
}
