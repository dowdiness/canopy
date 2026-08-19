///|
struct PackCase {
  bin_width : Int
  sizes : Array[Size]
} derive(Debug)

///|
fn gen_pack_case(rs : @splitmix.RandomState) -> PackCase {
  let bin_width = 8 + rs.split().next_positive_int() % 24
  let count = 1 + rs.split().next_positive_int() % 8
  let sizes : Array[Size] = []
  for _ in 0..<count {
    let width = 1 + rs.split().next_positive_int() % bin_width
    let height = 1 + rs.split().next_positive_int() % 12
    sizes.push(try! Size(width~, height~))
  }
  { bin_width, sizes }
}

///|
impl @quickcheck.Arbitrary for PackCase with fn arbitrary(_size, rs) {
  gen_pack_case(rs)
}

///|
impl @qc.Shrink for PackCase

///|
fn pack_case(case_ : PackCase) -> (Packer, Array[Placement]) {
  let packer = try! Packer(width=case_.bin_width)
  let placements : Array[Placement] = []
  for size in case_.sizes {
    placements.push(try! packer.place(size))
  }
  (packer, placements)
}

///|
fn prop_in_bin_and_disjoint(case_ : PackCase) -> Bool {
  let (packer, placements) = pack_case(case_)
  try! assert_skyline_invariants(packer)
  placements_in_bin(placements, case_.bin_width) &&
  !any_interior_overlap(placements) &&
  skyline_matches_placements(packer, placements)
}

///|
fn prop_deterministic(case_ : PackCase) -> Bool {
  let first = try! pack_in_order(case_.sizes, bin_width=case_.bin_width)
  let second = try! pack_in_order(case_.sizes, bin_width=case_.bin_width)
  first == second
}

///|
fn prop_constrained_uses_allowed_x(case_ : PackCase) -> Bool {
  let packer = try! Packer(width=case_.bin_width)
  guard case_.sizes.length() > 0 else { true }
  let size = case_.sizes[0]
  let allowed = [0, case_.bin_width / 2, packer.width - size.width]
  match
    (Ok(packer.place_constrained(size, allowed)) catch { error => Err(error) }) {
    Err(NoPlacement(_)) => true
    Err(_) => false
    Ok(placement) => allowed.contains(placement.x)
  }
}

///|
test "property: packed rectangles stay in-bin, disjoint, and match the skyline" {
  @qc.quick_check_fn(prop_in_bin_and_disjoint)
}

///|
test "property: packing is deterministic" {
  @qc.quick_check_fn(prop_deterministic)
}

///|
test "property: constrained placement stays on allowed x" {
  @qc.quick_check_fn(prop_constrained_uses_allowed_x)
}
