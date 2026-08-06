///|
extern "js" fn without_web_crypto(callback : () -> String) -> String =
  #| (callback) => {
  #|   const descriptor = Object.getOwnPropertyDescriptor(globalThis, "crypto");
  #|   Object.defineProperty(globalThis, "crypto", { configurable: true, value: undefined });
  #|   try {
  #|     return callback();
  #|   } finally {
  #|     if (descriptor === undefined) delete globalThis.crypto;
  #|     else Object.defineProperty(globalThis, "crypto", descriptor);
  #|   }
  #| }

///|
test "identity allocation remains available without secure-context crypto" {
  let first = without_web_crypto(random_uuid)
  let second = without_web_crypto(random_uuid)
  assert_false(first.is_empty())
  assert_false(first == second)
}

///|
extern "js" fn install_fake_local_storage(initial : String?) -> Unit =
  #| (initial) => {
  #|   let value = { current: initial };
  #|   globalThis.localStorage = {
  #|     getItem() { return value.current == null ? null : value.current; },
  #|     setItem(_key, next) { value.current = next; },
  #|   };
  #| }

///|
extern "js" fn clear_local_storage() -> Unit =
  #| () => { delete globalThis.localStorage; }

///|
extern "js" fn install_throwing_local_storage(
  operation : String,
  name : String,
) -> Unit =
  #| (operation, name) => {
  #|   globalThis.localStorage = {
  #|     getItem() {
  #|       if (operation === "get") throw { name };
  #|       return null;
  #|     },
  #|     setItem() {
  #|       if (operation === "set") throw { name };
  #|     },
  #|   };
  #| }

///|
test "local storage binding classifies missing and loaded records" {
  install_fake_local_storage(None)
  let mut observed = ""
  get_item("loomark.active-document-archive", (kind, value) => {
    observed = kind.to_string() + ":" + value
  })
  assert_eq(observed, "0:")

  install_fake_local_storage(Some("archive"))
  get_item("loomark.active-document-archive", (kind, value) => {
    observed = kind.to_string() + ":" + value
  })
  assert_eq(observed, "1:archive")
}

///|
test "local storage binding preserves callback classification for failures" {
  clear_local_storage()
  let mut observed = ""
  get_item("loomark.active-document-archive", (kind, value) => {
    observed = kind.to_string() + ":" + value
  })
  assert_eq(observed, "2:")

  install_throwing_local_storage("get", "SecurityError")
  get_item("loomark.active-document-archive", (kind, value) => {
    observed = kind.to_string() + ":" + value
  })
  assert_eq(observed, "2:")

  install_throwing_local_storage("get", "UnknownError")
  get_item("loomark.active-document-archive", (kind, value) => {
    observed = kind.to_string() + ":" + value
  })
  assert_eq(observed, "3:")
}

///|
extern "js" fn install_preserving_write_failure(
  initial : String,
  name : String,
) -> Unit =
  #| (initial, name) => {
  #|   let current = { value: initial };
  #|   globalThis.localStorage = {
  #|     getItem() { return current.value; },
  #|     setItem() { throw { name }; },
  #|   };
  #| }

///|
test "local storage binding classifies writes and does not replace old value on failure" {
  install_fake_local_storage(Some("old"))
  let mut observed = -1
  set_item("loomark.active-document-archive", "new", kind => observed = kind)
  assert_eq(observed, 0)

  install_throwing_local_storage("set", "SecurityError")
  set_item("loomark.active-document-archive", "new", kind => observed = kind)
  assert_eq(observed, 1)

  install_throwing_local_storage("set", "QuotaExceededError")
  set_item("loomark.active-document-archive", "new", kind => observed = kind)
  assert_eq(observed, 2)

  install_throwing_local_storage("set", "UnknownError")
  set_item("loomark.active-document-archive", "new", kind => observed = kind)
  assert_eq(observed, 3)

  install_preserving_write_failure("old", "QuotaExceededError")
  set_item("loomark.active-document-archive", "new", kind => observed = kind)
  assert_eq(observed, 2)
  let mut preserved = ""
  get_item("loomark.active-document-archive", (_, value) => preserved = value)
  assert_eq(preserved, "old")
}
