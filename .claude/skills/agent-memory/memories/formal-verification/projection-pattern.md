---
summary: "Pattern for proving enum properties: #proof_pure projection functions (rank/payload/score) bridge custom enums to the prover's Int world"
created: 2026-04-12
tags: [moon-prove, design-pattern, proof-pure]
related: [lib/semantic/proof/confidence.mbt]
---

# Projection Pattern for Enum Verification

## Problem

`moon prove` can't use `==` on custom enums or call methods in .mbtp predicates. How do you express properties like "result is IConflict" or "result has the same payload as input"?

## Solution

Define `#proof_pure` projection functions that map enum variants to Int values, then write predicates using those projections.

```moonbit
// .mbt — projection functions
#proof_pure
pub fn IntConfidence::rank(self : IntConfidence) -> Int {
  match self {
    IUnknown => 0
    IGuessed(_p, _v) => 1      // Use _v not _ (wildcard codegen bug)
    IRuleBased(_v) => 2
    IConfirmed(_v) => 3
    IConflict => 4
  }
}

#proof_pure
pub fn IntConfidence::payload(self : IntConfidence) -> Int {
  match self {
    IGuessed(_, v) => v
    IRuleBased(v) => v
    IConfirmed(v) => v
    _ => -1  // sentinel for variants without payload
  }
}
```

```
// .mbtp — predicates using projections
predicate conflict_is_top(a : IntConfidence, b : IntConfidence, result : IntConfidence) {
  (a.rank() == 4 → result.rank() == 4) &&
  (b.rank() == 4 → result.rank() == 4)
}
```

## Design choices

- **One projection per "dimension"**: rank (variant tier), payload (value), score (confidence level). Each captures one aspect the prover needs.
- **Sentinel values for missing data**: `-1` for payload of Unknown/Conflict. The prover can distinguish these from real payloads.
- **Named bindings, not wildcards**: `_v` not `_` to avoid the moonc codegen bug.
- **Exhaustive match, not catch-all**: List all variants explicitly in `#proof_pure` functions rather than using `_ => default`. Helps the prover reason about each case.

## When to use

Use when the property is about the *structure* of enum values (which variant, what payload) rather than full structural equality. If you need full equality, @qc is the better tool.
