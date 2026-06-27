# Concurrent Drag-Drop Convergence Tests

**Status:** Scoping plan
**Date:** 2026-06-26
**Dependency:** `SyncEditor::move_node` (landed), `apply_lambda_tree_edit` Drop route (landed)

## Problem

Concurrent drag-drop (structural `Drop` `TreeEditOp` operations issued concurrently across CRDT peers) has no editor-level convergence test coverage. The existing coverage lives at two layers:

1. **CRDT / movable tree** (`event-graph-walker/container/document_test.mbt:428-489`): `Document::move_node_after` / `move_node_before` convergence — tests the `TreeMoveOp` CRDT layer. Does not exercise the structural-edit pipeline (span edits, placeholders, projection reconcile).

2. **Text-level SyncEditor** (`editor/sync_editor_test.mbt:81-96`): `insert` convergence — tests the text CRDT layer only. Does not test structural edits.

The TODO exit criterion: *"property tests covering concurrent drop, undo grouping after relocation, and reconciliation"* — so the centerpiece is a **quickcheck model**, not hand-written tests. Named deterministic tests punctuate the property.

## Key Design Constraint

`SyncEditor::move_node` semantics:

| `DropPosition` | Behavior |
|---|---|
| `Before` / `After` | **Move:** source expr replaced with placeholder; source text inserted before/after target. Source vacates its position. |
| `Inside` | **Exchange/Swap:** both nodes exchange their expression content (text swap). Neither node vacates. |

`Inside` is **not** "move into target as child" — it's a symmetric content swap. This constrains the test model: concurrent-swap tests check CRDT ordering of identical-intent swaps; concurrent move-vs-swap tests check conflicting-intent arbitration.

### Undo constraint

`SyncEditor.undo` reverts only the local editor's own delta — remote ops applied via `apply_sync` are not captured in the local undo stack. This means after both peers drop + sync:

- Editor 1's undo reverts Editor 1's span edits only (Editor 2's edits persist locally)
- Editor 2's undo reverts Editor 2's span edits only

After both undo + bidirectional sync, both editors converge on the mutual undo state (both drops reverted, initial seed restored). The undo assertions below account for this: they assert convergence after each sync round, not immediate identity with the initial seed.

## Scope

**Test-only.** No blueprint changes, no new SyncEditor methods, no new `TreeEditOp` variants. All machinery is live — this fills the gap between the CRDT layer and the text layer at the structural-edit pipeline level.

## Test Structure

**File:** `lang/lambda/companion/drop_convergence_test.mbt` (new blackbox test file)

The lambda companion package already imports `@qc` (`moon.pkg` line 20).

## Model Layer

A small generator that produces **pairs of concurrent Drop operations** on a shared initial seed text.

### Types

```moonbit
enum DropPosition { Before; After; Inside }

struct ConcurrentDropScenario {
  seed_text : String
  peer1_drop : DropOp
  peer2_drop : DropOp
}

struct DropOp {
  source_idx : Int   // index into the seed's top-level children
  target_idx : Int   // index into the seed's top-level children
  position : DropPosition
}
```

### Arbitrary instance

```moonbit
impl @qc.Arbitrary for ConcurrentDropScenario with fn arbitrary(size, rs) {
  // 1. Pick a seed AST with 3-6 top-level children from a small fixed set
  //    of seed strings (e.g. "a b c", "f(x) g(y) h(z)", "f(a) g(b) h(c) i(d)").
  // 2. Pick source and target indices (0..n-1, source != target) for each peer.
  //    Both peers pick from the seed's children independently.
  // 3. Pick DropPosition for each peer.
  // 4. Return { seed_text, peer1_drop, peer2_drop }
}
```

### Properties

#### P1: Concurrent drops converge

Given scenario, set up two editors on `seed_text`, apply each peer's drop, sync bidirectional, assert:

```
ed1.get_text() == ed2.get_text()
get_lambda_ast(ed1) == get_lambda_ast(ed2)
ed1.get_proj_node() is Some(_)
ed2.get_proj_node() is Some(_)
```

Quickcheck over 200 iterations.

#### P2: Undo grouping — local drop's multi-span edit undoes as one step

Given scenario, after drops + sync converge:

1. Both editors report `can_undo()` = true (undo stack is non-empty — the local drop, which was a multi-span edit)
2. Both editors' `undo()` succeeds (no crash, returns success)
3. After bidirectional sync of undo operations: both converge again (`text == text`, `AST == AST`, valid ProjNode)
4. (Diagnostic) If both peers are back at the initial seed text after undo sync, the inverse span edits cleanly commuted. This is expected but not guaranteed — inverse edits applied to interleaved remote text may not reconstruct the literal seed. The hard assertion is step 3: convergence + valid ProjNode.

Quickcheck over 100 iterations.

#### P3: Reconciliation produces no structural errors

After each sync round: the projection memo returns `Some(proj)`, the source map resolves every `NodeId` referenced by the ProjNode, and the AST round-trips (unparse → reparse → same AST). Quickcheck over 200 iterations.

### Shrink instance

The shrink produces shorter seed text (fewer children) and replaces both drop positions with `Before` (least structurally disruptive), shrinking toward the minimal scenario that still diverges.

### Wrinkles

- The seed text must be parseable lambda. A fixed set of 3-4 seed strings (with varying structure: only leaves, mix of leaves and branches) avoids generation of malformed input.
- Source/target indices refer to the **initial** AST children. After a move, the child list reshuffles — but both peers start from the same initial text and apply their drop to that same initial state, so indices resolve the same way before any sync happens.
- The model is small by design (2 peers, 2 concurrent drops) to keep the state space tractable. Multi-round concurrent scenarios would need a generator of op sequences, which is future work.

## Named Regression Tests (Deterministic)

These are fixed-scenario spot checks that exercise specific failure modes. They also serve as documentation of what edge cases the property generator covers.

### R1: Different sources, same target, both Before

- Peer 1: `Drop(source=a, target=b, Before)` — a already precedes b in seed
- Peer 2: `Drop(source=c, target=b, Before)` — c moves before b

After sync: both converge. Verifies two sources targeting the same position.

### R2: Same source, different targets, both Before — CRDT arbitrates relocation

- Peer 1: `Drop(source=b, target=a, Before)` — b moves before a
- Peer 2: `Drop(source=b, target=c, Before)` — b moves before c
- Both ops move the same node `b` to different positions. The CRDT must arbitrate the relocation conflict. After sync: converge.

### R3: Both peers issue same exchange (Inside, same pair)

- Both peers: `Drop(source=a, target=b, Inside)` — both swap a↔b identically
- Sync: still convergent. No CRDT conflict since both produced identical CRDT ops.
- Verifies that identical concurrent swaps don't diverge.

### R4: Exchange vs move (Inside vs Before) on same pair — conflicting intent

- Peer 1: `Drop(source=a, target=b, Inside)` — exchange/swap
- Peer 2: `Drop(source=a, target=b, Before)` — move-before
- The CRDT must arbitrate conflicting interpretation of "drop a at b" (swap vs relocate). After sync: converge.

### R5: Drop + concurrent text edit — structural-text interop

- Peer 1: `Drop(source=b, target=a, Before)` — structural edit
- Peer 2: `insert("x")` at cursor 0 — raw text edit
- After sync: converge. Verifies structural edit + raw text edit interop through the shared CRDT.

### R6: Undo after concurrent drops — grouped undo then resync

- Seed: `"a b c"`
- Peer 1: `Drop(source=b, target=a, Before)`
- Peer 2: `Drop(source=c, target=a, After)`
- Sync → converge
- Assert `can_undo()` for both editors
- Both `undo()` → succeeds without crash
- Bidirectional sync → converge again (text == text, AST == AST)
- (Diagnostic) If both peers are back at `"a b c"`, the inverse span edits commuted cleanly. This is not guaranteed when remote edits interleave — hard assertion is convergence above.

### R7: Three-peer convergence (sanity)

- Seed: `"a b c"`
- Three peers, each issues a different drop (different source-target pairs)
- All-pairs bidirectional sync
- Every pair converges on text + AST

## Timestamp Strategy

Each peer issues its ops with increasing timestamps, starting from 1. CRDT ops from different agents at the same timestamp are ordered by agent id tiebreak.

- Peer 1: `timestamp_ms = 1`
- Peer 2: `timestamp_ms = 1`

This matches real-world usage: concurrent ops from different clients are ordered by client id.

## Risks

1. **`get_lambda_ast` returns `Term`** — if `Term` does not `derive(Eq)`, fall back to string comparison: `@ast.print_term(get_lambda_ast(ed1)) == @ast.print_term(get_lambda_ast(ed2))`.

2. **Node ID instability after sync** — after sync+reparse, a given structural node may have a different `NodeId`. The test model uses **indices into the initial children array**, not cached NodeIds.

3. **Memo stabilization** — `get_proj_node()` returns `Option` from a reactive memo. Guard with `guard ... is Some(proj)` before accessing children.

4. **incr runtime isolation** — each editor owns its own incr runtime. No cross-editor dependency.

5. **Seed text must be valid lambda** — fixed seed set avoids generation of syntactically invalid input.

6. **Quickcheck size parameter** — `size` drives the number of children in the seed. Map `size = 0` → smallest seed ("a b"); larger sizes pick seeds with more children and branching.

7. **`move_node` timestamp reuse** — two peers using the same timestamp value is fine (agent-ID tiebreak). A peer reusing the same local timestamp for consecutive ops would be a bug, avoided here by each peer issuing exactly one drop per test.

8. **R1: move Before where source already precedes target** — `move_node` Before where the source is already first is a no-op in text terms (source stays in place, placeholder replaces nothing meaningful). The CRDT still records the op. Both peers converge trivially, leaving the other peer's conflicting move as the interesting test.

9. **Undo R6 final seed assertion** — after both undo + sync, both peers should converge on the initial seed provided undo operations are CRDT text ops that commute. If this assertion fails consistently, the undo property (P2) will still verify convergence after undo + sync without asserting specific content. The R6 test is the diagnostic that will surface the actual behavior.

## Exit Criteria

- `drop_convergence_test.mbt` exists with:
  - **3 quickcheck properties** (P1 concurrent drops converge, P2 undo after drops, P3 no structural errors)
  - **7 named regression tests** (R1-R7)
- `moon test` passes in the lambda companion package
- Every property test runs ≥100 iterations
- Every test asserts text convergence AND AST convergence AND ProjNode validity

## Non-Goals

- No changes to SyncEditor, move_node, lambda companion, or TreeEditOp
- No changes to the CRDT layer (MovableTree, Document)
- No new helper methods on SyncEditor
- No performance benchmarking
- No multi-round concurrent op sequences (future work)

## Plan Steps

1. Create `lang/lambda/companion/drop_convergence_test.mbt`
2. Implement helpers: `setup_two_peers`, `apply_drop`, `assert_converged`
3. Implement model types: `ConcurrentDropScenario`, `DropOp`, `Arbitrary`, `Shrink`
4. Implement 3 quickcheck properties (P1, P2, P3)
5. Implement 7 named regression tests (R1-R7)
6. Run `moon test` in lambda companion → fix any failures
7. Run `moon test` across workspace → verify no downstream breakage
