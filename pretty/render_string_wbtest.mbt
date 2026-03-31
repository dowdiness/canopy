///|
test "render_string simple" {
  let doc : Layout[Unit] = text("hello")
  inspect(render_string(doc), content="hello")
}

///|
test "render_string hardline" {
  let doc : Layout[Unit] = text("a") + hardline() + text("b")
  inspect(
    render_string(doc),
    content=(
      #|a
      #|b
    ),
  )
}

///|
test "render_string nest + hardline" {
  let doc : Layout[Unit] = text("a") + nest(hardline() + text("b"))
  inspect(
    render_string(doc),
    content=(
      #|a
      #|  b
    ),
  )
}

///|
test "render_string group fits" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b"))
  inspect(render_string(doc), content="a b")
}

///|
test "render_string group fits exactly" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b"))
  inspect(render_string(doc, width=3), content="a b")
}

///|
test "render_string group breaks" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b"))
  inspect(
    render_string(doc, width=2),
    content=(
      #|a
      #|b
    ),
  )
}

///|
test "render_string bracket" {
  let items : Layout[Unit] = separate(text(",") + line(), [
    text("1"),
    text("2"),
    text("3"),
  ])
  let doc = bracket("[", "]", items)
  inspect(
    render_string(doc, width=80),
    content=(
      #|[ 1, 2, 3 ]
    ),
  )
  inspect(
    render_string(doc, width=5),
    content=(
      #|[
      #|  1,
      #|  2,
      #|  3
      #|]
    ),
  )
}

///|
test "render_string nested brackets" {
  let inner : Layout[Unit] = bracket(
    "[",
    "]",
    separate(text(",") + line(), [text("a"), text("b")]),
  )
  let outer = bracket(
    "[",
    "]",
    separate(text(",") + line(), [text("x"), inner, text("y")]),
  )
  inspect(
    render_string(outer, width=80),
    content=(
      #|[ x, [ a, b ], y ]
    ),
  )
  inspect(
    render_string(outer, width=10),
    content=(
      #|[
      #|  x,
      #|  [
      #|    a,
      #|    b
      #|  ],
      #|  y
      #|]
    ),
  )
}
