# Container Undo Grouping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship document-level undo grouping in `@container.Document` so a single user gesture (drag-drop, multi-char paste, replace_text, block split) undoes as one atomic group while preserving CRDT convergence.

**Architecture:** Model I (inverse-op replay). Transactions (implicit per-call + explicit `transaction(fn)`) define groups. `TextOp::Undelete` is the only additive wire change. Undo/redo emit fresh inverse ops via a dedicated code path that bypasses the commit pipeline.

**Tech Stack:** MoonBit, event-graph-walker (Fugue + movable-tree CRDT), existing container sync infrastructure.

**Design source of truth:** [docs/plans/2026-04-17-container-undo-grouping-design.md](2026-04-17-container-undo-grouping-design.md) (committed ac9e350). If this plan and the design conflict, the design wins — stop and reconcile.

**Branch:** `feat/container-undo-grouping` (already created, design doc committed).

**Scope boundary:** `event-graph-walker/container/` only. No changes to `internal/movable_tree/`, `internal/fugue/`, sync infrastructure, block-editor, or FFI.

**Out of scope for this plan:** Block-editor integration, JS FFI exposure, typing coalescing policy, `RemoveProperty` op variant — all listed as v1 non-goals in design §11.

**Process rule per CLAUDE.md algorithm process:** Main-context work (no subagents) for Phase 1 (wire protocol correctness depends on understanding LWW), Phase 3 (algorithm — hook placement, execution code path), and Phase 4 (convergence proofs). Subagents acceptable for Phase 2 (mechanical data-structure scaffolding) and Phase 5 (formatting / mbti regen).

---

## File Structure

### New files

- `event-graph-walker/container/undo_types.mbt` — `UndoItem` enum (one variant per forward op type), `UndoGroup` struct. Private to container; expose nothing.
- `event-graph-walker/container/undo.mbt` — `UndoManager` internal helpers, transaction state machinery, undo/redo execution path, public API on `Document`.
- `event-graph-walker/container/undo_test.mbt` — blackbox tests for public API surface: implicit grouping, explicit composition, nested flattening, redo round-trip, tracking, convergence scenarios.
- `event-graph-walker/container/undo_wbtest.mbt` — whitebox tests for internal invariants: depth counter, undo-execution-mode gate, pre-state snapshot shape.

### Modified files

- `event-graph-walker/container/text_block.mbt` — add `TextUndeleteOp` struct, `TextOp::Undelete` variant, `Undelete` arm in `TextBlock::apply_op` calling `undelete_with_ts`.
- `event-graph-walker/container/document.mbt` — `text_op_timestamp`, `text_op_agent`, `compare_text_ops`, `text_op_key` gain `Undelete` arms. `Document` struct gains undo state fields (undo/redo stacks, txn buffer, txn depth, tracking flag, undo-execution-mode flag). Each public mutation method gains a hook to record after successful apply. No signatures of existing methods change.
- `event-graph-walker/container/errors.mbt` — potentially new `DocumentError` variants (`UndoStackEmpty`, `RedoStackEmpty` — or these might just return `false` without raising; decide in Task 3.3).
- `event-graph-walker/container/pkg.generated.mbti` — regenerated via `moon info` at the end of each phase; diff reviewed.

### Note on tests in whitebox vs blackbox

Blackbox (`undo_test.mbt`) for everything that can be written through the public API. Whitebox (`undo_wbtest.mbt`) only for internal invariants that can't be asserted through the API (e.g., txn depth counter, internal undo-execution-mode flag behavior during multi-step undo).

---

## Phase 0 — Baseline

Verify the working tree is green before touching anything. If this phase fails, the failure is pre-existing and must be understood before continuing; do not start Phase 1 until it's green.

### Task 0.1: Confirm baseline green

**Files:** none — this is a state check.

- [ ] **Step 1:** Run `cd event-graph-walker && moon check && moon test` from the canopy root.
- [ ] **Step 2:** Expected: all tests pass, no warnings. If anything fails, stop and investigate — this plan assumes a clean baseline.
- [ ] **Step 3:** Run `git status`. Expected: only submodule dirty markers and untracked files outside `event-graph-walker/`. If there are pending edits in `event-graph-walker/container/`, stop and investigate.

---

## Phase 1 — `TextOp::Undelete` wire protocol

**Goal:** extend the text op enum with a third variant, wire it through every pipeline stage (apply, dedup, sync, pending queues), and prove convergence under concurrent Delete/Undelete at the container boundary.

**Invariant this phase must preserve:** all existing text tests continue to pass unchanged. The enum widening is purely additive.

**Design sections exercised:** §5 convergence, §7 wire-protocol delta.

### Task 1.1: Add `TextUndeleteOp` struct and enum variant

**Files:**
- Modify: `event-graph-walker/container/text_block.mbt`

**Intent:** mirror the shape of `TextInsertOp` and `TextDeleteOp`. Fields are `target : Int` (the fugue LV to revive), `timestamp : Int` (for LWW comparison in `undelete_with_ts`), `agent : String` (for tie-break). Mark `pub(all)` for parity with the other text op variants. Extend the `TextOp` enum with `Undelete(TextUndeleteOp)`.

- [ ] **Step 1:** Open `text_block.mbt` and locate the `TextInsertOp` / `TextDeleteOp` / `TextOp` definitions (around line 10-30 per the current file).
- [ ] **Step 2:** Add the new struct and variant in the same block, preserving existing field order conventions (`target`, `timestamp`, `agent` mirror `TextDeleteOp`).
- [ ] **Step 3:** Run `moon check` from `event-graph-walker/`. Expected: compile error on `TextBlock::apply_op` match expression (non-exhaustive) and on `text_op_timestamp` / `text_op_agent` / `compare_text_ops` / `text_op_key` in `document.mbt`. These errors are the next tasks' work — do not fix in this task.
- [ ] **Step 4:** **Do not commit yet.** Phase 1 commits once the wire is fully plumbed and tests are green.

### Task 1.2: `TextBlock::apply_op` Undelete arm

**Files:**
- Modify: `event-graph-walker/container/text_block.mbt:101-129` (the `apply_op` match block).

**Intent:** the `Undelete` arm calls `self.tree.undelete_with_ts(Lv(target), timestamp, agent)`. **Not** `tree.undelete` — the `_with_ts` form is what routes through `should_win_delete` for LWW correctness. On success, invalidate `text_cache` the same way Insert/Delete do. On fugue-layer failure (missing item — should be impossible for a well-formed undelete against a known tombstone), raise `DocumentError::Internal` with a descriptive detail matching the delete arm's pattern.

- [ ] **Step 1:** Implement the arm in prose-to-code: match on `Undelete(undelete_op)`, call `self.tree.undelete_with_ts(...)` with an error-to-DocumentError catch, then invalidate the cache.
- [ ] **Step 2:** Run `moon check`. Expected: error list shrinks by one; remaining errors are in `document.mbt` helpers.

### Task 1.3: Extend `document.mbt` text-op helpers

**Files:**
- Modify: `event-graph-walker/container/document.mbt:136,144,152,263` (the four helpers `text_op_timestamp`, `text_op_agent`, `compare_text_ops`, `text_op_key`).

**Intent:**
- `text_op_timestamp`: return `undelete_op.timestamp`.
- `text_op_agent`: return `undelete_op.agent`.
- `compare_text_ops`: third variant uses target LV as the final tiebreak. Consider ordering: `Insert < Delete < Undelete` (so a conflict-insertion-then-delete-then-undelete stream sorts deterministically). Document the choice in a comment.
- `text_op_key`: new prefix `"text-undelete|..."` with `block`, `agent`, `timestamp`, `target` fields length-prefix-encoded the same way the other arms do.

- [ ] **Step 1:** Update each of the four helpers.
- [ ] **Step 2:** Run `moon check`. Expected: all compile errors cleared.

### Task 1.4: Verify JSON serialization path

**Files:** none — this is a read-and-confirm task.

**Intent:** text ops flow through `VersionedBlockTextOp` → `SyncMessage`. If those types derive `FromJson` / `ToJson` (typical for egw container types), adding a variant to `TextOp` is free — the derive picks it up. If not, we need to update manual serialization. Goal is to find out which.

- [ ] **Step 1:** Grep `event-graph-walker/container/` for `ToJson` / `FromJson` / `derive(`. Identify whether `TextOp`, `VersionedBlockTextOp`, and `SyncMessage` rely on derived serialization or manual code.
- [ ] **Step 2:** If derived: note this in a commit-message-ready observation and move on.
- [ ] **Step 3:** If manual: add a follow-up step to this task to extend the manual serialization. Do not improvise — update this plan first so the work is tracked.
- [ ] **Step 4:** Run `moon check` (still green from 1.3).

### Task 1.5: Failing test — local Delete then local Undelete round-trip

**Files:**
- Create or extend: `event-graph-walker/container/text_properties_test.mbt` (blackbox — reuses existing test scaffold).

**Test spec (prose):**

Create a `Document`. Create a block via `create_node(parent=root_id)`. Insert `"hello"`. Delete position 0 ("h"). Assert `get_text == "ello"`. Now synthesize a local `Undelete` op (call the internal `apply_block_text_op` with a hand-built `BlockTextOp` whose `Undelete` carries the same `target` as the prior Delete, with a timestamp higher than the Delete). Assert `get_text == "hello"`. This test exercises the fugue integration through the container boundary.

**Expected to fail because:** until this task, there was no way to observe an Undelete being applied; this test asserts the shape of the plumbing.

- [ ] **Step 1:** Write the test. Use the existing test file's patterns (agent id fixture, tree construction helpers).
- [ ] **Step 2:** Run `moon test` from `event-graph-walker/`. Expected: the test passes if 1.1–1.3 are correct. If it fails, the failure is diagnostic — the failure mode tells us where the plumbing is incomplete.
- [ ] **Step 3:** If the test fails for a non-obvious reason, **stop and debug**. Do not mask the failure with a try/catch; the test is a correctness probe.

### Task 1.6: Failing test — convergence across orderings

**Files:**
- Create or extend: `event-graph-walker/container/text_properties_test.mbt`.

**Test spec (prose):**

Two replicas `A` and `B`. Both start from the same initial state: one block containing one char `"x"` (so a single LV is shared). `A` issues `Delete` at timestamp 5. `B` issues `Undelete` at timestamp 10 (higher). Sync order 1: `A` receives B's Undelete *after* its local Delete. Sync order 2: `B` receives A's Delete *after* its local Undelete. Both replicas' final state must be **"x" visible** (the higher-timestamp Undelete wins on both). Use `apply_remote_sync_message` and assert `SyncReport.pending_ops == 0` on both sides.

**Why this test:** this is the exact divergence Codex flagged in the pre-implementation review. It must pass before this phase lands.

- [ ] **Step 1:** Write the test. Structure: two `Document` instances, apply local ops, then swap sync messages in different orders across two sub-tests.
- [ ] **Step 2:** Run `moon test`. Expected: pass in both orderings. Failure = `undelete_with_ts` was not wired correctly.
- [ ] **Step 3:** If either ordering produces divergent state, investigate: most likely cause is that the `Undelete` variant didn't route through `undelete_with_ts` (Task 1.2 bug), or that dedup in `record_text_op` is letting one side skip the op.

### Task 1.7: Failing test — tie-break add-wins

**Files:**
- Extend: `event-graph-walker/container/text_properties_test.mbt`.

**Test spec (prose):**

Replica `A` issues `Delete(target=lv, ts=7, agent="alpha")`. Replica `B` issues `Undelete(target=lv, ts=7, agent="beta")`. Same timestamp. Sync both ways. Expected final state: **item visible** (Undelete wins the tie). This is the add-wins rule documented in §5.

- [ ] **Step 1:** Write the test.
- [ ] **Step 2:** Run `moon test`. Expected: pass.
- [ ] **Step 3:** Sanity-check by reading `should_win_delete` in `internal/fugue/tree.mbt:~195` — the tie-break code should match our expectation.

### Task 1.8: Phase 1 green, format, commit

- [ ] **Step 1:** Run `moon test` in `event-graph-walker/`. All tests green (including pre-existing ones).
- [ ] **Step 2:** Run `moon check`. Clean.
- [ ] **Step 3:** Run `moon info && moon fmt`. Review `git diff event-graph-walker/container/*.mbti` — expected: only the `Undelete` variant added. No widened bounds on existing types.
- [ ] **Step 4:** Commit from canopy root. Staged files: `event-graph-walker/container/text_block.mbt`, `event-graph-walker/container/document.mbt`, `event-graph-walker/container/text_properties_test.mbt`, `event-graph-walker/container/pkg.generated.mbti`. Message: `feat(container): TextOp::Undelete wire support with LWW-aware revival`. Body should cite §7 of the design doc and note the three convergence tests.
- [ ] **Step 5:** Push the submodule commit (`cd event-graph-walker && git push origin <submodule-branch>`). **Ask the user before pushing** — per feedback memory, never push to submodule remote without confirmation.

---

## Phase 2 — Undo data structures and transaction machinery (internal)

**Goal:** build the internal bookkeeping (UndoItem, UndoGroup, stacks, transaction state, gating flags) without yet exposing any public API or hooking mutation methods. Everything stays private; tests are whitebox.

**Invariant this phase must preserve:** public API surface unchanged — the `pkg.generated.mbti` diff at the end of Phase 2 should have *no* additions to `Document`'s public methods. All additions are private.

**Design sections exercised:** §6 captured metadata, §8 internal hooks, §9 execution semantics (data-structure shape), §10 tricky corners.

### Task 2.1: Define `UndoItem` and `UndoGroup` types

**Files:**
- Create: `event-graph-walker/container/undo_types.mbt`.

**Intent — enum shape (prose):**

`UndoItem` is a private enum with variants capturing enough state to construct the inverse op for each forward op type:

- `TextInsert { block : TreeNodeId, lv : Int, content : String }`
- `TextDelete { block : TreeNodeId, lv : Int, content : String }`
- `TreeMove { target : TreeNodeId, old_parent : TreeNodeId, old_pos : FractionalIndex, new_parent : TreeNodeId, new_pos : FractionalIndex }`
- `TreeCreate { target : TreeNodeId, parent : TreeNodeId, pos : FractionalIndex }` — special-case of Move where there is no pre-state; inverse is always move-to-trash.
- `TreeDelete { target : TreeNodeId, old_parent : TreeNodeId, old_pos : FractionalIndex }` — special-case where the forward went to trash; need the pre-trash location to undo.
- `PropertySet { target : TreeNodeId, key : String, old_value : String?, new_value : String }` — `old_value: None` means the property was absent; undo emits `set_property(_, key, "")` with the known v1 non-invertibility.

`UndoGroup` is a struct: `items : Array[UndoItem]`. No timestamp, no group id — groups are identified by stack position only.

- [ ] **Step 1:** Write the type declarations. `priv` visibility on both. `derive(Debug)` for testability; no `derive(Show)` per MEMORY note on deprecation.
- [ ] **Step 2:** Add a `derive(Debug)` manual `Show` impl if any test needs human-readable output — defer unless needed.
- [ ] **Step 3:** Run `moon check`. Expected: compiles with no use yet.

### Task 2.2: Add Document undo-state fields

**Files:**
- Modify: `event-graph-walker/container/document.mbt:300-320` (the `Document` struct and `Document::new`).

**Intent — fields to add (prose):**

- `priv mut undo_stack : Array[UndoGroup]` — initialized to `[]`.
- `priv mut redo_stack : Array[UndoGroup]` — initialized to `[]`.
- `priv mut txn_depth : Int` — initialized to `0`. Counts open transactions; only `0 → 1` opens a buffer, only `1 → 0` closes it.
- `priv mut txn_buffer : Array[UndoItem]` — initialized to `[]`. Holds items for the currently-open transaction.
- `priv mut tracking_enabled : Bool` — initialized to `true`. Public flag, toggled by `set_tracking`.
- `priv mut undo_execution_mode : Bool` — initialized to `false`. Internal flag, true only during `undo()`/`redo()` execution.

- [ ] **Step 1:** Add fields to the struct body.
- [ ] **Step 2:** Add field initialization in `Document::new`.
- [ ] **Step 3:** Run `moon check`. Expected: clean.

### Task 2.3: Private `record_undo_item` helper

**Files:**
- Create: `event-graph-walker/container/undo.mbt`.

**Intent:** one internal function that mutation methods will call *after* a successful forward op apply + op-record + sync-record. Writes to `txn_buffer` iff all three gates pass: `tracking_enabled`, `!undo_execution_mode`, `txn_depth > 0`. Otherwise no-op.

- [ ] **Step 1:** Define `fn Document::record_undo_item(self, item : UndoItem) -> Unit`. Private (no `pub`).
- [ ] **Step 2:** Implement the three-gate check as described.
- [ ] **Step 3:** Run `moon check`. Expected: clean but `record_undo_item` is unused (no callers yet).

### Task 2.4: Private transaction open/close helpers

**Files:**
- Extend: `event-graph-walker/container/undo.mbt`.

**Intent — four helpers (prose):**

- `Document::txn_open(self) -> Unit` — increments `txn_depth`. If `txn_depth` was `0`, clears `txn_buffer` (idempotency: buffer should already be empty, but defensive).
- `Document::txn_close(self) -> Unit` — decrements `txn_depth`. If it reaches `0`, commits: if `txn_buffer` is non-empty, push `UndoGroup { items: txn_buffer.copy() }` onto `undo_stack` **and clear `redo_stack`**. Always clear `txn_buffer` at the end.
- `Document::with_implicit_transaction[T, E](self, fn : () -> T raise E) -> T raise E` — the main entry point used by public mutation methods. Opens a txn, calls `fn`, closes in both success and raise paths (guard/defer-style using MoonBit's error-handling primitives — if MoonBit doesn't support defer, use explicit try/catch with close-in-both-branches).
- `Document::commit_empty_noop_check(self) -> Unit` — private documentation helper; not strictly needed but a place to assert the "don't push empty groups" invariant if we want a readable callsite.

- [ ] **Step 1:** Write `txn_open` and `txn_close`.
- [ ] **Step 2:** Write `with_implicit_transaction`. Pin the exact MoonBit signature — if `raise E` generic form isn't supported, narrow to `raise DocumentError` and note in the design doc.
- [ ] **Step 3:** Run `moon check`. Expected: clean; still unused internally.

### Task 2.5: Whitebox test — transaction depth counter

**Files:**
- Create: `event-graph-walker/container/undo_wbtest.mbt`.

**Test specs (prose):**

- Depth starts at 0. After one `txn_open`, depth is 1. After matching `txn_close`, depth is 0 and undo_stack is empty (buffer was empty).
- Nested: `txn_open; txn_open; record_undo_item(X); txn_close; txn_close` → depth returns to 0, undo_stack has one group containing `[X]`. This asserts flattening.
- Redo-cleared-on-commit: pre-seed redo_stack with one dummy group; open + record + close; undo_stack has new group, redo_stack is empty.
- Empty txn: `txn_open; txn_close` with no records → undo_stack unchanged (no empty group pushed).

- [ ] **Step 1:** Write the four test cases. They require reaching into private fields; that's what whitebox tests are for.
- [ ] **Step 2:** Run `moon test`. Expected: all four pass. If any fail, the helper has a bug — fix in `undo.mbt`.

### Task 2.6: Whitebox test — gating flags

**Test specs (prose):**

- `tracking_enabled = false` + open txn + `record_undo_item(X)` + close → buffer was never written, no group pushed.
- `undo_execution_mode = true` + open txn + `record_undo_item(X)` + close → buffer was never written, no group pushed.
- `txn_depth == 0` + `record_undo_item(X)` (outside any txn) → no-op; buffer untouched.

- [ ] **Step 1:** Write these three test cases.
- [ ] **Step 2:** Run `moon test`. Expected: all pass. These assertions lock in the three-gate rule from §8.

### Task 2.7: Phase 2 green, format, commit

- [ ] **Step 1:** `moon test && moon check && moon info && moon fmt`.
- [ ] **Step 2:** `git diff event-graph-walker/container/pkg.generated.mbti` — expected: **no public additions** (all new surface is private). If public methods appear, something was declared `pub` by accident — fix before committing.
- [ ] **Step 3:** Commit: `feat(container): undo data structures and transaction scaffolding`. Cite §6, §8, §9 of the design doc. Note that no public API is exposed yet.

---

## Phase 3 — Public API and per-method hooks

**Goal:** expose `Document::transaction`, `Document::undo`, `Document::redo`, `Document::can_undo`, `Document::can_redo`, `Document::clear_undo`, `Document::set_tracking`, `Document::is_tracking`. Wire each public mutation method to record undo items. Verify with blackbox tests covering the gesture guarantee.

**Invariant this phase must preserve:** every existing public mutation method continues to work with the same signature and the same sync-layer behavior. Only additive change is that mutations now contribute to the undo stack.

**Design sections exercised:** §3 boundary policies, §8 public API, §9 undo/redo execution, §10 tricky corners.

### Task 3.1: Public `Document::transaction(fn)`

**Files:**
- Extend: `event-graph-walker/container/undo.mbt`.

**Intent:** thin wrapper over `with_implicit_transaction`. Signature: `pub fn Document::transaction[T, E](self, fn : () -> T raise E) -> T raise E`. If MoonBit's generic error propagation forces a narrower shape, document the limitation in a comment and raise only `DocumentError`.

- [ ] **Step 1:** Write the public function. Exact signature pinned here — note it in the design doc if it deviates from the spec.
- [ ] **Step 2:** `moon check`. Expected: clean.
- [ ] **Step 3:** Blackbox test (in `undo_test.mbt`, created fresh): `doc.transaction(fn = () => ())` completes and returns Unit without modifying any stack. This establishes the file exists and the API compiles.

### Task 3.2: Public accessor/mutator methods

**Files:**
- Extend: `event-graph-walker/container/undo.mbt`.

**Intent — five methods (prose):**

- `pub fn Document::can_undo(self) -> Bool` — `self.undo_stack.length() > 0`.
- `pub fn Document::can_redo(self) -> Bool` — `self.redo_stack.length() > 0`.
- `pub fn Document::clear_undo(self) -> Unit` — clears both stacks and the buffer; resets txn_depth to 0 (safety: should already be 0 unless called from inside a transaction, which is a misuse — consider raising in that case).
- `pub fn Document::set_tracking(self, enabled : Bool) -> Unit` — sets the flag.
- `pub fn Document::is_tracking(self) -> Bool` — reads the flag.

- [ ] **Step 1:** Write all five.
- [ ] **Step 2:** `moon check`. Clean.
- [ ] **Step 3:** Blackbox test: each method round-trips correctly (set_tracking(false) + is_tracking() → false; clear_undo on empty stacks is a no-op; can_undo/can_redo after direct stack pushes — wait, we can't push directly from blackbox. Test through the eventual mutation-method pathway in Task 3.4+).

### Task 3.3: Public `undo()` and `redo()`

**Files:**
- Extend: `event-graph-walker/container/undo.mbt`.

**Signature:** `pub fn Document::undo(self) -> Bool raise DocumentError` and same shape for `redo`. Return `false` on empty stack; return `true` on success. Raise `DocumentError::Internal` only on genuine internal inconsistency (captured snapshot malformed, etc.).

**Intent — execution algorithm (prose; no code):**

1. Pop top group from `undo_stack`. If none, return `false`.
2. Set `undo_execution_mode = true`. Wrap the remainder in a defer-style cleanup that always resets the flag at end.
3. Initialize an empty `redo_items : Array[UndoItem]`.
4. Iterate `group.items` in **reverse order**. For each item:
   - Compute the inverse op from the captured snapshot (see table below).
   - Apply the inverse directly via the low-level helpers: allocate a fresh LV + timestamp via `next_version_with_raw`, build the `@mt.TreeOp` or `TextOp`, call `apply_move_op` / `apply_property_op` / `apply_block_text_op`, then `record_op` / `record_text_op` and `record_sync_tree_op` / `record_sync_text_op`.
   - On success, capture a *redo item* shaped from the snapshot (for a `TextInsert` → redo is also a `TextInsert` with the same LV + content + origin hints captured from the snapshot; for a `TreeMove` → redo is a `TreeMove` with target + new_parent + new_pos from the snapshot). Append to `redo_items`.
   - On raise (e.g., missing LV because the target was remotely trashed beyond recovery), swallow the error and continue — this item is skipped per §10.5.
5. After the loop, if `redo_items.length() > 0`, push `UndoGroup { items: redo_items }` onto `redo_stack`.
6. Reset `undo_execution_mode = false` (via the defer set in step 2).
7. Return `true`.

**Inverse-op table** (from design §6 — restated here for implementation clarity, not as paste-ready code):

| `UndoItem` variant | Inverse to apply during undo | Redo item to stash |
|---|---|---|
| `TextInsert { block, lv, content }` | `TextOp::Delete { target=lv, ts=<new>, agent=self.agent_id }` | `TextInsert { block, lv, content }` — redo revives via `Undelete` which uses lv as target |
| `TextDelete { block, lv, content }` | `TextOp::Undelete { target=lv, ts=<new>, agent=self.agent_id }` | `TextDelete { block, lv, content }` — redo re-tombstones via `Delete` |
| `TreeMove { target, old_parent, old_pos, new_parent, new_pos }` | Move target → old_parent at old_pos | `TreeMove { target, old_parent, old_pos, new_parent, new_pos }` (swap which end we consider "current" per undo/redo direction) |
| `TreeCreate { target, parent, pos }` | Move target → trash | `TreeCreate { target, parent, pos }` — redo moves back out of trash |
| `TreeDelete { target, old_parent, old_pos }` | Move target → old_parent at old_pos | `TreeDelete { target, old_parent, old_pos }` — redo moves back to trash |
| `PropertySet { target, key, old_value, new_value }` | `set_property(target, key, old_value.unwrap_or(""))` | `PropertySet { target, key, old_value, new_value }` |

**Note on redo logic:** for text, redo of `TextInsert` is an `Undelete` targeting the original LV (not a fresh Insert — that would create a new LV and break round-trip). Redo of `TextDelete` is a fresh `Delete` against the same LV (idempotent on fugue LWW). This matches the symmetry: insert/delete/undelete are the three text states, and any undo or redo just switches between them using stable LVs.

`redo()` is the mirror: pop from `redo_stack`, re-emit forward ops, push to `undo_stack`. Same undo-execution-mode flag, same per-item try/catch, never touches `redo_stack` except to pop its own starting group.

- [ ] **Step 1:** Implement `undo()`. Per the design §9: bypass the transaction pipeline, call low-level apply helpers directly, don't touch `undo_stack` or `redo_stack` mid-loop.
- [ ] **Step 2:** Implement `redo()` as the mirror.
- [ ] **Step 3:** `moon check`. Expected: clean.
- [ ] **Step 4:** Verify the `pkg.generated.mbti` now shows eight new public `Document` methods. No other public changes.

### Task 3.4: Hook `insert_text`

**Files:**
- Modify: `event-graph-walker/container/text_ops.mbt:33-60` (the `Document::insert_text` function).

**Intent:** wrap the existing loop body in `self.with_implicit_transaction(fn = () => { ... })`. Inside the per-char loop, *after* `apply_block_text_op`, `record_text_op`, and `record_sync_text_op` all succeed, call `self.record_undo_item(TextInsert { block: id, lv, content: ch.to_string() })`. If `apply_block_text_op` raises (e.g., OOB), the raise propagates out naturally and no undo item is recorded for the failed char (but items already recorded for prior chars stay — this is the "partial group on failure" policy from §9).

**Critical:** do not place the `record_undo_item` call inside `apply_block_text_op` or any shared helper. It lives in the public mutation method per the hook-placement rule (§8).

- [ ] **Step 1:** Add the transaction wrapper and the per-char record call.
- [ ] **Step 2:** Run existing `moon test` — all pre-existing text tests should still pass. If they don't, something broke in the plumbing.

### Task 3.5: Hook `delete_text`

**Files:**
- Modify: `event-graph-walker/container/text_ops.mbt:64-82`.

**Intent:** capture the content of the char at `pos` *before* `apply_block_text_op` runs — use `block.get_visible_items()[pos]` to get the (lv, item) pair, call `item.content` for the string. Wrap the function body in `with_implicit_transaction`. After successful apply + record + sync-record, call `record_undo_item(TextDelete { block: id, lv, content })`.

- [ ] **Step 1:** Add the pre-apply lookup (captures the LV and content before the delete lands).
- [ ] **Step 2:** Wrap in transaction and add the record call.
- [ ] **Step 3:** `moon test`.

### Task 3.6: Hook `replace_text`

**Files:**
- Modify: `event-graph-walker/container/text_ops.mbt:90-106`.

**Intent:** wrap the entire function body in `with_implicit_transaction`. Because `replace_text` calls `delete_text` and `insert_text` internally, and those already open implicit transactions, the flattening in §3 kicks in — the whole replace becomes one group. No per-op record call needed at this layer; it's pure composition.

**Verify:** the flattening actually works by reading Task 2.4's `txn_open` / `txn_close` logic mentally. If depth increments correctly, `replace_text` calling N inner `delete_text`s will result in one outermost commit at depth 1→0.

- [ ] **Step 1:** Wrap the function body.
- [ ] **Step 2:** `moon test`.

### Task 3.7: Hook `move_node`, `move_node_before`, `move_node_after`

**Files:**
- Modify: `event-graph-walker/container/document.mbt:982,994,1007` (three public move methods).

**Intent — per method:**

1. Capture pre-state *before* `emit_move_op`: `old_parent = self.tree.parent(target)`, `old_position = self.tree.get_position(target)`. These lookups are cheap.
2. Wrap the body in `with_implicit_transaction`.
3. After `emit_move_op` returns (it does apply + record + sync-record internally), call `record_undo_item(TreeMove { target, old_parent, old_pos, new_parent, new_pos })`.

For `delete_node` (which is also a Move to trash), do the same but emit `TreeDelete` variant.

For `create_node` and `create_node_after`, emit `TreeCreate` variant — no pre-state to capture (node didn't exist).

- [ ] **Step 1:** Hook `move_node`.
- [ ] **Step 2:** Hook `move_node_after`.
- [ ] **Step 3:** Hook `move_node_before`.
- [ ] **Step 4:** Hook `delete_node`.
- [ ] **Step 5:** Hook `create_node` and `create_node_after`.
- [ ] **Step 6:** `moon test`.

### Task 3.8: Hook `set_property`

**Files:**
- Modify: `event-graph-walker/container/document.mbt:1059-1082`.

**Intent:** `set_property` has silent early-return paths (`if !self.tree.contains(id) { return }`, `catch { _ => return }`). These paths must NOT record undo items — the record call goes at the very end, after the `record_sync_tree_op` call, only on the success path. Capture `old_value = self.get_property(target, key)` before `apply_property_op`. Wrap the whole body in `with_implicit_transaction` (the early returns still exit through the transaction boundary without recording — that's fine).

- [ ] **Step 1:** Add the pre-apply `get_property` lookup.
- [ ] **Step 2:** Wrap in transaction.
- [ ] **Step 3:** Add the `record_undo_item(PropertySet { ... })` call on the success path only.
- [ ] **Step 4:** `moon test`.

### Task 3.9: Blackbox test — implicit per-call grouping

**Files:**
- Extend: `event-graph-walker/container/undo_test.mbt`.

**Test specs (prose):**

- `insert_text(block, 0, "abc")` → `can_undo()` true. `undo()` → `get_text == ""`. Asserts single group for multi-char insert.
- `replace_text(block, "new text")` after pre-seeding block with "old text" → one undo restores "old text". Asserts transaction composition flattens.
- `move_node_before(target, parent, before)` → one undo restores target to old position. Asserts single-op gesture round-trip.
- `delete_node(x)` after x was at old_parent with text content → undo restores x to old_parent *and* text is still there (descendants invariant from §10.6).
- Each test also asserts `can_redo()` becomes true after undo.

- [ ] **Step 1:** Write four tests (one per gesture class).
- [ ] **Step 2:** `moon test`. Expected: all pass.

### Task 3.10: Blackbox test — explicit composition and nested flattening

**Test specs (prose):**

- `doc.transaction(fn = () => { doc.delete_node(x); doc.create_node_after(parent=y, after=z); doc.insert_text(new_block, 0, "hi") })` → one undo reverts all three. Asserts explicit composition forms one group.
- Nested: `doc.transaction(fn = () => doc.insert_text(block, 0, "a"))` → single group (inner implicit txn flattens into outer explicit txn). Assert exactly one group on the stack, not two.
- Empty transaction: `doc.transaction(fn = () => ())` → `can_undo()` stays `false`. Asserts empty-group skip.

- [ ] **Step 1:** Write the three tests.
- [ ] **Step 2:** `moon test`.

### Task 3.11: Blackbox test — redo round-trip and redo-cleared-on-new-edit

**Test specs (prose):**

- `insert_text("h") → undo → redo`: final state identical to post-insert. `can_redo()` false after redo, `can_undo()` true.
- `insert_text("h") → undo → insert_text("x")`: `can_redo()` is `false` (new commit cleared redo stack). Asserts §9 commit path.
- Stable LVs: after an insert+undo+redo cycle, the visible item's LV equals the original (test via an internal hook — either a `Document::debug_text_lvs` helper promoted to `pub(all)` for tests or a whitebox test).

- [ ] **Step 1:** Write the three tests.
- [ ] **Step 2:** `moon test`.

### Task 3.12: Blackbox test — tracking suppression

**Test specs (prose):**

- `set_tracking(false) → insert_text("h") → can_undo() == false`. Assert the op still applied (text contains "h", sync has the op).
- `set_tracking(false) → mutate → set_tracking(true) → mutate → undo`: first mutation is not undoable, second is.

- [ ] **Step 1:** Write both tests.
- [ ] **Step 2:** `moon test`.

### Task 3.13: Phase 3 green, format, commit

- [ ] **Step 1:** Full `moon test && moon check && moon info && moon fmt`.
- [ ] **Step 2:** Review `git diff event-graph-walker/container/pkg.generated.mbti`. Expected: exactly the eight new public methods from Task 3.1–3.3. No trait bound changes to existing methods. No accidental `pub` on internal helpers.
- [ ] **Step 3:** Commit: `feat(container): undo/redo public API with per-method hooks`. Cite §3, §8, §9 of the design doc.

---

## Phase 4 — Convergence and concurrency

**Goal:** assert the three worked scenarios from design §5 and the edge cases from §10 via blackbox tests that exercise real `SyncMessage` flows.

**Invariant this phase must preserve:** no implementation changes. This is pure test coverage. If any test fails, the failure indicates a bug in Phase 1–3 that must be fixed.

**Design sections exercised:** §5 convergence, §10 tricky corners, §12 testing strategy.

### Task 4.1: Scenario §5.1 — undo doesn't clobber peer edits

**Files:**
- Extend: `event-graph-walker/container/undo_test.mbt`.

**Test spec (prose):**

Alice and Bob each start with one shared block. Alice `insert_text("hello")` in block. Sync Alice → Bob. Bob `insert_text("world")` at position 5 (right after "hello"). Sync Bob → Alice. Alice `undo()` (undoes her "hello"). Sync Alice → Bob. Assert both final texts are `"world"`. Assert `SyncReport.pending_ops == 0` on both ends after every sync call.

- [ ] **Step 1:** Write the test.
- [ ] **Step 2:** `moon test`. Expected: pass. If not, Alice's undo is generating ops that affect Bob's LVs — that would indicate a bug in the inverse-op construction for text-insert.

### Task 4.2: Scenario §5.2 — undo of delete_node preserves concurrent peer text

**Test spec (prose):**

Alice and Bob share one block X with text "abc". Alice `delete_node(X)` (moves X to trash). Concurrently (no sync yet), Bob `insert_text(X, 1, "Z")` → text in X becomes "aZbc" in Bob's view (but X is still live in Bob's view since he hasn't received the delete). Now sync both ways. Alice `undo()` (restores X to its original parent). Sync Alice → Bob. Assert block X is live on both sides, contains "aZbc", and is attached to the original parent at the original position. Assert `SyncReport.pending_ops == 0`.

- [ ] **Step 1:** Write the test.
- [ ] **Step 2:** `moon test`.

### Task 4.3: Scenario §5.3 — concurrent moves with undo

**Test spec (prose):**

Alice and Bob share the tree `root → {X, P1, P2, P3}`. Alice `move_node(target=X, new_parent=P2)`. Concurrently, Bob `move_node(target=X, new_parent=P3)`. Sync both ways. LWW (or whatever movable-tree conflict rule is in effect) picks one winner — observe which. Alice `undo()` — emits an inverse `Move(X, root, <old_pos>)`. Sync. Assert Alice's final tree has X under root (her undo's intent), and Bob's final tree matches (LWW or replay semantics — document whichever outcome is correct given the conflict rule). Assert `SyncReport.pending_ops == 0`.

**Note:** this test's exact expected outcome depends on movable-tree conflict semantics. Read `internal/movable_tree/conflict.mbt` before writing assertions — do not guess.

- [ ] **Step 1:** Read the movable-tree conflict rules.
- [ ] **Step 2:** Write the test with accurate expected values.
- [ ] **Step 3:** `moon test`.

### Task 4.4: Undelete LWW — later Delete beats earlier Undelete

**Test spec (prose):**

Two replicas, shared block with one char "x" (lv=L). Replica A: locally `delete_text(block, 0)` at `ts=5` (via the container's normal flow). Sync A → B. B receives Delete. B does NOT delete locally. B now does `doc.transaction(() => doc.insert_text(block, 0, "x_extra"))` — this gives us a baseline. Now, simulate an undo-delete: **this is hard to synthesize naturally because "undo a remote delete" isn't a thing** — per §4, only local ops are recorded. So this test must instead exercise: local Insert → local Delete → local Undo (which emits Undelete at high ts). Then a remote Delete at even higher ts arrives. Assert item ends up deleted on both sides.

**Reframe:** replica A inserts "x" at ts=1, deletes at ts=5, then undoes (emitting Undelete at ts=10). Meanwhile replica B concurrently issues a Delete at ts=15 (higher than A's Undelete) via a direct `delete_text` call. Sync both ways. Final state on both replicas: item deleted. Assert.

- [ ] **Step 1:** Write the test, carefully setting up the timestamps to hit the LWW ordering.
- [ ] **Step 2:** `moon test`. Expected: pass. Failure = Undelete is force-reviving.

### Task 4.5: Undelete tie-break — add-wins

**Test spec (prose):**

Replica A: `insert "x"` at ts=1, `delete` at ts=5, undo (emits `Undelete ts=10`). Replica B: receives the insert, then issues `delete` at ts=10 locally (same ts as A's Undelete). Sync. Expected final state on both: item **visible** (Undelete wins the tie per `should_win_delete`).

- [ ] **Step 1:** Write the test.
- [ ] **Step 2:** `moon test`.

### Task 4.6: Pending-queue flush after local undo

**Test spec (prose):**

Alice creates block X and inserts "hi" into it. Alice exports a `SyncMessage` (Bob will receive later). Alice does `delete_node(X)` then `undo()`. Now Alice exports a second `SyncMessage` — this contains: X-create, text inserts, delete-X move, and undo's inverse move. Bob receives this second SyncMessage. Due to causal ordering, some ops may land in `pending_sync_ops`. Bob then receives the first SyncMessage (or not — the second should be self-contained). Assert: Bob's final state matches Alice's (X live, contains "hi"), and `SyncReport.pending_ops == 0` after Bob's final flush.

- [ ] **Step 1:** Write the test.
- [ ] **Step 2:** `moon test`.

### Task 4.7: Property undo — prior value and absent-key cases

**Test specs (prose):**

- Prior value: `set_property(x, "type", "paragraph")`, `set_property(x, "type", "heading")`, undo → `get_property(x, "type") == Some("paragraph")`.
- Absent key: `set_property(x, "foo", "bar")` where x had no "foo" before, undo → `get_property(x, "foo") == Some("")`. Both the round-trip and the known non-invertibility are asserted — this test locks in the §11 limitation so it doesn't silently regress.

- [ ] **Step 1:** Write both tests.
- [ ] **Step 2:** `moon test`.

### Task 4.8: Remote ops never recorded

**Test spec (prose):**

Replica A mutates (insert_text, move_node, set_property). Exports a SyncMessage. Replica B (fresh Document) applies the SyncMessage. Assert `B.can_undo() == false`. Assert `B.undo()` returns `false` and state is unchanged.

- [ ] **Step 1:** Write the test.
- [ ] **Step 2:** `moon test`.

### Task 4.9: Phase 4 green, format, commit

- [ ] **Step 1:** `moon test && moon check && moon info && moon fmt`.
- [ ] **Step 2:** Commit: `test(container): convergence and concurrency coverage for undo grouping`. Cite §5, §10, §12.

---

## Phase 5 — Final verification and PR prep

### Task 5.1: `.mbti` diff review

- [ ] **Step 1:** `cd event-graph-walker && moon info`.
- [ ] **Step 2:** `git diff container/pkg.generated.mbti`. Expected additions: eight public `Document` methods (transaction, undo, redo, can_undo, can_redo, clear_undo, set_tracking, is_tracking), one new enum variant (`TextOp::Undelete`), one new struct (`TextUndeleteOp`). **Expected removals or changes to existing signatures: zero.** Any change to existing API is a regression to investigate.

### Task 5.2: /simplify review

Per CLAUDE.md algorithm process rule, run the `/simplify` skill across the new code to catch redundancy, missed reuse, or inefficiency before PR.

- [ ] **Step 1:** Invoke `/simplify` over the modified files.
- [ ] **Step 2:** Apply its findings if they're correct. If any finding conflicts with the design doc, skip and note.

### Task 5.3: Codex post-implementation review

Per CLAUDE.md algorithm process rule, Codex review before PR for interaction effects and efficiency.

- [ ] **Step 1:** Ask Codex to review the diff for: (a) any correctness regressions in existing tests; (b) hidden performance costs in the hook layer; (c) edge cases not covered by tests.
- [ ] **Step 2:** Fold material findings into a follow-up commit.

### Task 5.4: Push submodule and open canopy PR

- [ ] **Step 1:** **Ask the user** before pushing the submodule or opening the PR.
- [ ] **Step 2:** If approved: push `feat/container-undo-grouping` branch on the event-graph-walker submodule. Open a PR on the submodule repo first. Wait for CI.
- [ ] **Step 3:** Once submodule PR is mergeable, bump the submodule pointer in canopy and open the canopy-side PR referencing the submodule PR.

---

## Rollback plan

If a phase commits something that later turns out wrong, the rollback granularity is one commit per phase. The branch is linear; `git revert` on a phase's commit rolls back the whole phase cleanly.

If Phase 1's `TextOp::Undelete` wire change has an issue that only surfaces during Phase 3 integration, revert Phases 2–3 first, fix Phase 1, then re-do Phases 2–3. The commits are deliberately structured so this is possible.

---

## What this plan intentionally does not do

- **No block-editor integration.** The block editor gets a separate follow-up ticket. This plan produces only the container-level API.
- **No typing coalescing.** Cut in Phase 0 (design) per Codex review; not reintroduced here.
- **No `RemoveProperty` op variant.** Property None-vs-"" asymmetry is accepted as a v1 limitation, tested and documented via Task 4.7.
- **No FFI exposure.** The MoonBit API ships; JS FFI is follow-up.
- **No subagent dispatch during Phases 1, 3, or 4.** Algorithm-heavy phases stay in main context per CLAUDE.md algorithm process rule. Phase 2 (data-structure scaffolding) and Phase 5 (mechanical verification) are subagent-eligible but small enough to do inline.
