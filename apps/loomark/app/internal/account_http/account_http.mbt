///|
pub struct GoogleAuthorizationUrl {
  priv value : String
} derive(Eq, Debug)

///|
pub fn GoogleAuthorizationUrl::value(self : Self) -> String {
  self.value
}

///|
pub(all) enum LoginResult {
  Prepared(GoogleAuthorizationUrl)
  Unavailable
} derive(Eq, Debug)

///|
pub(all) enum LogoutResult {
  SignedOut
  Unconfirmed
} derive(Eq, Debug)

///|
priv struct AccountResponse {
  id : String
  name : String
} derive(FromJson)

///|
priv struct AuthorizationResponse {
  url : String
} derive(FromJson)

///|
extenum @cmd.Extension += {
  ResolveAccount((@sync.AccountResult) -> @cmd.Cmd)
  PrepareLogin((LoginResult) -> @cmd.Cmd)
  SignOut((LogoutResult) -> @cmd.Cmd)
}

///|
fn account_result(status : Int, body : String) -> @sync.AccountResult {
  match status {
    200 =>
      try {
        let account : AccountResponse = @json.from_json(@json.parse(body))
        let id = @source_repository.AccountId::parse(account.id)
        @sync.Resolved(id, account.name)
      } catch {
        _ => @sync.AccountUnavailable
      }
    401 => @sync.SignedOut
    _ => @sync.AccountUnavailable
  }
}

///|
fn authorization_url(body : String) -> LoginResult {
  try {
    let response : AuthorizationResponse = @json.from_json(@json.parse(body))
    let parsed = @url.parse(response.url)
    let normalized = response.url.to_lower()
    guard normalized.has_prefix("https://accounts.google.com/") &&
      parsed is { protocol: @url.Protocol::Https, host, port: None, .. } &&
      host.to_lower() == "accounts.google.com" else {
      return Unavailable
    }
    Prepared(GoogleAuthorizationUrl::{ value: response.url, })
  } catch {
    _ => Unavailable
  }
}

///|
async fn resolve_request(origin : String) -> @sync.AccountResult noraise {
  try {
    let (response, body) = @async_http.get(origin + "/api/account")
    account_result(response.code, @utf8.decode(body.binary()[:]))
  } catch {
    _ => @sync.AccountUnavailable
  } noraise {
    result => result
  }
}

///|
async fn login_request(origin : String) -> LoginResult noraise {
  try {
    let body = "{\"provider\":\"google\",\"callbackURL\":\"/\",\"errorCallbackURL\":\"/\",\"disableRedirect\":true}"
    let (response, response_body) = @async_http.post(
      origin + "/api/auth/sign-in/social",
      @utf8.encode(body),
      headers={ "content-type": "application/json" },
    )
    if response.code is (200..<300) {
      authorization_url(@utf8.decode(response_body.binary()[:]))
    } else {
      Unavailable
    }
  } catch {
    _ => Unavailable
  } noraise {
    result => result
  }
}

///|
async fn logout_request(origin : String) -> LogoutResult noraise {
  try {
    let (response, _) = @async_http.post(
      origin + "/api/auth/sign-out",
      @utf8.encode("{}"),
      headers={ "content-type": "application/json" },
    )
    if response.code is (200..<300) {
      SignedOut
    } else {
      Unconfirmed
    }
  } catch {
    _ => Unconfirmed
  } noraise {
    result => result
  }
}

///|
let op : @cmd.Op = @cmd.Op()..on_invoke((extension, context) => {
  match extension {
    ResolveAccount(done) =>
      @cmd.Async(() => done(resolve_request(context.get_origin())))
    PrepareLogin(done) =>
      @cmd.Async(() => done(login_request(context.get_origin())))
    SignOut(done) =>
      @cmd.Async(() => done(logout_request(context.get_origin())))
    _ => raise @cmd.Unhandled
  }
})

///|
pub fn resolve(emit : @cmd.Emit[@sync.AccountResult]) -> @cmd.Cmd {
  op.request(ResolveAccount(result => emit(result)))
}

///|
pub fn prepare_login(emit : @cmd.Emit[LoginResult]) -> @cmd.Cmd {
  op.request(PrepareLogin(result => emit(result)))
}

///|
pub fn sign_out(emit : @cmd.Emit[LogoutResult]) -> @cmd.Cmd {
  op.request(SignOut(result => emit(result)))
}
