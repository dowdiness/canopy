// Neutral TestExpr AST for the editor's language-agnostic test fixture.
//
// This is the contract that proves `editor/` works with ANY AST type, not a
// specific language. The redesign proposal ("Dependency and boundary rules")
// requires editor tests to stop importing `lang/*`; TestExpr + its loom
// grammar (see test_grammar.mbt) is the neutral replacement.
//
// The enum + trait impls are promoted verbatim from the proven fixture in
// `core/test_expr_wbtest.mbt` (which is `priv` and so cannot be imported),
// re-exported here as a `pub` surface for editor blackbox + whitebox tests.

///|
pub(all) enum TestExpr {
  Leaf(String)
  Branch(String, Array[TestExpr])
} derive(Debug, Eq)

///|
pub impl Show for TestExpr with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl @loomcore.TreeNode for TestExpr with fn children(self) {
  match self {
    Leaf(_) => []
    Branch(_, cs) => cs
  }
}

///|
pub impl @loomcore.TreeNode for TestExpr with fn same_kind(self, other) {
  match (self, other) {
    (Leaf(_), Leaf(_)) => true
    (Branch(_, _), Branch(_, _)) => true
    _ => false
  }
}

///|
pub impl @loomcore.Renderable for TestExpr with fn kind_tag(self) {
  match self {
    Leaf(_) => "Leaf"
    Branch(_, _) => "Branch"
  }
}

///|
pub impl @loomcore.Renderable for TestExpr with fn label(self) {
  match self {
    Leaf(s) => s
    Branch(tag, _) => tag
  }
}

///|
pub impl @loomcore.Renderable for TestExpr with fn placeholder(_self) {
  "?"
}

///|
pub impl @loomcore.Renderable for TestExpr with fn unparse(self) {
  match self {
    Leaf(s) => s
    Branch(tag, cs) =>
      tag +
      "(" +
      cs.map(fn(c) { @loomcore.Renderable::unparse(c) }).join(" ") +
      ")"
  }
}

///|
pub impl ToJson for TestExpr with fn to_json(self) {
  match self {
    Leaf(s) => Json::string(s)
    Branch(tag, _) => Json::string(tag)
  }
}
