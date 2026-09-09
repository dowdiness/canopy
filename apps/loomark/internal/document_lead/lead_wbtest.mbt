///|
fn assert_lead(
  source : String,
  form : DocumentLeadForm,
  primary : String,
  description : String,
) -> Unit raise {
  let lead = extract(source)
  assert_eq(lead.form(), form)
  assert_eq(lead.primary(), primary)
  assert_eq(lead.description(), description)
}

///|
test "extract presents the first readable Markdown block" {
  for
    fixture in [
      ("# Heading\n", Heading, "Heading", ""),
      ("Setext\n======\n", Heading, "Setext", ""),
      ("- [x] done\n", Task(true), "done", ""),
      ("- [ ] open\n", Task(false), "open", ""),
      ("> quote\n", Quote, "quote", ""),
      ("1. one\n", List("1."), "one", ""),
      ("single paragraph\n", Plain, "single paragraph", ""),
      ("plain **text**\n", Plain, "plain text", ""),
      ("![alt](image.png)\n", Plain, "alt", ""),
      ("[text](url\n", Plain, "[text](url", ""),
      ("# )bad\n", Heading, ")bad", ""),
      ("<div>raw</div>\n\nAfter HTML\n", Plain, "After HTML", ""),
      ("title: x\n", Plain, "title: x", ""),
      (
        "```\n  leading\n    interior\n```\n",
        Code,
        "  leading\n    interior",
        "",
      ),
      ("-\n- readable\n- later\n", List("-"), "readable", "- later"),
      ("-\n  - nested\n", List("-"), "nested", ""),
      ("-\n  - one\n  - two\n", List("-"), "one", "  - two"),
      ("-\n- [x] done\n", Task(true), "done", ""),
    ] {
    let (source, form, primary, description) = fixture
    assert_lead(source, form, primary, description)
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
    let lead = extract(source)
    assert_eq(lead.primary(), primary)
    assert_eq(lead.description(), description)
  }
}

///|
test "extract is total for empty and recovered Markdown" {
  for
    fixture in [
      ("    indented code\n", Code, "indented code"),
      (" \t\r\n  \n", Empty, ""),
      ("![](image.png)\n\nReadable later\n", Plain, "Readable later"),
      ("# CR\r", Heading, "CR"),
      ("# CRLF\r\n", Heading, "CRLF"),
      ("# EOF", Heading, "EOF"),
    ] {
    let (source, form, primary) = fixture
    let lead = extract(source)
    assert_eq(lead.form(), form)
    assert_eq(lead.primary(), primary)
  }
}

///|
test "fallback keeps the first line separate from the description" {
  let lead = fallback_lead("\u{0000} first\n\n    indented follow-up\n")
  assert_eq(lead.primary(), "\u{0000} first")
  assert_eq(lead.description(), "    indented follow-up")
}

///|
test "fixed limits count Unicode scalars and preserve equality contracts" {
  let primary_at_limit = "😀".repeat(80)
  let description_at_limit = "😀".repeat(160)
  let at_limit = extract("# \{primary_at_limit}\n\n\{description_at_limit}\n")
  assert_eq(at_limit.primary(), primary_at_limit)
  assert_eq(at_limit.description(), description_at_limit)
  assert_false(at_limit.primary_truncated())
  assert_false(at_limit.description_truncated())

  let above_primary = extract("# \{primary_at_limit}x\n")
  assert_eq(above_primary.primary(), primary_at_limit)
  assert_true(above_primary.primary_truncated())
  let above_description = extract("# same\n\n\{description_at_limit}x\n")
  assert_eq(above_description.description(), description_at_limit)
  assert_true(above_description.description_truncated())

  assert_eq(
    extract("# \{"a".repeat(80)}x\n"),
    extract("# \{"a".repeat(80)}y\n"),
  )
  assert_eq(
    extract("# same\n\n\{"b".repeat(160)}x\n"),
    extract("# same\n\n\{"b".repeat(160)}y\n"),
  )
  let not_truncated = extract("# same\n\nabc\n")
  let truncated = extract("# same\n\nabc" + "d".repeat(160) + "\n")
  assert_eq(not_truncated.description(), "abc")
  assert_false(not_truncated.primary_truncated())
  assert_false(not_truncated.description_truncated())
  assert_true(not_truncated != truncated)
}
