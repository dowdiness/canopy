///|
extern "js" fn js_return_undefined() -> Any =
  #|() => undefined

///|
extern "js" fn js_return_null() -> Any =
  #|() => null

///|
extern "js" fn js_throw_undefined() -> Any =
  #|() => { throw undefined; }

///|
extern "js" fn js_throw_null() -> Any =
  #|() => { throw null; }
///|
extern "js" fn js_throw_error() -> Any =
  #|() => { throw new Error("boom"); }

///|
extern "js" fn js_throw_string() -> Any =
  #|() => { throw "primitive boom"; }

///|
extern "js" fn js_throw_proxy() -> Any =
  #|() => {
  #|  throw new Proxy({}, { get() { throw new Error("message failed"); } });
  #|}

///|
test "error_detail handles throwing message access" {
  let detail : String = try {
    let _ = try_sync(() => js_throw_proxy())
    "no exception"
  } catch {
    JsError(raw) => error_detail(raw)
  }
  inspect(detail, content="JavaScript exception")
}

///|
extern "js" fn js_throw_unstringifiable() -> Any =
  #|() => {
  #|  throw { [Symbol.toPrimitive]() { throw new Error("coercion failed"); } };
  #|}

///|
test "try_sync handles unstringifiable exceptions" {
  let detail : String = try {
    let _ = try_sync(() => js_throw_unstringifiable())
    "no exception"
  } catch {
    JsError(raw) => error_detail(raw)
  }
  inspect(detail, content="JavaScript exception")
}

///|
test "try_sync returns ordinary values" {
  let value : Int = try_sync(() => any(42)).cast()
  inspect(value, content="42")
}

///|
test "try_sync preserves undefined as nullish" {
  let value = try_sync(() => js_return_undefined())
  inspect(value.is_nullish(), content="true")
}
///|
test "try_sync preserves null as a successful value" {
  let value = try_sync(() => js_return_null())
  inspect(value.is_nullish(), content="true")
}

///|
test "try_sync preserves undefined exceptions" {
  let was_nullish = try {
    let _ = try_sync(() => js_throw_undefined())
    false
  } catch {
    JsError(raw) => raw.is_nullish()
  }
  inspect(was_nullish, content="true")
}

///|
test "try_sync preserves null exceptions" {
  let was_nullish = try {
    let _ = try_sync(() => js_throw_null())
    false
  } catch {
    JsError(raw) => raw.is_nullish()
  }
  inspect(was_nullish, content="true")
}

///|
test "try_sync normalizes Error exceptions" {
  let detail : String = try {
    let _ = try_sync(() => js_throw_error())
    "no exception"
  } catch {
    JsError(raw) => error_detail(raw)
  }
  inspect(detail, content="boom")
}

///|
test "try_sync normalizes primitive exceptions" {
  let detail : String = try {
    let _ = try_sync(() => js_throw_string())
    "no exception"
  } catch {
    JsError(raw) => error_detail(raw)
  }
  inspect(detail, content="primitive boom")
}
