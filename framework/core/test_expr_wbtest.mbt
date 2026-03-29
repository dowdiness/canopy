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
} derive(Show, Eq)

///|
impl @loomcore.TreeNode for TestExpr with children(self) {
  match self {
    Leaf(_) => []
    Branch(_, cs) => cs
  }
}

///|
impl @loomcore.TreeNode for TestExpr with same_kind(self, other) {
  match (self, other) {
    (Leaf(_), Leaf(_)) => true
    (Branch(_, _), Branch(_, _)) => true
    _ => false
  }
}

///|
impl Renderable for TestExpr with kind_tag(self) {
  match self {
    Leaf(_) => "Leaf"
    Branch(_, _) => "Branch"
  }
}

///|
impl Renderable for TestExpr with label(self) {
  match self {
    Leaf(s) => s
    Branch(tag, _) => tag
  }
}

///|
impl Renderable for TestExpr with placeholder(_self) {
  "?"
}

///|
impl Renderable for TestExpr with unparse(self) {
  match self {
    Leaf(s) => s
    Branch(tag, cs) =>
      tag + "(" + cs.map(fn(c) { Renderable::unparse(c) }).join(", ") + ")"
  }
}

///|
impl ToJson for TestExpr with to_json(self) {
  match self {
    Leaf(s) => Json::string(s)
    Branch(tag, _) => Json::string(tag)
  }
}

///|
test "ProjNode[TestExpr] — construction and field access" {
  let leaf = ProjNode::new(Leaf("x"), 0, 1, 0, [])
  inspect(leaf.kind, content="Leaf(\"x\")")
  inspect(leaf.start, content="0")
  inspect(leaf.end, content="1")
  inspect(leaf.id(), content="NodeId(0)")
}

///|
test "SourceMap::from_ast works with TestExpr" {
  let child = ProjNode::new(Leaf("a"), 0, 1, 1, [])
  let root = ProjNode::new(Branch("root", [Leaf("a")]), 0, 5, 0, [child])
  let sm = SourceMap::from_ast(root)
  inspect(sm.node_count(), content="2")
  inspect(sm.get_range(NodeId::from_int(0)) is Some(_), content="true")
  inspect(sm.get_range(NodeId::from_int(1)) is Some(_), content="true")
}

///|
test "reconcile preserves IDs when kinds match" {
  let old = ProjNode::new(Leaf("x"), 0, 1, 42, [])
  let new_ = ProjNode::new(Leaf("y"), 0, 1, 99, [])
  let counter = Ref::new(100)
  let result = reconcile(old, new_, counter)
  // same_kind(Leaf, Leaf) is true → old ID preserved
  inspect(result.node_id, content="42")
  inspect(result.kind, content="Leaf(\"y\")")
}

///|
test "reconcile assigns fresh IDs when kinds differ" {
  let old = ProjNode::new(Leaf("x"), 0, 1, 42, [])
  let new_ = ProjNode::new(Branch("b", []), 0, 3, 99, [])
  let counter = Ref::new(100)
  let result = reconcile(old, new_, counter)
  // same_kind(Leaf, Branch) is false → fresh ID
  inspect(result.node_id, content="100")
}

///|
test "assign_fresh_ids renumbers entire subtree" {
  let child = ProjNode::new(Leaf("a"), 0, 1, 0, [])
  let root = ProjNode::new(Branch("r", [Leaf("a")]), 0, 5, 1, [child])
  let counter = Ref::new(50)
  let result = assign_fresh_ids(root, counter)
  // post-order: child gets 50, parent gets 51
  inspect(result.children[0].node_id, content="50")
  inspect(result.node_id, content="51")
}

///|
test "get_node_in_tree finds nested node" {
  let leaf = ProjNode::new(Leaf("target"), 2, 8, 7, [])
  let root = ProjNode::new(Branch("r", [Leaf("target")]), 0, 10, 0, [leaf])
  let found = get_node_in_tree(root, NodeId::from_int(7))
  inspect(found is Some(_), content="true")
  inspect(found.unwrap().kind, content="Leaf(\"target\")")
}

///|
test "ToJson for ProjNode[TestExpr] compiles" {
  let node = ProjNode::new(Leaf("x"), 0, 1, 0, [])
  let json = node.to_json()
  inspect(json.stringify().length() > 0, content="true")
}
