// Property-based tests for Confidence[T] lattice laws.
// Verifies: commutativity, associativity, idempotency, identity.

///|
impl @quickcheck.Arbitrary for Role with arbitrary(_size, rs) {
  let n = rs.split().next_positive_int() % 5
  match n {
    0 => Abstract
    1 => SectionIntro
    2 => CodeExplanation
    3 => KeyPoints
    _ => Unclassified
  }
}

///|
impl @quickcheck.Arbitrary for Confidence[Role] with arbitrary(size, rs) {
  let n = rs.split().next_positive_int() % 5
  let role : Role = @quickcheck.Arbitrary::arbitrary(size, rs.split())
  match n {
    0 => Unknown
    1 => {
      let p = Float::from_int(rs.split().next_positive_int() % 100) / 100.0F
      Guessed(p, role)
    }
    2 => RuleBased(role)
    3 => Confirmed(role)
    _ => Conflict
  }
}

///|
impl @qc.Shrink for Confidence[Role]

///|
/// Wrapper for pair-wise properties (quick_check_fn takes single-arg).
struct Pair {
  a : Confidence[Role]
  b : Confidence[Role]
} derive(Debug)

///|
impl Show for Pair with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
impl @quickcheck.Arbitrary for Pair with arbitrary(size, rs) {
  {
    a: @quickcheck.Arbitrary::arbitrary(size, rs.split()),
    b: @quickcheck.Arbitrary::arbitrary(size, rs.split()),
  }
}

///|
impl @qc.Shrink for Pair

///|
/// Wrapper for triple-wise properties.
struct Triple {
  a : Confidence[Role]
  b : Confidence[Role]
  c : Confidence[Role]
} derive(Debug)

///|
impl Show for Triple with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
impl @quickcheck.Arbitrary for Triple with arbitrary(size, rs) {
  {
    a: @quickcheck.Arbitrary::arbitrary(size, rs.split()),
    b: @quickcheck.Arbitrary::arbitrary(size, rs.split()),
    c: @quickcheck.Arbitrary::arbitrary(size, rs.split()),
  }
}

///|
impl @qc.Shrink for Triple

///|
fn prop_join_commutative(p : Pair) -> Bool {
  p.a.join(p.b) == p.b.join(p.a)
}

///|
test "lattice law: join is commutative" {
  @qc.quick_check_fn(prop_join_commutative)
}

///|
fn prop_join_associative(t : Triple) -> Bool {
  t.a.join(t.b).join(t.c) == t.a.join(t.b.join(t.c))
}

///|
test "lattice law: join is associative" {
  @qc.quick_check_fn(prop_join_associative)
}

///|
fn prop_join_idempotent(a : Confidence[Role]) -> Bool {
  a.join(a) == a
}

///|
test "lattice law: join is idempotent" {
  @qc.quick_check_fn(prop_join_idempotent)
}

///|
fn prop_join_identity(a : Confidence[Role]) -> Bool {
  Unknown.join(a) == a && a.join(Unknown) == a
}

///|
test "lattice law: Unknown is identity" {
  @qc.quick_check_fn(prop_join_identity)
}
