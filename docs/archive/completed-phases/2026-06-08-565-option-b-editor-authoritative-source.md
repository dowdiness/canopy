# #565 Option (b): editor-authoritative source, no caller rollback

**Status:** Implemented (Codex-validated design: SOUND-WITH-CAVEATS; pre-PR review PASS after a dirty-flag fix).
**Supersedes:** the `model.dirty` whole-source recovery branch shipped in `990256c`.

## Problem (from /code-review of PR #570)

Three confirmed findings share one root cause — the adapter rebases CodeMirror
deltas onto `SourceBackedGraph.source`, which can diverge from the editor's
actual buffer:

- **P1 / dirty recovery:** on a rejected edit, `apply_codemirror_changes`
  rolls the graph back (`self.source = old_source; attachment.set_source(old_source)`)
  while CodeMirror keeps the user's text. The next delta (editor coordinates)
  is spliced onto last-good → corruption (`220Hz` → `220Hz440Hz`). The shipped
  `990256c` fix recovers via whole-source reparse, but that **churns node
  identity — the exact property #565 exists to preserve.**
- **#1 stale-editor window:** TS-side ops (inspector rename/param, canvas
  delete/connect via `apply_source_graph_operation`) mutate `self.source` but
  do not update the editor (the removed `syncSourceEditorFromResult`); only the
  250 ms poll syncs it. Typing in that window rebases stale-buffer deltas onto
  the mutated source → corruption.
- **#3 inconsistent rollback:** `set_source_graph_source_checked` does **not**
  roll back on parse failure (leaves `self.source` = invalid text), while
  `apply_codemirror_changes` does. The two source-mutation paths disagree.

## Key facts established by reading the code

- `GraphAttachment` (loom `examples/graph-dsl/src/attachment.mbt`) keeps
  `current_source` even when the parse fails (`apply_edit`/`set_source` never
  roll back internally); on failure it sets `state=…Blocked`, `current=Err`,
  but retains the previous `last_good : GraphDoc?`.
- `source_graph_doc_for_render` already renders `current_result()` when `Ok`,
  else `last_good()` — so an invalid `current_source` does not break rendering.
- The identity tracker (`ProjectionIdentityTracker`) has
  `record_failed_input_with_optional_edit` (called on parse failure) and
  `realign_success_with_optional_edit` (called on the next success) —
  **designed to preserve node identity across a sequence of incremental edits
  that pass through invalid intermediate states.** A `set_source` reset
  discards this and re-baselines identity.

Conclusion: the caller-side rollback is the sole divergence source. The
attachment is already built to hold an invalid `current_source` and recover
incrementally with stable identity.

## Invariant

> `SourceBackedGraph.source` (and the attachment's `current_source`) always
> equals the CodeMirror editor's current buffer. The rendered graph is derived:
> `current_result()` when valid, else `last_good()`.

The editor is the single source of truth for text; the graph is downstream.

## Changes

1. **`apply_codemirror_changes(changes, expected_doc)`** (new `expected_doc`
   param = the editor's authoritative post-transaction buffer):
   - Apply the per-delta edits incrementally against `self.source`
     (`changes_to_edits` unchanged), feeding `attachment.apply_edit` — identity
     preserved through invalid states by the tracker.
   - **Stale-editor guard (fixes #1):** if after applying, `self.source !=
     expected_doc`, the editor had diverged from `self.source` (a TS op moved
     the graph out from under the stale editor). The incremental result is not
     what the user sees, so reparse the editor's authoritative text via
     `attachment.set_source(expected_doc)`. This resolves the conflict
     editor-wins (the racing TS-op change is superseded by the keystroke) — no
     corruption. Rare: only within the sub-250 ms window before the poll syncs.
   - **No rollback on parse failure.** `self.source` stays = `expected_doc`.
     Render falls back to `last_good`. `applied = current_result is Ok`.
2. **`source_demo` `SourceChanged`:** delete the `model.dirty` branch; always
   call the incremental entry, passing `model.editor` (current post-`EditorSynced`
   buffer) as `expected_doc`. `dirty = !result.applied`.
3. **`dirty` semantics = "editor's current source is not graph-valid"** (status
   + poll gate only). Fixes #2: button-op rejections (Connect/Insert via
   `apply_source_edit`, which rolls back and leaves the editor's valid text
   untouched) must set `dirty=false`, not `true`. CM-edit / ApplySource invalid
   → `dirty=true`. (Mechanism: derive `dirty` from current source validity, not
   from `result.applied`, OR set `dirty=false` on the button-op result path.)
4. **`set_source_graph_source_checked`:** keep no-rollback (now consistent with
   the invariant). Fix the misleading "rendering last-good" comment in
   `source_demo` to state the source string is the editor's text and only the
   *render* uses `last_good`.
5. **`apply_source_edit` (TS-op path):** keep its rollback — a rejected TS op
   never touched the editor, so `self.source` must stay = editor = last-good.
6. **`SyncFromGraph` poll:** unchanged in mechanism. Under the invariant the
   poll naturally no-ops when in sync (`source == editor`) and `set_doc`s after
   a TS op (closing #1's window in ≤250 ms). The sub-250 ms race is resolved
   editor-wins by the stale guard in (1); a future incr-reactive follow-up
   replaces the poll with immediate cross-app sync.

## Tests

- **Identity preservation (new, the headline):** drive an invalid→valid
  incremental recovery and assert node IDs are *stable* across it (proving the
  whole-source churn is gone). Whitebox on the adapter or E2E via the visualizer
  / node `data-node-id`.
- Existing dirty-recovery E2E (`220Hz440Hz`) still passes — now via incremental.
- **#1:** TS rename, then type in the stale editor within the window → coherent
  source, no corruption (editor-wins).
- **#2:** rejected ConnectSample leaves `dirty=false`; a subsequent graph change
  still syncs to the editor via the poll.
- Adapter whitebox: `self.source == expected_doc` after both valid and invalid
  CM edits; `last_good` render survives an invalid edit; no rollback.

## Non-goals

- Immediate cross-app editor sync after TS ops (the proper #1 fix) — deferred to
  the incr-reactive invalidation follow-up; the stale guard makes the window
  safe (no corruption) in the meantime.
- Changing `changes_to_edits` (correct as-is for in-coordinate deltas).
