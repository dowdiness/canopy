///|
extern "js" fn request(text : String) -> @http.Request =
  #|(text) => new Request("https://example.test/doc?after=a", {method: "PUT", headers: {"Content-Type": "text/plain"}, body: text})

///|
async test "bounded text reading preserves generated Unicode and rejects one byte less" {
  let alphabet = ["文", "🌳", "a", "\n", "\u0000", "\"", "\\"]
  let cases : Array[Array[UInt]] = @quickcheck.samples(50)
  for sample in cases {
    let text = "🌳" +
      sample.map(n => alphabet[(n % 7U).reinterpret_as_int()]).join("")
    let size = @utf8.encode(text).length()
    assert_eq(request(text).read_text(max_bytes=size), text)
    let limited = try {
      let _ = request(text).read_text(max_bytes=size - 1)
      false
    } catch {
      @http.BodyError::TooLarge => true
      _ => false
    }
    assert_true(limited)
  }
}

///|
test "request metadata uses typed accessors" {
  let req = request("body")
  inspect(req.verb(), content="PUT")
  inspect(req.path(), content="/doc")
  assert_true(req.query("after") == Some("a"))
  assert_true(req.header("Missing") is None)
}

///|
extern "js" fn streamed(mode : String) -> @http.Request =
  #|(mode) => {
  #|  const chunks = mode === "reject_after_prefix" ? [[65], [66], [67]] : mode === "truncated" ? [[0xe6, 0x97]] : mode === "invalid" ? [[0xff]] : [[0xe6], [0x97, 0xa5, 0xf0], [0x9f], [0x8c, 0xb3, 0x21]];
  #|  let index = 0;
  #|  let cancelled = false;
  #|  const body = new ReadableStream({pull(controller) {
  #|    if (mode === "reject" || (mode === "reject_after_prefix" && index === 3)) throw new Error("read failed");
  #|    if (index < chunks.length) controller.enqueue(new Uint8Array(chunks[index++]));
  #|    else if (mode === "pending") return new Promise(resolve => setTimeout(() => { controller.close(); resolve(); }, 100));
  #|    else if (mode !== "oversize") controller.close();
  #|  }, cancel() { cancelled = true; }});
  #|  const request = new Request("https://example.test/", {method: "PUT", body, duplex: "half"});
  #|  request.cancellationObserved = () => cancelled;
  #|  return request;
  #|}

///|
extern "js" fn locked(request : @http.Request) -> Bool =
  #|(request) => request.body.locked

///|
extern "js" fn cancellation_observed(request : @http.Request) -> Bool =
  #|(request) => request.cancellationObserved()

///|
async test "cancelling a pending body read releases its lock" {
  let req = streamed("pending")
  let result = @async.with_timeout_opt(20, () => req.read_text(max_bytes=8))
  assert_true(result is None)
  assert_false(locked(req))
}

///|
async test "streaming preserves split UTF8 and releases locks on success and failure" {
  let req = streamed("valid")
  assert_eq(req.read_text(max_bytes=8), "日🌳!")
  assert_false(locked(req))
  for
    mode in [
      "truncated", "invalid", "reject", "reject_after_prefix", "oversize",
    ] {
    let req = streamed(mode)
    let rejected = try {
      let _ = req.read_text(max_bytes=if mode == "oversize" { 7 } else { 8 })
      false
    } catch {
      @http.BodyError::TooLarge => mode == "oversize"
      @http.BodyError::InvalidBody => mode != "oversize"
      _ => false
    }
    assert_true(rejected)
    assert_false(locked(req))
    if mode == "oversize" {
      assert_true(cancellation_observed(req))
    }
  }
}
