// Property-based tests for reconcile.mbt using @qc (quickcheck).
// These tests verify invariants that hand-written snapshot tests cannot catch:
// ID uniqueness, ID preservation, kind propagation, idempotency,
// and LCS matching behavior under sibling insert/delete/reorder.

///|
/// Arbitrary impl for TestExpr — generates bounded random trees.
impl @quickcheck.Arbitrary for TestExpr with arbitrary(size, rs) {
  gen_test_expr(rs, if size < 1 { 1 } else if size > 4 { 4 } else { size })
}

///|
/// No-op shrink impl (required by quick_check_fn).
impl @qc.Shrink for TestExpr

///|
/// Bounded-depth recursive generator for TestExpr trees.
fn gen_test_expr(rs : @splitmix.RandomState, depth : Int) -> TestExpr {
  if depth <= 0 {
    let tag = rs.split().next_positive_int() % 10
    Leaf("l" + tag.to_string())
  } else {
    let coin = rs.split().next_positive_int() % 3
    if coin == 0 {
      let tag = rs.split().next_positive_int() % 10
      Leaf("l" + tag.to_string())
    } else {
      let child_count = rs.split().next_positive_int() % 4
      let children : Array[TestExpr] = []
      for i = 0; i < child_count; i = i + 1 {
        children.push(gen_test_expr(rs.split(), depth - 1))
      }
      let tag = rs.split().next_positive_int() % 10
      Branch("b" + tag.to_string(), children)
    }
  }
}

///|
/// Convert a TestExpr into a ProjNode[TestExpr] with post-order IDs
/// (children numbered before parent, matching assign_fresh_ids).
fn to_proj_node(expr : TestExpr, counter : Ref[Int]) -> ProjNode[TestExpr] {
  let children : Array[ProjNode[TestExpr]] = match expr {
    Leaf(_) => []
    Branch(_, cs) => cs.map(fn(c) { to_proj_node(c, counter) })
  }
  let id = next_proj_node_id(counter)
  ProjNode::new(expr, 0, 0, id, children)
}

///|
/// Collect all node_ids from a ProjNode tree (pre-order).
fn collect_ids(node : ProjNode[TestExpr]) -> Array[Int] {
  let result : Array[Int] = []
  collect_ids_rec(node, result)
  result
}

///|
fn collect_ids_rec(node : ProjNode[TestExpr], acc : Array[Int]) -> Unit {
  acc.push(node.node_id)
  for child in node.children {
    collect_ids_rec(child, acc)
  }
}

///|
/// Collect all .kind values from a ProjNode tree (pre-order).
fn collect_kinds(node : ProjNode[TestExpr]) -> Array[TestExpr] {
  let result : Array[TestExpr] = []
  collect_kinds_rec(node, result)
  result
}

///|
fn collect_kinds_rec(node : ProjNode[TestExpr], acc : Array[TestExpr]) -> Unit {
  acc.push(node.kind)
  for child in node.children {
    collect_kinds_rec(child, acc)
  }
}

///|
/// Insert an element at position `idx` in an array (returns new array).
fn[T] insert_at(arr : Array[T], idx : Int, elem : T) -> Array[T] {
  let result : Array[T] = []
  for i = 0; i < arr.length(); i = i + 1 {
    if i == idx {
      result.push(elem)
    }
    result.push(arr[i])
  }
  if idx >= arr.length() {
    result.push(elem)
  }
  result
}

///|
/// Remove element at position `idx` from an array (returns new array).
fn[T] remove_at(arr : Array[T], idx : Int) -> Array[T] {
  let result : Array[T] = []
  for i = 0; i < arr.length(); i = i + 1 {
    if i != idx {
      result.push(arr[i])
    }
  }
  result
}

///|
/// Check that all elements in an array are unique.
fn all_unique(arr : Array[Int]) -> Bool {
  let seen : Map[Int, Bool] = {}
  for id in arr {
    if seen.contains(id) {
      return false
    }
    seen[id] = true
  }
  true
}

///|
/// Property 1: All NodeIds are unique after reconcile.
/// After reconcile(old, new, counter), the result tree has no duplicate IDs.
fn prop_unique_ids_after_reconcile(pair : (TestExpr, TestExpr)) -> Bool {
  let (old_expr, new_expr) = pair
  let old_counter = Ref::new(0)
  let old_node = to_proj_node(old_expr, old_counter)
  let new_counter = Ref::new(0)
  let new_node = to_proj_node(new_expr, new_counter)
  let counter = Ref::new(1000)
  let result = reconcile(old_node, new_node, counter)
  let ids = collect_ids(result)
  all_unique(ids)
}

///|
test "property: unique IDs after reconcile" {
  @qc.quick_check_fn(prop_unique_ids_after_reconcile)
}

///|
/// Property 2: Reconcile preserves all old IDs when old and new are identical trees.
/// Building two ProjNodes from the same TestExpr (with different ID ranges)
/// and reconciling should yield the old tree's IDs positionally.
fn prop_preserves_ids_for_identical_trees(expr : TestExpr) -> Bool {
  let counter = Ref::new(0)
  let old_node = to_proj_node(expr, counter)
  let new_counter = Ref::new(500)
  let new_node = to_proj_node(expr, new_counter)
  let reconcile_counter = Ref::new(1000)
  let result = reconcile(old_node, new_node, reconcile_counter)
  let old_ids = collect_ids(old_node)
  let result_ids = collect_ids(result)
  // Every ID from old should be in result
  if old_ids.length() != result_ids.length() {
    return false
  }
  for i = 0; i < old_ids.length(); i = i + 1 {
    if old_ids[i] != result_ids[i] {
      return false
    }
  }
  true
}

///|
test "property: preserves IDs for identical trees" {
  @qc.quick_check_fn(prop_preserves_ids_for_identical_trees)
}

///|
/// Property 3: Reconcile uses new kind values.
/// After reconcile, the .kind values should come from the new tree.
/// We test this by building two trees with the same shape but different labels.
fn prop_uses_new_kind_values(expr : TestExpr) -> Bool {
  let relabeled = relabel_expr(expr, "old_")
  let counter_old = Ref::new(0)
  let old_node = to_proj_node(relabeled, counter_old)
  let counter_new = Ref::new(500)
  let new_node = to_proj_node(expr, counter_new)
  let reconcile_counter = Ref::new(1000)
  let result = reconcile(old_node, new_node, reconcile_counter)
  let result_kinds = collect_kinds(result)
  let new_kinds = collect_kinds(new_node)
  if result_kinds.length() != new_kinds.length() {
    return false
  }
  for i = 0; i < result_kinds.length(); i = i + 1 {
    if result_kinds[i] != new_kinds[i] {
      return false
    }
  }
  true
}

///|
/// Relabel a TestExpr by prefixing all labels while preserving tree shape.
fn relabel_expr(expr : TestExpr, prefix : String) -> TestExpr {
  match expr {
    Leaf(s) => Leaf(prefix + s)
    Branch(s, cs) =>
      Branch(prefix + s, cs.map(fn(c) { relabel_expr(c, prefix) }))
  }
}

///|
test "property: uses new kind values after reconcile" {
  @qc.quick_check_fn(prop_uses_new_kind_values)
}

///|
/// Property 4: Reconcile is idempotent on stable trees.
/// reconcile(tree, tree) then reconcile(result, tree) should produce
/// the same IDs as the first reconcile.
fn prop_idempotent_on_stable(expr : TestExpr) -> Bool {
  let counter1 = Ref::new(0)
  let tree1 = to_proj_node(expr, counter1)
  let counter2 = Ref::new(500)
  let tree2 = to_proj_node(expr, counter2)
  let counter3 = Ref::new(800)
  let tree3 = to_proj_node(expr, counter3)
  // First reconcile
  let rc1 = Ref::new(1000)
  let result1 = reconcile(tree1, tree2, rc1)
  // Second reconcile: reconcile(result1, tree3)
  let rc2 = Ref::new(2000)
  let result2 = reconcile(result1, tree3, rc2)
  // IDs from result1 and result2 should be the same
  let ids1 = collect_ids(result1)
  let ids2 = collect_ids(result2)
  if ids1.length() != ids2.length() {
    return false
  }
  for i = 0; i < ids1.length(); i = i + 1 {
    if ids1[i] != ids2[i] {
      return false
    }
  }
  true
}

///|
test "property: reconcile is idempotent on stable trees" {
  @qc.quick_check_fn(prop_idempotent_on_stable)
}

///|
/// Property 5: Retained siblings keep their old IDs after a child insertion.
/// Given a Branch with children, insert a new Leaf in the middle to form
/// a new tree. Reconcile should preserve old IDs for the siblings that
/// remained (matched by LCS), and assign fresh IDs only for the inserted child.
fn prop_retained_siblings_keep_ids_after_insert(expr : TestExpr) -> Bool {
  // Only meaningful for Branch nodes with at least 1 child
  let children = match expr {
    Branch(_, cs) => if cs.length() > 0 { cs } else { return true }
    Leaf(_) => return true
  }
  let tag = match expr {
    Branch(t, _) => t
    _ => ""
  }
  let old_counter = Ref::new(0)
  let old_node = to_proj_node(expr, old_counter)
  // Build new tree with an extra Leaf inserted in the middle
  let insert_idx = children.length() / 2
  let new_children = insert_at(children, insert_idx, Leaf("inserted"))
  let new_expr = Branch(tag, new_children)
  let new_counter = Ref::new(500)
  let new_node = to_proj_node(new_expr, new_counter)
  let reconcile_counter = Ref::new(1000)
  let result = reconcile(old_node, new_node, reconcile_counter)
  // The old IDs for retained children should appear in the result.
  // Build a set of old child IDs
  let old_child_ids : Map[Int, Bool] = {}
  for child in old_node.children {
    old_child_ids[child.node_id] = true
  }
  // Count how many result children reuse an old child ID
  let mut reused = 0
  for child in result.children {
    if old_child_ids.contains(child.node_id) {
      reused = reused + 1
    }
  }
  // At least all original children should be matched (LCS finds them all
  // since they're in the same order with one insertion)
  reused >= old_node.children.length()
}

///|
test "property: retained siblings keep IDs after child insertion" {
  @qc.quick_check_fn(prop_retained_siblings_keep_ids_after_insert)
}

///|
/// Property 6: After deleting a child, the number of reused old IDs equals
/// the LCS length between old and new children (by same_kind).
/// We can't assume WHICH old children are matched (LCS tie-breaking is
/// implementation-defined), but we can verify the COUNT of reused IDs
/// matches the number of surviving same-kind matches.
fn prop_reused_id_count_after_delete(expr : TestExpr) -> Bool {
  // Only meaningful for Branch nodes with at least 2 children
  let children = match expr {
    Branch(_, cs) => if cs.length() >= 2 { cs } else { return true }
    Leaf(_) => return true
  }
  let tag = match expr {
    Branch(t, _) => t
    _ => ""
  }
  let old_counter = Ref::new(0)
  let old_node = to_proj_node(expr, old_counter)
  // Build new tree with one child removed from the middle
  let remove_idx = children.length() / 2
  let new_children = remove_at(children, remove_idx)
  let new_expr = Branch(tag, new_children)
  let new_counter = Ref::new(500)
  let new_node = to_proj_node(new_expr, new_counter)
  let reconcile_counter = Ref::new(1000)
  let result = reconcile(old_node, new_node, reconcile_counter)
  // Result should have one fewer child
  if result.children.length() != old_node.children.length() - 1 {
    return false
  }
  // Collect all old child root IDs
  let old_child_ids : Map[Int, Bool] = {}
  for child in old_node.children {
    old_child_ids[child.node_id] = true
  }
  // Count how many result children reuse an old child ID
  let mut reused = 0
  for child in result.children {
    if old_child_ids.contains(child.node_id) {
      reused = reused + 1
    }
  }
  // new_children is a subsequence of old_children (one element removed),
  // so LCS length = new_children.length() (all can be matched).
  // Therefore ALL result children should reuse old IDs.
  reused == result.children.length()
}

///|
test "property: reused ID count correct after child deletion" {
  @qc.quick_check_fn(prop_reused_id_count_after_delete)
}

///|
/// Property 7: Reconcile is idempotent on different trees.
/// Given different old and new trees, reconcile(old, new) then
/// reconcile(result1, new_copy) should produce the same IDs —
/// a second pass on the same new tree shouldn't change anything.
fn prop_reconcile_idempotent_on_diff_trees(pair : (TestExpr, TestExpr)) -> Bool {
  let (old_expr, new_expr) = pair
  // Build old tree with counter range 0+
  let old_node = to_proj_node(old_expr, Ref::new(0))
  // Build first new tree with counter range 500+
  let new_node1 = to_proj_node(new_expr, Ref::new(500))
  // First reconcile with fresh IDs from 1000+
  let result1 = reconcile(old_node, new_node1, Ref::new(1000))
  // Build second copy of new tree with counter range 600+
  let new_node2 = to_proj_node(new_expr, Ref::new(600))
  // Second reconcile with fresh IDs from 2000+
  let result2 = reconcile(result1, new_node2, Ref::new(2000))
  // IDs should match positionally
  let ids1 = collect_ids(result1)
  let ids2 = collect_ids(result2)
  if ids1.length() != ids2.length() {
    return false
  }
  for i = 0; i < ids1.length(); i = i + 1 {
    if ids1[i] != ids2[i] {
      return false
    }
  }
  true
}

///|
test "property: reconcile idempotent on different trees" {
  @qc.quick_check_fn(prop_reconcile_idempotent_on_diff_trees)
}

///|
/// Property 8: Triple reconcile is stable — no drift after multiple passes.
/// Runs reconcile three times: old→new, result1→new, result2→new.
/// result2 and result3 should have identical IDs, catching any drift
/// that only manifests after multiple passes.
fn prop_reconcile_triple_idempotent(pair : (TestExpr, TestExpr)) -> Bool {
  let (old_expr, new_expr) = pair
  // Build old tree with counter range 0+
  let old_node = to_proj_node(old_expr, Ref::new(0))
  // Build three copies of new tree with different counter ranges
  let new_node1 = to_proj_node(new_expr, Ref::new(500))
  let new_node2 = to_proj_node(new_expr, Ref::new(600))
  let new_node3 = to_proj_node(new_expr, Ref::new(700))
  // Three rounds of reconcile with well-separated counter ranges
  let result1 = reconcile(old_node, new_node1, Ref::new(1000))
  let result2 = reconcile(result1, new_node2, Ref::new(2000))
  let result3 = reconcile(result2, new_node3, Ref::new(3000))
  // result2 and result3 should have identical IDs
  let ids2 = collect_ids(result2)
  let ids3 = collect_ids(result3)
  if ids2.length() != ids3.length() {
    return false
  }
  for i = 0; i < ids2.length(); i = i + 1 {
    if ids2[i] != ids3[i] {
      return false
    }
  }
  true
}

///|
test "property: triple reconcile is stable" {
  @qc.quick_check_fn(prop_reconcile_triple_idempotent)
}
