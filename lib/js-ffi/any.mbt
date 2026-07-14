// The `Any` handle and its zero-cost conversions.
//
// `Any` is `#external`: at runtime it *is* the JavaScript value, so every
// conversion here compiles to nothing (`%identity`). They exist only to move a
// value across MoonBit's type boundary — never to transform it.

///|
/// An opaque handle to any JavaScript value.
#external
pub type Any

///|
/// Reinterpret one representation as another with no runtime cost. The caller
/// asserts the JS representations match; misuse is unchecked. Prefer the named
/// helpers (`any` / `cast`) — reach for this only when neither side is `Any`.
pub fn[A, B] identity(value : A) -> B = "%identity"

///|
/// View a MoonBit value as a JS `Any`.
pub fn[T] any(value : T) -> Any = "%identity"

///|
/// Reinterpret an `Any` as `T`. Unchecked: `T` must match the runtime value.
pub fn[T] Any::cast(self : Any) -> T = "%identity"

///|
/// View an `Option` as `Any`: `None` becomes JS `undefined`, `Some(v)` becomes
/// `v`. (A concrete `Option[T]` already compiles to `T | undefined` in JS.)
pub fn[T] nullable(value : T?) -> Any = "%identity"

///|
/// Read a possibly-absent JS value into an `Option`: `null`/`undefined` →
/// `None`, otherwise `Some(cast)`. The safe alternative to `cast` for values
/// that may be missing — avoids materializing a `Some(null)`.
pub fn[T] Any::to_option(self : Any) -> T? {
  if self.is_nullish() {
    None
  } else {
    Some(self.cast())
  }
}

// MoonBit closures as JS callables (zero-cost). Pick the wrapper by arity; the
// wrapped function is invoked by JS with the matching number of arguments.

///|
pub fn[A] fn0(f : () -> A) -> Any = "%identity"

///|
pub fn[A, B] fn1(f : (A) -> B) -> Any = "%identity"

///|
pub fn[A, B, C] fn2(f : (A, B) -> C) -> Any = "%identity"

///|
pub fn[A, B, C, D] fn3(f : (A, B, C) -> D) -> Any = "%identity"
