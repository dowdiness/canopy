// Tests for ReconcileTraceEvent emission during structural reconciliation.
// Verifies that each structural edit type produces the correct trace events
// and that to_structured_changes correctly filters Matched events.
//
// Reuses the TestExpr fixture (Leaf / Branch) from test_expr_wbtest.mbt.
// LCS behavior note: TestExpr same_kind checks constructor (Leaf vs Branch)
// only, not the label. Tests use mixed constructors to control which children
// LCS pairs.

///|
test "no events when trace_ref is None" {
  let old = ProjNode(Leaf("x"), 0, 1, 0, [])
  let new_ = ProjNode(Leaf("y"), 0, 1, 1, [])
  let result = reconcile(old, new_, Ref(100))
  inspect(result.node_id, content="0")
}

///|
test "identical trees produce only Matched events" {
  let child = ProjNode(Leaf("a"), 0, 1, 1, [])
  let old = ProjNode(Branch("r", [Leaf("a")]), 0, 5, 0, [child])
  let new_child = ProjNode(Leaf("a"), 0, 1, 10, [])
  let new_ = ProjNode(Branch("r", [Leaf("a")]), 0, 5, 11, [new_child])
  let trace = Ref([])
  let _result = reconcile(old, new_, Ref(100), trace_ref=Some(trace))
  inspect(trace.val.length(), content="1")
  guard trace.val[0] is Matched(_, _, _, _, _) else { fail("expected Matched") }
}

///|
test "inserted child produces Inserted event" {
  // LCS: old Leaf matches new Leaf; Branch is unlike → Inserted at new idx 1
  let c1 = ProjNode(Leaf("a"), 0, 1, 1, [])
  let old = ProjNode(Branch("r", [Leaf("a")]), 0, 5, 0, [c1])
  let nc1 = ProjNode(Leaf("a"), 0, 1, 10, [])
  let nc2 = ProjNode(Branch("w", []), 1, 2, 11, [])
  let new_ = ProjNode(Branch("r", [Leaf("a"), Branch("w", [])]), 0, 5, 12, [
    nc1, nc2,
  ])
  let trace = Ref([])
  let _result = reconcile(old, new_, Ref(100), trace_ref=Some(trace))
  inspect(trace.val.length(), content="2")
  guard trace.val[0] is Matched(_, _, _, _, _) else {
    fail("first should be Matched")
  }
  guard trace.val[1] is Inserted(_parent, idx, _node, _kind) else {
    fail("second should be Inserted")
  }
  inspect(idx, content="1")
}

///|
test "deleted child produces Deleted event" {
  // LCS: old Leaf matches new Leaf; Branch is unlike → Deleted at old idx 1
  let c1 = ProjNode(Leaf("a"), 0, 1, 1, [])
  let c2 = ProjNode(Branch("w", []), 1, 2, 2, [])
  let old = ProjNode(Branch("r", [Leaf("a"), Branch("w", [])]), 0, 5, 0, [
    c1, c2,
  ])
  let nc1 = ProjNode(Leaf("a"), 0, 1, 10, [])
  let new_ = ProjNode(Branch("r", [Leaf("a")]), 0, 5, 11, [nc1])
  let trace = Ref([])
  let _result = reconcile(old, new_, Ref(100), trace_ref=Some(trace))
  inspect(trace.val.length(), content="2")
  guard trace.val[0] is Matched(_, _, _, _, _) else {
    fail("first should be Matched")
  }
  guard trace.val[1] is Deleted(_parent, old_idx, _node, _kind) else {
    fail("second should be Deleted")
  }
  inspect(old_idx, content="1")
}

///|
test "bulk insert: N children produce N Inserted events" {
  let old_child = ProjNode(Leaf("x"), 0, 1, 1, [])
  let old = ProjNode(Branch("r", [Leaf("x")]), 0, 5, 0, [old_child])
  let n = 20
  let new_children : Array[ProjNode[TestExpr]] = []
  // First child matches old Leaf (same_kind Leaf)
  new_children.push(ProjNode(Leaf("x"), 0, 1, 10, []))
  // 20 Branch children are unlike Leaf → each produces an Inserted event
  for i = 0; i < n; i = i + 1 {
    new_children.push(ProjNode(Branch("w", []), i + 1, i + 2, 20 + i, []))
  }
  let new_ = ProjNode(Branch("r", []), 0, n + 1, 50, new_children)
  let trace = Ref([])
  let _result = reconcile(old, new_, Ref(100), trace_ref=Some(trace))
  // 1 Matched + 20 Inserted = 21 events
  inspect(trace.val.length(), content="21")
  let inserted_count = [
    for ev in trace.val if ev is Inserted(_, _, _, _) => 1
  ].length()
  inspect(inserted_count, content="20")
}

///|
test "all children matched with aligned constructors" {
  // Constructors aligned at same indices: old [Leaf, Branch] → new [Leaf, Branch]
  // LCS: Leaf↔Leaf (idx 0), Branch↔Branch (idx 1) → 2 pairs → 2 Matched, no insert/delete
  let c1 = ProjNode(Leaf("a"), 0, 1, 1, [])
  let c2 = ProjNode(Branch("x", []), 1, 2, 2, [])
  let old = ProjNode(Branch("r", [Leaf("a"), Branch("x", [])]), 0, 5, 0, [
    c1, c2,
  ])
  let nc1 = ProjNode(Leaf("b"), 0, 1, 10, [])
  let nc2 = ProjNode(Branch("y", []), 1, 2, 11, [])
  let new_ = ProjNode(Branch("r", [Leaf("b"), Branch("y", [])]), 0, 5, 12, [
    nc1, nc2,
  ])
  let trace = Ref([])
  let _result = reconcile(old, new_, Ref(100), trace_ref=Some(trace))
  inspect(trace.val.length(), content="2")
  guard trace.val[0] is Matched(_, _, _, _, _) else {
    fail("first should be Matched")
  }
  guard trace.val[1] is Matched(_, _, _, _, _) else {
    fail("second should be Matched")
  }
}

///|
test "one insert and one delete when LCS leaves unmatched children" {
  // old: [Leaf(a)@1, Branch(w)@2] — Branch unmatched in new
  // new: [Leaf(b)@10, Leaf(c)@11] — no Branch, one extra Leaf unmatched
  // LCS: Leaf(a)↔Leaf(b)/Leaf(c) (one pair), Branch(w) has no match → 1 Deleted
  // Unmatched new Leaf → 1 Inserted
  let c1 = ProjNode(Leaf("a"), 0, 1, 1, [])
  let c2 = ProjNode(Branch("w", []), 1, 2, 2, [])
  let old = ProjNode(Branch("r", [Leaf("a"), Branch("w", [])]), 0, 5, 0, [
    c1, c2,
  ])
  let nc1 = ProjNode(Leaf("b"), 0, 1, 10, [])
  let nc2 = ProjNode(Leaf("c"), 1, 2, 11, [])
  let new_ = ProjNode(Branch("r", [Leaf("b"), Leaf("c")]), 0, 5, 12, [nc1, nc2])
  let trace = Ref([])
  let _result = reconcile(old, new_, Ref(100), trace_ref=Some(trace))
  // 3 events: Inserted(Leaf at new 0), Matched(Leaf at new 1), Deleted(Branch at old 1)
  inspect(trace.val.length(), content="3")
  guard trace.val[0] is Inserted(_parent, idx, _node, kind) else {
    fail("first should be Inserted")
  }
  guard trace.val[1] is Matched(_, _, _, _, _) else {
    fail("second should be Matched")
  }
  guard trace.val[2] is Deleted(_, _, _, _) else {
    fail("third should be Deleted")
  }
  inspect(idx, content="0")
  inspect(kind, content="Leaf")
}

///|
test "Wrap via hint produces Wrapped event" {
  let inner = ProjNode(Leaf("x"), 0, 1, 1, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 5, 0, [inner])
  let new_inner = ProjNode(Leaf("x"), 1, 2, 90, [])
  let wrapper = ProjNode(Branch("w", [Leaf("x")]), 1, 3, 91, [new_inner])
  let new_ = ProjNode(Branch("root", [Branch("w", [Leaf("x")])]), 0, 5, 92, [
    wrapper,
  ])
  let hints = mk_hints([(1, Wrap(inner=NodeId::from_int(1)))])
  let trace = Ref([])
  let _result = reconcile_hinted(
    old,
    new_,
    Ref(1000),
    hints,
    trace_ref=Some(trace),
  )
  inspect(trace.val.length() >= 1, content="true")
  let found_wrapped = [
    for ev in trace.val if ev is Wrapped(_, _, _) => ev
  ].length()
  inspect(found_wrapped, content="1")
}

///|
test "Unwrap via hint produces Unwrapped event" {
  let kept = ProjNode(Leaf("x"), 1, 2, 1, [])
  let wrapper = ProjNode(Branch("w", [Leaf("x")]), 1, 3, 10, [kept])
  let old = ProjNode(Branch("root", [Branch("w", [Leaf("x")])]), 0, 5, 0, [
    wrapper,
  ])
  let new_child = ProjNode(Leaf("x"), 1, 2, 90, [])
  let new_ = ProjNode(Branch("root", [Leaf("x")]), 0, 5, 91, [new_child])
  let hints = mk_hints([
    (10, Unwrap(wrapper=NodeId::from_int(10), keep=NodeId::from_int(1))),
  ])
  let trace = Ref([])
  let _result = reconcile_hinted(
    old,
    new_,
    Ref(1000),
    hints,
    trace_ref=Some(trace),
  )
  inspect(trace.val.length() >= 1, content="true")
  let found_unwrapped = [
    for ev in trace.val if ev is Unwrapped(_, _, _) => ev
  ].length()
  inspect(found_unwrapped, content="1")
}

///|
test "to_structured_changes drops Matched, keeps others" {
  let events : Array[ReconcileTraceEvent] = [
    Matched(NodeId::from_int(0), 0, 0, NodeId::from_int(1), "Leaf"),
    Inserted(NodeId::from_int(0), 1, NodeId::from_int(2), "Leaf"),
    Deleted(NodeId::from_int(0), 0, NodeId::from_int(3), "Leaf"),
    Matched(NodeId::from_int(0), 1, 1, NodeId::from_int(4), "Branch"),
  ]
  let changes = to_structured_changes(events)
  inspect(changes.length(), content="2")
  guard changes[0] is StructuredChange::Inserted(_, _, _, _) else {
    fail("first should be Inserted")
  }
  guard changes[1] is StructuredChange::Deleted(_, _, _, _) else {
    fail("second should be Deleted")
  }
}

///|
test "nested hierarchy produces Matched per child level" {
  // Events are depth-first: reconcile_children recurses into the Branch's own
  // children before emitting the outer Matched for Branch. So first event is
  // Leaf's Matched (parent=Branch#1), second is Branch's Matched (parent=root#0).
  let leaf = ProjNode(Leaf("x"), 0, 1, 2, [])
  let branch = ProjNode(Branch("inner", [Leaf("x")]), 0, 2, 1, [leaf])
  let old = ProjNode(Branch("root", [Branch("inner", [Leaf("x")])]), 0, 5, 0, [
    branch,
  ])
  let n_leaf = ProjNode(Leaf("x"), 0, 1, 20, [])
  let n_branch = ProjNode(Branch("inner", [Leaf("x")]), 0, 2, 21, [n_leaf])
  let new_ = ProjNode(
    Branch("root", [Branch("inner", [Leaf("x")])]),
    0,
    5,
    22,
    [n_branch],
  )
  let trace = Ref([])
  let _result = reconcile(old, new_, Ref(100), trace_ref=Some(trace))
  inspect(trace.val.length(), content="2")
  guard trace.val[0] is Matched(parent0, _, _, _, _) else {
    fail("first should be Matched")
  }
  guard trace.val[1] is Matched(parent1, _, _, _, _) else {
    fail("second should be Matched")
  }
  // First event: Branch#1's children → parent = Branch#1 = NodeId(1)
  // Second event: root#0's children → parent = root#0 = NodeId(0)
  inspect(parent0, content="NodeId(1)")
  inspect(parent1, content="NodeId(0)")
}

///|
/// Count nodes in a TestExpr tree.
fn count_test_expr_nodes(expr : TestExpr) -> Int {
  match expr {
    Leaf(_) => 1
    Branch(_, cs) =>
      1 + cs.fold(init=0, fn(acc, c) { acc + count_test_expr_nodes(c) })
  }
}

///|
/// Count trace events by variant.
fn count_matched(events : Array[ReconcileTraceEvent]) -> Int {
  [ for ev in events if ev is Matched(_, _, _, _, _) => 1 ].length()
}

///|
/// Property: For identical trees, all events are Matched and count = N-1 (all non-root nodes).
fn prop_identical_trees_all_matched(expr : TestExpr) -> Bool {
  let counter_old = Ref(0)
  let old_node = to_proj_node(expr, counter_old)
  let counter_new = Ref(500)
  let new_node = to_proj_node(expr, counter_new)
  let trace = Ref([])
  let _result = reconcile(old_node, new_node, Ref(1000), trace_ref=Some(trace))
  let total_nodes = count_test_expr_nodes(expr)
  let matched_count = count_matched(trace.val)
  if matched_count != total_nodes - 1 {
    return false
  }
  for ev in trace.val {
    guard ev is Matched(_, _, _, _, _) else { return false }
  }
  true
}

///|
test "property: identical trees produce N-1 Matched events" {
  @qc.quick_check_fn(prop_identical_trees_all_matched)
}
