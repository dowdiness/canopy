# Container Undo Grouping — Design

**Status:** Design (Codex-reviewed 2026-04-17, coalesce_key cut, awaiting user sign-off before commit + implementation plan)
**Scope:** `event-graph-walker/container/` (the `Document` CRDT)
**Depends on:** SyncReport API (egw #26, landed 2026-04-17)
**Unblocks:** Drag-drop undo, block-editor undo, replace_text atomicity

## 1. Problem

`@container.Document` today has no undo. Every public mutation
(`insert_text`, `delete_text`, `replace_text`, `move_node_*`, `create_node*`,
`delete_node`, `set_property`) commits immediately; a user gesture that
internally emits N ops (multi-char paste = N inserts, `replace_text` = N
deletes + M inserts, block split = delete + create + insert) has no atomic
revert.

Goal: a single user gesture undoes as one atomic group, in a way that
preserves CRDT convergence and does not pollute the wire protocol with
group metadata.

## 2. Model: inverse-op replay (Model I)

Undo is not state rewinding; it is *new intentional ops that compensate
for prior ops*. The CRDT only sees ops. The undo stack is a layer above.

Rejected alternatives:

- **Snapshot + roll-forward.** Rewinds past remote work. Breaks collab.
- **Retreat flags in the wire protocol** (Automerge / eg-walker paper).
  Requires wire-format changes and new conflict rules for concurrent
  undo/redo. Not justified by any requirement here.

**Committing to Model I** because:

1. Zero wire-protocol pressure for grouping — groups are session-local
   metadata and never hit the network.
2. Exactly one additive wire change: `TextOp::Undelete`. The fugue layer
   already supports tombstone revival (`FugueTree::undelete`).
3. Peer convergence is "more ops arrived" — inherits existing CRDT
   correctness.
4. Redo stability comes from stable LVs plus `Undelete`.

## 3. Grouping: transactions as the single primitive

One mechanism, not three. Every local mutation runs inside a *transaction*;
ops emitted during a transaction share a group id. All other grouping
behaviors are expressed as transactions with different boundary policies.

```
Document::transaction(Self, fn : () -> T raise E) -> T raise E
```

### Boundary policies

- **Implicit per-call.** Each public mutation opens an implicit
  transaction if none is active and commits it on return. Delivers
  "paste = one group" and "replace_text = one group" without caller
  discipline.
- **Explicit composition.** `doc.transaction(fn = () => { ... })`
  merges multiple mutation calls into one group. Required for block
  split / join / indent / outdent and any future N-primitive gesture.
- **Nested transactions flatten.** Depth counter, not a stack. Only
  the outermost commit pushes a group. Inner calls piggyback.

### Why this shape

- Per-call-only grouping cannot express split / join / indent; those
  are genuinely N-primitive gestures.
- Explicit-only grouping pushes too much discipline onto every caller;
  missed wrapping turns paste into per-char undo (terrible UX).

Implicit-per-call + explicit composition is the minimum that covers
every gesture class that the container can identify on its own.

### What about typing (consecutive keystrokes)?

Typing is the one gesture class the container cannot identify, because
each keystroke is a separate `insert_text` call and from the
container's point of view looks identical to any other single-char
insert. In v1, **typing coalescing is editor-layer policy**, not a
container mechanism. A block editor that wants "one undo reverts the
whole word I just typed" has two clean choices:

1. Buffer keystrokes at the editor layer and flush as a single
   `insert_text("hello")` call on focus change / selection change /
   Enter / timeout.
2. Wrap a run of keystrokes in an explicit `transaction(fn)` at the
   editor layer, re-using the same transaction object across
   consecutive keydown events until a boundary signal fires.

An earlier draft of this design exposed a container-level
`coalesce_key` + `coalesce_timeout_ms` hint that would append a closed
transaction's ops to the previous group under a matching key and time
window. Cut for v1 because (a) it mutates an already-closed stack
entry, which adds non-trivial invariants around undo execution and
commit ordering, (b) the editor has strictly more information than a
time window (focus changes, selection moves, Enter key), and (c) the
mechanism can be added later without breaking the v1 API. See §11.

## 4. Ownership: per-replica, session-local

- Undo state lives on the `Document` instance, not in the replicated CRDT.
- Two tabs by the same user = two independent stacks.
- Document reload = empty stack.
- Remote ops (via `apply_remote_op`, `apply_remote_text_op`,
  `apply_remote_sync_message`) are **never** recorded. This is a structural
  guarantee: remote-op application goes through a different code path that
  does not touch the transaction machinery. No filtering needed.

## 5. Convergence: inherit existing CRDT semantics

Because inverse ops are normal ops, there is no new convergence story.
Three worked scenarios:

- **Alice undoes "hello" while Bob typed " world" after it.** Alice's undo
  emits 5 `Delete` ops targeting her tombstone LVs. They merge with Bob's
  inserts; result: " world". ✓
- **Alice `delete_node`s block X while Bob edits X's text concurrently.**
  Alice's undo emits an inverse `Move(X, old_parent, old_position)`. Bob's
  text edits landed in the fugue tree regardless of X's tree location. Undo
  restores X with Bob's edits present. ✓
- **Alice moves X P1→P2 while Bob moves X P1→P3 concurrently.** Whoever
  loses movable-tree LWW on the forward ops has their intent lost — that is
  a pre-existing property of this CRDT, not an undo concern. Alice's undo
  emits `Move(X, P1, old_pos)`; it merges via the same LWW rule.

**Concurrent text `Delete` vs `Undelete`: LWW by timestamp, add-wins
on ties.** The Fugue layer already implements exactly this rule in
`FugueTree::delete_with_ts` / `undelete_with_ts`
(`event-graph-walker/internal/fugue/tree.mbt:211,245`), using a shared
`should_win_delete` predicate that keeps the higher-timestamp side, and
on equal timestamps prefers `Undelete` (then tie-breaks on agent). The
earlier claim in this doc that concurrent Delete/Undelete is
"unconditionally add-wins" was wrong — **a later `Delete` beats an
earlier `Undelete`**. This means a remote peer's newer deletion will
override a local user's older undo of their own delete, which matches
user expectation that "the latest edit wins." The user-surprising case
is only the tie: same timestamp, different agents — and that is already
how the Fugue layer behaves in other contexts.

## 6. Captured undo metadata (per op)

Each item in a group stores what's needed to construct the inverse op.
For tree ops, pre-state is read from the tree *before* `apply_move_op`.
For text deletes, the deleted char's content and LV are looked up
*before* applying the delete.

| Forward op                        | Captured snapshot                       | Undo emits                                | Redo emits                      |
|-----------------------------------|-----------------------------------------|-------------------------------------------|---------------------------------|
| `Move(t, new_parent, new_pos)` (reparent) | `old_parent`, `old_position` (read from tree before `apply_move_op`) | `Move(t, old_parent, old_pos)` | `Move(t, new_parent, new_pos)` |
| `Move(new_id, parent, pos)` (from `create_node*`) | `new_id`, `parent`, `pos`; no pre-state (node didn't exist) | `Move(new_id, trash, trash_pos)` | `Move(new_id, parent, pos)` |
| `Move(t, trash, _)` (from `delete_node`) | pre-trash `old_parent`, `old_position` | `Move(t, old_parent, old_pos)` | `Move(t, trash, trash_pos)` |
| `SetProperty(t, key, new_val)`    | `old_value : String?` (absent = None)   | `SetProperty(t, key, old_val ?? "")` *(see caveat below)* | `SetProperty(t, key, new_val)` |
| `TextOp::Insert{id=lv, content}`  | `block`, `lv`, `content`                | `TextOp::Delete{target=lv}`               | `TextOp::Undelete{target=lv}`   |
| `TextOp::Delete{target=lv}`       | `block`, `lv`, `content` (pre-delete)   | `TextOp::Undelete{target=lv}`             | `TextOp::Delete{target=lv}`     |

All three tree-op rows are structurally the same: capture forward target + parent + position, and if the forward op had a non-null pre-state (reparent / delete), capture that too. The three rows are split only to document which public method each row corresponds to.

Both stacks hold `UndoGroup` values with these snapshots. Redo entries are
populated at undo time with fresh snapshots so round-trip (undo → redo →
undo) is stable.

**Property undo caveat (v1):** Clearing a previously-absent property maps
to `SetProperty(t, key, "")` since there is no `RemoveProperty` op variant.
Document this limitation; revisit if an editor needs true property
absence.

## 7. Wire-protocol delta

**Only one additive change:**

```moonbit
pub(all) struct TextUndeleteOp {
  target : Int
  timestamp : Int
  agent : String
}

pub(all) enum TextOp {
  Insert(TextInsertOp)
  Delete(TextDeleteOp)
  Undelete(TextUndeleteOp)   // NEW
}
```

`TextBlock::apply_op` gains an `Undelete` arm that calls
`self.tree.undelete_with_ts(Lv(target), timestamp, agent)`
(`event-graph-walker/internal/fugue/tree.mbt:245`) — *not* plain
`tree.undelete`. The `_with_ts` form is mandatory: it goes through
`should_win_delete`, which is what preserves convergence under
concurrent Delete/Undelete. Naive `tree.undelete` force-revives the
tombstone with no LWW and causes replica divergence when the two sides
observe the ops in different orders.

Routing through `BlockTextOp`, `VersionedBlockTextOp`, dedup, sync, and
pending-queues is unchanged; `Undelete` rides the existing text-op
pipeline. `text_op_timestamp` and `text_op_agent` helpers
(`event-graph-walker/container/document.mbt:136,144`) need an `Undelete`
arm, and the dedup key in `text_op_key`
(`event-graph-walker/container/document.mbt:263`) needs an
`"text-undelete|..."` arm.

**No changes to tree ops.** `Move` is self-inverse at the schema level;
`SetProperty` is overwrite-based.

**No group id on the wire.** Peers never see groups.

## 8. Public API surface

All additions. No breaking changes to existing methods.

```
// Transactions — exact MoonBit signature pinned during implementation.
// Intent: take a closure and (optionally) a coalesce_key + timeout;
// return the closure's result; propagate the closure's error.
Document::transaction(Self,
                      fn : () -> T raise E) -> T raise E

// Undo / redo
Document::undo(Self) -> Bool raise DocumentError     // false if stack empty
Document::redo(Self) -> Bool raise DocumentError
Document::can_undo(Self) -> Bool
Document::can_redo(Self) -> Bool
Document::clear_undo(Self) -> Unit

// Tracking control (public — for callers' programmatic mutations
// that shouldn't enter the undo stack, e.g. initial load / migrations).
// Distinct from the internal suppression used during undo / redo
// execution, which is stack-scoped and not user-visible.
Document::set_tracking(Self, Bool) -> Unit
Document::is_tracking(Self) -> Bool
```

The exact closure / error form (generic parameters, `raise` propagation,
captured-environment constraints) is pinned at implementation time; the
signature above captures intent. If MoonBit limitations force a narrower
shape (e.g. `raise DocumentError` only), that is an acceptable v1
constraint and will be noted in the implementation plan.

### Internal hooks

Existing mutation methods gain internal wiring:

1. Wrap body in `self.with_implicit_transaction(fn)` — opens a
   transaction if none is active, commits at return.
2. For each sub-op:
   - **Snapshot pre-state before apply.** Read `tree.parent(target)`,
     `tree.get_position(target)`, or `block.get_visible_items()[pos]`
     content into a local variable *before* calling `apply_move_op` /
     `apply_property_op` / `apply_block_text_op`.
   - **Apply the op.** If this raises (e.g., `make_delete_op_at` OOB at
     `event-graph-walker/container/text_block.mbt:79`) or silently
     returns (e.g., `set_property` early-return at
     `event-graph-walker/container/document.mbt:1058`), **do not record
     an undo item.** The undo stack must only reflect work that actually
     happened.
   - **Record the undo item only after successful apply + sync-op
     recording.** This matches egw's prior-art pattern in
     `event-graph-walker/undo/undo_manager.mbt` (capture then act).

**Hook placement.** Recording happens inside each *public mutation
method*, never inside the shared `apply_move_op` / `apply_property_op` /
`apply_block_text_op` helpers. Those helpers are also used by remote-op
paths (`apply_remote_op` at `document.mbt:1133`,
`try_apply_versioned_tree_op` at `document.mbt:511`, etc.), and
recording at the shared layer would taint the local undo stack with
remote work. Placement at the public-method layer is the structural
guarantee named in §4 ("remote ops are never recorded").

A new private `Document::record_undo_item(item : UndoItem) -> Unit`
writes to the transaction buffer if public tracking is on, no internal
undo execution is in progress, and a transaction is active; otherwise
no-op.

## 9. Execution semantics

### Transaction commit

1. Close active transaction; gather its `UndoItem`s.
2. Push them as a new `UndoGroup` onto the undo stack. If the group
   has zero items (the transaction's fn made no mutations, or all of
   them were rejected / silently no-op'd), skip the push entirely —
   empty groups are a user-hostile footgun.
3. Clear the redo stack (standard editor semantics: any new committed
   work invalidates redo).

The commit path is the ONLY place that clears the redo stack and the
ONLY place that pushes to the undo stack during normal user mutation.
Undo and redo execution (below) have their own stack-touching code
path and do not go through commit.

### Undo

Undo and redo do **not** go through `transaction(fn)` or the commit
pipeline. They have their own code path, because:

- The commit pipeline clears the redo stack on every commit; if undo's
  inverse ops went through normal commits, the first inverse-op commit
  would wipe the redo stack that undo is still building.
- Coalescing must be off during undo execution — we don't want inverse
  ops merging with whatever the last coalesce key was.

Undo code path:

1. Pop top group from undo stack. If empty, return `false`.
2. Enter "undo execution mode" — a stack-internal flag distinct from
   the public `set_tracking` boolean. Two independent gates: undo
   records an item iff *both* public tracking is on *and*
   undo-execution-mode is off. During undo/redo execution,
   undo-execution-mode is set so the inverse ops we emit do not get
   recorded as new groups. Guard/defer so the flag is always cleared,
   even on failure.
3. For each item in **reverse order**, call the same low-level apply
   helpers that the public mutation methods call (`apply_move_op`,
   `apply_property_op`, `apply_block_text_op`) plus the op-recording
   and sync-recording calls, **bypassing the public-method undo-hook
   layer** (because we're in undo-execution-mode). Per-item try/catch:
   skip items whose targets have vanished rather than abort the whole
   group.
4. For each successfully-applied inverse op, capture a fresh snapshot
   (the forward-direction info needed to redo it) into a growing redo
   group. Never push mid-loop; push once at the end so a mid-undo
   failure doesn't leave a half-built redo group visible.
5. After the loop, push the redo group. Exit undo execution mode.
   Return `true`.

Redo is the mirror image. It does not clear the undo stack; successful
redo pushes a fresh undo group (the redo group's own inverses).

### Redo

Mirror of undo: pop from redo stack, apply forward ops using the snapshot
captured at undo time, push a new undo group with inverses.

### Partial failure

If a mutation fn inside `transaction(fn)` raises mid-way, ops that
already hit the oplog remain committed. Policy: **whatever *applied and
recorded successfully* stays in the group.** Items for which the forward
op raised or silently no-op'd (e.g., `set_property` early-return) are
*not* recorded — see §8 internal hooks. Undo on the resulting group
reverts exactly the sub-ops that really happened, not phantom ones.

True buffered atomicity (hold ops in a staging area, flush on commit) is
rejected for v1: bloats memory for long transactions with no clear
requirement driving it.

### Remote ops inside a local transaction

Not possible under the Document's single-threaded assumption —
`apply_remote_*` is only invoked between gestures, never during
transaction execution. Not a concern for v1.

## 10. Tricky corners — explicit takes

1. **Transaction fn raises** → partial group recorded (see §9). Document.
2. **Nested transactions** → flatten by depth counter. Only depth-0 commit
   pushes a group.
3. **Tracking disabled** → mutations still emit CRDT ops (sync requires
   it); no undo items recorded. Used for initial load, migrations,
   programmatic imports.
4. **Peer ops arrive between undo and redo** → redo still works because
   text uses stable LVs + `Undelete`, and tree redo uses the snapshot
   captured at undo time.
5. **Undo where some targets were remotely deleted / GC'd** → per-item
   try/catch; skip the failed items, keep the rest.
6. **`delete_node` of a subtree** → undo restores only the root's
   parent/position. Descendants stay as they were (they were never
   moved). Correct: movable_tree's `delete_node` only moves the root to
   trash. Consequence: undoing `delete_node` revives the **entire
   subtree, including any descendants that were added under the root
   while it was in the trash**. This is safe and convergent (the
   additions are ordinary Move ops applied independently of the trash
   location), and it matches reasonable user expectation, but it is
   observable and worth naming.
7. **Tree undo when `old_parent` is now dead.** If the captured
   `old_parent` has itself been `delete_node`d by the time the user
   undoes, the public mutation API would reject the inverse move (see
   `is_local_parent_valid` / `validate_move` at `document.mbt:758,942`).
   Undo must bypass that validation — the inverse op goes through the
   low-level `emit_move_op`-equivalent path the same way `apply_remote_op`
   does, so a dangling-or-trashed parent resolves to "the node is
   restored into the trashed subtree of its former parent," matching the
   movable-tree CRDT's replay semantics
   (`internal/movable_tree/conflict.mbt:145`). This is a deliberate
   asymmetry: public API rejects dead parents *for local-intent
   operations*; undo replays captured history and does not.

## 11. Explicitly NOT in v1

- Document-shared undo history. (Rejected at the model level.)
- Group serialization or cross-session persistence.
- Selective undo (skip a middle group). Stack-only, top-of-stack only.
- Compaction / GC of undone groups once their LVs are GC'd. (LVs
  aren't GC'd yet.)
- **`RemoveProperty` op variant — and the property-undo
  non-invertibility that goes with it.** `Document::get_property`
  publicly distinguishes `None` (absent) from `Some("")` (empty
  string), but `set_property` takes only `String`, so v1 property undo
  of "None → set('x')" produces `Some("")` rather than restoring
  `None`. **This is a real semantic asymmetry, not merely a caveat.**
  Block editor consumers must either (a) treat `""` as absence at
  their layer (the current `block_doc.mbt` pattern of defaulting
  unset fields is fine), or (b) never rely on round-tripping a
  property through `set_property → undo` to recover `None`. Fix path
  for a future release: add `Document::remove_property` plus a
  `SetProperty(_, key, None)`-equivalent op variant, which lets undo
  capture `old_val : String?` and emit either a set or a remove. Out
  of scope for v1 because no current consumer observes the
  difference.
- **Container-level coalesce_key / coalesce_timeout_ms hint.** Cut
  after Codex review — the mechanism would mutate an already-closed
  stack entry, adding non-trivial invariants around undo execution and
  commit ordering, and the editor layer has strictly more information
  than a time window (focus changes, selection moves, Enter key). See
  §3 "What about typing" for the editor-side workarounds available
  today. Re-introduction requires a follow-up design pass; the v1 API
  is forward-compatible with later addition.
- FFI exposure. Ship the MoonBit API; JS FFI is a follow-up.
- Block-editor integration (typing coalescing policy, keyboard
  bindings, toolbar buttons). Separate ticket; this design ships only
  the container mechanism.

## 12. Testing strategy (sketch — elaborated in the implementation plan)

Each test class exercises one invariant:

- **Implicit grouping.** `insert_text("abc")` → one undo pops all three
  chars. `replace_text` → one undo restores the prior text.
- **Explicit grouping.** `doc.transaction(fn = () => { delete; insert;
  move })` → one undo reverts all three.
- **Nested flattening.** Outer transaction wrapping a mutation → same
  group.
- **Redo round-trip.** Insert → undo → redo → text identical, LVs
  stable for redoable ops.
- **Convergence under concurrent edits.** The three scenarios from §5,
  asserted via `SyncReport.pending_ops == 0` and expected end-states.
- **Tracking suppression.** `set_tracking(false)` → mutation emits op,
  undo stack empty.
- **Partial failure.** Transaction raising mid-way → partial group
  recorded; undo reverts the partial state.
- **Empty stack.** `undo()` / `redo()` returns `false`, no-op.
- **Redo cleared on new edit.** Undo, then a new mutation → redo stack
  empty.
- **Property undo.** SetProperty on a previously-set key → undo
  reverts to prior value. SetProperty on a previously-absent key →
  undo sets to `""` (documented limitation, §11). Both paths covered
  so the non-invertible case doesn't silently regress.
- **Undelete LWW.** Concurrent `Delete(ts=10)` + `Undelete(ts=10)`
  (tie) → add-wins. `Delete(ts=11)` arriving after a local
  `Undelete(ts=10)` → item stays deleted. Both orderings tested to
  assert convergence across replicas.
- **Empty transaction.** `doc.transaction(fn = () => ())` → no group
  pushed, undo stack unchanged.
- **Remote ops never recorded.** Apply a remote SyncMessage containing
  inserts + moves; undo stack is unchanged.
- **Pending-queue flush after local undo.** Local mutation, local
  undo, then a remote SyncMessage whose ops were previously queued in
  `pending_sync_ops` arrives and flushes: final state is convergent
  with a peer that saw the ops in arrival order, and `SyncReport`
  shows the expected applied/pending counts.

## 13. File impact (rough)

| File                                              | Action   | Approx. |
|---------------------------------------------------|----------|---------|
| `event-graph-walker/container/undo.mbt`           | new      | ~250 LOC|
| `event-graph-walker/container/undo_types.mbt`     | new      | ~60 LOC |
| `event-graph-walker/container/undo_test.mbt`      | new      | ~350 LOC|
| `event-graph-walker/container/document.mbt`       | modify   | +~80 LOC (internal hooks, public API re-exports)|
| `event-graph-walker/container/text_block.mbt`     | modify   | +~15 LOC (`Undelete` arm in `apply_op`)|
| `event-graph-walker/container/text_ops.mbt`       | modify   | +~10 LOC (enum widening, dedup key)|
| `event-graph-walker/container/errors.mbt`         | modify   | +~5 LOC  (new error variants if any)|
| `event-graph-walker/container/pkg.generated.mbti` | regen    | via `moon info`|

No changes outside `container/`. No changes to `internal/movable_tree/`,
`internal/fugue/`, or sync infrastructure.

## 14. Codex review outcomes

Codex reviewed an earlier draft of this design on 2026-04-17. Verdict
was "revise"; the following material issues were raised and have since
been folded into the sections cited:

1. **Fugue `undelete` must be LWW-aware.** Original §7 called plain
   `tree.undelete`, which force-revives without timestamp comparison
   and diverges under concurrent Delete/Undelete ordering. Fixed: §5,
   §7 now mandate `undelete_with_ts` and document the real
   LWW-by-timestamp + add-wins-on-ties rule.
2. **Property None-vs-"" is an observable semantic asymmetry, not a
   caveat.** Fixed: §11 promotes this to a named v1 limitation with an
   explicit fix-forward plan (`RemoveProperty` op variant).
3. **Undo/redo must bypass the transaction commit pipeline.** Original
   §9 implied inverse ops went through normal commits, which would
   wipe the redo stack mid-loop. Fixed: §9 "Undo code path" section
   explicitly calls low-level apply helpers and does not touch stacks
   mid-loop.
4. **Record only after successful apply + sync-op record, not
   before.** `make_delete_op_at` can OOB, `set_property` can silently
   early-return — recording before apply would invent phantom undo
   items. Fixed: §8 internal hooks.
5. **Hook placement at public mutation methods, not shared apply
   helpers.** The shared helpers are also used by remote-op paths;
   hooking there would taint the local undo stack with remote work.
   Fixed: §8 "Hook placement" subsection.
6. **`delete_node` subtree revival + dead-`old_parent` undo
   behavior.** Documented as §10.6 and §10.7 respectively.

Settled questions from the original review (no spec change needed):

- Partial-group-on-failure — "whatever *applied and recorded
  successfully* stays in the group" is the honest rule (narrowed from
  the original "whatever succeeded"). §9 reflects this.
- Coalesce-key stack mutation concerns — moot, because the feature was
  cut for v1 (§11).
- `create_node` undo racing concurrent children under the created
  node — safe; additions become children in the trash subtree.
- `pending_sync_ops` interaction — none; undo uses local captured
  state. Test should still include "local undo then queued remote ops
  flush" to pin the invariant (§12 will incorporate).
