///|
test "listen key format" {
  inspect(
    build_listen_key("a", true, true, false),
    content="codemirror.listen(id=a,doc=true,selection=true,focus=false)",
  )
}

///|
test "listen key deterministic" {
  inspect(
    build_listen_key("a", true, false, false) ==
    build_listen_key("a", true, false, false),
    content="true",
  )
}

///|
test "listen key id matters" {
  inspect(
    build_listen_key("a", true, false, false) ==
    build_listen_key("b", true, false, false),
    content="false",
  )
}

///|
test "listen key doc flag matters" {
  inspect(
    build_listen_key("a", true, false, false) ==
    build_listen_key("a", false, false, false),
    content="false",
  )
}

///|
test "listen key selection and focus flags matter" {
  inspect(
    build_listen_key("a", false, true, false) ==
    build_listen_key("a", false, false, true),
    content="false",
  )
}
