///|
fn test_limits(
  primary? : Int = 32,
  description? : Int = 64,
) -> DocumentLeadLimits {
  DocumentLeadLimits::try_new(primary~, description~).unwrap()
}

///|
fn assert_lead(
  source : String,
  form : DocumentLeadForm,
  primary : String,
  description : String,
) -> Unit raise {
  let lead = extract(source, limits=test_limits())
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
    let lead = extract(source, limits=test_limits())
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
    let lead = extract(source, limits=test_limits())
    assert_eq(lead.form(), form)
    assert_eq(lead.primary(), primary)
  }
}

///|
test "fallback keeps the first line separate from the description" {
  let lead = fallback_lead(
    "\u{0000} first\n\n    indented follow-up\n",
    test_limits(),
  )
  assert_eq(lead.primary(), "\u{0000} first")
  assert_eq(lead.description(), "    indented follow-up")
}

///|
test "limits are positive and count Unicode characters" {
  assert_true(DocumentLeadLimits::try_new(primary=0, description=1) is Err(_))
  assert_true(DocumentLeadLimits::try_new(primary=1, description=-1) is Err(_))

  let lead = extract(
    "# 😀abcde\n\n😀😀😀\n",
    limits=test_limits(primary=4, description=2),
  )
  assert_eq(lead.primary(), "😀abc")
  assert_eq(lead.description(), "😀😀")
  assert_true(lead.primary_truncated())
  assert_true(lead.description_truncated())

  let at_limit = extract(
    "# abcd\n\nbc\n",
    limits=test_limits(primary=4, description=2),
  )
  assert_false(at_limit.primary_truncated())
  assert_false(at_limit.description_truncated())
}

///|
test "equality depends only on the bounded presentation" {
  let limits = test_limits(primary=3, description=3)
  assert_eq(extract("# abcdef\n", limits~), extract("# abcxyz\n", limits~))
  assert_eq(
    extract("# same\n\nabcdef\n", limits~),
    extract("# same\n\nabcxyz\n", limits~),
  )
  assert_eq(
    extract("[same](https://one.example)\n", limits=test_limits()),
    extract("[same](https://two.example)\n", limits=test_limits()),
  )

  let not_truncated = extract("# same\n\nabc\n", limits~)
  let truncated = extract("# same\n\nabcd\n", limits~)
  assert_eq(not_truncated.description(), truncated.description())
  assert_true(not_truncated != truncated)
}
