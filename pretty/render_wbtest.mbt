///|
test "flat_width of text" {
  inspect(flat_width((text("hello") : Layout[Unit])), content="5")
}

///|
test "flat_width of line" {
  inspect(flat_width((line() : Layout[Unit])), content="1")
}

///|
test "flat_width of hardline" {
  inspect(flat_width((hardline() : Layout[Unit])), content="-1")
}

///|
test "flat_width of concat" {
  let doc : Layout[Unit] = text("ab") + text("cd")
  inspect(flat_width(doc), content="4")
}

///|
test "flat_width of concat with hardline" {
  let doc : Layout[Unit] = text("ab") + hardline() + text("cd")
  inspect(flat_width(doc), content="-1")
}

///|
test "flat_width of nest" {
  let doc : Layout[Unit] = nest(text("hello"))
  inspect(flat_width(doc), content="5")
}

///|
test "flat_width of group" {
  let doc : Layout[Unit] = group(text("hello"))
  inspect(flat_width(doc), content="5")
}

///|
test "flat_width of annotate" {
  let doc = annotate(42, text("hello"))
  inspect(flat_width(doc), content="5")
}

///|
test "resolve simple text" {
  let doc : Layout[Unit] = text("hello")
  inspect(resolve(80, doc), content="[CText(\"hello\")]")
}

///|
test "resolve concat" {
  let doc : Layout[Unit] = text("a") + text("b")
  inspect(resolve(80, doc), content="[CText(\"a\"), CText(\"b\")]")
}

///|
test "resolve hardline" {
  let doc : Layout[Unit] = text("a") + hardline() + text("b")
  inspect(resolve(80, doc), content="[CText(\"a\"), CNewline(0), CText(\"b\")]")
}

///|
test "resolve nest + hardline" {
  let doc : Layout[Unit] = text("a") + nest(hardline() + text("b"))
  inspect(resolve(80, doc), content="[CText(\"a\"), CNewline(2), CText(\"b\")]")
}

///|
test "resolve group that fits" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b"))
  inspect(
    resolve(80, doc),
    content="[CText(\"a\"), CText(\" \"), CText(\"b\")]",
  )
}

///|
test "resolve group that fits exactly" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b"))
  // flat_width = 3, width = 3: exact fit, should flatten (Wadler <=)
  inspect(resolve(3, doc), content="[CText(\"a\"), CText(\" \"), CText(\"b\")]")
}

///|
test "resolve group that breaks" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b"))
  // flat_width = 3, width = 2: doesn't fit, should break
  inspect(resolve(2, doc), content="[CText(\"a\"), CNewline(0), CText(\"b\")]")
}

///|
test "resolve annotate" {
  let doc = annotate("ann", text("x"))
  inspect(
    resolve(80, doc),
    content="[CAnnStart(\"ann\"), CText(\"x\"), CAnnEnd(\"ann\")]",
  )
}

///|
/// Group considers trailing suffix when deciding Flat vs Break.
/// group("a b") + "c" at width=3: group flat_width=3, suffix=1, total=4 > 3 → Break.
test "resolve group considers suffix" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b")) + text("c")
  // flat_width(group content) = 3, suffix "c" = 1, total = 4 > width 3 → Break
  inspect(
    resolve(3, doc),
    content="[CText(\"a\"), CNewline(0), CText(\"b\"), CText(\"c\")]",
  )
}

///|
/// When group + suffix fits exactly, it should still flatten.
test "resolve group with suffix fits exactly" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b")) + text("c")
  // flat_width = 3, suffix = 1, total = 4, width = 4: 4 <= 4 → Flat
  inspect(
    resolve(4, doc),
    content="[CText(\"a\"), CText(\" \"), CText(\"b\"), CText(\"c\")]",
  )
}
