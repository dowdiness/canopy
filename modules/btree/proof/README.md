# BTree scalar proofs

This standalone module proves the integer decisions behind BTree splice cardinality, non-root grouping, underfull-child repair, checked span addition, and root publication. It intentionally does not depend on `dowdiness/btree`: the production package remains executable while this package mirrors only pure `Int`/`Bool` formulas that Why3 can model accurately.

## Production mapping

| Proof-model function | Production source | Mirrored decision and preconditions | Proved postcondition |
|---|---|---|---|
| `splice_leaf_delta` | `modules/btree/walker_propagate.mbt`, `propagate` | `inserted_count - (end_idx - start_idx)` | The returned delta equals the replacement formula. |
| `splice_new_count` | `modules/btree/walker_propagate.mbt`, `propagate`; callers publishing `size` | `0 <= start <= end <= old_count`, `inserted_count >= 0` | `new_count = old_count - (end - start) + inserted_count = old_count + leaf_delta`, and the result is non-negative. |
| `planned_group_size` | `modules/btree/walker_propagate.mbt`, `legal_chunk_sizes` | `min_degree >= 2`, `remaining >= min_degree`; terminal push or the loop's next chunk | Every emitted group is in `[min_degree, 2 * min_degree]`; a non-terminal remainder stays at least `min_degree` and strictly decreases. |
| `planned_group_total` | `modules/btree/walker_propagate.mbt`, repeated `legal_chunk_sizes` steps | The same grouping preconditions and the strictly decreasing remainder | The recursive scalar planner terminates and all emitted group sizes sum exactly to the input child count. |
| `advance_group_sum` | `modules/btree/walker_propagate.mbt`, `legal_chunk_sizes` | `original_count = emitted_count + remaining` and the grouping preconditions | One step preserves `emitted + remaining = original_count`; a terminal step emits exactly `original_count`. |
| `repaired_node_count` | `modules/btree/walker_repair.mbt`, `repair_underfull_children`, `bulk_steal_from_left`, and `bulk_steal_from_right` | Reactive underfull count in `[0, t)`, sibling in `[0, 2t]`, target in `[t, t + 1]` | Every merge or steal preserves the participating child total and keeps the result in `[0, 2t]`. A steal restores both occupancies. A merge at or above `t` restores occupancy; a smaller adjacent-underfull merge remains a conserved candidate for another repair step. |
| `repair_total_with_unaffected` | One iteration of `modules/btree/walker_repair.mbt`, `repair_underfull_children` | A non-negative count outside the selected pair and the same reactive repair preconditions | `unaffected + participating pair` is unchanged by either branch, so each new loop decomposition preserves the global child total. |
| `span_add_accepted` | `modules/btree/utils.mbt`, `checked_span_add` | The exact non-negative guard against the mathematical constant `2147483647` (`@int.MAX_VALUE`) | Acceptance implies a sum in `[0, MAX]`; every non-negative sum in range is accepted; rejection of non-negative inputs is equivalent to a sum above `MAX`; negative inputs are rejected. |
| `project_root_present` | Leaf-count policy abstracted from `modules/btree/btree.mbt`, `PropagateResult::root_candidate` and `normalize_root_after_delete` | `leaf_count >= 0`; executable properties establish that production segment/root state corresponds to this count | In the scalar policy, zero leaves project to no root and every present root has a positive leaf count. |

## Why the grouping proof is scalar

`legal_chunk_sizes` returns an `Array[Int]`, which `moon prove` cannot model. The proof instead verifies its exact one-step transition:

1. each chosen chunk has legal occupancy;
2. `chunk + next_remaining = remaining`;
3. a non-terminal `next_remaining` is legal and strictly smaller;
4. `advance_group_sum` preserves `emitted + remaining = original_count`;
5. `planned_group_total` uses the decreasing remainder as its termination measure and proves that the recursive sum equals `child_count`;
6. the terminal transition sets `remaining` to zero and `emitted` to `original_count`.

Starting from `(emitted, remaining) = (0, child_count)`, the verified scalar recurrence establishes legal scalar steps and an exact scalar total. It does not prove that the production `Array[Int]` contains those values; executable `legal_chunk_sizes` and `pack_level` properties cover that linkage. No sequence axiom or bounded sample is assumed by the scalar proof.

## Why the repeated-repair proof is scalar

`repair_underfull_children` may process several adjacent underfull nodes. `repaired_node_count` proves pair conservation and the selected postcondition for each reactive step: steal restores both occupancies; merge yields a node in `[0, 2t]`, which is occupied when its combined count reaches `t` and otherwise remains the one conserved candidate for the next iteration. `repair_total_with_unaffected` lifts pair conservation to a whole-segment accumulator, so repeated iterations preserve the complete child total by induction.

Why3 cannot model the production `Array[BTreeNode]`, sibling selection, or the loop's final array shape. Final occupancy after traversing an adjacent-underfull sequence therefore remains explicitly excluded from the scalar proof and retained in BTree deterministic/property tests. This model also excludes proactive `ensure_min_children`, whose trigger includes `child_count == t`; it covers the reactive `child_count < t` policy only.

## Guarantee boundary

Why3 integers are unbounded mathematical integers. These proofs establish the scalar model only. They do **not** establish:

- recursive BTree shape or path correctness;
- production `Array` materialization or sibling selection;
- final array occupancy after traversing a sequence of adjacent underfull siblings (covered by executable BTree repair properties);
- proactive descent repair for a child with exactly `min_degree` children;
- callback behavior or failure atomicity;
- the correspondence between root segments and the leaf-count projection;
- MoonBit machine-`Int` overflow semantics;
- cross-parent OrderTree canonicalization.

Production deterministic/property tests cover those integration boundaries, including adjacent-underfull repair and grouping arrays. In particular, `modules/btree/btree_wbtest.mbt` retains exact `@int.MAX_VALUE` acceptance and `@int.MAX_VALUE + 1` rejection regressions.

## Run

The repository pins MoonBit `0.10.4+ade96c819`; the proof toolchain uses Why3 1.7.2 and Z3 4.13.x.

```bash
cd modules/btree/proof
NEW_MOON_MOD=0 moon check --deny-warn
NEW_MOON_MOD=0 moon test --release
NEW_MOON_MOD=0 moon info
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon prove
```
