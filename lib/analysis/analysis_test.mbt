///|
test "snapshot matches itself" {
  let snap = SourceSnapshot::SourceSnapshot(
    doc_id="doc1",
    version=1,
    source="hello",
  )
  inspect(snap.matches(snap), content="true")
}

///|
test "snapshot rejects stale version" {
  let source = "fn(x){ x + 世界 }"
  let snap_v1 = SourceSnapshot::SourceSnapshot(
    doc_id="doc1",
    version=1,
    source~,
  )
  let snap_v2 = SourceSnapshot::SourceSnapshot(
    doc_id="doc1",
    version=2,
    source~,
  )
  inspect(snap_v1.matches(snap_v2), content="false")
}

///|
test "snapshot rejects different content at same version" {
  let snap_a = SourceSnapshot::SourceSnapshot(
    doc_id="doc1",
    version=1,
    source="hello",
  )
  let snap_b = SourceSnapshot::SourceSnapshot(
    doc_id="doc1",
    version=1,
    source="world",
  )
  inspect(snap_a.matches(snap_b), content="false")
}

///|
test "snapshot rejects same-content fact from different document" {
  // docA and docB share identical text at the same version — a fact tagged
  // to docA must not be accepted as current for docB.
  let source = "fn(x){ x }"
  let snap_a = SourceSnapshot::SourceSnapshot(doc_id="docA", version=1, source~)
  let snap_b = SourceSnapshot::SourceSnapshot(doc_id="docB", version=1, source~)
  inspect(snap_a.matches(snap_b), content="false")
  let fact = PatternMatchFact::PatternMatchFact(
    snapshot=snap_a,
    from=0,
    to=3,
    pattern_id="lam",
    captures=Map([]),
  )
  inspect(fact.is_current(snap_b), content="false")
}

///|
test "byte_offset_to_utf16 handles ascii" {
  let s = "hello"
  inspect(byte_offset_to_utf16(s, 0), content="0")
  inspect(byte_offset_to_utf16(s, 3), content="3")
  inspect(byte_offset_to_utf16(s, 5), content="5")
}

///|
test "byte_offset_to_utf16 handles 3-byte UTF-8 (BMP non-ASCII)" {
  // "ab世c" — '世' (U+4E16) is 3 UTF-8 bytes, 1 UTF-16 unit
  // UTF-8 byte layout: a=0, b=1, 世=2..4, c=5
  let s = "ab世c"
  inspect(byte_offset_to_utf16(s, 0), content="0")
  inspect(byte_offset_to_utf16(s, 1), content="1")
  inspect(byte_offset_to_utf16(s, 2), content="2")
  inspect(byte_offset_to_utf16(s, 5), content="3")
}

///|
test "byte_offset_to_utf16 handles surrogate-pair emoji" {
  // "a😀b" — 😀 (U+1F600) is 4 UTF-8 bytes, 2 UTF-16 units (surrogate pair)
  // UTF-8 byte layout: a=0, 😀=1..4, b=5
  // UTF-16 unit layout: a=0, 😀=1..2, b=3
  let s = "a😀b"
  inspect(byte_offset_to_utf16(s, 0), content="0")
  inspect(byte_offset_to_utf16(s, 1), content="1")
  inspect(byte_offset_to_utf16(s, 5), content="3")
}

///|
test "fact is_current accepts matching snapshot" {
  let source = "fn(x){ x }"
  let snap = SourceSnapshot::SourceSnapshot(doc_id="test", version=1, source~)
  let fact = PatternMatchFact::PatternMatchFact(
    snapshot=snap,
    from=0,
    to=3,
    pattern_id="lambda",
    captures=Map([]),
  )
  inspect(fact.is_current(snap), content="true")
}

///|
test "fact is_current rejects stale snapshot" {
  let source = "fn(x){ x }"
  let snap = SourceSnapshot::SourceSnapshot(doc_id="test", version=1, source~)
  let stale = SourceSnapshot::SourceSnapshot(doc_id="test", version=2, source~)
  let fact = PatternMatchFact::PatternMatchFact(
    snapshot=snap,
    from=0,
    to=3,
    pattern_id="lambda",
    captures=Map([]),
  )
  inspect(fact.is_current(stale), content="false")
}
