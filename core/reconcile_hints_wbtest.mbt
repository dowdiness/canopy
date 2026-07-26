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
  let m : Map[NodeId, IdentityTransform] = Map([])
  for pair in pairs {
    m[NodeId::from_int(pair.0)] = pair.1
  }
  m
}

///|
test "Wrap hint at a child position carries the inner id" {
  // old: root#1 -> Leaf#5
  let inner = ProjNode(Leaf("x"), 0, 1, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 5, 1, [inner])
  // new: root -> Branch wrapper -> Leaf  (Leaf#5 got wrapped one level deeper)
  let new_inner = ProjNode(Leaf("x"), 1, 2, 90, [])
  let wrapper = ProjNode(Branch("w", [Leaf("x")]), 1, 3, 91, [new_inner])
  let new_ = ProjNode(Branch("root", [Branch("w", [Leaf("x")])]), 0, 5, 92, [
    wrapper,
  ])
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
  let kept = ProjNode(Leaf("x"), 1, 2, 5, [])
  let wrapper = ProjNode(Branch("w", [Leaf("x")]), 1, 3, 10, [kept])
  let old = ProjNode(Branch("root", [Branch("w", [Leaf("x")])]), 0, 5, 1, [
    wrapper,
  ])
  // new: root -> Leaf  (wrapper removed, Leaf promoted)
  let new_child = ProjNode(Leaf("x"), 1, 2, 90, [])
  let new_ = ProjNode(Branch("root", [Leaf("x")]), 0, 5, 91, [new_child])
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
  let inner = ProjNode(Leaf("x"), 0, 1, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 5, 1, [inner])
  let new_inner = ProjNode(Leaf("x"), 1, 2, 90, [])
  let wrapper = ProjNode(Branch("w", [Leaf("x")]), 1, 3, 91, [new_inner])
  let new_ = ProjNode(Branch("root", [Branch("w", [Leaf("x")])]), 0, 5, 92, [
    wrapper,
  ])
  let result = reconcile_hinted(old, new_, Ref(1000), Map([]))
  // no hint → LCS cannot pair Leaf#5 with the Branch wrapper → inner is fresh
  inspect(result.children[0].children[0].node_id >= 1000, content="true")
}

///|
test "ambiguous wrap target degrades to fresh (two same-kind children)" {
  let inner = ProjNode(Leaf("x"), 0, 1, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 5, 1, [inner])
  // wrapper has TWO Leaf children → cannot disambiguate which carries id 5
  let la = ProjNode(Leaf("a"), 1, 2, 90, [])
  let lb = ProjNode(Leaf("b"), 2, 3, 91, [])
  let wrapper = ProjNode(Branch("w", [Leaf("a"), Leaf("b")]), 1, 4, 92, [la, lb])
  let new_ = ProjNode(
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
  let a_leaf = ProjNode(Leaf("x"), 0, 1, 6, [])
  let a = ProjNode(Branch("a", [Leaf("x")]), 0, 2, 5, [a_leaf])
  let old = ProjNode(Branch("root", [Branch("a", [Leaf("x")])]), 0, 5, 1, [a])
  // new: a#5 wrapped in another Branch of the SAME kind (Branch -> Branch)
  let new_a_leaf = ProjNode(Leaf("x"), 1, 2, 90, [])
  let new_a = ProjNode(Branch("a", [Leaf("x")]), 1, 3, 91, [new_a_leaf])
  let wrapper = ProjNode(Branch("w", [Branch("a", [Leaf("x")])]), 1, 4, 92, [
    new_a,
  ])
  let new_ = ProjNode(
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
  let l5 = ProjNode(Leaf("x"), 0, 1, 5, [])
  let l6 = ProjNode(Leaf("y"), 1, 2, 6, [])
  let old = ProjNode(Branch("root", [Leaf("x"), Leaf("y")]), 0, 3, 1, [l5, l6])
  // new: root -> single wrapper Branch with one Leaf child
  let new_leaf = ProjNode(Leaf("x"), 0, 1, 90, [])
  let wrapper = ProjNode(Branch("w", [Leaf("x")]), 0, 2, 91, [new_leaf])
  let new_ = ProjNode(Branch("root", [Branch("w", [Leaf("x")])]), 0, 3, 92, [
    wrapper,
  ])
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
  let a_leaf = ProjNode(Leaf("x"), 0, 1, 6, [])
  let a = ProjNode(Branch("a", [Leaf("x")]), 0, 2, 5, [a_leaf])
  let old = ProjNode(Branch("root", [Branch("a", [Leaf("x")])]), 0, 5, 1, [a])
  // new: a#5 "wrapped" in a same-kind Branch that has TWO Branch children →
  // the wrapped node cannot be located unambiguously.
  let c1_leaf = ProjNode(Leaf("x"), 1, 2, 90, [])
  let c1 = ProjNode(Branch("a", [Leaf("x")]), 1, 3, 91, [c1_leaf])
  let c2_leaf = ProjNode(Leaf("y"), 3, 4, 92, [])
  let c2 = ProjNode(Branch("b", [Leaf("y")]), 3, 5, 93, [c2_leaf])
  let wrapper = ProjNode(
    Branch("w", [Branch("a", [Leaf("x")]), Branch("b", [Leaf("y")])]),
    1,
    5,
    94,
    [c1, c2],
  )
  let new_ = ProjNode(
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
  let l5 = ProjNode(Leaf("x"), 0, 1, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 1, [l5])
  // new: root -> [wrapperA(Leaf), wrapperB(Leaf)] — two same-kind wrappers, each
  // a valid wrap target for #5, so the wrapped node is not locatable in exactly
  // one new sibling.
  let a_leaf = ProjNode(Leaf("x"), 0, 1, 90, [])
  let wa = ProjNode(Branch("w", [Leaf("x")]), 0, 2, 91, [a_leaf])
  let b_leaf = ProjNode(Leaf("x"), 2, 3, 92, [])
  let wb = ProjNode(Branch("w", [Leaf("x")]), 2, 4, 93, [b_leaf])
  let new_ = ProjNode(
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

///|
test "hinted old child is not consumed by an LCS match against the wrong sibling" {
  // old: root#1 -> [Leaf#5 (hinted wrapped), Leaf#6]
  let l5 = ProjNode(Leaf("x"), 0, 1, 5, [])
  let l6 = ProjNode(Leaf("y"), 1, 2, 6, [])
  let old = ProjNode(Branch("root", [Leaf("x"), Leaf("y")]), 0, 3, 1, [l5, l6])
  // new: [Leaf(new), Branch(Leaf)] — the standalone Leaf is same_kind as #5, but
  // per the hint #5 belongs to the Branch wrapper. LCS must not consume #5
  // against the standalone Leaf first.
  let nl = ProjNode(Leaf("z"), 0, 1, 90, [])
  let w_leaf = ProjNode(Leaf("x"), 1, 2, 91, [])
  let wrapper = ProjNode(Branch("w", [Leaf("x")]), 1, 3, 92, [w_leaf])
  let new_ = ProjNode(
    Branch("root", [Leaf("z"), Branch("w", [Leaf("x")])]),
    0,
    3,
    93,
    [nl, wrapper],
  )
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  // #5 reaches the wrapper's inner leaf, not the standalone Leaf sibling
  inspect(result.children[1].children[0].node_id, content="5")
}

///|
test "Replace hint retires the old id (node is fresh, not preserved)" {
  // old: root#1 -> a#5 (Branch)
  let a_leaf = ProjNode(Leaf("x"), 0, 1, 6, [])
  let a = ProjNode(Branch("a", [Leaf("x")]), 0, 2, 5, [a_leaf])
  let old = ProjNode(Branch("root", [Branch("a", [Leaf("x")])]), 0, 5, 1, [a])
  // new: a same-kind Branch occupies #5's position, but the edit replaced it.
  let n_leaf = ProjNode(Leaf("y"), 0, 1, 90, [])
  let n = ProjNode(Branch("b", [Leaf("y")]), 0, 2, 91, [n_leaf])
  let new_ = ProjNode(Branch("root", [Branch("b", [Leaf("y")])]), 0, 5, 92, [n])
  let hints = mk_hints([(5, Replace(old=NodeId::from_int(5)))])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  // same-kind would normally preserve #5; Replace retires it → the node is fresh
  inspect(result.children[0].node_id >= 1000, content="true")
}

///|
/// Sequencing: two wraps at different depths, both hints supplied to ONE
/// reconcile. Neither wrap makes the other's target an ambiguous sibling, so
/// this isolates "can a batch carry more than one hint" from the ambiguity
/// degrade tested above.
test "a batch of two independent Wrap hints preserves both ids" {
  // old: root#1 -> a#4 -> Leaf#5 ; root#1 -> b#6 -> Leaf#7
  let x = ProjNode(Leaf("x"), 1, 2, 5, [])
  let a = ProjNode(Branch("a", [Leaf("x")]), 1, 3, 4, [x])
  let y = ProjNode(Leaf("y"), 4, 5, 7, [])
  let b = ProjNode(Branch("b", [Leaf("y")]), 4, 6, 6, [y])
  let old = ProjNode(
    Branch("root", [Branch("a", [Leaf("x")]), Branch("b", [Leaf("y")])]),
    0,
    7,
    1,
    [a, b],
  )
  // new: each leaf gained a wrapper; every id is fresh (as after a reparse)
  let nx = ProjNode(Leaf("x"), 1, 2, 90, [])
  let wx = ProjNode(Branch("w", [Leaf("x")]), 1, 3, 91, [nx])
  let na = ProjNode(Branch("a", [Branch("w", [Leaf("x")])]), 1, 4, 92, [wx])
  let ny = ProjNode(Leaf("y"), 4, 5, 93, [])
  let wy = ProjNode(Branch("w", [Leaf("y")]), 4, 6, 94, [ny])
  let nb = ProjNode(Branch("b", [Branch("w", [Leaf("y")])]), 4, 7, 95, [wy])
  let new_ = ProjNode(
    Branch("root", [
      Branch("a", [Branch("w", [Leaf("x")])]),
      Branch("b", [Branch("w", [Leaf("y")])]),
    ]),
    0,
    8,
    96,
    [na, nb],
  )
  let hints = mk_hints([
    (5, Wrap(inner=NodeId::from_int(5))),
    (7, Wrap(inner=NodeId::from_int(7))),
  ])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  // both wrapped leaves keep their ids from the one batched reconcile
  inspect(result.children[0].children[0].children[0].node_id, content="5")
  inspect(result.children[1].children[0].children[0].node_id, content="7")
}

///|
/// Monotonicity: a hint whose topology no longer matches the new tree.
///
/// This arises whenever a batch's net effect cancels the edit the hint
/// describes — wrap then unwrap the same node leaves the tree shaped exactly
/// as it started, while the wrap hint computed at the first step survives.
///
/// The two tests below pin CURRENT behaviour, and together they say: supplying
/// a stale hint is worse than supplying none. That makes "attach a hint
/// whenever one is available" unsafe as a caller contract.
///
/// Three ways out, at different costs. These tests exist so that whichever is
/// taken shows up here as a diff.
///
/// 1. Consumer side — reconcile refuses a hint whose topology does not match
///    the new tree and leaves the node to ordinary matching.
/// 2. Caller contract — hints are required to be fresh, so producing a stale
///    one is a caller bug rather than something reconcile absorbs.
/// 3. Producer side — compose the pending transforms before emitting anything,
///    so a batch whose net effect cancels emits NO hint instead of a stale one.
///    This also recovers the identity that the current all-or-nothing degrade
///    discards when a batch carries several perfectly describable transforms,
///    so it answers both failures at once. Its cost is that the transform
///    vocabulary is a flat set of named topology changes and so is not closed
///    under composition — the opaque fallback is the honest bottom element of
///    that. Buying composition means giving the vocabulary a compositional
///    shape, which is a much larger change than 1 or 2 and should wait for a
///    consumer that needs it.
test "without hints, an edit whose net effect is nil preserves identity" {
  let inner = ProjNode(Leaf("x"), 1, 2, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 1, [inner])
  // same shape, all ids fresh (a reparse after wrap-then-unwrap)
  let new_inner = ProjNode(Leaf("x"), 1, 2, 90, [])
  let new_ = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 91, [new_inner])
  let result = reconcile(old, new_, Ref(1000))
  inspect(result.node_id, content="1")
  inspect(result.children[0].node_id, content="5")
}

///|
test "a stale Wrap hint loses identity that the unhinted path keeps" {
  let inner = ProjNode(Leaf("x"), 1, 2, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 1, [inner])
  let new_inner = ProjNode(Leaf("x"), 1, 2, 90, [])
  let new_ = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 91, [new_inner])
  // The wrap this hint describes was undone later in the same batch: there is
  // no wrapper in `new_` for #5 to be found inside.
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  inspect(result.children[0].node_id >= 1000, content="true")
}

///|
/// Weak monotonicity for hints, as a named predicate.
///
/// Strong monotonicity — "a hint never makes any node worse off" — is neither
/// achievable nor wanted: a hint that DOES apply is authoritative and is meant
/// to override a coincidental LCS match, which can cost some other node the
/// match it would otherwise have had. The property worth holding is the weaker
/// one:
///
///   **A hint that cannot be applied has no effect.**
///
/// Caller must supply a `hints` map whose entries cannot land in `new_`;
/// for an applicable hint the two results are expected to differ.
///
/// Returns whether the property HOLDS.
fn prop_unapplicable_hint_is_inert(
  old : ProjNode[TestExpr],
  new_ : ProjNode[TestExpr],
  hints : Map[NodeId, IdentityTransform],
) -> Bool {
  let unhinted = collect_ids(reconcile(old, new_, Ref(1000)))
  let hinted = collect_ids(reconcile_hinted(old, new_, Ref(1000), hints))
  unhinted == hinted
}

///|
/// The property above does NOT hold today, and this pins that.
///
/// The cause is an ordering choice in `reconcile_children`: an old child
/// carrying a Wrap/Unwrap/Replace/Move hint is removed from LCS by
/// `lcs_excluded` BEFORE anything checks whether the hint can land, and a hint
/// that then fails to pair has no route back into ordinary matching.
///
/// If reconcile is changed so that exclusion is decided from hint
/// applicability — `hint_pair_counts` already computes very nearly that
/// predicate, though today it counts only among LCS-unmatched new children —
/// this flips to "true". When it does: update the pin here, and drop the
/// stale-hint caveat from the two tests above.
test "PROPERTY, currently violated: an unapplicable hint is inert" {
  let inner = ProjNode(Leaf("x"), 1, 2, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 1, [inner])
  // Net effect of the batch was nil, so `new_` has the shape of `old`.
  let new_inner = ProjNode(Leaf("x"), 1, 2, 90, [])
  let new_ = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 91, [new_inner])
  // Describes a wrapper that the completed batch left no trace of.
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  inspect(prop_unapplicable_hint_is_inert(old, new_, hints), content="false")
}

///|
/// Known-positive control for the pin above: with no hints at all the two
/// reconciles are the same call, so the predicate must report "holds". Without
/// this, a predicate that had become stuck at `false` would let the pin pass
/// vacuously and the violation above would stop meaning anything.
test "control: the inertness predicate does report holding when it should" {
  let inner = ProjNode(Leaf("x"), 1, 2, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 1, [inner])
  let new_inner = ProjNode(Leaf("x"), 1, 2, 90, [])
  let new_ = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 91, [new_inner])
  inspect(prop_unapplicable_hint_is_inert(old, new_, Map([])), content="true")
}
