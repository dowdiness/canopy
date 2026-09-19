///|
priv struct AccountResponse {
  id : String
  name : String
} derive(FromJson)

///|
extenum @cmd.Extension += {
  ResolveAccount((@sync.AccountResult) -> @cmd.Cmd)
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
async fn request(origin : String) -> @sync.AccountResult noraise {
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
let op : @cmd.Op = @cmd.Op()..on_invoke((extension, context) => {
  match extension {
    ResolveAccount(done) =>
      @cmd.Async(() => done(request(context.get_origin())))
    _ => raise @cmd.Unhandled
  }
})

///|
pub fn resolve(emit : @cmd.Emit[@sync.AccountResult]) -> @cmd.Cmd {
  op.request(ResolveAccount(result => emit(result)))
}
