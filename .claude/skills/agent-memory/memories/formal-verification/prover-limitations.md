---
summary: "moon prove limitations discovered: no enum ==, no method calls in predicates, wildcard codegen bug, proof-enabled cascading, Float blindness"
created: 2026-04-12
status: resolved
tags: [moon-prove, limitations, workarounds]
related: [lib/semantic/proof/confidence.mbt, lib/semantic/proof/confidence.mbtp]
---

# moon prove Prover Limitations

## No `==` on custom enums in .mbtp predicates

The prover only supports `==` on primitives (Int, Bool). Writing `result == IConflict` in a predicate gives "unsupported expression in logic body".

**Workaround:** Project enums to Int via `#proof_pure` functions, then compare Ints.

## No method calls in .mbtp predicates

Only `#proof_pure` function calls and primitive operators are allowed. Regular methods and non-pure functions cannot be called.

**Workaround:** Mark projection functions with `#proof_pure`. These become callable from predicates.

## Wildcard `_` codegen bug in #proof_pure functions

Match arms like `IRuleBased(_) => 2` generate broken WhyML: `IRuleBased -> 2` (missing the wildcard argument). The Why3 type checker rejects this.

**Workaround:** Use named bindings: `IRuleBased(_v) => 2`. This generates correct WhyML: `IRuleBased _ -> 2`.

**Status:** moonc bug, not reported yet (as of 2026-04-12).

## `proof-enabled` cascades to all transitive dependencies

Setting `"proof-enabled": true` in moon.pkg causes moonc to attempt proving all transitive deps, not just the current package. For a package like lib/semantic that depends on loom (huge dep tree), this hits compiler bugs.

**Workaround:** Isolate proof code in standalone modules with their own moon.mod.json and zero project dependencies. The proof package mirrors the types it needs.

## Float is invisible to the prover

`moon prove` uses unbounded mathematical integers. No IEEE float modeling, no overflow. Properties involving Float must use @qc instead.

**Workaround:** Create Int-specialized mirror types for verification. The proof covers the algorithm structure; @qc covers the real type with Float.

## Enum constructors in .mbtp

Bare enum constructors (e.g., `IUnknown`) work in .mbtp when the enum is defined in the same package. Qualified syntax `IntConfidence::IUnknown` does NOT work in .mbtp — the parser rejects uppercase after `::`.

Use `match` patterns instead when you need to branch on variants in predicates.
