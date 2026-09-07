///|
fn test_limits(
  primary? : Int = 32,
  description? : Int = 64,
) -> DocumentLeadLimits {
  DocumentLeadLimits::try_new(primary~, description~).unwrap()
}

///|
test "extracts primary and following readable blocks" {
  let lead = extract(
    "# Heading\n\nBody\n\n- one\n- two\n",
    limits=test_limits(),
  )
  assert_eq(lead.form(), Heading)
  assert_eq(lead.primary(), "Heading")
  assert_eq(lead.description(), "Body\n- one\n- two")

  let paragraph = extract("single paragraph\n", limits=test_limits())
  assert_eq(paragraph.primary(), "single paragraph")
  assert_eq(paragraph.description(), "")
}

///|
test "preserves code spacing and structured list markers" {
  let code = extract(
    "```\n  leading\n    interior\n```\n",
    limits=test_limits(),
  )
  assert_eq(code.primary(), "  leading\n    interior")
  assert_eq(code.description(), "")

  let ordered = extract(
    "3. first\n7. second\n12. third\n",
    limits=test_limits(),
  )
  assert_eq(ordered.primary(), "first")
  assert_eq(ordered.description(), "7. second\n12. third")

  let nested = extract(
    "- outer\n  1. nested one\n  4. nested four\n- sibling\n",
    limits=test_limits(),
  )
  assert_eq(nested.primary(), "outer")
  assert_eq(
    nested.description(),
    "  1. nested one\n  4. nested four\n- sibling",
  )
  let nested_later = extract(
    "- first\n- second\n  * child\n",
    limits=test_limits(),
  )
  assert_eq(nested_later.description(), "- second\n  * child")
  let empty_first = extract("-\n- readable\n- later\n", limits=test_limits())
  assert_eq(empty_first.primary(), "readable")
  assert_eq(empty_first.description(), "- later")
  let nested_only = extract("-\n  - nested\n", limits=test_limits())
  assert_eq(nested_only.form(), List("-"))
  assert_eq(nested_only.primary(), "nested")
  assert_eq(nested_only.description(), "")
  let later_task = extract("-\n- [x] done\n", limits=test_limits())
  assert_eq(later_task.form(), Task(true))
  assert_eq(later_task.primary(), "done")
  let ordered_task = extract(
    "1. first\n2. [x] checked\n3. [ ] open\n",
    limits=test_limits(),
  )
  assert_eq(ordered_task.description(), "2. [x] checked\n3. [ ] open")
}

///|
test "nested primary is omitted while remaining task items retain provenance" {
  let lead = extract(
    "-\n  - [x] nested\n  - [ ] remaining\n- [x] later\n",
    limits=test_limits(),
  )
  assert_eq(lead.primary(), "nested")
  assert_eq(lead.description(), "  - [ ] remaining\n- [x] later")
  let ranges = lead.task_marker_ranges()
  assert_eq(ranges.length(), 2)
  assert_eq(lead.description()[ranges[0].start():ranges[0].end()], "- [ ] ")
  assert_eq(lead.description()[ranges[1].start():ranges[1].end()], "- [x] ")
  assert_eq((ranges[0].start(), ranges[0].end()), (2, 8))
  assert_eq((ranges[1].start(), ranges[1].end()), (18, 24))
}

///|
test "description task marker provenance is IR-backed and UTF16 indexed" {
  let lead = extract(
    "# Heading\n\n- [ ] open\n- [x] checked\n",
    limits=test_limits(),
  )
  let ranges = lead.task_marker_ranges()
  assert_eq(ranges.length(), 2)
  assert_eq(
    (ranges[0].start(), ranges[0].end(), ranges[0].checked()),
    (0, 6, false),
  )
  assert_eq(
    (ranges[1].start(), ranges[1].end(), ranges[1].checked()),
    (11, 17, true),
  )

  let literal = extract(
    "# Heading\n\n```\n- [ ] literal\n```\n\n- [x] actual\n",
    limits=test_limits(),
  )
  assert_eq(literal.task_marker_ranges().length(), 1)
  let literal_range = literal.task_marker_ranges()[0]
  assert_eq(
    literal.description()[literal_range.start():literal_range.end()],
    "- [x] ",
  )
  assert_true(literal_range.start() < literal_range.end())
  assert_true(literal_range.end() <= literal.description().length())
  assert_true(literal_range.checked())

  let nested = extract(
    "- first\n  - [x] nested\n- [ ] later\n",
    limits=test_limits(),
  )
  let nested_ranges = nested.task_marker_ranges()
  assert_eq(nested_ranges.length(), 2)
  assert_true(nested_ranges[0].checked())
  assert_true(!nested_ranges[1].checked())
}

///|
test "marker ranges slice exact retained prefixes across later items" {
  let lead = extract(
    "- first\n- second\n- [x] third\n- [ ] later\n",
    limits=test_limits(),
  )
  let description = lead.description()
  let ranges = lead.task_marker_ranges()
  assert_eq(ranges.length(), 2)
  assert_eq(description[ranges[0].start():ranges[0].end()], "- [x] ")
  assert_eq(description[ranges[1].start():ranges[1].end()], "- [ ] ")
  assert_true(ranges[0].start() < ranges[0].end())
  assert_true(ranges[1].start() < ranges[1].end())
  assert_true(ranges[1].end() <= description.length())

  let nested = extract(
    "- first\n  - [x] nested\n    continuation\n- [ ] later\n",
    limits=test_limits(),
  )
  let nested_description = nested.description()
  let nested_ranges = nested.task_marker_ranges()
  assert_eq(nested_ranges.length(), 2)
  assert_eq(
    nested_description[nested_ranges[0].start():nested_ranges[0].end()],
    "- [x] ",
  )
  assert_eq(
    nested_description[nested_ranges[1].start():nested_ranges[1].end()],
    "- [ ] ",
  )

  let copy = nested.task_marker_ranges()
  copy[0] = { start: 99, end: 100, checked: false }
  assert_eq(nested.task_marker_ranges()[0].start(), nested_ranges[0].start())
}

///|
test "task marker provenance omits partial prefixes and handles Unicode" {
  let unicode = extract(
    "# 😀\n\n- [ ] task\n",
    limits=test_limits(description=7),
  )
  assert_eq(unicode.task_marker_ranges().length(), 1)
  assert_eq(unicode.task_marker_ranges()[0].start(), 0)
  assert_eq(unicode.task_marker_ranges()[0].end(), 6)
  let unicode_preceding = extract(
    "# heading\n\n😀\n\n- first\n- [x] task\n",
    limits=test_limits(),
  )
  let unicode_description = unicode_preceding.description()
  let unicode_range = unicode_preceding.task_marker_ranges()[0]
  assert_eq(
    unicode_description[unicode_range.start():unicode_range.end()],
    "- [x] ",
  )
  assert_true(unicode_range.end() <= unicode_description.length())
  let cut = extract("# h\n\n- [ ] task\n", limits=test_limits(description=4))
  assert_eq(cut.description(), "- [ ")
  assert_eq(cut.task_marker_ranges().length(), 0)
  let empty = extract("# h\n", limits=test_limits())
  assert_eq(empty.task_marker_ranges().length(), 0)
}

///|
test "structured quotes retain nested markers and code" {
  let lead = extract(
    "# Heading\n\n> - item\n>   - nested\n",
    limits=test_limits(),
  )
  assert_eq(lead.form(), Heading)
  assert_eq(lead.primary(), "Heading")
  assert_eq(lead.description(), "> - item\n> - nested")
}

///|
test "forms and equality ignore presentation-only source" {
  let cases = [
    ("# Heading\n", Heading, "Heading"),
    ("Setext\n======\n", Heading, "Setext"),
    ("- [x] done\n", Task(true), "done"),
    ("- [ ] open\n", Task(false), "open"),
    ("> quote\n", Quote, "quote"),
    ("1. one\n", List("1."), "one"),
    ("plain **text**\n", Plain, "plain text"),
    ("![alt](image.png)\n", Plain, "alt"),
  ]
  for case in cases {
    let (source, form, primary) = case
    let lead = extract(source, limits=test_limits())
    assert_eq(lead.form(), form)
    assert_eq(lead.primary(), primary)
  }
  assert_eq(
    extract("[same](https://one.example)\n", limits=test_limits()),
    extract("[same](https://two.example)\n", limits=test_limits()),
  )
}

///|
test "deep nested primary retains later descendants with provenance" {
  let lead = extract(
    "-\n  -\n    - primary\n\n    - [x] retained\n",
    limits=test_limits(),
  )
  assert_eq(lead.primary(), "primary")
  assert_eq(lead.description(), "    - [x] retained")
  let markers = lead.task_marker_ranges()
  assert_eq(markers.length(), 1)
  assert_eq(markers[0].start(), 4)
  assert_eq(markers[0].end(), 10)
  assert_true(markers[0].checked())
}

///|
test "concrete recovery fixtures remain total" {
  assert_eq(extract("    indented code\n", limits=test_limits()).form(), Code)
  assert_eq(extract(" \t\r\n  \n", limits=test_limits()).form(), Empty)
  let altless = extract(
    "![](image.png)\n\nReadable later\n",
    limits=test_limits(),
  )
  assert_eq(altless.primary(), "Readable later")
  assert_eq(extract("# CR\r", limits=test_limits()).primary(), "CR")
  assert_eq(extract("# CRLF\r\n", limits=test_limits()).primary(), "CRLF")
  assert_eq(extract("# EOF", limits=test_limits()).primary(), "EOF")
}

///|
test "limits reject invalid values without aborting" {
  assert_true(DocumentLeadLimits::try_new(primary=0, description=1) is Err(_))
  assert_true(DocumentLeadLimits::try_new(primary=1, description=-1) is Err(_))
}

///|
test "bounded output has explicit flags without an ellipsis" {
  let lead = extract(
    "# 😀abcde\n",
    limits=test_limits(primary=4, description=5),
  )
  assert_eq(lead.primary(), "😀abc")
  assert_true(lead.primary_truncated())
  assert_eq(lead.description(), "")
  let below = extract("# abc\n", limits=test_limits(primary=4, description=5))
  let at = extract("# abcd\n", limits=test_limits(primary=4, description=5))
  assert_true(!below.primary_truncated())
  assert_true(!at.primary_truncated())
}

///|
test "omitted suffixes preserve equality and flags" {
  let primary_a = extract("# abcdef\n", limits=test_limits(primary=3))
  let primary_b = extract("# abcxyz\n", limits=test_limits(primary=3))
  assert_eq(primary_a, primary_b)
  assert_eq(primary_a.primary(), "abc")
  assert_true(primary_a.primary_truncated())

  let description_a = extract(
    "# same\n\nabcdef\n",
    limits=test_limits(description=3),
  )
  let description_b = extract(
    "# same\n\nabcxyz\n",
    limits=test_limits(description=3),
  )
  assert_eq(description_a, description_b)
  assert_eq(description_a.description(), "abc")
  assert_true(description_a.description_truncated())

  let below = extract("# 😀a\n\nb\n", limits=test_limits(description=2))
  let at = extract("# 😀a\n\nbc\n", limits=test_limits(description=2))
  let above = extract("# 😀a\n\nbcd\n", limits=test_limits(description=2))
  let non_bmp = extract(
    "# 😀a\n\n😀😀😀\n",
    limits=test_limits(description=2),
  )
  assert_eq(below.description(), "b")
  assert_eq(at.description(), "bc")
  assert_eq(above.description(), "bc")
  assert_eq(non_bmp.description(), "😀😀")
  assert_true(!below.description_truncated())
  assert_true(!at.description_truncated())
  assert_true(above.description_truncated())
  assert_true(non_bmp.description_truncated())
}

///|
test "fallback excludes primary line and keeps following indentation" {
  let lead = fallback_lead(
    "\u{0000} first\n\n    indented follow-up\n",
    test_limits(),
  )
  assert_eq(lead.primary(), "\u{0000} first")
  assert_eq(lead.description(), "    indented follow-up")
}

///|
test "bench: extract mixed large source in release JS" (b : @bench.T) {
  let source = stage2_large_sources()[0]
  let limits = test_limits(primary=80, description=160)
  b.bench(() => b.keep(extract(source, limits~)))
}

///|
test "bench: extract distinct large source in release JS" (b : @bench.T) {
  let source = stage2_large_sources()[1]
  let limits = test_limits(primary=80, description=160)
  b.bench(() => b.keep(extract(source, limits~)))
}

///|
test "bench: equality output cost is a separate named case" (b : @bench.T) {
  let left = extract("# stable\n", limits=test_limits())
  let right = extract("# stable\n", limits=test_limits())
  b.bench(() => b.keep(left == right))
}
