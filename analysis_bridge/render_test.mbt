///|
test "facts_to_decorations filters stale and keeps current" {
  let source = "fn(x){ x }"
  let snap = @facts.SourceSnapshot::SourceSnapshot(
    doc_id="test",
    version=1,
    source~,
  )
  let stale_snap = @facts.SourceSnapshot::SourceSnapshot(
    doc_id="test",
    version=2,
    source~,
  )
  let current = @facts.PatternMatchFact::PatternMatchFact(
    snapshot=snap,
    from=3,
    to=6,
    pattern_id="lam",
    captures=Map([]),
  )
  let stale = @facts.PatternMatchFact::PatternMatchFact(
    snapshot=stale_snap,
    from=3,
    to=6,
    pattern_id="lam",
    captures=Map([]),
  )
  let decs = facts_to_decorations([current, stale], snap)
  inspect(decs.length(), content="1")
  inspect(decs[0].from, content="3")
  inspect(decs[0].to, content="6")
  inspect(decs[0].css_class, content="analysis-match pattern-lam")
  guard decs[0].data is Some(d) else { fail("expected Some data") }
  inspect(d, content="lam")
}

///|
test "facts_to_decorations returns empty when all stale" {
  let source = "fn(x){ x }"
  let snap = @facts.SourceSnapshot::SourceSnapshot(
    doc_id="test",
    version=1,
    source~,
  )
  let stale_snap = @facts.SourceSnapshot::SourceSnapshot(
    doc_id="test",
    version=2,
    source~,
  )
  let fact = @facts.PatternMatchFact::PatternMatchFact(
    snapshot=stale_snap,
    from=0,
    to=3,
    pattern_id="lam",
    captures=Map([]),
  )
  let decs = facts_to_decorations([fact], snap)
  inspect(decs.length(), content="0")
}

///|
test "facts_to_decorations non-ascii range passthrough" {
  // UTF-16 offsets pass through unchanged (conversion already done at adapter boundary)
  let source = "世界"
  let snap = @facts.SourceSnapshot::SourceSnapshot(
    doc_id="test",
    version=1,
    source~,
  )
  let fact = @facts.PatternMatchFact::PatternMatchFact(
    snapshot=snap,
    from=0,
    to=2,
    pattern_id="cjk",
    captures=Map([]),
  )
  let decs = facts_to_decorations([fact], snap)
  inspect(decs.length(), content="1")
  inspect(decs[0].from, content="0")
  inspect(decs[0].to, content="2")
}

///|
test "facts_to_match_list filters stale and returns current" {
  let source = "fn(x){ x }"
  let snap = @facts.SourceSnapshot::SourceSnapshot(
    doc_id="test",
    version=1,
    source~,
  )
  let stale_snap = @facts.SourceSnapshot::SourceSnapshot(
    doc_id="test",
    version=2,
    source~,
  )
  let current = @facts.PatternMatchFact::PatternMatchFact(
    snapshot=snap,
    from=3,
    to=6,
    pattern_id="lam",
    captures=Map([]),
  )
  let stale = @facts.PatternMatchFact::PatternMatchFact(
    snapshot=stale_snap,
    from=0,
    to=3,
    pattern_id="lam",
    captures=Map([]),
  )
  let entries = facts_to_match_list([current, stale], snap)
  inspect(entries.length(), content="1")
  inspect(entries[0].from, content="3")
  inspect(entries[0].to, content="6")
  inspect(entries[0].pattern_id, content="lam")
}

///|
test "facts_to_match_list empty when all stale" {
  let source = "fn(x){ x }"
  let snap = @facts.SourceSnapshot::SourceSnapshot(
    doc_id="test",
    version=1,
    source~,
  )
  let stale_snap = @facts.SourceSnapshot::SourceSnapshot(
    doc_id="test",
    version=2,
    source~,
  )
  let fact = @facts.PatternMatchFact::PatternMatchFact(
    snapshot=stale_snap,
    from=0,
    to=3,
    pattern_id="lam",
    captures=Map([]),
  )
  let entries = facts_to_match_list([fact], snap)
  inspect(entries.length(), content="0")
}
