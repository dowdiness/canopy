///|
/// JavaScript exceptions captured as opaque values at the FFI boundary.
pub suberror JsError {
  JsError(Any)
}

///|
/// Invoke a JavaScript operation and convert thrown values to `JsError`.
pub fn try_sync(op : () -> Any) -> Any raise JsError {
  let result : @ref.Ref[Any?] = @ref.Ref(None)
  let error : @ref.Ref[Any?] = @ref.Ref(None)
  ffi_wrap_sync(op, value => result.val = Some(value), value => {
    error.val = Some(value)
  })
  match error.val {
    Some(value) => raise JsError(value)
    None =>
      match result.val {
        Some(value) => value
        None => raise JsError(any("JavaScript operation produced no result"))
      }
  }
}

///|
/// Safely derive a display detail without letting exception coercion escape.
pub fn error_detail(value : Any) -> String {
  js_error_detail(value)
}

///|
extern "js" fn js_error_detail(value : Any) -> String =
  #|(value) => {
  #|  try {
  #|    if (value == null) return "JavaScript exception";
  #|    if (typeof value === "string") return value;
  #|    if (typeof value.message === "string") return value.message;
  #|    return "JavaScript exception";
  #|  } catch (_) {
  #|    return "JavaScript exception";
  #|  }
  #|}

///|
extern "js" fn ffi_wrap_sync(
  op : () -> Any,
  on_ok : (Any) -> Unit,
  on_error : (Any) -> Unit,
) -> Unit =
  #|(op, on_ok, on_error) => {
  #|  try {
  #|    on_ok(op());
  #|  } catch (error) {
  #|    on_error(error);
  #|  }
  #|}
