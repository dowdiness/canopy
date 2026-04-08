///|
/// A join-semilattice for annotation confidence.
///
/// Two annotation sources (symbolic rules, LLM inference) write to the same
/// fields. `Confidence[T]` tracks provenance and merges via `join`.
///
/// Ordering: Unknown < Guessed < RuleBased < Confirmed < Conflict (top).
/// Conflict carries no payload — it's the unique top element.
/// Conflict details (what disagreed) are a logging concern, not a lattice concern.
pub(all) enum Confidence[T] {
  Unknown
  /// Confidence must be finite and in [0, 1]. NaN breaks lattice laws.
  Guessed(Float, T)
  RuleBased(T)
  Confirmed(T)
  Conflict
} derive(Eq, Debug)

///|
pub impl[T : Debug] Show for Confidence[T] with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Join two confidence values (least upper bound).
///
/// Laws (tested via quickcheck):
///   1. Commutativity: a.join(b) == b.join(a)
///   2. Associativity: a.join(b).join(c) == a.join(b.join(c))
///   3. Idempotency:   a.join(a) == a
///   4. Identity:      Unknown.join(a) == a
pub fn[T : Eq] Confidence::join(
  self : Confidence[T],
  other : Confidence[T],
) -> Confidence[T] {
  match (self, other) {
    // Identity: Unknown is bottom
    (Unknown, x) | (x, Unknown) => x
    // Conflict is top — absorbing unconditionally
    (Conflict, _) | (_, Conflict) => Conflict
    // Same value from different sources → Confirmed; different → Conflict
    (Confirmed(a), Confirmed(b))
    | (Confirmed(a), RuleBased(b))
    | (RuleBased(b), Confirmed(a))
    | (Confirmed(a), Guessed(_, b))
    | (Guessed(_, b), Confirmed(a))
    | (RuleBased(a), Guessed(_, b))
    | (Guessed(_, b), RuleBased(a)) =>
      if a == b {
        Confirmed(a)
      } else {
        Conflict
      }
    // Two RuleBased: agree → stay, disagree → conflict
    (RuleBased(a), RuleBased(b)) => if a == b { RuleBased(a) } else { Conflict }
    // Two Guessed: same value → merge confidence, different → conflict
    (Guessed(p, a), Guessed(q, b)) =>
      if a == b {
        Guessed(if p >= q { p } else { q }, a)
      } else {
        Conflict
      }
  }
}
