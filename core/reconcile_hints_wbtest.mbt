// Tests for structural-edit hint consumption in reconcile_hinted.
// Reuses the TestExpr fixture (Leaf / Branch) from test_expr_wbtest.mbt.
//
// The hints that do real work are exactly the constructor-changing edits LCS
// loses: Wrap and Unwrap at a CHILD position (a wrap of the whole root never
// happens in practice). `same_kind` for TestExpr compares constructor only, so
// rename / sibling insert / delete are already identity-preserving by LCS and
// need no hint.

///|
/// Build a hint map from (NodeId, IdentityTransform) pairs.
fn mk_hints(
  pairs : Array[(Int, IdentityTransform)],
) -> Map[NodeId, IdentityTransform] {
  let m : Map[NodeId, IdentityTransform] = {}
  for pair in pairs {
    m[NodeId::from_int(pair.0)] = pair.1
  }
  m
}

///|
test "Wrap hint at a child position carries the inner id" {
  // old: root#1 -> Leaf#5
  let inner = ProjNode::new(Leaf("x"), 0, 1, 5, [])
  let old = ProjNode::new(Branch("root", [Leaf("x")]), 0, 5, 1, [inner])
  // new: root -> Branch wrapper -> Leaf  (Leaf#5 got wrapped one level deeper)
  let new_inner = ProjNode::new(Leaf("x"), 1, 2, 90, [])
  let wrapper = ProjNode::new(Branch("w", [Leaf("x")]), 1, 3, 91, [new_inner])
  let new_ = ProjNode::new(
    Branch("root", [Branch("w", [Leaf("x")])]),
    0,
    5,
    92,
    [wrapper],
  )
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  // root keeps id 1 (same_kind Branch)
  inspect(result.node_id, content="1")
  // the wrapped Leaf keeps id 5; the wrapper node itself is fresh
  inspect(result.children[0].children[0].node_id, content="5")
  inspect(result.children[0].node_id >= 1000, content="true")
}

///|
test "Unwrap hint at a child position carries the kept id" {
  // old: root#1 -> wrapper#10 -> Leaf#5
  let kept = ProjNode::new(Leaf("x"), 1, 2, 5, [])
  let wrapper = ProjNode::new(Branch("w", [Leaf("x")]), 1, 3, 10, [kept])
  let old = ProjNode::new(Branch("root", [Branch("w", [Leaf("x")])]), 0, 5, 1, [
    wrapper,
  ])
  // new: root -> Leaf  (wrapper removed, Leaf promoted)
  let new_child = ProjNode::new(Leaf("x"), 1, 2, 90, [])
  let new_ = ProjNode::new(Branch("root", [Leaf("x")]), 0, 5, 91, [new_child])
  let hints = mk_hints([
    (10, Unwrap(wrapper=NodeId::from_int(10), keep=NodeId::from_int(5))),
  ])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  inspect(result.node_id, content="1")
  // promoted Leaf keeps the kept child's id 5
  inspect(result.children[0].node_id, content="5")
}

///|
test "without a hint, a wrap loses the inner id (degrades to fresh)" {
  let inner = ProjNode::new(Leaf("x"), 0, 1, 5, [])
  let old = ProjNode::new(Branch("root", [Leaf("x")]), 0, 5, 1, [inner])
  let new_inner = ProjNode::new(Leaf("x"), 1, 2, 90, [])
  let wrapper = ProjNode::new(Branch("w", [Leaf("x")]), 1, 3, 91, [new_inner])
  let new_ = ProjNode::new(
    Branch("root", [Branch("w", [Leaf("x")])]),
    0,
    5,
    92,
    [wrapper],
  )
  let result = reconcile_hinted(old, new_, Ref(1000), {})
  // no hint → LCS cannot pair Leaf#5 with the Branch wrapper → inner is fresh
  inspect(result.children[0].children[0].node_id >= 1000, content="true")
}

///|
test "ambiguous wrap target degrades to fresh (two same-kind children)" {
  let inner = ProjNode::new(Leaf("x"), 0, 1, 5, [])
  let old = ProjNode::new(Branch("root", [Leaf("x")]), 0, 5, 1, [inner])
  // wrapper has TWO Leaf children → cannot disambiguate which carries id 5
  let la = ProjNode::new(Leaf("a"), 1, 2, 90, [])
  let lb = ProjNode::new(Leaf("b"), 2, 3, 91, [])
  let wrapper = ProjNode::new(Branch("w", [Leaf("a"), Leaf("b")]), 1, 4, 92, [
    la, lb,
  ])
  let new_ = ProjNode::new(
    Branch("root", [Branch("w", [Leaf("a"), Leaf("b")])]),
    0,
    6,
    93,
    [wrapper],
  )
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  // ambiguous → degrade: id 5 carried into neither child
  inspect(result.children[0].children[0].node_id >= 1000, content="true")
  inspect(result.children[0].children[1].node_id >= 1000, content="true")
}

///|
test "same-kind Wrap carries the wrapped node id, not the new wrapper" {
  // old: root#1 -> a#5 (Branch) -> Leaf#6
  let a_leaf = ProjNode::new(Leaf("x"), 0, 1, 6, [])
  let a = ProjNode::new(Branch("a", [Leaf("x")]), 0, 2, 5, [a_leaf])
  let old = ProjNode::new(Branch("root", [Branch("a", [Leaf("x")])]), 0, 5, 1, [
    a,
  ])
  // new: a#5 wrapped in another Branch of the SAME kind (Branch -> Branch)
  let new_a_leaf = ProjNode::new(Leaf("x"), 1, 2, 90, [])
  let new_a = ProjNode::new(Branch("a", [Leaf("x")]), 1, 3, 91, [new_a_leaf])
  let wrapper = ProjNode::new(
    Branch("w", [Branch("a", [Leaf("x")])]),
    1,
    4,
    92,
    [new_a],
  )
  let new_ = ProjNode::new(
    Branch("root", [Branch("w", [Branch("a", [Leaf("x")])])]),
    0,
    5,
    93,
    [wrapper],
  )
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  inspect(result.node_id, content="1") // root preserved
  // the wrapper Branch is fresh; the wrapped Branch a keeps id 5
  inspect(result.children[0].node_id >= 1000, content="true")
  inspect(result.children[0].children[0].node_id, content="5")
}

///|
test "two old children claiming one wrapper degrade to fresh" {
  // old: root#1 -> [Leaf#5, Leaf#6], both hinted as wrapped
  let l5 = ProjNode::new(Leaf("x"), 0, 1, 5, [])
  let l6 = ProjNode::new(Leaf("y"), 1, 2, 6, [])
  let old = ProjNode::new(Branch("root", [Leaf("x"), Leaf("y")]), 0, 3, 1, [
    l5, l6,
  ])
  // new: root -> single wrapper Branch with one Leaf child
  let new_leaf = ProjNode::new(Leaf("x"), 0, 1, 90, [])
  let wrapper = ProjNode::new(Branch("w", [Leaf("x")]), 0, 2, 91, [new_leaf])
  let new_ = ProjNode::new(
    Branch("root", [Branch("w", [Leaf("x")])]),
    0,
    3,
    92,
    [wrapper],
  )
  let hints = mk_hints([
    (5, Wrap(inner=NodeId::from_int(5))),
    (6, Wrap(inner=NodeId::from_int(6))),
  ])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  // both #5 and #6 pair the single wrapper → ambiguous → degrade → inner fresh
  inspect(result.children[0].children[0].node_id >= 1000, content="true")
}

///|
test "same-kind Wrap with ambiguous target degrades to fresh (no id on wrapper)" {
  // old: root#1 -> a#5 (Branch)
  let a_leaf = ProjNode::new(Leaf("x"), 0, 1, 6, [])
  let a = ProjNode::new(Branch("a", [Leaf("x")]), 0, 2, 5, [a_leaf])
  let old = ProjNode::new(Branch("root", [Branch("a", [Leaf("x")])]), 0, 5, 1, [
    a,
  ])
  // new: a#5 "wrapped" in a same-kind Branch that has TWO Branch children →
  // the wrapped node cannot be located unambiguously.
  let c1_leaf = ProjNode::new(Leaf("x"), 1, 2, 90, [])
  let c1 = ProjNode::new(Branch("a", [Leaf("x")]), 1, 3, 91, [c1_leaf])
  let c2_leaf = ProjNode::new(Leaf("y"), 3, 4, 92, [])
  let c2 = ProjNode::new(Branch("b", [Leaf("y")]), 3, 5, 93, [c2_leaf])
  let wrapper = ProjNode::new(
    Branch("w", [Branch("a", [Leaf("x")]), Branch("b", [Leaf("y")])]),
    1,
    5,
    94,
    [c1, c2],
  )
  let new_ = ProjNode::new(
    Branch("root", [
      Branch("w", [Branch("a", [Leaf("x")]), Branch("b", [Leaf("y")])]),
    ]),
    0,
    6,
    95,
    [wrapper],
  )
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  // hint present but unlocatable (2 same-kind targets) → degrade: the wrapper
  // must NOT keep id 5; it is fresh.
  inspect(result.children[0].node_id >= 1000, content="true")
}

///|
test "one hint matching two new wrappers degrades to fresh" {
  // old: root#1 -> Leaf#5 (hinted as wrapped)
  let l5 = ProjNode::new(Leaf("x"), 0, 1, 5, [])
  let old = ProjNode::new(Branch("root", [Leaf("x")]), 0, 3, 1, [l5])
  // new: root -> [wrapperA(Leaf), wrapperB(Leaf)] — two same-kind wrappers, each
  // a valid wrap target for #5, so the wrapped node is not locatable in exactly
  // one new sibling.
  let a_leaf = ProjNode::new(Leaf("x"), 0, 1, 90, [])
  let wa = ProjNode::new(Branch("w", [Leaf("x")]), 0, 2, 91, [a_leaf])
  let b_leaf = ProjNode::new(Leaf("x"), 2, 3, 92, [])
  let wb = ProjNode::new(Branch("w", [Leaf("x")]), 2, 4, 93, [b_leaf])
  let new_ = ProjNode::new(
    Branch("root", [Branch("w", [Leaf("x")]), Branch("w", [Leaf("x")])]),
    0,
    4,
    94,
    [wa, wb],
  )
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  // #5 could land in either wrapper → ambiguous → degrade → neither inner keeps 5
  inspect(result.children[0].children[0].node_id >= 1000, content="true")
  inspect(result.children[1].children[0].node_id >= 1000, content="true")
}
