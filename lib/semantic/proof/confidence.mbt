///|
/// Int-specialized confidence for formal verification.
///
/// Proved with:
///   - MoonBit moon 0.1.20260409 (a87440e 2026-04-09)
///   - Why3 1.7.2
///   - Z3 4.13.4
///
/// `moon prove` reasons over unbounded mathematical integers, not IEEE floats.
/// This mirrors `Confidence[T]` from lib/semantic with Int payloads so the
/// lattice laws can be formally verified. The generic Float-bearing version
/// remains tested via @qc (quickcheck).
pub(all) enum IntConfidence {
  IUnknown
  IGuessed(Int, Int)
  IRuleBased(Int)
  IConfirmed(Int)
  IConflict
} derive(Eq, Debug)

///|
pub impl Show for IntConfidence with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Rank in the lattice: Unknown(0) < Guessed(1) < RuleBased(2) < Confirmed(3) < Conflict(4).
/// Marked #proof_pure so it can be used in .mbtp predicates.
#proof_pure
pub fn IntConfidence::rank(self : IntConfidence) -> Int {
  match self {
    IUnknown => 0
    IGuessed(_p, _v) => 1
    IRuleBased(_v) => 2
    IConfirmed(_v) => 3
    IConflict => 4
  }
}

///|
/// Extract payload value (-1 for Unknown/Conflict which carry none).
/// Used by the prover to reason about value-agreement rules.
#proof_pure
pub fn IntConfidence::payload(self : IntConfidence) -> Int {
  match self {
    IUnknown => -1
    IGuessed(_, v) => v
    IRuleBased(v) => v
    IConfirmed(v) => v
    IConflict => -1
  }
}

///|
/// Extract confidence score (only meaningful for IGuessed, 0 otherwise).
#proof_pure
pub fn IntConfidence::score(self : IntConfidence) -> Int {
  match self {
    IGuessed(p, _v) => p
    IUnknown => 0
    IRuleBased(_v) => 0
    IConfirmed(_v) => 0
    IConflict => 0
  }
}

///|
/// Join for IntConfidence — structurally identical to Confidence::join.
///
/// Verified properties (via moon prove, see proof_ensure below):
///   - Conflict is top: if either input is Conflict, result is Conflict
///   - Unknown is left/right identity: join(Unknown, x) == x and vice versa
///   - Disagreement absorption: different payloads → Conflict
///   - Guessed max score: Guessed+Guessed with same payload → Guessed
///     with exactly max(score_a, score_b) and payload preserved
pub fn IntConfidence::join(
  self : IntConfidence,
  other : IntConfidence,
) -> IntConfidence where {
  proof_ensure: result => conflict_is_top(self, other, result),
  proof_ensure: result => unknown_is_bottom_left(self, other, result),
  proof_ensure: result => unknown_is_bottom_right(self, other, result),
  proof_ensure: result => disagreement_yields_conflict(self, other, result),
  proof_ensure: result => guessed_max_score(self, other, result),
} {
  match (self, other) {
    (IUnknown, x) | (x, IUnknown) => x
    (IConflict, _) | (_, IConflict) => IConflict
    (IConfirmed(a), IConfirmed(b))
    | (IConfirmed(a), IRuleBased(b))
    | (IRuleBased(b), IConfirmed(a))
    | (IConfirmed(a), IGuessed(_, b))
    | (IGuessed(_, b), IConfirmed(a))
    | (IRuleBased(a), IGuessed(_, b))
    | (IGuessed(_, b), IRuleBased(a)) =>
      if a == b {
        IConfirmed(a)
      } else {
        IConflict
      }
    (IRuleBased(a), IRuleBased(b)) =>
      if a == b {
        IRuleBased(a)
      } else {
        IConflict
      }
    (IGuessed(p, a), IGuessed(q, b)) =>
      if a == b {
        IGuessed(if p >= q { p } else { q }, a)
      } else {
        IConflict
      }
  }
}
