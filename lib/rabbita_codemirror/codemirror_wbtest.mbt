///|
test "listen key format" {
  inspect(
    build_listen_key("a", true, true, false, true),
    content="codemirror.listen(id=a,doc=true,selection=true,focus=false,changes=true)",
  )
}

///|
test "listen key deterministic" {
  inspect(
    build_listen_key("a", true, false, false, false) ==
    build_listen_key("a", true, false, false, false),
    content="true",
  )
}

///|
test "listen key id matters" {
  inspect(
    build_listen_key("a", true, false, false, false) ==
    build_listen_key("b", true, false, false, false),
    content="false",
  )
}

///|
test "listen key doc flag matters" {
  inspect(
    build_listen_key("a", true, false, false, false) ==
    build_listen_key("a", false, false, false, false),
    content="false",
  )
}

///|
test "listen key selection and focus flags matter" {
  inspect(
    build_listen_key("a", false, true, false, false) ==
    build_listen_key("a", false, false, true, false),
    content="false",
  )
}

///|
test "listen key changes flag matters" {
  inspect(
    build_listen_key("a", false, false, false, false) ==
    build_listen_key("a", false, false, false, true),
    content="false",
  )
}
