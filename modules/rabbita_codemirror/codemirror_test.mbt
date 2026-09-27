///|
test "SelRange constructor exposes selection offsets to consumers" {
  let range = @rabbita_codemirror.SelRange::new(2, 5)
  inspect(range.from, content="2")
  inspect(range.to, content="5")
}

///|
test "ChangeEvent preserves its transaction snapshot and source version" {
  let event = @rabbita_codemirror.ChangeEvent::new(
    [@rabbita_codemirror.ChangeDelta::new(1, 1, "x")],
    "after",
    source_version="v1",
  )
  inspect(event.changes.length(), content="1")
  inspect(event.doc, content="after")
  inspect(event.source_version, content="v1")
}

///|
test "mount accepts extension factory" {
  let factory : (@js_value.Value) -> @js_ffi.Extension raise = fn(_cm) {
    @js_ffi.js_extension_combine([])
  }
  ignore(
    @rabbita_codemirror.mount(
      "test-editor",
      "test-host",
      initial_extension=Some(factory),
    ),
  )
}
