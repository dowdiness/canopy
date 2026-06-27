// Proof that framework/core/ works with any AST type, not just @ast.Term.
//
// This is the contract that enables multi-language support: JSON, Markdown,
// and future editors share framework/core/ (ProjNode, SourceMap, reconcile)
// by implementing TreeNode + Renderable for their AST types.
//
// If these tests break, the framework has acquired a hidden @ast dependency
// and new language editors will not work.

///|
using @loomcore {trait Renderable}

///|
priv enum TestExpr {
  Leaf(String)
  Branch(String, Array[TestExpr])
} derive(Debug, Eq)

///|
impl Show for TestExpr with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
impl @loomcore.TreeNode for TestExpr with fn children(self) {
  match self {
    Leaf(_) => []
    Branch(_, cs) => cs
  }
}

///|
impl @loomcore.TreeNode for TestExpr with fn same_kind(self, other) {
  match (self, other) {
    (Leaf(_), Leaf(_)) => true
    (Branch(_, _), Branch(_, _)) => true
    _ => false
  }
}

///|
impl Renderable for TestExpr with fn kind_tag(self) {
  match self {
    Leaf(_) => "Leaf"
    Branch(_, _) => "Branch"
  }
}

///|
impl Renderable for TestExpr with fn label(self) {
  match self {
    Leaf(s) => s
    Branch(tag, _) => tag
  }
}

///|
impl Renderable for TestExpr with fn placeholder(_self) {
  "?"
}

///|
impl Renderable for TestExpr with fn unparse(self) {
  match self {
    Leaf(s) => s
    Branch(tag, cs) =>
      tag + "(" + cs.map(c => Renderable::unparse(c)).join(" ") + ")"
  }
}

///|
impl ToJson for TestExpr with fn to_json(self) {
  match self {
    Leaf(s) => Json::string(s)
    Branch(tag, _) => Json::string(tag)
  }
}

///|
// Drift guard for the TestExpr fixture (issue #601).
//
// TestExpr is intentionally duplicated: this `priv` copy backs core's "works
// with any AST" contract and cannot import the `workspace/probe` copy without a
// layering cycle (probe depends on core). The other copy is `pub(all)` in
// `workspace/probe/test_expr.mbt` and backs the editor's neutral grammar.
// To stop the two from drifting silently, BOTH files pin their TestExpr's
// observable surface to the SAME frozen literals below — a frozen reference,
// never a call back through the other copy (layering forbids it anyway), so a
// change to EITHER definition's unparse / placeholder / kind_tag / label /
// children fails its own file's guard. Keep the two literal blocks
// byte-identical; if you change one, change the other (see
// `workspace/probe/test_grammar_contract_wbtest.mbt`,
// "TestExpr fixture surface is frozen").
test "TestExpr fixture surface is frozen (drift guard vs workspace/probe)" {
  let sample : TestExpr = Branch("f", [Leaf("x"), Leaf("y")])
  inspect(Renderable::kind_tag(sample), content="Branch")
  inspect(Renderable::label(sample), content="f")
  inspect(Renderable::placeholder(sample), content="?")
  inspect(Renderable::unparse(sample), content="f(x y)")
  inspect(@loomcore.TreeNode::children(sample).length(), content="2")
  let leaf : TestExpr = Leaf("x")
  inspect(Renderable::kind_tag(leaf), content="Leaf")
  inspect(Renderable::label(leaf), content="x")
  inspect(Renderable::unparse(leaf), content="x")
  inspect(@loomcore.TreeNode::children(leaf).length(), content="0")
}

///|
test "ProjNode[TestExpr] — construction and field access" {
  let leaf = ProjNode(Leaf("x"), 0, 1, 0, [])
  inspect(leaf.kind, content="Leaf(\"x\")")
  inspect(leaf.start, content="0")
  inspect(leaf.end, content="1")
  inspect(leaf.id(), content="NodeId(0)")
}

///|
test "ProjNode::leaf allocates a fresh id from syntax span" {
  let syntax_node = @seam.SyntaxNode::from_cst(
    @seam.CstNode::new(@seam.RawKind(1), [
      @seam.CstElement::Token(
        @seam.CstToken::CstToken(@seam.RawKind(2), "text"),
      ),
    ]),
  )
  let counter = Ref(7)
  let leaf = ProjNode::leaf(Leaf("x"), syntax_node, counter)
  inspect(leaf.node_id, content="7")
  inspect(counter.val, content="8")
  inspect(leaf.start, content="0")
  inspect(leaf.end, content="4")
  inspect(leaf.children.length(), content="0")
}

///|
test "ProjNode::branch allocates a fresh id" {
  let counter = Ref(7)
  let child = ProjNode(Leaf("x"), 0, 1, 0, [])
  let branch = ProjNode::branch(
    Branch("root", [Leaf("x")]),
    0,
    5,
    [child],
    counter,
  )
  inspect(branch.node_id, content="7")
  inspect(counter.val, content="8")
  inspect(branch.children.length(), content="1")
}

///|
test "ProjNode::map transforms kinds recursively and preserves metadata" {
  let left = ProjNode(Leaf("a"), 1, 2, 11, [])
  let right = ProjNode(Leaf("b"), 3, 4, 12, [])
  let root = ProjNode(Branch("root", [Leaf("a"), Leaf("b")]), 0, 5, 10, [
    left, right,
  ])
  let mapped = root.map(kind => Renderable::label(kind))
  inspect(mapped.node_id, content="10")
  inspect(mapped.kind, content="root")
  inspect(mapped.start, content="0")
  inspect(mapped.end, content="5")
  inspect(mapped.children[0].node_id, content="11")
  inspect(mapped.children[0].kind, content="a")
  inspect(mapped.children[0].start, content="1")
  inspect(mapped.children[0].end, content="2")
  inspect(mapped.children[1].node_id, content="12")
  inspect(mapped.children[1].kind, content="b")
  inspect(mapped.children[1].start, content="3")
  inspect(mapped.children[1].end, content="4")
}

///|
test "ProjNode::map propagates raising callbacks" {
  let root = ProjNode(Leaf("boom"), 0, 4, 10, [])
  let caught = try {
    let _ = root.map(kind => {
      match kind {
        Leaf("boom") => fail("boom")
        Leaf(s) => s
        Branch(tag, _) => tag
      }
    })
    false
  } catch {
    _ => true
  }
  inspect(caught, content="true")
}

///|
test "ProjNode Show — depth-1 only, uses Renderable::kind_tag" {
  let leaf = ProjNode(Leaf("x"), 0, 1, 0, [])
  inspect(leaf, content="#0 Leaf [0..1]")
}

///|
test "ProjNode Show — Branch with children does not recurse into kind/children" {
  let child = ProjNode(Leaf("a"), 0, 1, 1, [])
  let root = ProjNode(Branch("root", [Leaf("a")]), 0, 5, 7, [child])
  inspect(root, content="#7 Branch [0..5]")
}

///|
test "SourceMap::from_ast works with TestExpr" {
  let child = ProjNode(Leaf("a"), 0, 1, 1, [])
  let root = ProjNode(Branch("root", [Leaf("a")]), 0, 5, 0, [child])
  let sm = SourceMap::from_ast(root)
  inspect(sm.node_count(), content="2")
  inspect(sm.get_range(NodeId::from_int(0)) is Some(_), content="true")
  inspect(sm.get_range(NodeId::from_int(1)) is Some(_), content="true")
}

///|
test "reconcile preserves IDs when kinds match" {
  let old = ProjNode(Leaf("x"), 0, 1, 42, [])
  let new_ = ProjNode(Leaf("y"), 0, 1, 99, [])
  let counter = Ref(100)
  let result = reconcile(old, new_, counter)
  // same_kind(Leaf, Leaf) is true → old ID preserved
  inspect(result.node_id, content="42")
  inspect(result.kind, content="Leaf(\"y\")")
}

///|
test "reconcile assigns fresh IDs when kinds differ" {
  let old = ProjNode(Leaf("x"), 0, 1, 42, [])
  let new_ = ProjNode(Branch("b", []), 0, 3, 99, [])
  let counter = Ref(100)
  let result = reconcile(old, new_, counter)
  // same_kind(Leaf, Branch) is false → fresh ID
  inspect(result.node_id, content="100")
}

///|
test "assign_fresh_ids renumbers entire subtree" {
  let child = ProjNode(Leaf("a"), 0, 1, 0, [])
  let root = ProjNode(Branch("r", [Leaf("a")]), 0, 5, 1, [child])
  let counter = Ref(50)
  let result = assign_fresh_ids(root, counter)
  // post-order: child gets 50, parent gets 51
  inspect(result.children[0].node_id, content="50")
  inspect(result.node_id, content="51")
}

///|
test "get_node_in_tree finds nested node" {
  let leaf = ProjNode(Leaf("target"), 2, 8, 7, [])
  let root = ProjNode(Branch("r", [Leaf("target")]), 0, 10, 0, [leaf])
  let found = get_node_in_tree(root, NodeId::from_int(7))
  inspect(found is Some(_), content="true")
  inspect(found.unwrap().kind, content="Leaf(\"target\")")
}

///|
test "ProjNode::fold — leaf node returns f(node, [])" {
  let leaf = ProjNode(Leaf("x"), 0, 1, 0, [])
  let result = leaf.fold((n, _) => n.kind)
  inspect(result, content="Leaf(\"x\")")
}

///|
test "ProjNode::fold — branch passes folded children to f" {
  let a = ProjNode(Leaf("a"), 0, 1, 11, [])
  let b = ProjNode(Leaf("b"), 3, 4, 12, [])
  let root = ProjNode(Branch("r", [Leaf("a"), Leaf("b")]), 0, 5, 10, [a, b])
  let result = root.fold((n, children) => {
    children.length().to_string() + ":" + n.id().to_string()
  })
  // root has 2 children, id=10
  inspect(result, content="2:NodeId(10)")
}

///|
test "ProjNode::fold — count_nodes: fold(_, _, (_, child_counts) => 1 + sum(child_counts))" {
  let a = ProjNode(Leaf("a"), 0, 1, 1, [])
  let b = ProjNode(Leaf("b"), 1, 2, 2, [])
  let c = ProjNode(Leaf("c"), 2, 3, 3, [])
  let middle = ProjNode(Branch("m", [Leaf("b"), Leaf("c")]), 1, 3, 4, [b, c])
  let root = ProjNode(Branch("r", [Leaf("a"), middle.kind]), 0, 3, 5, [
    a, middle,
  ])
  let count = root.fold((_, child_counts) => {
    1 + child_counts.fold(init=0, (acc, c) => acc + c)
  })
  inspect(count, content="5")
}

///|
test "ProjNode::fold — preserves ProjNode structure (identity-like fold)" {
  let a = ProjNode(Leaf("a"), 0, 1, 1, [])
  let b = ProjNode(Leaf("b"), 3, 4, 2, [])
  let root = ProjNode(Branch("r", [Leaf("a"), Leaf("b")]), 0, 5, 0, [a, b])
  let reconstructed = root.fold((n, children) => {
    ProjNode(n.kind, n.start, n.end, n.node_id, children)
  })
  inspect(reconstructed == root, content="true")
}

///|
test "ProjNode::fold — stack safety on deep chain" {
  // Build a deep chain of 500 nodes (worst-case for recursion)
  let mut leaf = ProjNode(Leaf("x"), 0, 1, 0, [])
  for i in 1..<=500 {
    leaf = ProjNode(Branch("r", [leaf.kind]), 0, 1, i, [leaf])
  }
  let count = leaf.fold((_, child_counts) => {
    1 + (if child_counts.is_empty() { 0 } else { child_counts[0] })
  })
  inspect(count, content="501")
}

///|
test "ProjNode::walk_preorder visits all nodes" {
  let a = ProjNode(Leaf("a"), 0, 1, 1, [])
  let b = ProjNode(Leaf("b"), 1, 2, 2, [])
  let root = ProjNode(Branch("r", [Leaf("a"), Leaf("b")]), 0, 3, 0, [a, b])
  let visited : Array[Int] = []
  root.walk_preorder(n => visited.push(n.node_id))
  // Pre-order: parent (0), then left child (1), then right child (2)
  @debug.assert_eq(visited, [0, 1, 2])
}

///|
test "ProjNode::walk_preorder visits single leaf" {
  let leaf = ProjNode(Leaf("x"), 0, 1, 7, [])
  let visited : Array[Int] = []
  leaf.walk_preorder(n => visited.push(n.node_id))
  @debug.assert_eq(visited, [7])
}

///|
test "ProjNode::walk_preorder passes correct FoldNode fields" {
  let leaf = ProjNode(Leaf("x"), 2, 8, 42, [])
  let seen : Array[String] = []
  leaf.walk_preorder(n => {
    seen.push("\{n.kind}|n.\{n.node_id}|s.\{n.start}|e.\{n.end}")
  })
  inspect(seen[0], content="Leaf(\"x\")|n.42|s.2|e.8")
}

///|
test "ToJson for ProjNode[TestExpr] compiles" {
  let node = ProjNode(Leaf("x"), 0, 1, 0, [])
  let json = node.to_json()
  inspect(json.stringify().length() > 0, content="true")
}
