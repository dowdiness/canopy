///|
test "text" {
  let doc : Layout[Unit] = text("hello")
  inspect(doc, content="Text(\"hello\")")
}

///|
test "char" {
  let doc : Layout[Unit] = char('x')
  inspect(doc, content="Text(\"x\")")
}

///|
test "line" {
  let doc : Layout[Unit] = line()
  inspect(doc, content="Line")
}

///|
test "hardline" {
  let doc : Layout[Unit] = hardline()
  inspect(doc, content="HardLine")
}

///|
test "softline is group(line)" {
  let doc : Layout[Unit] = softline()
  inspect(doc, content="Group(Line)")
}

///|
test "nest" {
  let doc : Layout[Unit] = nest(text("x"))
  inspect(doc, content="Nest(2, Text(\"x\"))")
}

///|
test "nest custom indent" {
  let doc : Layout[Unit] = nest(indent=4, text("x"))
  inspect(doc, content="Nest(4, Text(\"x\"))")
}

///|
test "group" {
  let doc : Layout[Unit] = group(text("x"))
  inspect(doc, content="Group(Text(\"x\"))")
}

///|
test "concat via +" {
  let doc : Layout[Unit] = text("a") + text("b")
  inspect(doc, content="Concat(Text(\"a\"), Text(\"b\"))")
}

///|
test "annotate" {
  let doc = annotate(42, text("x"))
  inspect(doc, content="Annotate(42, Text(\"x\"))")
}

///|
test "separate" {
  let doc : Layout[Unit] = separate(text(", "), [
    text("a"),
    text("b"),
    text("c"),
  ])
  inspect(
    doc,
    content="Concat(Concat(Concat(Concat(Text(\"a\"), Text(\", \")), Text(\"b\")), Text(\", \")), Text(\"c\"))",
  )
}

///|
test "separate empty" {
  let doc : Layout[Unit] = separate(text(", "), [])
  inspect(doc, content="Empty")
}

///|
test "parens" {
  let doc : Layout[Unit] = parens(text("x"))
  inspect(doc, content="Concat(Concat(Text(\"(\"), Text(\"x\")), Text(\")\"))")
}
