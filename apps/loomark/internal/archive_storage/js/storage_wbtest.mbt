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
