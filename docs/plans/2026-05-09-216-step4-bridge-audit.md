# #216 Step 4 — Bridge position-unit audit

**Status:** investigation only. No code changes. Informs the moji-blocked
grapheme-aware fixes (Step 2 of #216).

**Scope:** confirm where the editor's UTF-16 code-unit ↔ grapheme-cluster
conversion needs to live for each external bridge. The original framing in
[#216] singles out "the ProseMirror bridge"; in practice canopy now has
**three** position-bearing bridges plus a non-bridge structural path, and they
do not all share the same unit.

[#216]: https://github.com/dowdiness/canopy/issues/216

## TL;DR

- **Two bridges already use UTF-16 code-unit offsets end-to-end** and are the
  only places that need a grapheme-aware conversion shim once **moji** lands:
  CM6Adapter (used by the lambda editor) and BlockInput's `split_block`
  intent (used by the markdown block editor).
- **PMAdapter does not need a position-unit shim.** Its PM doc is
  non-editable; all `TextEdit`/`TextChange` patches are no-ops in the PM
  branch. PM positions that *do* cross the bridge (`SetCursor.position`,
  `SetSelection.{anchor,head}`) are PM-tree positions, not character offsets,
  and don't reach the CRDT.
- The conversion can sit at a **single editor-side seam** —
  `SyncEditor::apply_text_edit_internal` (and its `set_text` /
  `compute_text_change` companion) — rather than per-bridge in TypeScript.
  Per-bridge adapters add no value for the lambda editor and the markdown
  block editor; PMAdapter does not need an adapter at all.
- The `UserIntent.SetCursor.position` field and `ViewPatch.SetSelection.{anchor,head}`
  are **type-promiscuous today**: same `number` shape carries CM-doc
  code-unit offsets, PM-tree positions, and (potentially) markdown-block
  text-span offsets. Tightening these is a separate naming exercise; it does
  not block the moji work.

## Bridge inventory

| Bridge | File | Editable text source | Position unit on the wire |
|---|---|---|---|
| CM6Adapter | `adapters/editor-adapter/cm6-adapter.ts` | CodeMirror 6 doc | UTF-16 code units (CM6 native) |
| BlockInput | `adapters/editor-adapter/block-input.ts` | `<textarea>` overlay | UTF-16 code units (`HTMLTextAreaElement.selectionStart`) |
| PMAdapter | `adapters/editor-adapter/pm-adapter.ts` | none — PM doc is non-editable | PM-tree positions; not character offsets |
| MarkdownPreview | `adapters/editor-adapter/markdown-preview.ts` | none — render only | n/a |
| HTMLAdapter | `adapters/editor-adapter/html-adapter.ts` | n/a in current setup | n/a |

The two text-bearing bridges (CM6 and BlockInput) already speak the same
unit as the canopy editor (`String.length()` = UTF-16 code units in
MoonBit's host string). The mismatch is not *between* JS and MoonBit —
it's between **code-unit** addressing and the **grapheme-cluster**
addressing the editor will eventually need to expose at its public boundary.

## Path-by-path trace

### Path A — CM6Adapter (lambda editor, today's hot path)

```
CM6 EditorView.update
  → update.changes.iterChanges(fromA, toA, _, _, inserted)        [code units, CM6]
  → CM6Adapter.intentCallback({ type: "TextEdit", from, to, insert })
  → main.ts handleIntent → crdt.handle_text_intent(handle, from, to-from, insert, ts)
  → ffi/lambda/intent.mbt:63 handle_text_intent
  → editor/sync_editor_text.mbt:149 SyncEditor::apply_text_edit
  → apply_text_edit_internal — clamps `start` / `deleted_len` against
                                doc.len() (eg-walker visible_count, item-space)
  → @text.Pos / @text.Range — addresses item-space slots in eg-walker
```

**Sharp edge.** `apply_text_edit_internal` clamps a code-unit `start` against
an item-space `doc.len()`. After eg-walker [#31][egw31] / canopy [#240][canopy240]
each visible item is one codepoint, so the two lengths coincide for ASCII
and for BMP-non-combining text, and diverge once a non-BMP codepoint enters
the document — code units count it as 2, item-space as 1.

The `SetSelection` patch path (`view.dispatch({ selection: { anchor, head } })`
in `cm6-adapter.ts:309`) carries positions back to CM6. These come from the
canopy side and are dispatched into CM6 as code-unit offsets. If MoonBit
ever emits an item-space offset here, the selection lands on the wrong
character for non-ASCII docs.

[egw31]: https://github.com/dowdiness/event-graph-walker/issues/31
[canopy240]: https://github.com/dowdiness/canopy/pull/240

### Path B — BlockInput (markdown block editor)

```
HTMLTextAreaElement
  → onKeydown('Enter' mid-text)
  → emit StructuralEdit { op: 'split_block', params: { offset: String(selectionStart) } }
  → main.ts handleStructuralIntent → crdt.handle_structural_intent(...)
  → ffi/markdown/markdown_ffi.mbt → apply_markdown_tree_edit_json
  → lang/markdown/edits/compute_markdown_edit.mbt:211 compute_split_block
       offset is treated as a code-unit offset *inside the text span*:
         split_pos = text_range.start + offset
         delete_len = range.end - split_pos
         FocusHint::MoveCursor(position = split_pos + separator.length())
```

**Sharp edge.** `selectionStart` from a `<textarea>` is UTF-16 code units in
JS. `text_range.start/end` from the source map are derived from MoonBit
`String` indices, also UTF-16 code units. The two sides agree, so this path
is internally consistent — but neither side is grapheme-aware. A user
splitting a block "after the emoji" who lands `selectionStart` on the low
surrogate produces a malformed `inserted` payload.

`CommitEdit { value }` (full-string replace) carries no positions and is
unaffected.

### Path C — PMAdapter (structural, non-editable)

```
PMAdapter view editable: false
  → applyPatch("TextChange") => break;        // explicit no-op
  → dispatchTransaction selectionSet branch
       sel.anchor                              [PM-tree position, NOT a character offset]
  → emit SetCursor { position: sel.anchor }
  → main.ts handleIntent for SetCursor:        return; (drops it)
```

**No sharp edge today.** PM positions never reach the CRDT in the structural
editor. `SetCursor` is dropped at the lambda main.ts handler, and
`TextChange` patches are no-ops in the PMAdapter applyPatch switch.

If a future revision makes the PM doc editable (or routes PM-side selections
back into the CRDT), `sel.anchor` would have to be converted from PM-tree
position → underlying text offset → grapheme offset. That conversion is not
"a code-unit ↔ grapheme shim"; it is a separate PM-tree → text mapping
problem. **Out of scope for #216 Step 4 unless PM is made editable.**

### Path D — set_text initialization & ProseMirror-bridge `insert_at` / `delete_at`

`ffi/lambda/intent.mbt:6,22` exposes `insert_at(handle, position, text, ts)`
and `delete_at(handle, position, ts)` "for the ProseMirror bridge." No JS
bridge currently calls these (PMAdapter doesn't, the lambda main.ts uses
`handle_text_intent` instead). They are dormant code-unit-offset entry
points; same shim plan as Path A applies if revived.

`crdt.set_text(handle, ...)` at startup goes through
`SyncEditor::set_text` → `text_diff::compute_text_change` → code-unit
splice — already documented in PR #241 (`Position Units` section).

## Conversion-point recommendation

**Single editor-side seam, not per-bridge adapters.**

Once moji lands, the canonical conversion site is
`editor/sync_editor_text.mbt::apply_text_edit_internal` — every text-mutating
path funnels through it (see comment at `sync_editor_text.mbt:131`). The
conversion shape:

```
apply_text_edit_internal(start_cu : Int, deleted_len_cu : Int, inserted : String, ...)
  → start_g, deleted_len_g
       = clamp_to_grapheme_boundary(doc_text, start_cu),
         shrink_to_grapheme_boundary(doc_text, start_cu, deleted_len_cu)
  → recompute start_item, deleted_len_item against eg-walker item-space
  → forward to @text.Range / @text.Pos
```

The `inserted` string still goes to eg-walker as-is (eg-walker [#31][egw31]
/ canopy [#240][canopy240] now splits to per-codepoint atomic Ops and
rejects mid-surrogate inputs at that layer with a typed `TextError`).

**Why a single seam beats per-bridge:**

1. CM6's `iterChanges` emits offsets in the *CM6 doc*, which mirrors
   `doc.text()` 1:1 — so the JS side has no privileged knowledge to do the
   conversion that the editor doesn't have.
2. BlockInput's `selectionStart` is an offset into the *active block's text
   span*. The editor side already has that text span in its source map; the
   JS side does not. Conversion *cannot* happen on the JS side without
   shipping the source map across the wire.
3. PMAdapter does not generate text positions, so there is nothing to convert.
4. Concentrating the conversion in MoonBit lets the editor library carry
   one canonical implementation; per-bridge adapters would each need their
   own moji binding.

**What lives on the JS side:** nothing position-related changes. JS continues
to send code-unit offsets (because that is what the host editors natively
expose) and the editor seam normalises them. The eventual `GraphemeOffset`
opaque type (name reserved per #241) is a *MoonBit-internal* type; the
JSON wire format keeps `Int`.

## Open follow-ups (not blocking moji work)

These do not gate Step 2; they are smaller cleanups that fall out of the audit.

1. **`ViewPatch.SetSelection.{anchor,head}`** is dispatched into CM6 as a
   code-unit offset. Once the editor's public surface flips to grapheme
   offsets, the Patch emitter must convert *back* before crossing the wire.
   Add this to the same seam that handles inputs.
2. **`UserIntent.SetCursor.position`** is type-promiscuous — same `number`
   carries PM-tree positions (PMAdapter), CM-doc code-unit offsets
   (CM6Adapter), and is not currently handled at the lambda editor. When PM
   becomes editable or CM gains structural awareness, give these distinct
   intent variants instead of overloading one field.
3. **`ffi/lambda/intent.mbt::insert_at` / `delete_at`** are documented "for
   the ProseMirror bridge" but no current JS code calls them. Either wire
   them in (when PM is editable) or remove the comment to avoid implying
   active use. Track in #216 only if PM is in scope.
4. **`compute_split_block` offset semantics** (`lang/markdown/edits/compute_markdown_edit.mbt:211`)
   should gain a brief docstring noting the offset is a code-unit offset
   inside the text span — same caveat as `SyncEditor::move_cursor`.

## What this changes about #216 Step 2

- **Step 2 stays single-target:** the editor seam, not per-bridge JS code.
- **No new TypeScript work** falls out of the bridge audit.
- The original Checklist item *"Audit ProseMirror bridge position
  conversion"* can be marked done with this audit as evidence; no separate
  PR-bridge adapter is required.

## References

- `adapters/editor-adapter/cm6-adapter.ts:248-271` — CM6 update listener emits `TextEdit` with code-unit `fromA`/`toA`.
- `adapters/editor-adapter/cm6-adapter.ts:309` — `SetSelection` patch dispatch.
- `adapters/editor-adapter/block-input.ts:313-329` — textarea `selectionStart` → `split_block` offset param.
- `adapters/editor-adapter/pm-adapter.ts:152` — `editable: () => false`.
- `adapters/editor-adapter/pm-adapter.ts:236-241` — `TextChange` no-op in PM applyPatch.
- `editor/sync_editor_text.mbt:105-146` — `apply_text_edit_internal` clamping.
- `lang/markdown/edits/compute_markdown_edit.mbt:211-273` — `compute_split_block` offset use.
- `ffi/lambda/intent.mbt:6,22,63` — FFI receivers.
- canopy [#241](https://github.com/dowdiness/canopy/pull/241) — Step 3 docs (Position Units section).
