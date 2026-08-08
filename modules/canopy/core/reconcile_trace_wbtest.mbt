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
test "positional fast path preserves nested IDs and trace order" {
  let old_leaf = ProjNode(Leaf("old"), 0, 1, 2, [])
  let old_branch = ProjNode(Branch("child", [Leaf("old")]), 0, 2, 1, [old_leaf])
  let old_tail = ProjNode(Leaf("tail-old"), 2, 3, 3, [])
  let old = ProjNode(
    Branch("root", [Branch("child", [Leaf("old")]), Leaf("tail-old")]),
    0,
    3,
    0,
    [old_branch, old_tail],
  )
  let new_leaf = ProjNode(Leaf("new"), 0, 1, 12, [])
  let new_branch = ProjNode(Branch("child", [Leaf("new")]), 0, 2, 11, [new_leaf])
  let new_tail = ProjNode(Leaf("tail-new"), 2, 3, 13, [])
  let new_ = ProjNode(
    Branch("root", [Branch("child", [Leaf("new")]), Leaf("tail-new")]),
    0,
    3,
    10,
    [new_branch, new_tail],
  )
  let trace = Ref([])
  let counter = Ref(100)
  let result = reconcile(old, new_, counter, trace_ref=Some(trace))
  inspect(result.children[0].id() == old_branch.id(), content="true")
  inspect(result.children[0].children[0].id() == old_leaf.id(), content="true")
  inspect(result.children[1].id() == old_tail.id(), content="true")
  inspect(counter.val, content="100")
  inspect(trace.val.length(), content="3")
  guard trace.val[0] is Matched(_, 0, 0, _, _) else {
    fail("nested match should be traced first")
  }
  guard trace.val[1] is Matched(_, 0, 0, _, _) else {
    fail("first root match should follow nested match")
  }
  guard trace.val[2] is Matched(_, 1, 1, _, _) else {
    fail("second root match should be traced last")
  }
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

// ---------------------------------------------------------------------------
// Characterization pins for LCS-fallback trace order (Phase 1 of
// docs/plans/2026-08-08-core-reconcile-engine-deepening.md).
// These pin today's observable emission order so the engine extraction
// cannot silently change it.
// ---------------------------------------------------------------------------

///|
test "LCS fallback emits inner Matched before outer Matched" {
  // Root children are unequal in length (1 vs 2) → LCS fallback; the matched
  // nested Branch's own Leaf emits its Matched (parent = inner branch #1)
  // before the outer Branch's Matched (parent = root #0): DFS emission order.
  let old = ProjNode(Branch("root", [Branch("inner", [Leaf("x")])]), 0, 5, 0, [
    ProjNode(Branch("inner", [Leaf("x")]), 0, 2, 1, [
      ProjNode(Leaf("x"), 0, 1, 2, []),
    ]),
  ])
  let new_ = ProjNode(
    Branch("root", [Leaf("a"), Branch("inner", [Leaf("x")])]),
    0,
    5,
    23,
    [
      ProjNode(Leaf("a"), 0, 1, 20, []),
      ProjNode(Branch("inner", [Leaf("x")]), 1, 3, 22, [
        ProjNode(Leaf("x"), 1, 2, 21, []),
      ]),
    ],
  )
  let trace = Ref([])
  let _result = reconcile(old, new_, Ref(1000), trace_ref=Some(trace))
  // [Inserted(new Leaf a), Matched(inner Leaf, parent=1), Matched(inner Branch, parent=0)]
  inspect(trace.val.length(), content="3")
  guard trace.val[0] is Inserted(_, _, _, _) else {
    fail("first should be Inserted")
  }
  guard trace.val[1] is Matched(parent_inner, _, _, _, _) else {
    fail("second should be Matched")
  }
  guard trace.val[2] is Matched(parent_outer, _, _, _, _) else {
    fail("third should be Matched")
  }
  inspect(parent_inner == NodeId::from_int(1), content="true")
  inspect(parent_outer == NodeId::from_int(0), content="true")
}

///|
test "LCS fallback emits all Deleted events after Matched events" {
  // Crossing tie [L,B]→[B,L]: Deleted comes last, after the Inserted and
  // Matched events.
  let old = ProjNode(Branch("root", [Leaf("a"), Branch("b", [])]), 0, 5, 0, [
    ProjNode(Leaf("a"), 0, 1, 1, []),
    ProjNode(Branch("b", []), 1, 2, 2, []),
  ])
  let new_ = ProjNode(Branch("root", [Branch("b", []), Leaf("x")]), 0, 5, 22, [
    ProjNode(Branch("b", []), 0, 1, 20, []),
    ProjNode(Leaf("x"), 1, 2, 21, []),
  ])
  let trace = Ref([])
  let _result = reconcile(old, new_, Ref(1000), trace_ref=Some(trace))
  inspect(trace.val.length(), content="3")
  guard trace.val[0] is Inserted(_, _, _, _) else {
    fail("first should be Inserted")
  }
  guard trace.val[1] is Matched(_, _, _, _, _) else {
    fail("second should be Matched")
  }
  guard trace.val[2] is Deleted(_, _, _, _) else {
    fail("third should be Deleted (last)")
  }
}

///|
test "LCS fallback crossing tie emits one Inserted and one Deleted" {
  // Same crossing-tie fixture: exactly one Inserted (new B) and one Deleted
  // (old B); the old L keeps its id via the single Matched event.
  let old = ProjNode(Branch("root", [Leaf("a"), Branch("b", [])]), 0, 5, 0, [
    ProjNode(Leaf("a"), 0, 1, 1, []),
    ProjNode(Branch("b", []), 1, 2, 2, []),
  ])
  let new_ = ProjNode(Branch("root", [Branch("b", []), Leaf("x")]), 0, 5, 22, [
    ProjNode(Branch("b", []), 0, 1, 20, []),
    ProjNode(Leaf("x"), 1, 2, 21, []),
  ])
  let trace = Ref([])
  let _result = reconcile(old, new_, Ref(1000), trace_ref=Some(trace))
  let inserted = [
    for ev in trace.val if ev is Inserted(_, _, _, _) => ev
  ].length()
  let deleted = [
    for ev in trace.val if ev is Deleted(_, _, _, _) => ev
  ].length()
  let matched = [
    for ev in trace.val if ev is Matched(_, _, _, _, _) => ev
  ].length()
  inspect(inserted, content="1")
  inspect(deleted, content="1")
  inspect(matched, content="1")
  guard trace.val[1] is Matched(_, _, _, node_id, _) else {
    fail("second should be Matched")
  }
  inspect(node_id == NodeId::from_int(1), content="true")
}

///|
test "exact-key emits the same realization order as plain on the crossing tie" {
  // old [Leaf a, Branch b] → new [Branch b, Leaf a] via exact key: both
  // diagonals carry equal weighted scores (same-kind base + equal fingerprint
  // bonus — same payloads on both sides), so the front reconstruction yields
  // the same observable sequence as plain: Inserted (new Branch, fresh 1000),
  // Matched (old Leaf #1 → new Leaf), Deleted (old Branch #2).
  let old = ProjNode(Branch("root", [Leaf("a"), Branch("b", [])]), 0, 5, 0, [
    ProjNode(Leaf("a"), 0, 1, 1, []),
    ProjNode(Branch("b", []), 1, 2, 2, []),
  ])
  let new_ = ProjNode(Branch("root", [Branch("b", []), Leaf("a")]), 0, 5, 22, [
    ProjNode(Branch("b", []), 0, 1, 20, []),
    ProjNode(Leaf("a"), 1, 2, 21, []),
  ])
  let trace = Ref([])
  let counter = Ref(1000)
  let _result = reconcile_with_exact_key(
    old,
    new_,
    counter,
    exact_test_key,
    trace_ref=Some(trace),
  )
  inspect(trace.val.length(), content="3")
  guard trace.val[0] is Inserted(_, _, node0, _) else {
    fail("first should be Inserted")
  }
  guard trace.val[1] is Matched(_, _, _, node1, _) else {
    fail("second should be Matched")
  }
  guard trace.val[2] is Deleted(_, _, _, _) else {
    fail("third should be Deleted")
  }
  inspect(node0 == NodeId::from_int(1000), content="true")
  inspect(node1 == NodeId::from_int(1), content="true")
}

///|
test "hinted pair emits Matched(old_index=-1) then Deleted for the consumed old node" {
  // A successful post-LCS hint pair emits Matched with old_index=-1 while
  // leaving old_matched untouched, so the Deleted loop later reports the
  // consumed old node as Deleted too. This pins the current sequence — a
  // known wart; correcting it is a separate behavior change, not part of the
  // engine extraction.
  let old = ProjNode(Branch("root", [Leaf("a")]), 0, 5, 0, [
    ProjNode(Leaf("a"), 0, 1, 1, []),
  ])
  let new_ = ProjNode(Branch("root", [Branch("w", [Leaf("x")])]), 0, 5, 22, [
    ProjNode(Branch("w", [Leaf("x")]), 1, 3, 21, [
      ProjNode(Leaf("x"), 1, 2, 20, []),
    ]),
  ])
  let hints = mk_hints([(1, IdentityTransform::Wrap(inner=NodeId::from_int(1)))])
  let trace = Ref([])
  let counter = Ref(1000)
  let result = reconcile_hinted(
    old,
    new_,
    counter,
    hints,
    trace_ref=Some(trace),
  )
  // wrapper fresh (1000), its child carries old Leaf a's id (1)
  inspect(result.children[0].node_id, content="1000")
  inspect(
    result.children[0].children[0].node_id == old.children[0].node_id,
    content="true",
  )
  inspect(counter.val, content="1001")
  inspect(trace.val.length(), content="3")
  guard trace.val[0] is Wrapped(_, _, _) else {
    fail("first should be Wrapped")
  }
  guard trace.val[1] is Matched(_, -1, 0, _, _) else {
    fail("second should be Matched with old_index=-1")
  }
  guard trace.val[2] is Deleted(_, 0, node_id, _) else {
    fail("third should be Deleted")
  }
  inspect(node_id == NodeId::from_int(1), content="true")
}
