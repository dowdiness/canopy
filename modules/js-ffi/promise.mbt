// Async bridge to JS Promises.
//
// We build on `moonbitlang/async` (canopy's async runtime, already a
// dependency — see ffi/lambda/llm.mbt) rather than reinventing the
// suspend/resume machinery: `@js_async.Promise[T]` is the canonical JS-Promise
// interop. lib/js only connects it to `Any`, so a JS value known to be a
// thenable can be awaited, and a MoonBit async computation can be handed back
// to JS as a Promise.

///|
/// View a JS thenable `Any` as a typed `Promise[T]` (zero-cost). Pair with the
/// async runtime's `wait`, or use `await_` below.
pub fn[T] Any::as_promise(self : Any) -> @js_async.Promise[T] = "%identity"

///|
/// Await a JS promise value into MoonBit. Use inside an `async` context:
/// `let text : String = obj.call("text", []).await_()`.
pub async fn[T] Any::await_(self : Any) -> T {
  self.as_promise().wait()
}

///|
/// Expose a MoonBit async computation to JS as a `Promise` (an `Any`), e.g. to
/// return one across the FFI boundary.
pub fn[T] promise(f : async () -> T) -> Any {
  @js_async.Promise::from_async(f) |> identity
}
