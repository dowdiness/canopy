// Contract tests for the neutral TestExpr grammar / editor fixture.
// Proves new_test_editor parses, round-trips text, and is TOTAL over
// valid Unicode input (garbage / non-BMP) without aborting. Malformed UTF-16
// is rejected at the text boundary before parsing.

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
/// A lone surrogate is malformed UTF-16. The text facade rejects it before
/// CRDT allocation or parsing, leaving source, cursor, and parsed AST unchanged.
test "rejects a lone surrogate before parsing without changing text" {
  let half = "😀".view(start_offset=0, end_offset=1).to_owned()
  let ed = new_test_editor("agent")
  try ed.insert("a" + half + "b") catch {
    @text.TextError::InvalidText(detail~) =>
      inspect(detail, content="malformed UTF-16")
    _ => fail("expected malformed UTF-16 to be rejected")
  } noraise {
    _ => fail("lone surrogate insertion must fail")
  }
  inspect(ed.get_text(), content="")
  inspect(ed.get_cursor(), content="0")
  inspect(get_test_ast(ed), content="Branch(\"\", [])")
}

///|
// #5 (issue #600): the generic `get_errors` / diagnostics contract is exercised
// against TestExpr's SINGLE structural error shape — an unclosed '('. This is
// by design, not an oversight, and the limitation is documented here so it
// cannot be mistaken for missing coverage. The grammar is deliberately TOTAL
// over valid Unicode input (see test_grammar.mbt header): stray punctuation,
// garbage, and non-BMP runs become silent lexer gaps rather than diagnostics.
// Malformed UTF-16 is rejected by the text facade before reaching this grammar.
// Adding a second parser error shape would require a non-total parser path and
// risk the totality invariant the contract tests above pin — so the single
// trigger is intentional. This test pins both sides: exactly one diagnostic for
// the one trigger, and zero for silent-gap garbage.
test "TestExpr reports exactly one structural diagnostic kind (unclosed '(')" {
  let ed = new_test_editor("agent")
  ed.insert("foo(")
  let errs = ed.get_errors()
  inspect(errs.length(), content="1")
  inspect(errs[0].has_prefix("unclosed '('"), content="true")
  // Totality: garbage punctuation is a silent lexer gap, NOT a diagnostic, so
  // there is no second error shape to broaden the contract with.
  let ed2 = new_test_editor("agent")
  ed2.insert("@#$%^&")
  inspect(ed2.get_errors().length(), content="0")
}

///|
// Drift guard for the TestExpr fixture (issue #601).
//
// This `pub(all)` TestExpr (workspace/probe/test_expr.mbt) was promoted from
// the `priv` copy in `core/test_expr_wbtest.mbt`, which core's "works with any
// AST" contract must keep (probe depends on core, so the priv copy cannot be
// replaced by importing this one without a layering cycle). To stop the two
// from drifting silently, BOTH files pin their TestExpr's observable surface to
// the SAME frozen literals below — a frozen reference, never a call back
// through the other copy, so a change to EITHER definition's unparse /
// placeholder / kind_tag / label / children fails its own file's guard. Keep
// the two literal blocks byte-identical; if you change one, change the other
// (see `core/test_expr_wbtest.mbt`,
// "TestExpr fixture surface is frozen (drift guard vs workspace/probe)").
test "TestExpr fixture surface is frozen (drift guard vs core)" {
  let sample : TestExpr = Branch("f", [Leaf("x"), Leaf("y")])
  inspect(@loomcore.Renderable::kind_tag(sample), content="Branch")
  inspect(@loomcore.Renderable::label(sample), content="f")
  inspect(@loomcore.Renderable::placeholder(sample), content="?")
  inspect(@loomcore.Renderable::unparse(sample), content="f(x y)")
  inspect(@loomcore.TreeNode::children(sample).length(), content="2")
  let leaf : TestExpr = Leaf("x")
  inspect(@loomcore.Renderable::kind_tag(leaf), content="Leaf")
  inspect(@loomcore.Renderable::label(leaf), content="x")
  inspect(@loomcore.Renderable::unparse(leaf), content="x")
  inspect(@loomcore.TreeNode::children(leaf).length(), content="0")
}

///|
test "proj node available for non-empty editor" {
  let ed = new_test_editor("agent")
  ed.insert("f(x)")
  inspect(ed.get_proj_node() is Some(_), content="true")
}
