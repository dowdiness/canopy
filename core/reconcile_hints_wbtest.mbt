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
/// It is reachable: hints are cleared exactly once per reparse
/// (lang/lambda/proj/projection_memo.mbt), the projection is a pull-based
/// `@incr.Derived`, and the editor's T4 guard drops only a hint whose OWN span
/// batch produced no text change (editor/sync_editor.mbt) — it cannot see a
/// later op cancelling an earlier one.
///
/// Exit 1 of the three recorded here has been taken: exclusion from LCS is
/// decided from hint APPLICABILITY, and `apply_wrap` distinguishes "no trace of
/// this wrap here" (inert, fall through) from "ambiguous" (degrade, T3).
///
/// The two exits NOT taken:
///
/// 2. Caller contract — hints are required to be fresh, so producing a stale
///    one is a caller bug rather than something reconcile absorbs.
/// 3. Producer side — compose the pending transforms before emitting anything,
///    so a batch whose net effect cancels emits NO hint instead of a stale one.
///    This is the generalisation of the editor's existing T4 guard from one
///    span batch to the whole reparse window. It also recovers the identity
///    that the all-or-nothing degrade discards when a batch carries several
///    perfectly describable transforms, so it answers both failures at once.
///    Its cost is that the transform vocabulary is a flat set of named topology
///    changes and so is not closed under composition — the opaque fallback is
///    the honest bottom element of that. Buying composition means giving the
///    vocabulary a compositional shape, which is a much larger change than 2
///    and should wait for a consumer that needs it.
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
test "a stale Wrap hint is inert: identity survives it" {
  let inner = ProjNode(Leaf("x"), 1, 2, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 1, [inner])
  let new_inner = ProjNode(Leaf("x"), 1, 2, 90, [])
  let new_ = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 91, [new_inner])
  // The wrap this hint describes was undone later in the same batch: there is
  // no wrapper in `new_` for #5 to be found inside. Neither the LCS exclusion
  // nor `structural_pair` may act on it.
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  inspect(result.children[0].node_id, content="5")
}

///|
/// Does supplying `hints` change the identities reconcile assigns, relative to
/// supplying `base` instead?
///
/// Deliberately named for what it computes, not for a property it is claimed to
/// witness: the claims live in the test names below, which pin it both ways.
///
/// The `base` parameter is what makes the property statable. Inertness is a
/// MARGINAL claim — "this entry changes nothing" — and comparing a whole map
/// against the empty map cannot express it: any other entry in the map is
/// entitled to change the result, so the comparison would fail for reasons that
/// have nothing to do with the entry under test.
fn hinted_result_is_inert(
  old : ProjNode[TestExpr],
  new_ : ProjNode[TestExpr],
  hints : Map[NodeId, IdentityTransform],
  base~ : Map[NodeId, IdentityTransform] = Map([]),
) -> Bool {
  let without = collect_ids(reconcile_hinted(old, new_, Ref(1000), base))
  let with_ = collect_ids(reconcile_hinted(old, new_, Ref(1000), hints))
  without == with_
}

///|
/// Weak monotonicity for hints, at the scope that is actually achievable.
///
/// Strong monotonicity — "a hint never makes any node worse off" — is neither
/// achievable nor wanted: a hint that DOES apply is authoritative and is meant
/// to override a coincidental LCS match, which can cost some other node the
/// match it would otherwise have had.
///
/// The obvious next weakening, "a hint that cannot be APPLIED has no effect",
/// is also not achievable, and not because of an unfixed defect. An ambiguous
/// Wrap — two or more same-kind children — cannot be applied, yet the new node
/// may genuinely be a wrapper, and invariant T3 requires degrading to fresh ids
/// rather than leaving the preserved id on that wrapper. Inertness would demand
/// the opposite. The two invariants are in direct conflict for that case, and
/// T3 wins by design.
///
/// What holds is the properly scoped, MARGINAL statement:
///
///   **Adding a hint with no applicable target to a hint map changes nothing.**
///
/// "No applicable target" is decidable locally and carries no T3 tension: for
/// `Wrap`, zero same-kind children means the new node is not a wrapper of this
/// node at all, so ordinary matching is exactly the right decision. For
/// `Unwrap` it means the kept child is absent from the old wrapper — a mismatch
/// of KIND is not inapplicability, because the recursion is what interprets it.
///
/// Marginal, not absolute: the map may hold other entries that are entitled to
/// change the result. The second test below is the one that would have caught a
/// property stated over the whole map instead of the added entry.
test "PROPERTY: adding a hint with no applicable target is inert" {
  let inner = ProjNode(Leaf("x"), 1, 2, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 1, [inner])
  // Net effect of the batch was nil, so `new_` has the shape of `old`.
  let new_inner = ProjNode(Leaf("x"), 1, 2, 90, [])
  let new_ = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 91, [new_inner])
  // Describes a wrapper that the completed batch left no trace of.
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  inspect(hinted_result_is_inert(old, new_, hints), content="true")
}

///|
/// The property holds against a NON-EMPTY base too: a coexisting `Replace` is
/// entitled to freshen its own node, and the zero-target `Wrap` added alongside
/// it must still change nothing. Stated over the whole map against no hints at
/// all, this comparison would fail — on the `Replace`'s account, not the
/// `Wrap`'s — and the property would look violated when it is not.
test "PROPERTY: still inert when the map already carries an applicable hint" {
  let l5 = ProjNode(Leaf("x"), 1, 2, 5, [])
  let l6 = ProjNode(Leaf("y"), 2, 3, 6, [])
  let old = ProjNode(Branch("root", [Leaf("x"), Leaf("y")]), 0, 4, 1, [l5, l6])
  let n5 = ProjNode(Leaf("x"), 1, 2, 90, [])
  let n6 = ProjNode(Leaf("y"), 2, 3, 91, [])
  let new_ = ProjNode(Branch("root", [Leaf("x"), Leaf("y")]), 0, 4, 92, [n5, n6])
  let base = mk_hints([(6, Replace(old=NodeId::from_int(6)))])
  let with_stale = mk_hints([
    (6, Replace(old=NodeId::from_int(6))),
    (5, Wrap(inner=NodeId::from_int(5))),
  ])
  inspect(hinted_result_is_inert(old, new_, with_stale, base~), content="true")
}

///|
/// Known-negative control for the pin above. A predicate stuck at `true` would
/// let the property pass vacuously, so one input on which it MUST report "not
/// inert" is pinned here: an applicable Wrap changes the result by design.
test "control: the inertness predicate does report NOT holding when it should" {
  let inner = ProjNode(Leaf("x"), 0, 1, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 5, 1, [inner])
  let new_inner = ProjNode(Leaf("x"), 1, 2, 90, [])
  let wrapper = ProjNode(Branch("w", [Leaf("x")]), 1, 3, 91, [new_inner])
  let new_ = ProjNode(Branch("root", [Branch("w", [Leaf("x")])]), 0, 5, 92, [
    wrapper,
  ])
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  inspect(hinted_result_is_inert(old, new_, hints), content="false")
}

///|
/// Known-positive control: with no hints at all the two reconciles are the same
/// call, so the predicate must report "inert".
test "control: the inertness predicate does report holding when it should" {
  let inner = ProjNode(Leaf("x"), 1, 2, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 1, [inner])
  let new_inner = ProjNode(Leaf("x"), 1, 2, 90, [])
  let new_ = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 91, [new_inner])
  inspect(hinted_result_is_inert(old, new_, Map([])), content="true")
}

///|
/// Regression pin for an over-tightening that an independent review caught
/// before it shipped: gating `apply_unwrap` on `same_kind(new, keep)` would
/// make this batch preserve #10, which is wrong.
///
/// The batch is unwrap-then-wrap: #10 is removed and #5 promoted, then #5 is
/// wrapped in a NEW node. The shape ends up identical to where it started, but
/// the outer node of the new tree is not #10 — #10 was destroyed and a fresh
/// wrapper built. Only the recursion can see this: `apply_unwrap` descends to
/// #5, and #5's own `Wrap` hint consumes the new outer node, retiring #10.
///
/// A kind mismatch between `keep` and `new` is therefore NOT inapplicability.
test "composed unwrap-then-wrap retires the old wrapper id" {
  let kept = ProjNode(Leaf("x"), 1, 2, 5, [])
  let old = ProjNode(Branch("w", [Leaf("x")]), 0, 3, 10, [kept])
  let new_inner = ProjNode(Leaf("x"), 1, 2, 90, [])
  let new_ = ProjNode(Branch("w2", [Leaf("x")]), 0, 3, 91, [new_inner])
  let hints = mk_hints([
    (10, Unwrap(wrapper=NodeId::from_int(10), keep=NodeId::from_int(5))),
    (5, Wrap(inner=NodeId::from_int(5))),
  ])
  let result = reconcile_hinted(old, new_, Ref(1000), hints)
  // the new outer node is fresh — #10 did not survive its own unwrap
  inspect(result.node_id >= 1000, content="true")
  // and #5 rode the wrap into it
  inspect(result.children[0].node_id, content="5")
}

// ── Still violated: hints that ARE applicable somewhere ───────────────────
//
// The three pins below are NOT covered by the property above, and are recorded
// so the remaining surface is visible rather than implied by its absence. Each
// names its own cause. The first is a design decision (T3); the other two are
// open defects of the same family as the one just fixed — a hint's presence
// costing identity that plain LCS would have kept.

///|
/// Cause: T3, deliberately — but note the mechanism, which is NOT `apply_wrap`.
/// Two candidate wrappers make `hint_pair_counts` return 2, so
/// `try_unmatched_hint_pair` rejects the candidate and `structural_pair` is
/// never reached. `apply_wrap`'s own ambiguity branch guards the same principle
/// one level in (see the same-kind ambiguous-wrap test above, which does reach
/// it). Making either inert would require leaving #5's id on a node that may
/// really be its wrapper.
test "STILL VIOLATED (by design, T3): an ambiguous Wrap hint is not inert" {
  let inner = ProjNode(Leaf("x"), 1, 2, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 1, [inner])
  // Unhinted, LCS carries #5 into the standalone Leaf. Hinted, #5 is withheld
  // from LCS for two candidate wrappers and then paired with neither.
  let plain = ProjNode(Leaf("x"), 1, 2, 90, [])
  let wa_leaf = ProjNode(Leaf("x"), 2, 3, 91, [])
  let wa = ProjNode(Branch("w", [Leaf("x")]), 2, 4, 92, [wa_leaf])
  let wb_leaf = ProjNode(Leaf("x"), 4, 5, 93, [])
  let wb = ProjNode(Branch("w", [Leaf("x")]), 4, 6, 94, [wb_leaf])
  let new_ = ProjNode(
    Branch("root", [
      Leaf("x"),
      Branch("w", [Leaf("x")]),
      Branch("w", [Leaf("x")]),
    ]),
    0,
    7,
    95,
    [plain, wa, wb],
  )
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  inspect(hinted_result_is_inert(old, new_, hints), content="false")
}

///|
/// Cause: domain mismatch across the LCS step. Exclusion asks "does this hint
/// pair with ANY new child"; pairing afterwards asks "does it pair with an
/// LCS-UNMATCHED new child". LCS runs in between and can consume the sole
/// wrapper, leaving the withheld old child with nothing.
///
/// Fixing this means reserving hint partners globally BEFORE LCS, so that
/// exclusion and pairing agree on one domain — a strictly larger change than
/// the applicability gate, because the reservation must be unique in both
/// directions and must then also remove the reserved NEW child from LCS.
test "STILL VIOLATED: LCS can consume the sole wrapper a hint needed" {
  let l5 = ProjNode(Leaf("x"), 0, 1, 5, [])
  let b6 = ProjNode(Branch("b", [Leaf("y")]), 1, 3, 6, [
    ProjNode(Leaf("y"), 1, 2, 7, []),
  ])
  let old = ProjNode(
    Branch("root", [Leaf("x"), Branch("b", [Leaf("y")])]),
    0,
    4,
    1,
    [l5, b6],
  )
  // The wrapper is same_kind as #6, so LCS pairs it with #6 first; #5 was
  // withheld on that wrapper's account and now has no partner left.
  let plain = ProjNode(Leaf("x"), 0, 1, 90, [])
  let w_leaf = ProjNode(Leaf("x"), 2, 3, 91, [])
  let wrapper = ProjNode(Branch("w", [Leaf("x")]), 2, 4, 92, [w_leaf])
  let new_ = ProjNode(
    Branch("root", [Leaf("x"), Branch("w", [Leaf("x")])]),
    0,
    5,
    93,
    [plain, wrapper],
  )
  let hints = mk_hints([(5, Wrap(inner=NodeId::from_int(5)))])
  inspect(hinted_result_is_inert(old, new_, hints), content="false")
}

///|
/// Cause: the same domain mismatch, stated as the caller hazard it actually is.
/// This one is not measured against the unhinted path but against a SMALLER
/// hint map: adding a second hint that cannot be satisfied destroys the
/// identity the first hint was successfully carrying. So hints do not compose,
/// and "attach every hint you have" remains unsafe even after exit 1.
test "STILL VIOLATED: an extra unsatisfiable hint destroys a live hint's work" {
  let l5 = ProjNode(Leaf("x"), 0, 1, 5, [])
  let l6 = ProjNode(Leaf("x"), 1, 2, 6, [])
  let old = ProjNode(Branch("root", [Leaf("x"), Leaf("x")]), 0, 3, 1, [l5, l6])
  let plain = ProjNode(Leaf("x"), 0, 1, 90, [])
  let w_leaf = ProjNode(Leaf("x"), 2, 3, 91, [])
  let wrapper = ProjNode(Branch("w", [Leaf("x")]), 2, 4, 92, [w_leaf])
  let new_ = ProjNode(
    Branch("root", [Leaf("x"), Branch("w", [Leaf("x")])]),
    0,
    5,
    93,
    [plain, wrapper],
  )
  // With only #6 hinted, #6 rides the hint into the wrapper.
  let one = mk_hints([(6, Wrap(inner=NodeId::from_int(6)))])
  let with_one = reconcile_hinted(old, new_, Ref(1000), one)
  inspect(with_one.children[1].children[0].node_id, content="6")
  // Adding #5's hint — which cannot be satisfied, both claim the one wrapper —
  // costs #6 the identity it had.
  let two = mk_hints([
    (5, Wrap(inner=NodeId::from_int(5))),
    (6, Wrap(inner=NodeId::from_int(6))),
  ])
  let with_two = reconcile_hinted(old, new_, Ref(1000), two)
  inspect(with_two.children[1].children[0].node_id >= 1000, content="true")
}

///|
/// Cause: `reconcile_hinted` consults `structural_pair` at the ROOT before any
/// child LCS runs, so the applicability gate — which lives in
/// `reconcile_children` — never sees this hint. Exit 1 fixes the zero-target
/// root case (via `apply_wrap`), but an ambiguous root Wrap still freshens the
/// whole tree where the unhinted path preserves the root id.
test "STILL VIOLATED: an ambiguous Wrap on the ROOT freshens the whole tree" {
  let inner = ProjNode(Leaf("x"), 1, 2, 5, [])
  let old = ProjNode(Branch("root", [Leaf("x")]), 0, 3, 1, [inner])
  let c1 = ProjNode(Branch("a", [Leaf("x")]), 1, 3, 90, [
    ProjNode(Leaf("x"), 1, 2, 91, []),
  ])
  let c2 = ProjNode(Branch("b", [Leaf("y")]), 3, 5, 92, [
    ProjNode(Leaf("y"), 3, 4, 93, []),
  ])
  let new_ = ProjNode(
    Branch("root", [Branch("a", [Leaf("x")]), Branch("b", [Leaf("y")])]),
    0,
    6,
    94,
    [c1, c2],
  )
  let hints = mk_hints([(1, Wrap(inner=NodeId::from_int(1)))])
  // Unhinted the root keeps #1; hinted it does not.
  inspect(reconcile(old, new_, Ref(1000)).node_id, content="1")
  inspect(
    reconcile_hinted(old, new_, Ref(1000), hints).node_id >= 1000,
    content="true",
  )
}
