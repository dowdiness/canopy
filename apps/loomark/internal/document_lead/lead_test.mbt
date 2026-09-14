///|
fn assert_lead(
  source : String,
  primary~ : String,
  description? : String = "",
) -> @document_lead.DocumentLead raise {
  let lead = @document_lead.extract(source)
  assert_eq(lead.primary(), primary)
  assert_eq(lead.description(), description)
  lead
}

///|
test "headings are recognized across syntax and line endings" {
  for
    fixture in [
      ("# Heading\n", "Heading"),
      ("Setext\n======\n", "Setext"),
      ("# )bad\n", ")bad"),
      ("# CR\r", "CR"),
      ("# CRLF\r\n", "CRLF"),
      ("# EOF", "EOF"),
    ] {
    let (source, primary) = fixture
    let lead = assert_lead(source, primary~)
    assert_true(lead.form() is Heading)
  }
}

///|
test "tasks retain their completion state after empty items" {
  for
    fixture in [
      ("- [x] done\n", true, "done"),
      ("- [ ] open\n", false, "open"),
      ("-\n- [x] done\n", true, "done"),
    ] {
    let (source, expected, primary) = fixture
    let lead = assert_lead(source, primary~)
    guard lead.form() is Task(checked) else { fail("expected a task lead") }
    assert_eq(checked, expected)
  }
}

///|
test "a quote retains its block form" {
  let lead = assert_lead("> quote\n", primary="quote")
  assert_true(lead.form() is Quote)
}

///|
test "lists skip empty items without losing markers or later items" {
  for
    fixture in [
      ("1. one\n", "1.", "one", ""),
      ("-\n- readable\n- later\n", "-", "readable", "- later"),
      ("-\n  - nested\n", "-", "nested", ""),
      ("-\n  - one\n  - two\n", "-", "one", "  - two"),
    ] {
    let (source, expected_marker, primary, description) = fixture
    let lead = assert_lead(source, primary~, description~)
    guard lead.form() is List(marker) else { fail("expected a list lead") }
    assert_eq(marker, expected_marker)
  }
}

///|
test "plain leads flatten inline markup and skip unreadable content" {
  for
    fixture in [
      ("single paragraph\n", "single paragraph"),
      ("plain **text**\n", "plain text"),
      ("![alt](image.png)\n", "alt"),
      ("[text](url\n", "[text](url"),
      ("<div>raw</div>\n\nAfter HTML\n", "After HTML"),
      ("title: x\n", "title: x"),
      ("![](image.png)\n\nReadable later\n", "Readable later"),
    ] {
    let (source, primary) = fixture
    let lead = assert_lead(source, primary~)
    assert_true(lead.form() is Plain)
  }
}

///|
test "code leads preserve literal indentation and line breaks" {
  for
    fixture in [
      ("```\n  leading\n    interior\n```\n", "  leading\n    interior"),
      ("    indented code\n", "indented code"),
    ] {
    let (source, primary) = fixture
    let lead = assert_lead(source, primary~)
    assert_true(lead.form() is Code)
  }
}

///|
test "extract preserves readable structure in the description" {
  for
    fixture in [
      ("# Heading\n\nBody\n\n- one\n- two\n", "Heading", "Body\n- one\n- two"),
      ("3. first\n7. second\n12. third\n", "first", "7. second\n12. third"),
      (
        "- outer\n  1. nested one\n  4. nested four\n- sibling\n", "outer", "  1. nested one\n  4. nested four\n- sibling",
      ),
      ("- first\n- second\n  * child\n", "first", "- second\n  * child"),
      (
        "# Heading\n\n> - item\n>   - nested\n", "Heading", "> - item\n> - nested",
      ),
      (
        "1. first\n2. [x] checked\n3. [ ] open\n", "first", "2. [x] checked\n3. [ ] open",
      ),
    ] {
    let (source, primary, description) = fixture
    let lead = @document_lead.extract(source)
    assert_eq(lead.primary(), primary)
    assert_eq(lead.description(), description)
  }
}

///|
test "whitespace-only source has no readable lead" {
  let lead = assert_lead(" \t\r\n  \n", primary="")
  assert_true(lead.form() is Empty)
}

///|
test "lead limits count Unicode scalars rather than UTF-16 units" {
  let primary = "😀".repeat(80)
  let description = "😀".repeat(160)
  let at_limit = @document_lead.extract("# \{primary}\n\n\{description}\n")
  assert_eq(at_limit.primary(), primary)
  assert_eq(at_limit.description(), description)
  assert_false(at_limit.primary_truncated())
  assert_false(at_limit.description_truncated())

  let over_limit = @document_lead.extract("# \{primary}x\n\n\{description}x\n")
  assert_eq(over_limit.primary(), primary)
  assert_eq(over_limit.description(), description)
  assert_true(over_limit.primary_truncated())
  assert_true(over_limit.description_truncated())
}

///|
test "lead equality ignores clipped text but distinguishes truncation flags" {
  let primary = "a".repeat(80)
  let description = "b".repeat(160)
  assert_eq(
    @document_lead.extract("# \{primary}x\n"),
    @document_lead.extract("# \{primary}y\n"),
  )
  assert_eq(
    @document_lead.extract("# same\n\n\{description}x\n"),
    @document_lead.extract("# same\n\n\{description}y\n"),
  )

  let at_limit = @document_lead.extract("# \{primary}\n\n\{description}\n")
  let clipped_primary = @document_lead.extract(
    "# \{primary}x\n\n\{description}\n",
  )
  let clipped_description = @document_lead.extract(
    "# \{primary}\n\n\{description}x\n",
  )
  assert_true(clipped_primary.primary_truncated())
  assert_false(clipped_primary.description_truncated())
  assert_false(clipped_description.primary_truncated())
  assert_true(clipped_description.description_truncated())
  assert_true(at_limit != clipped_primary)
  assert_true(at_limit != clipped_description)
}
