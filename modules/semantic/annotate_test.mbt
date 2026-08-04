///|
test "heading then paragraph → SectionIntro" {
  let doc = @md.Block::Document([
    @md.Block::Heading(1, [@md.Inline::Text("Title")]),
    @md.Block::Paragraph([@md.Inline::Text("Introduction")]),
  ])
  let map = annotate_symbolic(doc)
  inspect(map[1], content="RuleBased(SectionIntro)")
  inspect(map[0], content="Unknown")
}

///|
test "first paragraph → Abstract" {
  let doc = @md.Block::Document([
    @md.Block::Paragraph([@md.Inline::Text("Opening paragraph")]),
    @md.Block::Paragraph([@md.Inline::Text("Second paragraph")]),
  ])
  let map = annotate_symbolic(doc)
  inspect(map[0], content="RuleBased(Abstract)")
  inspect(map[1], content="Unknown")
}

///|
test "paragraph before code block → CodeExplanation" {
  let doc = @md.Block::Document([
    @md.Block::Heading(2, [@md.Inline::Text("Example")]),
    @md.Block::Paragraph([@md.Inline::Text("Section intro")]),
    @md.Block::Paragraph([@md.Inline::Text("Here is the code:")]),
    @md.Block::CodeBlock("moonbit", "let x = 1"),
  ])
  let map = annotate_symbolic(doc)
  inspect(map[1], content="RuleBased(SectionIntro)")
  inspect(map[2], content="RuleBased(CodeExplanation)")
}

///|
test "list after heading → KeyPoints" {
  let doc = @md.Block::Document([
    @md.Block::Heading(1, [@md.Inline::Text("Features")]),
    @md.Block::UnorderedList([
      @md.Block::UnorderedListItem([@md.Inline::Text("Fast")]),
      @md.Block::UnorderedListItem([@md.Inline::Text("Safe")]),
    ]),
  ])
  let map = annotate_symbolic(doc)
  inspect(map[1], content="RuleBased(KeyPoints)")
}

///|
test "ordered list after heading → KeyPoints" {
  let doc = @md.Block::Document([
    @md.Block::Heading(1, [@md.Inline::Text("Steps")]),
    @md.Block::OrderedList(
      [
        @md.Block::OrderedListItem([@md.Inline::Text("First")], None),
        @md.Block::OrderedListItem([@md.Inline::Text("Second")], None),
      ],
      None,
    ),
  ])
  let map = annotate_symbolic(doc)
  inspect(map[1], content="RuleBased(KeyPoints)")
}

///|
test "SectionIntro takes priority over CodeExplanation" {
  let doc = @md.Block::Document([
    @md.Block::Heading(1, [@md.Inline::Text("Demo")]),
    @md.Block::Paragraph([@md.Inline::Text("After heading and before code")]),
    @md.Block::CodeBlock("", "x = 1"),
  ])
  let map = annotate_symbolic(doc)
  inspect(map[1], content="RuleBased(SectionIntro)")
}

///|
test "non-Document input → empty array" {
  let block = @md.Block::Paragraph([@md.Inline::Text("just a paragraph")])
  let map = annotate_symbolic(block)
  inspect(map.length(), content="0")
}

///|
test "empty document → empty array" {
  let doc = @md.Block::Document([])
  let map = annotate_symbolic(doc)
  inspect(map.length(), content="0")
}

///|
test "heading first, paragraph later → no Abstract" {
  let doc = @md.Block::Document([
    @md.Block::Heading(1, [@md.Inline::Text("Title")]),
    @md.Block::Paragraph([@md.Inline::Text("This is not Abstract")]),
  ])
  let map = annotate_symbolic(doc)
  // Not index 0, so not Abstract. After heading, so SectionIntro.
  inspect(map[1], content="RuleBased(SectionIntro)")
  inspect(map[0], content="Unknown")
}

///|
test "mixed document — full annotation" {
  let doc = @md.Block::Document([
    @md.Block::Paragraph([@md.Inline::Text("Abstract paragraph")]),
    @md.Block::Heading(1, [@md.Inline::Text("Overview")]),
    @md.Block::Paragraph([@md.Inline::Text("Section intro")]),
    @md.Block::Heading(2, [@md.Inline::Text("Features")]),
    @md.Block::UnorderedList([
      @md.Block::UnorderedListItem([@md.Inline::Text("A")]),
      @md.Block::UnorderedListItem([@md.Inline::Text("B")]),
    ]),
    @md.Block::Paragraph([@md.Inline::Text("Code explanation")]),
    @md.Block::CodeBlock("moonbit", "fn main {}"),
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
