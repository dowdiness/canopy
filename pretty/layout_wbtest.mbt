///|
test "Layout constructors" {
  let doc : Layout[Unit] = Concat(
    Text("hello"),
    Concat(Text(" "), Text("world")),
  )
  inspect(
    doc,
    content="Concat(Text(\"hello\"), Concat(Text(\" \"), Text(\"world\")))",
  )
}
