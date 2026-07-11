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
  Guessed(Float, T)
  RuleBased(T)
  Confirmed(T)
  Conflict
} derive(Eq, Debug)

///|
pub impl[T : Debug] Show for Confidence[T] with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) suberror InvalidConfidence {
  /// Float is NaN, infinite, or outside [0, 1].
  BadConfidence(Float)
} derive(Debug)

///|
pub impl Show for InvalidConfidence with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Validated constructor for `Guessed`. Confidence must be finite and in [0, 1].
/// NaN and infinity break lattice laws (reflexivity, idempotency).
pub fn[T] Confidence::guessed(
  confidence : Float,
  value : T,
) -> Confidence[T] raise InvalidConfidence {
  if confidence.is_nan() ||
    confidence.is_inf() ||
    confidence < 0.0F ||
    confidence > 1.0F {
    raise BadConfidence(confidence)
  }
  Guessed(confidence, value)
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
