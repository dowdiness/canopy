///|
test "heading then paragraph → SectionIntro" {
  let doc = @md.Document([
    @md.Heading(1, [@md.Text("Title")]),
    @md.Paragraph([@md.Text("Introduction")]),
  ])
  let map = annotate_symbolic(doc)
  inspect(map[1], content="RuleBased(SectionIntro)")
  inspect(map[0], content="Unknown")
}

///|
test "first paragraph → Abstract" {
  let doc = @md.Document([
    @md.Paragraph([@md.Text("Opening paragraph")]),
    @md.Paragraph([@md.Text("Second paragraph")]),
  ])
  let map = annotate_symbolic(doc)
  inspect(map[0], content="RuleBased(Abstract)")
  inspect(map[1], content="Unknown")
}

///|
test "paragraph before code block → CodeExplanation" {
  let doc = @md.Document([
    @md.Heading(2, [@md.Text("Example")]),
    @md.Paragraph([@md.Text("Section intro")]),
    @md.Paragraph([@md.Text("Here is the code:")]),
    @md.CodeBlock("moonbit", "let x = 1"),
  ])
  let map = annotate_symbolic(doc)
  inspect(map[1], content="RuleBased(SectionIntro)")
  inspect(map[2], content="RuleBased(CodeExplanation)")
}

///|
test "list after heading → KeyPoints" {
  let doc = @md.Document([
    @md.Heading(1, [@md.Text("Features")]),
    @md.UnorderedList([
      @md.ListItem([@md.Text("Fast")]),
      @md.ListItem([@md.Text("Safe")]),
    ]),
  ])
  let map = annotate_symbolic(doc)
  inspect(map[1], content="RuleBased(KeyPoints)")
}

///|
test "SectionIntro takes priority over CodeExplanation" {
  let doc = @md.Document([
    @md.Heading(1, [@md.Text("Demo")]),
    @md.Paragraph([@md.Text("After heading and before code")]),
    @md.CodeBlock("", "x = 1"),
  ])
  let map = annotate_symbolic(doc)
  inspect(map[1], content="RuleBased(SectionIntro)")
}

///|
test "non-Document input → empty array" {
  let block = @md.Paragraph([@md.Text("just a paragraph")])
  let map = annotate_symbolic(block)
  inspect(map.length(), content="0")
}

///|
test "empty document → empty array" {
  let doc = @md.Document([])
  let map = annotate_symbolic(doc)
  inspect(map.length(), content="0")
}

///|
test "heading first, paragraph later → no Abstract" {
  let doc = @md.Document([
    @md.Heading(1, [@md.Text("Title")]),
    @md.Paragraph([@md.Text("This is not Abstract")]),
  ])
  let map = annotate_symbolic(doc)
  // Not index 0, so not Abstract. After heading, so SectionIntro.
  inspect(map[1], content="RuleBased(SectionIntro)")
  inspect(map[0], content="Unknown")
}

///|
test "mixed document — full annotation" {
  let doc = @md.Document([
    @md.Paragraph([@md.Text("Abstract paragraph")]),
    @md.Heading(1, [@md.Text("Overview")]),
    @md.Paragraph([@md.Text("Section intro")]),
    @md.Heading(2, [@md.Text("Features")]),
    @md.UnorderedList([
      @md.ListItem([@md.Text("A")]),
      @md.ListItem([@md.Text("B")]),
    ]),
    @md.Paragraph([@md.Text("Code explanation")]),
    @md.CodeBlock("moonbit", "fn main {}"),
  ])
  let map = annotate_symbolic(doc)
  inspect(map[0], content="RuleBased(Abstract)")
  inspect(map[1], content="Unknown")
  inspect(map[2], content="RuleBased(SectionIntro)")
  inspect(map[3], content="Unknown")
  inspect(map[4], content="RuleBased(KeyPoints)")
  inspect(map[5], content="RuleBased(CodeExplanation)")
  inspect(map[6], content="Unknown")
}
