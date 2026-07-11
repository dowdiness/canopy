# Formal Verification

## Overview

MoonBit provides formal verification via `moon prove`, which uses SMT solvers (z3) through Why3 to mathematically prove properties about code. Unlike property-based tests (@qc) that check random samples, `moon prove` guarantees a property holds for **all** inputs.

Canopy uses both: `moon prove` for properties the prover can model, @qc for everything else. The two layers complement each other.

## Toolchain

```
moon prove  →  moonc (WhyML codegen)  →  Why3  →  z3 (SMT solver)
```

**Tested versions:**
- MoonBit moon 0.1.20260409
- Why3 1.7.2 (install via `opam install why3.1.7.2`)
- Z3 4.13.x (install via `pip3 install z3-solver==4.13.4.0` or `opam install z3`)

**Why3 1.7.2 specifically:** moonc's built-in Why3 harness expects this version. Stock 1.7.2 recognizes z3 up to 4.13.x — newer z3 versions are not detected.

## How It Works

### File structure

```
lib/semantic/proof/
├── moon.mod.json          # Standalone module (no canopy deps)
├── moon.pkg               # options("proof-enabled": true)
├── confidence.mbt          # Code + proof_ensure contracts
├── confidence.mbtp         # Logical predicates (spec-only)
└── pkg.generated.mbti
```

### Program side (`.mbt`)

Functions carry contracts via `where` blocks:

```moonbit
pub fn join(self : T, other : T) -> T where {
  proof_ensure: result => conflict_is_top(self, other, result),
  proof_ensure: result => identity_left(self, other, result),
} {
  // implementation
}
```

- `proof_require`: preconditions (assumed true at call site)
- `proof_ensure`: postconditions (must hold for every execution path)
- `proof_assert`: intermediate facts within function body
- `proof_invariant`: loop invariants
- `#proof_pure`: marks a function as callable from `.mbtp` predicates

### Logic side (`.mbtp`)

Pure specifications — predicates, lemmas, models:

```
predicate conflict_is_top(a : T, b : T, result : T) {
  (a.rank() == 4 → result.rank() == 4) &&
  (b.rank() == 4 → result.rank() == 4)
}
```

### Running

```bash
cd lib/semantic/proof
moon prove          # verify all proof_ensure contracts
```

## Prover Limitations

These constraints determine what `moon prove` can and cannot verify:

| Limitation | Impact | Workaround |
|---|---|---|
| Unbounded integers only | No Float, no overflow modeling | Use Int-specialized mirror types |
| No `==` on custom enums | Can't write `result == expected` for enum types | Project to Int via `#proof_pure` functions |
| No method calls in predicates | Only `#proof_pure` functions and primitives | Write pure projection functions |
| No Map/Array[T]/closure reasoning | Can't model stateful data structures | Use @qc for these properties |
| Wildcard `_` codegen bug | `IRuleBased(_) => 2` emits broken WhyML | Use named bindings: `IRuleBased(_v) => 2` |
| `proof-enabled` cascades to deps | Enabling on a package proves all transitive deps | Isolate proof packages in standalone modules |

## When to Use What

### Decision flow

```
Is the property about pure Int/Bool/FixedArray functions?
├── yes → Can you avoid == on custom enums?
│   ├── yes → moon prove
│   └── no → Can you project to Int via #proof_pure?
│       ├── yes → moon prove (projection pattern)
│       └── no → @qc
└── no → @qc
```

### Three tiers

| Tier | Tool | Guarantee | Best for |
|---|---|---|---|
| 1. Formal proof | `moon prove` | All inputs, mathematical | Index arithmetic, lattice laws, loop invariants, sorted-order |
| 2. Property tests | `@qc` | High confidence, random sampling | CRDT convergence, tree reconciliation, round-trips, stateful interactions |
| 3. Snapshot tests | `inspect` | Specific examples only | Regression detection, expected output |

### Composition principle

**Prove the algorithm, test the integration.**

For `Confidence::join`: we proved the lattice laws on `IntConfidence` (the algorithm structure), while @qc tests cover `Confidence[Role]` with Float scores (the real type with integration concerns). If someone changes the match arms, `moon prove` catches it. If someone breaks Float validation in `guessed()`, @qc catches it.

## Current Coverage

### Formally verified (lib/semantic/proof/)

`IntConfidence::join` — 5 properties:

| Predicate | What it proves |
|---|---|
| `conflict_is_top` | Conflict absorbs: join with Conflict always yields Conflict |
| `unknown_is_bottom_left` | Left identity: join(Unknown, x) == x (via rank/payload/score) |
| `unknown_is_bottom_right` | Right identity: join(x, Unknown) == x |
| `disagreement_yields_conflict` | Different payloads from non-trivial inputs → Conflict |
| `guessed_max_score` | Guessed+Guessed same payload → Guessed with exact max score, payload preserved |

### Property-tested (@qc)

| Package | File | Properties |
|---|---|---|
| core/ | reconcile_properties_wbtest.mbt | ID uniqueness, ID preservation, kind propagation, idempotency, insert/delete stability |
| core/ | source_map_properties_wbtest.mbt | Node coverage, range sorting, rebuild consistency, parent enclosure, innermost node minimality |
| lib/semantic/ | confidence_properties_wbtest.mbt | Commutativity, associativity, idempotency, identity, absorbing top (on real `Confidence[Role]`) |
| lib/zipper/ | zipper_properties_wbtest.mbt | Zipper navigation laws |
| event-graph-walker/ | Various *_properties_test.mbt | CRDT convergence, version vector properties, FractionalIndex ordering |

## Future Proof Targets

Candidates ordered by value and feasibility:

### High value, good fit for moon prove

| Target | Package | Properties | Why provable |
|---|---|---|---|
| BTree node invariants | lib/btree | Key count in [t-1, 2t-1] after insert/delete | Pure Int arithmetic with loop invariants |
| delete_range boundaries | lib/btree | Index parameters stay valid through descent | Index math — exactly what z3 excels at |
| SourceMap range sorting | core/ | Ranges array sorted after rebuild | Int comparisons on array indices |
| FractionalIndex ordering | event-graph-walker/ | midpoint(a, b) is strictly between a and b | Byte-array arithmetic |

### High value, better as @qc

| Target | Package | Properties | Why not provable |
|---|---|---|---|
| Reconcile ID uniqueness | core/ | No duplicate NodeIds after reconcile | Involves Map, recursive trees, counters |
| CRDT convergence | event-graph-walker/ | Two peers converge regardless of op order | Multi-step stateful interactions |
| Projection idempotence | projection/ | project → reconcile → project is stable | Full pipeline with many moving parts |
| Projection stability | projection/ | Same input → same output across rebuilds | Depends on mutable SourceMap state |

### Not worth verifying (unit/snapshot tests sufficient)

- FFI serialization (test at the boundary, trust the format)
- UI rendering (test in browser via Playwright)
- Config parsing (finite cases, exhaustive unit tests)

## Setup Guide

### Local development

```bash
# Install opam (OCaml package manager)
bash -c "sh <(curl -fsSL https://opam.ocaml.org/install.sh)"
opam init --yes

# Install Why3 and z3
opam install why3.1.7.2 --yes
pip3 install --user z3-solver==4.13.4.0

# Register z3 with Why3
why3 config detect

# Run proofs
cd lib/semantic/proof
moon prove
```

### CI

The `prove` job in `.github/workflows/ci.yml` uses `ocaml/setup-ocaml@v3` to install OCaml/opam, then installs Why3 1.7.2 and z3. The opam switch is cached across runs.

### Adding a new proof package

1. Create a standalone module with its own `moon.mod.json` (avoids cascading `proof-enabled` to the entire dependency graph)
2. Add `options("proof-enabled": true)` to `moon.pkg`
3. Write `#proof_pure` projection functions for any custom types
4. Write predicates in `.mbtp`
5. Add `proof_ensure` contracts to the function under verification
6. Run `moon prove` and iterate

### Common issues

- **z3 not recognized**: Why3 1.7.2 only supports z3 up to 4.13.x
- **"no configured provers"**: Run `why3 config detect` after installing z3
- **Wildcard codegen bug**: Use `_v` not `_` in match arms of `#proof_pure` functions
- **`proof-enabled` cascading**: Keep proof packages in standalone modules with no project dependencies
