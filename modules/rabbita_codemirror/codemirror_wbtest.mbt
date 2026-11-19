///|
test "shortcut signature preserves order and boundaries" {
  inspect(
    build_shortcut_signature([
      Shortcut::new("a", @cmd.none),
      Shortcut::new("bc", @cmd.none),
    ]),
    content="2:1:a:02:bc:0",
  )
}

///|
test "shortcut signature preserves duplicate occurrences" {
  inspect(
    build_shortcut_signature([
      Shortcut::new("Mod-z", @cmd.none),
      Shortcut::new("Mod-z", @cmd.none),
    ]),
    content="2:5:Mod-z:05:Mod-z:0",
  )
}

///|
test "shortcut signature includes shifted command shape" {
  inspect(
    build_shortcut_signature([
      Shortcut::new("Mod-z", @cmd.none, shift=@cmd.none),
    ]),
    content="1:5:Mod-z:1",
  )
}

///|
test "listen key format" {
  inspect(
    build_listen_key("a", true, true, false, true, false),
    content="codemirror.listen(id=a,doc=true,selection=true,focus=false,changes=true,changes_with_doc=false)",
  )
}

///|
test "listen key deterministic" {
  inspect(
    build_listen_key("a", true, false, false, false, false) ==
    build_listen_key("a", true, false, false, false, false),
    content="true",
  )
}

///|
test "listen key id matters" {
  inspect(
    build_listen_key("a", true, false, false, false, false) ==
    build_listen_key("b", true, false, false, false, false),
    content="false",
  )
}

///|
test "listen key doc flag matters" {
  inspect(
    build_listen_key("a", true, false, false, false, false) ==
    build_listen_key("a", false, false, false, false, false),
    content="false",
  )
}

///|
test "listen key selection and focus flags matter" {
  inspect(
    build_listen_key("a", false, true, false, false, false) ==
    build_listen_key("a", false, false, true, false, false),
    content="false",
  )
}

///|
test "listen key changes flag matters" {
  inspect(
    build_listen_key("a", false, false, false, false, false) ==
    build_listen_key("a", false, false, false, true, false),
    content="false",
  )
}

///|
test "listen key snapshot flag matters" {
  inspect(
    build_listen_key("a", false, false, false, false, false) ==
    build_listen_key("a", false, false, false, false, true),
    content="false",
  )
}

///|
#cfg(target="js")
extern "js" fn zz_make_changes() -> @js_value.Value =
  #| () => [{ from: 5, to: 5, insert: "Z" }, { from: 9, to: 11, insert: "" }]

///|
#cfg(target="js")
test "change deltas decode a JS array of ranges" {
  let deltas = change_deltas_from_value(zz_make_changes())
  inspect(deltas.length(), content="2")
  inspect(deltas[0].from, content="5")
  inspect(deltas[0].insert, content="Z")
  inspect(deltas[1].to, content="11")
}
