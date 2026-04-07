// Property-based tests for the rose tree zipper using @qc (quickcheck).
// These verify structural invariants that hand-written tests cannot exhaustively cover:
// round-trip laws, path serialization, and persistence guarantees.

///|
/// Bounded-depth recursive generator for RoseNode[Int] trees.
fn gen_rose_node(rs : @splitmix.RandomState, depth : Int) -> RoseNode[Int] {
  if depth <= 0 {
    RoseNode::new(data=rs.split().next_positive_int() % 100)
  } else {
    let coin = rs.split().next_positive_int() % 3
    if coin == 0 {
      RoseNode::new(data=rs.split().next_positive_int() % 100)
    } else {
      let child_count = rs.split().next_positive_int() % 4
      let children : Array[RoseNode[Int]] = []
      for _ in 0..<child_count {
        children.push(gen_rose_node(rs.split(), depth - 1))
      }
      RoseNode::new(data=rs.split().next_positive_int() % 100, children~)
    }
  }
}

///|
impl @quickcheck.Arbitrary for RoseNode[Int] with arbitrary(size, rs) {
  gen_rose_node(rs, if size < 1 { 1 } else if size > 4 { 4 } else { size })
}

///|
/// No-op shrink impl (required by quick_check_fn).
impl @qc.Shrink for RoseNode[Int]

///|
fn prop_from_root_to_tree_identity(tree : RoseNode[Int]) -> Bool {
  RoseZipper::from_root(tree).to_tree() == tree
}

///|
test "property: from_root then to_tree is identity" {
  @qc.quick_check_fn(prop_from_root_to_tree_identity)
}

///|
fn prop_go_down_go_up_round_trip(tree : RoseNode[Int]) -> Bool {
  let z = RoseZipper::from_root(tree)
  if z.num_children() > 0 {
    let z2 = z.go_down().unwrap().go_up().unwrap()
    z2.focus == tree
  } else {
    true
  }
}

///|
test "property: go_down then go_up round-trip preserves focus" {
  @qc.quick_check_fn(prop_go_down_go_up_round_trip)
}

///|
fn prop_to_path_focus_at_inverse(tree : RoseNode[Int]) -> Bool {
  let z = RoseZipper::from_root(tree)
  // Root case: empty path round-trips
  let root_path = z.to_path()
  if root_path != ([] : Array[Int]) {
    return false
  }
  match RoseZipper::focus_at(tree, root_path) {
    Some(z_root) => if z_root.focus != tree { return false }
    None => return false
  }
  // Navigate to first child if possible
  if z.num_children() > 0 {
    let z2 = z.go_down().unwrap()
    let path = z2.to_path()
    match RoseZipper::focus_at(tree, path) {
      Some(z3) => z2.focus == z3.focus
      None => false
    }
  } else {
    true
  }
}

///|
test "property: to_path and focus_at are inverse" {
  @qc.quick_check_fn(prop_to_path_focus_at_inverse)
}
