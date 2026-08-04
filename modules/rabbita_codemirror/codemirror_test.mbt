///|
test "SelRange constructor exposes selection offsets to consumers" {
  let range = SelRange::new(2, 5)
  inspect(range.from, content="2")
  inspect(range.to, content="5")
}

///|
test "mount accepts extension factory" {
  let factory : (@js_value.Value) -> @js_ffi.Extension raise = fn(_cm) {
    @js_ffi.js_extension_combine([])
  }
  ignore(mount("test-editor", "test-host", initial_extension=Some(factory)))
}
