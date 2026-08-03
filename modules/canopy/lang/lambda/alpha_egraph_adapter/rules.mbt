///|
// Do not install untyped arithmetic identity rewrites such as `?x + 0 => ?x`.
// `optimize_projected` accepts arbitrary projected Lambda terms, so `?x` may be
// a lambda, unit, hole, or other non-numeric term that the evaluator would leave
// stuck/type-erroneous. Constant folding remains analysis-driven and only unions
// with integer literals when the e-class data proves a concrete integer value.
fn safe_rules() -> Array[@egraph.Rewrite] {
  []
}
