///|
#external
priv type NativeModule

///|
#external
priv type Database

///|
extern "js" fn install_worker_listener(handler : (@js.Value) -> Unit) -> Unit =
  #| handler => { self.onmessage = event => handler(event.data) }

///|
extern "js" fn post_raw(value : @js.Value) -> Unit =
  #| value => self.postMessage(value)

///|
extern "js" fn invalid_envelope() -> Unit =
  #| () => { throw Error('Invalid request envelope') }

///|
extern "js" fn load_native() -> @js.Promise[@js.Value] =
  #| () => import('./worker-native.mjs').then(value => ({ok: true, value}), error => ({ok: false, error: error?.message || String(error)}))

///|
extern "js" fn js_invoke(
  api : NativeModule,
  name : String,
  args : FixedArray[@js.Value],
) -> @js.Value =
  #| (api, name, args) => api.invoke(name, ...args)

///|
extern "js" fn js_field(value : @js.Value, name : String) -> @js.Value =
  #| (value, name) => value == null ? undefined : value[name]

///|
extern "js" fn js_is_safe_integer(value : @js.Value) -> Bool =
  #| value => Number.isSafeInteger(value)

///|
extern "js" fn js_is_array(value : @js.Value) -> Bool =
  #| value => Array.isArray(value)

///|
extern "js" fn js_null() -> @js.Value =
  #| () => null

///|
extern "js" fn js_undefined() -> @js.Value =
  #| () => undefined

///|
extern "js" fn text_is_well_formed(value : String) -> Bool =
  #| value => value.isWellFormed()

///|
extern "js" fn text_slice(
  value : String,
  start : Double,
  end : Double,
) -> String =
  #| (value, start, end) => value.slice(start, end)

///|
extern "js" fn save_options(
  fault : Bool,
  hold : Double,
  before_commit : Double,
  checkpoint : () -> Unit,
) -> @js.Value =
  #| (abort, hold, beforeCommit, checkpoint) => ({abort, hold, beforeCommit, checkpoint})

///|
extern "js" fn never_resolves() -> @js.Promise[Unit] =
  #| () => new Promise(() => {})

///|
extern "js" fn js_error_message(value : @js.Value) -> String =
  #| value => value && value.message ? String(value.message) : String(value)

///|
fn error_text(error : Error) -> String {
  match error {
    @text.TextError::SyncFailed(reason) => reason.to_string()
    @js.Error_::Error_(value) => js_error_message(value)
    Failure(message) => message
    _ => error.to_string()
  }
}

///|
fn checked_string(value : @js.Value) -> String raise {
  if !value.is_string() {
    raise Failure("Expected a string")
  }
  value.cast()
}

///|
fn checked_double(value : @js.Value) -> Double raise {
  if !value.is_number() {
    raise Failure("Expected a number")
  }
  value.cast()
}

///|
fn field_string(value : @js.Value, name : String) -> String raise {
  checked_string(js_field(value, name))
}

///|
fn field_double(value : @js.Value, name : String) -> Double raise {
  checked_double(js_field(value, name))
}

///|
fn optional_double(value : @js.Value, name : String) -> Double raise {
  let field = js_field(value, name)
  if field.is_undefined() || field.is_null() {
    0.0
  } else {
    checked_double(field)
  }
}

///|
fn optional_bool(value : @js.Value, name : String) -> Bool raise {
  let field = js_field(value, name)
  if field.is_undefined() || field.is_null() {
    return false
  }
  if !field.is_bool() {
    raise Failure("Expected a boolean")
  }
  field.cast()
}

///|
fn native_array(value : @js.Value) -> Iter[@js.Value] raise {
  if !js_is_array(value) {
    raise Failure("Expected an array")
  }
  let array : @js.JsArray[@js.Value] = value.cast()
  array.iter().map(value => value.unwrap_or(js_undefined()))
}

///|
fn[T : @js.Cast] as_value(value : T) -> @js.Value {
  @js.Cast::from(value)
}

///|
fn object(fields : FixedArray[(String, @js.Value)]) -> @js.Value {
  let result = @js.Object::new()
  for (key, value) in fields {
    result.set(key, value)
  }
  result.to_value()
}

///|
fn native_call(
  api : NativeModule,
  name : String,
  args : FixedArray[@js.Value],
) -> @js.Value raise @js.Error_ {
  @js.Error_::wrap(() => js_invoke(api, name, args))
}

///|
async fn native_promise(
  api : NativeModule,
  name : String,
  args : FixedArray[@js.Value],
) -> @js.Value {
  let pending = native_call(api, name, args)
  let settled : @js.Promise[@js.Value] = native_call(api, "settle", [pending]).cast()
  let result = settled.wait()
  if !optional_bool(result, "ok") {
    raise Failure(field_string(result, "error"))
  }
  js_field(result, "value")
}

///|
fn now(api : NativeModule) -> Double raise {
  checked_double(native_call(api, "now", []))
}

///|
fn uuid(api : NativeModule) -> String raise {
  checked_string(native_call(api, "uuid", []))
}

///|
fn snapshot_changes(
  api : NativeModule,
  before : String,
  after : String,
) -> Changes raise {
  let value = native_call(api, "snapshotChanges", [
    as_value(before),
    as_value(after),
  ])
  let items : Array[TextChange] = []
  for change in native_array(value) {
    items.push(decode_change(change))
  }
  { items, approximate: optional_bool(value, "approximate"), }
}

///|
fn scalar_at(api : NativeModule, text : String, offset : Double) -> Int raise {
  // The shared helper checks bounds and rejects offsets splitting a surrogate pair.
  native_call(api, "scalarAt", [as_value(text), as_value(offset)]).cast()
}

///|
async fn read_rows(
  api : NativeModule,
  db : Database,
  document : String,
  cursor : Double,
) -> Array[JournalRow] {
  decode_rows(
    native_promise(api, "readJournal", [
      @js.Value::cast_from(db),
      as_value(document),
      as_value(cursor),
    ]),
  )
}
