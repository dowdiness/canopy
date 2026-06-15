// The JS escape hatches: property access, method/function calls, construction,
// globals, type guards, object/array builders, and JSON. Every binding in the
// codebase can be expressed with these — `host.call("save", [..])` instead of a
// bespoke `extern "js"` per method.

// ── Members ───────────────────────────────────────────────────────────────

///|
/// `self[key]`
pub extern "js" fn Any::get(self : Any, key : String) -> Any =
  #|(o, k) => o[k]

///|
/// `self[index]`
pub extern "js" fn Any::at(self : Any, index : Int) -> Any =
  #|(o, i) => o[i]

///|
/// `self[key] = value`
pub extern "js" fn Any::set(self : Any, key : String, value : Any) -> Unit =
  #|(o, k, v) => { o[k] = v; }

///|
/// `self[name](...args)` — call the method `name` on `self`.
pub extern "js" fn Any::call(
  self : Any,
  name : String,
  args : Array[Any],
) -> Any =
  #|(o, m, args) => o[m](...args)

///|
/// `self(...args)` — call `self` itself as a function.
pub extern "js" fn Any::invoke(self : Any, args : Array[Any]) -> Any =
  #|(f, args) => f(...args)

///|
/// `new self(...args)` — construct via `self` as a class/constructor.
pub extern "js" fn Any::construct(self : Any, args : Array[Any]) -> Any =
  #|(c, args) => new c(...args)

// ── Globals & builders ──────────────────────────────────────────────────────

///|
/// `globalThis`
pub extern "js" fn global() -> Any =
  #|() => globalThis

///|
/// A fresh `{}`.
pub extern "js" fn object() -> Any =
  #|() => ({})

///|
/// A fresh `[]`.
pub extern "js" fn array() -> Any =
  #|() => []

///|
/// JS `undefined`.
pub extern "js" fn undefined() -> Any =
  #|() => undefined

///|
/// JS `null`.
pub extern "js" fn null_() -> Any =
  #|() => null

// ── Type guards ─────────────────────────────────────────────────────────────

///|
/// `self == null` — true for both `null` and `undefined`.
pub extern "js" fn Any::is_nullish(self : Any) -> Bool =
  #|(v) => v == null

///|
/// `typeof self === "function"`
pub extern "js" fn Any::is_function(self : Any) -> Bool =
  #|(v) => typeof v === "function"

///|
/// `Array.isArray(self)`
pub extern "js" fn Any::is_array(self : Any) -> Bool =
  #|(v) => Array.isArray(v)

///|
/// `typeof self`
pub extern "js" fn Any::type_of(self : Any) -> String =
  #|(v) => typeof v

///|
/// `a === b` (reference / SameValueZero-ish identity).
pub extern "js" fn equal(a : Any, b : Any) -> Bool =
  #|(a, b) => a === b

///|
/// `Object.keys(self)`
pub extern "js" fn Any::keys(self : Any) -> Array[String] =
  #|(o) => Object.keys(o)

// ── JSON & stringify ────────────────────────────────────────────────────────

///|
/// `JSON.stringify(self)`. Non-serializable values (functions, `undefined`,
/// symbols) make `JSON.stringify` return `undefined`; coalesce to a real string
/// so the `String` return type never lies.
pub extern "js" fn Any::stringify(self : Any) -> String =
  #|(v) => JSON.stringify(v) ?? "undefined"

///|
/// `JSON.parse(text)`
pub extern "js" fn parse(text : String) -> Any =
  #|(t) => JSON.parse(t)

///|
/// `String(self)` for nullish, else `self.toString()`.
pub extern "js" fn Any::to_str(self : Any) -> String =
  #|(v) => v == null ? String(v) : v.toString()
