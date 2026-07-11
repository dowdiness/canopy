# #216 Step 4 — Bridge position-unit audit

**Status:** historical investigation. The main bridge-seam recommendation
shipped via #246 and #251; current remaining follow-ups live in TODO.md §16.

**Scope:** confirm where the editor's UTF-16 code-unit ↔ grapheme-cluster
conversion needs to live for each external bridge. The original framing in
[#216] singles out "the ProseMirror bridge"; in practice canopy now has
**multiple** position-bearing bridges and **two distinct routes** into the
editor (bulk splice vs. per-character). The recommendation is narrower than
"one seam to rule them all" — it covers the bulk-splice route and lists the
remaining position-bearing surfaces explicitly.

[#216]: https://github.com/dowdiness/canopy/issues/216

## TL;DR

- For **bulk-splice text edits** from `CM6Adapter` and the markdown
  `BlockInput`, the conversion belongs at a single editor-side seam:
  `editor/sync_editor_text.mbt::apply_text_edit_internal` (and its
  `set_text`/`compute_text_change` companion). Per-bridge JS shims add no
  value for these two bridges.
- The new `adapters/editor-adapter/pm-adapter.ts` does not need a
  position-unit shim. Its PM doc is non-editable; `TextChange` is a no-op
  in its `applyPatch`; PM-tree positions never reach the CRDT.
- ~~The **older ProseMirror bridge** at `examples/ideal/web/src/bridge.ts`
  *does* call `insert_at`/`delete_at` char-by-char, *does* read the source
  map on the JS side via `get_source_map_json`, and is therefore **not
  served by the bulk-splice seam**. It needs its own grapheme story —
  either retire the per-char loop in favor of `handle_text_intent`, or add
  matching grapheme handling at the `insert_at`/`delete_at` FFI.~~
  **Resolved by PR #246:** the older ProseMirror bridge has been migrated
  onto `handle_text_intent_checked` (a Bool-returning variant of
  `handle_text_intent`). It now joins the bulk-splice seam, so the same
  MoonBit-side grapheme shim covers it. The JS-side source map is still
  read for `basePos` lookup; the per-char loop and the `insert_at`/
  `delete_at` codepath in the bridge are gone.
- Position-bearing surfaces the seam did *not* cover at investigation time:
  - per-character `SyncEditor::insert` / `delete` / `backspace` and the
    `_and_record` family — bypass `apply_text_edit_internal`
  - `move_cursor(position : Int)` — cursor-only API, no text change
  - `undo` / `redo` — replay CRDT ops directly on the doc
  - remote sync (`apply_sync`) — applies peer ops via the CRDT
  **Status after #251:** the local editor/cursor/undo surfaces are now
  grapheme-aware through `@moji`; remote sync remains a CRDT-layer concern.
- The "infeasibility" framing in earlier drafts is too strong:
  per-bridge JS-side conversion is *available* (the ideal bridge already
  does it via `get_source_map_json`), just **not preferred** for new
  bridges because it forces every bridge to take a moji binding.

## Bridge inventory

| Bridge | File | User text input source | Position unit on the wire | Reaches CRDT? |
|---|---|---|---|---|
| CM6Adapter | `adapters/editor-adapter/cm6-adapter.ts` | CodeMirror 6 doc | UTF-16 code units (CM6 native) | yes — via `handle_text_intent` |
| BlockInput | `adapters/editor-adapter/block-input.ts` | `<textarea>` overlay | UTF-16 code units (`HTMLTextAreaElement.selectionStart`) | yes — via `compute_split_block` (text-span offset) |
| Older ideal bridge | `examples/ideal/web/src/bridge.ts` | CM6 NodeViews per leaf | UTF-16 code units, **plus JS-side `get_source_map_json`** | yes — via `handle_text_intent_checked` (post #246; was `insert_at`/`delete_at` char-by-char) |
| PMAdapter (new) | `adapters/editor-adapter/pm-adapter.ts` | PM doc is `editable: () => false` | PM-tree positions only (`SelectNode`/`SetCursor`) | no — `SetCursor` dropped in `examples/prosemirror/src/main.ts:63` |
| HTMLAdapter | `adapters/editor-adapter/html-adapter.ts` | none — click → `SelectNode` only | n/a (no text positions) | partial — only `SelectNode` |
| MarkdownPreview | `adapters/editor-adapter/markdown-preview.ts` | render-only, emits no intents | n/a | no |

The two text-bearing intent producers wired into the new `editor-adapter`
package (CM6 and BlockInput) speak the same unit as the canopy editor
(`String.length()` = UTF-16 code units). The ideal bridge is older, lives
under `examples/ideal/web/`, and uses a different FFI route.

## Path-by-path trace

### Path A — CM6Adapter (lambda editor, primary text path)

```
CM6 EditorView.update
  → update.changes.iterChanges(fromA, toA, _, _, inserted)        [code units, CM6]
  → cm6-adapter.ts:248-271 emits TextEdit{ from, to, insert }
  → main.ts handleIntent → crdt.handle_text_intent(handle, from, to-from, insert, ts)
  → ffi/lambda/intent.mbt:63  handle_text_intent
  → editor/sync_editor_text.mbt:149  SyncEditor::apply_text_edit
  → apply_text_edit_internal — clamps `start` / `deleted_len` against
                                doc.len() (eg-walker visible_count, item-space)
  → @text.Pos / @text.Range — addresses item-space slots in eg-walker
```

**Sharp edge.** `apply_text_edit_internal` clamps a code-unit `start`
against an item-space `doc.len()`. After eg-walker [#31][egw31] / canopy
[#240][canopy240] each visible item is one codepoint, so the two lengths
coincide for ASCII and BMP-non-combining text and diverge once a non-BMP
codepoint enters the document — code units count it as 2, item-space as 1.

`SetSelection` (outbound to CM6) is *not currently emitted by MoonBit* —
`compute_view_patches` in `editor/view_updater.mbt:40` produces only
`FullTree`, `ReplaceNode`, `InsertChild`, `RemoveChild`, `UpdateNode`, and
`SetDiagnostics`. The `SetSelection` dispatch path in
`cm6-adapter.ts:309` is *forward-looking* infrastructure, not a live
mismatch. When MoonBit eventually emits `SetSelection`, it will need to
emit code-unit offsets (not item-space) — same conversion shape applies
in reverse at the same seam.

[egw31]: https://github.com/dowdiness/event-graph-walker/issues/31
[canopy240]: https://github.com/dowdiness/canopy/pull/240

### Path B — BlockInput (markdown block editor)

```
HTMLTextAreaElement
  → onKeydown('Enter' mid-text)
  → emit StructuralEdit{ op: 'split_block', params: { offset: String(selectionStart) } }
  → examples/web/src/markdown-editor.ts blockInput.onIntent
  → applyEdit('split_block', nodeId, '', parseInt(params.offset))
  → crdt.markdown_apply_edit(handle, 'split_block', nodeId, '', offset, ts)
  → ffi/markdown/markdown_ffi.mbt:62 markdown_apply_edit
       (param2 is reused as the offset slot; "split_block" → SplitBlock op)
  → lang/markdown/edits/compute_markdown_edit.mbt:211 compute_split_block
       offset is a code-unit offset *inside the source-mapped text span*:
         split_pos = text_range.start + offset
         delete_len = range.end - split_pos
         FocusHint::MoveCursor(position = split_pos + separator.length())
```

The markdown editor uses its own `markdown_apply_edit` FFI (a fixed-arity
six-argument bridge with a `param1: String` / `param2: Int` reuse pattern),
*not* the lambda editor's `handle_structural_intent` — the two structural-
edit FFIs evolved separately.

**Sharp edge.** `selectionStart` and `text_range.start/end` are both
UTF-16 code units, so the path is internally consistent for ASCII; for
non-ASCII inputs neither side is grapheme-aware. A user splitting a block
"after the emoji" who lands `selectionStart` on the low surrogate produces
a malformed `inserted` payload.

`CommitEdit{ value }` (full-string replace) carries no positions and is
unaffected.

### Path C — PMAdapter (new structural, non-editable)

```
PMAdapter view editable: false                                  [pm-adapter.ts:152]
  → applyPatch("TextChange") => break;                          [pm-adapter.ts:236]
  → applyPatch("SetSelection") => break;                        [pm-adapter.ts:238]
  → dispatchTransaction selectionSet branch
       sel.anchor                                               [PM-tree position]
  → emit SelectNode | SetCursor{ position: sel.anchor }         [pm-adapter.ts:167-178]
  → examples/prosemirror/src/main.ts:63 — SetCursor returns; (dropped)
```

**No sharp edge today.** PM-tree positions never reach the CRDT in this
adapter. If a future revision makes the PM doc editable (or routes
PM-side selections back into the CRDT), `sel.anchor` would have to be
converted from PM-tree position → underlying text offset → grapheme
offset. That is a separate PM-tree → text mapping problem; **out of
scope for #216 Step 4 unless PM is made editable.**

### Path D — older ideal bridge (ProseMirror with NodeViews + per-char FFI)

> **Post-#246 update:** the bridge has since been migrated to bulk-splice
> via `handle_text_intent_checked` (PR #246). The trace below describes
> the *pre-#246* state that this audit recommended changing — preserved
> as the historical motivation for the migration. For the current call
> shape, see `examples/ideal/web/src/bridge.ts::applySpliceChanges`.

```
CM6 NodeView leaf change
  → bridge.ts:67 handleLeafEdit(nodeId, changes)
  → bridge.ts:54 getSourceMap() ← crdt.get_source_map_json(handle)
  → basePos = entry.start                                        [code units, source map]
  → bridge.ts:143 applyCharChanges(basePos, ts, changes)
       for each change.from..change.to (code units in the leaf's local frame):
         crdt.delete_at(handle, basePos + change.from + i + offset, ts)
         crdt.insert_at(handle, basePos + change.from + offset + i, change.insert[i], ts)
  → ffi/lambda/intent.mbt:6  insert_at  → SyncEditor::insert_at  → apply_text_edit_internal
  → ffi/lambda/intent.mbt:22 delete_at  → SyncEditor::delete_at  → apply_text_edit_internal
```

**This bridge does call into `apply_text_edit_internal`** (via `insert_at`
/ `delete_at`), so the seam recommendation does apply — but the input
positions are computed *in JS* using a JS-side copy of the source map
plus per-character iteration over `change.insert`. Two issues:

1. The JS-side iteration assumes `change.insert.length` is the right
   loop bound; for non-BMP input that count is in code units, so each
   iteration's `change.insert[i]` may be a lone surrogate, sent to
   `insert_at` directly. This is not fixed by a MoonBit-side seam alone —
   the JS loop has to switch to grapheme iteration on `change.insert`.
2. `basePos + change.from + i` is an arithmetic position composed of
   code-unit offsets. Once the editor flips its public boundary to
   grapheme offsets, the JS arithmetic stops being valid even if the seam
   converts at the FFI edge — the *base* and *delta* must agree on units.

So the ideal bridge **does** need bridge-specific revisions. Easiest path:
move it onto the same `handle_text_intent` route as CM6Adapter, dropping
the per-char loop entirely.

### Path E — non-bridge text-mutating routes (out of scope but listed for completeness)

These are not bridge concerns; they are positions arising inside MoonBit.
The bulk-splice seam does **not** funnel them.

| Route | Entry | Bypasses `apply_text_edit_internal`? |
|---|---|---|
| Per-char cursor edits | `SyncEditor::insert` / `delete` / `backspace` (`editor/sync_editor_text.mbt:4`) | Yes — go directly to `self.doc.insert/delete` and update `self.cursor` by `text.length()` |
| Undo-recorded per-char edits | `insert_and_record` / `delete_and_record` / `backspace_and_record` (FFI in `ffi/lambda/undo.mbt:37,46,55`) | Yes — same per-char path |
| Undo / redo | `SyncEditor::undo` / `redo` (`editor/sync_editor_undo.mbt:78`) | Yes — replay CRDT ops via `self.undo.undo(self.doc)` |
| Remote sync | `apply_sync` (in `editor/sync_editor.mbt:392`) | Yes — applies peer ops directly on the CRDT |
| Tree-edit-derived span edits | `apply_tree_edit_json` → tree edit helpers (`editor/sync_editor_tree_edit.mbt:50`, `editor/sync_editor.mbt:353`) | No — these *do* funnel through `apply_text_edit_internal` |

For the non-funnel routes:

- **Per-char cursor edits / `_and_record`**: the position is the *current
  cursor*, not a parameter. If the cursor is kept on a grapheme boundary
  (Step 2's `move_cursor` clamping + insert clamping in #216's "Direction
  of the fix"), the per-char path produces grapheme-aligned writes
  automatically. No dedicated seam needed; the cursor invariant carries it.
- **Undo / redo**: the recorded ops were already grapheme-aligned at
  record-time (assuming the cursor invariant above). Replay re-applies
  the same offsets. No dedicated seam.
- **Remote sync**: peer ops are CRDT-internal positions (item-space),
  validated by eg-walker [#31][egw31] / canopy [#240][canopy240] at
  receive time. Grapheme alignment is a *local-input* concern, not a
  remote-op concern.

So the seam recommendation covers the *bridge-originated* text splices;
the per-char and undo paths are covered transitively by enforcing the
cursor invariant Step 2 already calls for.

## Conversion-point recommendation (revised)

**Bulk-splice text edits from CM6Adapter and BlockInput → single editor-side
seam at `apply_text_edit_internal` (and its `set_text` / `compute_text_change`
companion).**

```
apply_text_edit_internal(start_cu : Int, deleted_len_cu : Int, inserted : String, ...)
  → start_g, deleted_len_g
       = clamp_to_grapheme_boundary(doc_text, start_cu),
         shrink_to_grapheme_boundary(doc_text, start_cu, deleted_len_cu)
  → recompute start_item, deleted_len_item against eg-walker item-space
  → forward to @text.Range / @text.Pos
```

**Why this is the right level for these two bridges:**

1. CM6's `iterChanges` emits offsets in the CM6 doc which mirrors
   `doc.text()` 1:1; the JS side has no privileged knowledge that the
   editor doesn't.
2. BlockInput's `selectionStart` is an offset into the active block's
   *text span*. The MoonBit source map owns the spans natively, while the
   JS side does not currently receive them via the BlockInput path. JS
   *could* read them via `get_source_map_json` (the ideal bridge does),
   but exposing that to BlockInput just to convert offsets is heavier than
   doing it once on the MoonBit side.
3. Concentrating the conversion in MoonBit means one moji binding rather
   than one per bridge.

**What this recommendation did NOT solve at the time** (each was a
separate decision outside this bridge seam):

- The ideal bridge's per-char loop in `examples/ideal/web/src/bridge.ts:143-164`.
  Status: resolved by #246, which migrated it to the shared text-intent
  seam.
- `SyncEditor::move_cursor(position : Int)` and the cursor invariant at
  insert / backspace in `editor/sync_editor_text.mbt:62,11,40` — these
  were the *cursor*, not the seam. Status: #251 added the local
  grapheme-boundary invariant through `@moji`; the follow-up parser/undo fix
  converted the non-BMP panic probes into behavior tests.
- Outbound `ViewPatch::SetSelection.{anchor,head}` — not currently
  emitted by `compute_view_patches`; if/when added, the same seam (in
  the emit direction) applies.
- `UserIntent.SetCursor.position` is type-promiscuous: the same `number`
  carries PM-tree positions (PMAdapter) and CM-doc code-unit offsets
  (CM6Adapter). Naming-cleanup, not unit-conversion; tracked separately.

## Open follow-ups (not blocking moji work)

These do not gate Step 2; they are smaller cleanups that fall out of the audit.

1. ~~**Migrate the older ideal bridge** off the per-char `insert_at` /
   `delete_at` loop and onto `handle_text_intent`, so it joins the
   bulk-splice seam. Otherwise it needs a parallel grapheme story.~~
   **Shipped: PR #246.** Bridge now calls `handle_text_intent_checked`
   (Bool-returning FFI variant) once per CM6 change with cumulative-
   delta bookkeeping. Drift detection preserved.
2. ~~**`compute_split_block` offset semantics** (`lang/markdown/edits/compute_markdown_edit.mbt:211`)
   should gain a brief docstring noting the offset is a code-unit offset
   inside the text span — same caveat as `SyncEditor::move_cursor`.~~
   **Shipped: PR #248.**
3. **`UserIntent.SetCursor.position`** type-promiscuity (PM-tree vs CM-doc).
   Naming cleanup, not unit conversion.
4. **`ffi/lambda/intent.mbt::insert_at` / `delete_at`** are documented "for
   the ProseMirror bridge" — post-#246 the ideal bridge no longer calls
   them in its hot path, but the FFI surface is retained for whitebox
   tests under `examples/ideal/main/view_history_wbtest.mbt`. Doc
   strings remain as-is; the "ProseMirror bridge" framing is now stale
   but not actively misleading.

## What this changes about #216 Step 2

- **Step 2 stays single-target for the bulk-splice seam** at
  `apply_text_edit_internal` + `set_text`. Cursor clamping at insert /
  backspace and at `move_cursor` is part of the same Step 2 work in
  MoonBit — no separate JS work needed for the new `editor-adapter`
  package.
- **The older ideal bridge needs a separate decision** before Step 2 ships:
  migrate it onto `handle_text_intent`, or accept that it carries its own
  per-char grapheme handling on the JS side. Migration is the simpler
  outcome.
- **PMAdapter is a no-op for #216 unless the PM doc becomes editable**,
  which is a separate question.
- The original Checklist item *"Audit ProseMirror bridge position
  conversion"* can be marked done with this audit as evidence; no separate
  PR-bridge adapter is required for the new PMAdapter.

## References

- `adapters/editor-adapter/cm6-adapter.ts:248-271` — CM6 update listener emits `TextEdit` with code-unit `fromA`/`toA`.
- `adapters/editor-adapter/cm6-adapter.ts:309` — `SetSelection` patch dispatch (forward-looking; not currently emitted from MoonBit).
- `adapters/editor-adapter/block-input.ts:311-329` — textarea `selectionStart` → `split_block` offset param.
- `adapters/editor-adapter/pm-adapter.ts:152` — `editable: () => false`.
- `adapters/editor-adapter/pm-adapter.ts:236-241` — `TextChange` / `SetSelection` no-op in PM applyPatch.
- `adapters/editor-adapter/html-adapter.ts:166,340` — `TextChange`/`SetSelection` no-op; emits `SelectNode` on click.
- `examples/ideal/web/src/bridge.ts:54,67,143-164` — older ideal bridge, JS-side source map + per-char `insert_at`/`delete_at`.
- `examples/prosemirror/src/main.ts:63` — `SetCursor` is dropped at the lambda main.ts handler.
- `editor/view_updater.mbt:40` — `compute_view_patches` does not emit `SetSelection` today.
- `editor/sync_editor_text.mbt:4` — per-char `insert`/`delete`/`backspace` (bypass the seam).
- `editor/sync_editor_text.mbt:62` — `move_cursor` (cursor-only API).
- `editor/sync_editor_text.mbt:105-146` — `apply_text_edit_internal` clamping (the seam).
- `editor/sync_editor_text.mbt:174` — `set_text` → `compute_text_change` → seam.
- `editor/sync_editor_undo.mbt:78` — `undo` replays via `self.undo.undo(self.doc)`, bypasses the seam.
- `editor/sync_editor.mbt:353,392` — span-edit funnel that *does* use the seam; remote sync that does not.
- `lang/markdown/edits/compute_markdown_edit.mbt:211-273` — `compute_split_block` offset use.
- `ffi/lambda/intent.mbt:6,22,63` — FFI receivers (`insert_at`, `delete_at`, `handle_text_intent`).
- `ffi/lambda/undo.mbt:37,46,55` — `_and_record` per-char family.
- `lib/text-change/text_change.mbt:13` — `compute_text_change` uses code-unit indexing.
- canopy [#241](https://github.com/dowdiness/canopy/pull/241) — Step 3 docs (Position Units section).
