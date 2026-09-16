///|
#external
pub type Request

///|
#external
pub type Response

///|
pub(all) suberror BodyError {
  TooLarge
  InvalidBody
  InvalidLimit
} derive(Debug, Eq)

///|
pub fn Request::verb(self : Request) -> String {
  @js.any(self).get("method").cast()
}

///|
pub fn Request::header(self : Request, name : String) -> String? raise {
  @js.try_sync(() => @js.any(self).get("headers").call("get", [@js.any(name)])).to_option()
}

///|
fn Request::url(self : Request) -> @js.Any {
  @js.global().get("URL").construct([@js.any(self).get("url")])
}

///|
pub fn Request::path(self : Request) -> String {
  self.url().get("pathname").cast()
}

///|
pub fn Request::query(self : Request, name : String) -> String? {
  self.url().get("searchParams").call("get", [@js.any(name)]).to_option()
}

///|
pub fn Response::json(body : Json, status? : Int = 200) -> Response raise {
  @js.try_sync(() => {
    let options = @js.object()
    options.set("status", @js.any(status))
    let headers = @js.object()
    headers.set("Content-Type", @js.any("application/json"))
    options.set("headers", headers)
    @js.global().get("Response").construct([@js.any(body.stringify()), options])
  }).cast()
}

///|
/// Consumes a body once, with strict UTF-8 decoding and a byte limit checked
/// before accumulation. Oversize input cancels the reader; every path releases
/// its lock. This does not interpret JSON, content type or application policy.
pub async fn Request::read_text(self : Request, max_bytes~ : Int) -> String {
  if max_bytes < 0 {
    raise InvalidLimit
  }
  let body = @js.any(self).get("body")
  if body.is_nullish() {
    raise InvalidBody
  }
  let reader = @js.try_sync(() => body.call("getReader", [])) catch {
    _ => raise InvalidBody
  }
  defer {
    let _ = @js.try_sync(() => reader.call("releaseLock", [])) catch {
      _ => raise InvalidBody
    }
  }
  let options = @js.object()
  options.set("fatal", @js.any(true))
  let decoder = @js.global()
    .get("TextDecoder")
    .construct([@js.any("utf-8"), options])
  let streaming = @js.object()
  streaming.set("stream", @js.any(true))
  let text = StringBuilder()
  let result : Result[String, BodyError] = try {
    for size = 0 {
      let chunk : @js.Any = @js.try_sync(() => reader.call("read", [])).await_()
      let done : Bool = chunk.get("done").cast()
      if done {
        break
      }
      let bytes = chunk.get("value")
      let count : Int = bytes.get("byteLength").cast()
      if count > max_bytes - size {
        let _ : @js.Any = @js.try_sync(() => reader.call("cancel", [])).await_()
        raise TooLarge
      }
      let decoded : String = @js.try_sync(() => {
        decoder.call("decode", [bytes, streaming])
      }).cast()
      text.write_string(decoded)
      continue size + count
    }
    let ending : String = @js.try_sync(() => decoder.call("decode", [])).cast()
    text.write_string(ending)
    Ok(text.to_string())
  } catch {
    TooLarge => Err(TooLarge)
    _ => Err(InvalidBody)
  }
  match result {
    Ok(text) => text
    Err(error) => raise error
  }
}
