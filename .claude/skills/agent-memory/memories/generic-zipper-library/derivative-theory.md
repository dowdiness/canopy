---
summary: "Type derivative theory for generic zippers — rules, proofs, and why ProjNode/OrderTree zippers work without codegen"
created: 2026-04-04
tags: [zipper, theory, type-derivative, generic-programming]
related: [core/proj_node.mbt, order-tree/src/walker_types.mbt, lang/lambda/zipper/]
---

# Type Derivative Theory for Generic Zippers

## Core Result

McBride (2001): The derivative of a regular type IS its type of one-hole contexts. A zipper for type T is `(T, dT)` — the focused element plus the derivative (context).

## Types as Arithmetic

```
Unit           = 1       (one value)
Bool           = 1 + 1   (true OR false)
Option[T]      = 1 + T   (None OR Some)
(A, B)         = A * B   (pair — every combination)
Either[A, B]   = A + B   (one from A OR one from B)
```

`+` means OR (enum/sum). `*` means AND (tuple/struct/product).

## Derivative Rules

Same as calculus, applied to type expressions:

```
derivative of 1         = 0              -- constant disappears
derivative of T         = 1              -- variable becomes 1
derivative of (A + B)   = dA + dB        -- sum rule
derivative of (A * B)   = dA * B + A * dB  -- product rule
derivative of (mu X. F(X)) = List(dF)    -- recursive type
```

## Key Examples

### List[T] = 1 + T * List[T]

Context = List[T] * List[T]  — elements before hole, elements after hole. The classic list zipper.

### Binary tree = 1 + X * T * X

Context = WentLeft(T, BinTree) | WentRight(BinTree, T) — two variants for which child the hole is in.

### Rose tree = T * List(X)  — THIS IS ProjNode

```
d(T * List(RoseTree)) = dT * List(RoseTree) + T * d(List(RoseTree))
```

T is constant (data, not recursive structure), so dT = 0:

```
= T * List(RoseTree) * List(RoseTree)
  ^   ^^^^^^^^^^^^^^   ^^^^^^^^^^^^^^
 parent  left siblings   right siblings
 data
```

**One context type. Generic in T. Works for every language.** This is why ProjNode's zipper needs no codegen.

## The Critical Insight: Constant Position

When T is in "constant position" (node data, not part of the branching structure), its derivative is 0 — it drops out. The derivative only depends on the recursive structure.

```
RoseTree[T] = T * List[RoseTree[T]]
              ^   ^^^^^^^^^^^^^^^^^
          constant   recursive (determines derivative)
          (drops out)
```

This is why:
- ProjNode[LambdaTerm] has the same zipper as ProjNode[JsonValue]
- OrderTree[VisibleRun] has the same zipper as OrderTree[anything]
- No per-language code generation needed

## References

- Huet (1997) — "Functional Pearl: The Zipper" — origin
- McBride (2001) — "The Derivative of a Regular Type is its Type of One-Hole Contexts"
- McBride (2008) — "Clowns to the Left of me, Jokers to the Right" — dissections
- Hinze & Paterson (2006) — "Finger trees: a simple general-purpose data structure"
- Abbott, Altenkirch, Ghani (2003) — "Categories of Containers"
