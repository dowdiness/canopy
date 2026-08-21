# Formal Verification

## Overview

MoonBit provides formal verification via `moon prove`, which uses SMT solvers (z3) through Why3 to mathematically prove properties about code. Unlike property-based tests (@qc) that check random samples, `moon prove` guarantees a property holds for **all** inputs.

Canopy uses both: `moon prove` for properties the prover can model, @qc for everything else. The two layers complement each other.

## Toolchain

```
moon prove  →  moonc (WhyML codegen)  →  Why3  →  z3 (SMT solver)
```

**Tested versions:**
- MoonBit 0.10.8+8606a5800 (repository-pinned toolchain)
- Why3 1.7.2 (install via `opam install why3.1.7.2`)
- Z3 4.13.x (install via `pip3 install z3-solver==4.13.4.0` or `opam install z3`)

**Why3 1.7.2 specifically:** moonc's built-in Why3 harness expects this version. Stock 1.7.2 recognizes z3 up to 4.13.x — newer z3 versions are not detected.

## How It Works

### File structure

```
modules/semantic/proof/ or modules/btree/proof/
├── moon.mod               # Standalone module (no Canopy dependencies)
├── moon.pkg               # options("proof-enabled": true)
├── *.mbt                  # Code + proof_ensure contracts
├── *.mbtp                 # Logical predicates (spec-only)
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
cd modules/semantic/proof  # or modules/btree/proof
moon prove             # verify all proof_ensure contracts
```

## Prover Limitations

These constraints determine what `moon prove` can and cannot verify:

| Limitation | Impact | Workaround |
|---|---|---|
| Unbounded integers only | No Float, no overflow modeling | Use Int-specialized mirror types |
| No `==` on custom enums | Can't write `result == expected` for enum types | Project to Int via `#proof_pure` functions |
| No method calls in predicates | Only `#proof_pure` functions and primitives | Write pure projection functions |
| `#proof_pure` functions cannot carry contracts | A projection cannot prove its own postcondition | Put the arithmetic directly in a contracted side-effect-free function; reserve `#proof_pure` for logic-side projections |
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

### Formally verified (modules/semantic/proof/)

`IntConfidence::join` — 5 properties:

| Predicate | What it proves |
|---|---|
| `conflict_is_top` | Conflict absorbs: join with Conflict always yields Conflict |
| `unknown_is_bottom_left` | Left identity: join(Unknown, x) == x (via rank/payload/score) |
| `unknown_is_bottom_right` | Right identity: join(x, Unknown) == x |
| `disagreement_yields_conflict` | Different payloads from non-trivial inputs → Conflict |
| `guessed_max_score` | Guessed+Guessed same payload → Guessed with exact max score, payload preserved |

### Formally verified (modules/btree/proof/)

Nine scalar contracts mirror production decisions without importing the BTree package:

| Function | What it proves |
|---|---|
| `splice_leaf_delta` | Leaf delta equals inserted leaves minus the replaced range |
| `splice_new_count` | Splice cardinality is non-negative and equals `old_count + leaf_delta` under valid indices |
| `planned_group_size` | Every scalar grouping step emits a value in `[t, 2t]`; nonterminal steps preserve a legal remainder and make progress |
| `planned_group_total` | The recursive scalar grouping model terminates and its emitted sizes sum to the input count |
| `advance_group_sum` | The emitted-plus-remaining invariant is preserved and the terminal sum equals the input count |
| `repaired_node_count` | Merge/steal arithmetic preserves participating child counts; steal and sufficiently large merge restore occupancy, while smaller merges remain conserved intermediate states |
| `repair_total_with_unaffected` | One repair step preserves the global child total when counts outside the selected sibling pair are held fixed |
| `span_add_accepted` | Checked-add acceptance exactly matches the supported non-negative mathematical range |
| `project_root_present` | The scalar publication policy maps zero leaves to no root and requires a present root to have a positive leaf count |

See [`modules/btree/proof/README.md`](../../modules/btree/proof/README.md) for the exact production mapping, preconditions, composition argument, and limitations. Production Array materialization, final repeated-repair occupancy, root-state linkage, recursive tree integration, and MoonBit machine-`Int` behavior remain executable/property-test coverage.

### Property-tested (@qc)

| Package | File | Properties |
|---|---|---|
| modules/canopy/core/ | reconcile_properties_wbtest.mbt | ID uniqueness, ID preservation, kind propagation, idempotency, insert/delete stability |
| modules/canopy/core/ | source_map_properties_wbtest.mbt | Node coverage, range sorting, rebuild consistency, parent enclosure, innermost node minimality |
| modules/semantic/ | confidence_properties_wbtest.mbt | Commutativity, associativity, idempotency, identity, absorbing top (on real `Confidence[Role]`) |
| modules/btree/ | btree_property_wbtest.mbt | Cached spans, splice cardinality, occupancy repair, root normalization, and range-delete integration |
| modules/zipper/ | zipper_properties_wbtest.mbt | Zipper navigation laws |
| deps/event-graph-walker/ | Various *_properties_test.mbt | CRDT convergence, version vector properties, FractionalIndex ordering |

## Future Proof Targets

Candidates ordered by value and feasibility:

### High value, good fit for moon prove

| Target | Package | Properties | Why provable |
|---|---|---|---|
| delete_range boundaries | modules/btree | Index parameters stay valid through descent | Index math — exactly what z3 excels at |
| SourceMap range sorting | modules/canopy/core/ | Ranges array sorted after rebuild | Int comparisons on array indices |
| FractionalIndex ordering | deps/event-graph-walker/ | midpoint(a, b) is strictly between a and b | Byte-array arithmetic |

### High value, better as @qc

| Target | Package | Properties | Why not provable |
|---|---|---|---|
| Reconcile ID uniqueness | modules/canopy/core/ | No duplicate NodeIds after reconcile | Involves Map, recursive trees, counters |
| CRDT convergence | deps/event-graph-walker/ | Two peers converge regardless of op order | Multi-step stateful interactions |
| Projection idempotence | modules/canopy/projection/ | project → reconcile → project is stable | Full pipeline with many moving parts |
| Projection stability | modules/canopy/projection/ | Same input → same output across rebuilds | Depends on mutable SourceMap state |

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

# Run either standalone proof module
cd modules/semantic/proof  # or modules/btree/proof
moon prove
```

### CI

The `prove` job in `.github/workflows/ci.yml` installs Why3 1.7.2 and z3 through opam. The opam switch is cached across runs. It currently executes `modules/semantic/proof`; adding `modules/btree/proof` to the gating matrix remains tracked by #1007.

### Adding a new proof package

1. Create a standalone module with its own `moon.mod` (avoids cascading `proof-enabled` to the entire dependency graph)
2. Add `options("proof-enabled": true)` to `moon.pkg`
3. Write `#proof_pure` projection functions only when logic predicates must inspect custom types
4. Write predicates in `.mbtp`
5. Add `proof_ensure` contracts to the function under verification
6. Run `moon prove` and iterate

### Common issues

- **z3 not recognized**: Why3 1.7.2 only supports z3 up to 4.13.x
- **"no configured provers"**: Run `why3 config detect` after installing z3
- **Wildcard codegen bug**: Use `_v` not `_` in match arms of `#proof_pure` functions
- **`proof-enabled` cascading**: Keep proof packages in standalone modules with no project dependencies
