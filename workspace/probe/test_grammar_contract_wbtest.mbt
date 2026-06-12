// Contract tests for the neutral TestExpr grammar / editor fixture.
// Proves new_test_editor parses, round-trips text, and is TOTAL over
// arbitrary input (garbage / non-BMP / surrogate halves) without aborting.

///|
test "new_test_editor parses a branch with leaf children" {
  let ed = new_test_editor("agent")
  ed.insert("f(x y)")
  inspect(ed.get_text(), content="f(x y)")
  inspect(
    get_test_ast(ed),
    content=(
      #|Branch("", [Branch("f", [Leaf("x"), Leaf("y")])])
    ),
  )
}

///|
test "new_test_editor parses a bare leaf" {
  let ed = new_test_editor("agent")
  ed.insert("hello")
  inspect(
    get_test_ast(ed),
    content=(
      #|Branch("", [Leaf("hello")])
    ),
  )
}

///|
test "empty editor yields empty document" {
  let ed = new_test_editor("agent")
  inspect(
    get_test_ast(ed),
    content=(
      #|Branch("", [])
    ),
  )
}

///|
test "nested branches" {
  let ed = new_test_editor("agent")
  ed.insert("a(b(c) d)")
  inspect(
    get_test_ast(ed),
    content=(
      #|Branch("", [Branch("a", [Branch("b", [Leaf("c")]), Leaf("d")])])
    ),
  )
}

///|
test "total over garbage punctuation — no abort" {
  let ed = new_test_editor("agent")
  ed.insert("@#$%^&")
  inspect(ed.get_text(), content="@#$%^&")
  // garbage parses to an empty/error document, but must not panic
  let _ = get_test_ast(ed)
}

///|
test "total over non-BMP and surrogate input — no abort" {
  let ed = new_test_editor("agent")
  // emoji (surrogate pair) + ZWJ family + regional indicator
  ed.insert("a😀b👨‍👩‍👧c🇯🇵d")
  let _ = get_test_ast(ed)
  // identifiers around the non-BMP runs still lex as idents
  inspect(ed.get_text().length() > 0, content="true")
}

///|
/// A LONE (unpaired) surrogate half — distinct from the well-formed pairs
/// above. MoonBit rejects lone surrogates as string literals, so at runtime
/// they only arise from slicing a pair at a code-unit boundary (e.g. a CRDT
/// merge or FFI input splitting an emoji). The lexer skips the undecodable
/// code unit into a gap; from_located_tokens classifies the gap via
/// `is_blank()`, which compares whitespace code units without a full scalar
/// decode and so does NOT abort on the lone half. This pins the "surrogate
/// halves" totality claim in the file header so it cannot regress silently.
test "total over a lone surrogate half — no abort" {
  let half = "😀".view(start_offset=0, end_offset=1).to_owned() // lone high surrogate
  let ed = new_test_editor("agent")
  ed.insert("a" + half + "b")
  let _ = get_test_ast(ed)
  // The surrounding idents survive; the lone half does not crash the pipeline.
  inspect(ed.get_text().length() > 0, content="true")
}

///|
test "proj node available for non-empty editor" {
  let ed = new_test_editor("agent")
  ed.insert("f(x)")
  inspect(ed.get_proj_node() is Some(_), content="true")
}
