///|
test "from_ast_grep_matches converts byte offsets to UTF-16" {
  // "fn 世界(x)" — 世 at byte 3, 界 at byte 6, ( at byte 9
  // UTF-16: fn=0-2, 世=3, 界=4, (=5, x=6, )=7
  let source = "fn 世界(x)"
  let snap = @facts.SourceSnapshot::SourceSnapshot(
    doc_id="test",
    version=1,
    source~,
  )
  let facts = from_ast_grep_matches(
    [
      AstGrepMatch::AstGrepMatch(
        byte_start=3,
        byte_end=9,
        pattern_id="cjk-ident",
      ),
    ],
    source,
    snap,
  )
  inspect(facts.length(), content="1")
  inspect(facts[0].from, content="3")
  inspect(facts[0].to, content="5")
  inspect(facts[0].pattern_id, content="cjk-ident")
}

///|
test "from_ast_grep_matches preserves snapshot" {
  let source = "fn(x){ x }"
  let snap = @facts.SourceSnapshot::SourceSnapshot(
    doc_id="doc1",
    version=7,
    source~,
  )
  let facts = from_ast_grep_matches(
    [AstGrepMatch::AstGrepMatch(byte_start=0, byte_end=3, pattern_id="lam")],
    source,
    snap,
  )
  inspect(facts[0].snapshot.version, content="7")
  inspect(facts[0].snapshot.doc_id, content="doc1")
}

///|
test "from_ast_grep_matches empty input" {
  let source = "fn(x){ x }"
  let snap = @facts.SourceSnapshot::SourceSnapshot(
    doc_id="test",
    version=1,
    source~,
  )
  let facts = from_ast_grep_matches([], source, snap)
  inspect(facts.length(), content="0")
}
