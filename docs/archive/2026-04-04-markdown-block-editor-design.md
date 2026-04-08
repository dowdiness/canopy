# Markdown Block Editor — Design

## Why

The block editor is currently property-driven: block types (`heading`, `paragraph`, `list_item`) are CRDT properties set manually via `set_block_type`. This means block structure is disconnected from text content — you can have a block with `block_type=heading` whose text doesn't start with `#`.

By making the Markdown parser the source of truth for block structure, block types become *derived from text*, not stored separately. The incremental parser (loom) handles syntax, the projection pipeline produces ViewNodes, and the editor renders them — the same architecture as lambda and JSON editors.

## Goal

Build a Markdown-backed block editor with three view modes sharing one `SyncEditor[Block]` ground truth:

- **Raw mode** — CM6 text editor. Direct Markdown source editing. Full transparency.
- **Block mode** — Canopy-owned thin input layer. Structural editing with explicit commands.
- **Preview mode** — Read-only rendered Markdown with semantic HTML.

**Relationship to existing block-editor:** This is a new editor, not a migration of `examples/block-editor/`. The existing property-based block editor remains as-is. Once the Markdown editor reaches feature parity, the old block editor can be retired (§18).

## Design Principles

### Progressive disclosure, not hidden magic

The three modes serve a fundamental UX balance:

- **Raw mode** — full transparency, zero learning curve. See exactly what's happening. The escape hatch when block mode feels opaque.
- **Block mode** — clean focus, but demands learning commands. The power mode.
- **Preview mode** — pure reading. Zero interaction cost.

Hiding Markdown syntax in block mode makes the editor clean and focused, but it also hides information. Users must learn commands to change structure. This is a trade-off: **clean UI demands practiced users.** We accept this trade-off because:

1. Users can always drop to raw mode when they need transparency
2. Commands are discoverable (slash menu, toolbar, tooltips with shortcuts)
3. The command vocabulary is small (7 ops at launch)

### Explicit conversion, not autoformat

In block mode, typing never triggers structural re-interpretation. Block types change only via explicit commands:
- Slash menu (`/heading`, `/list`)
- Toolbar buttons
- Keyboard shortcuts (Ctrl+1 for H1, etc.)

This follows the Notion/Linear/Slack convention. It's safe and predictable for a first implementation. Autoformat (type `# ` → heading) can be added later as an opt-in behavior.

Why not implicit: if the parser re-interprets text on every keystroke, users get disturbed by blocks changing type while they type. The flow in their mind is interrupted. Explicit conversion respects the user's intent.

## Architecture

```
SyncEditor[Block]  (text CRDT ground truth — same as lambda/JSON editors)
       │
  loom Markdown parser (incremental)
       │
  CST → ProjNode[Block] projection
       │
  ViewNode tree (kind_tag: "heading", "paragraph", "list_item", ...)
       │
  ┌────┴──────────────┬───────────────────┐
  │                   │                   │
CM6Adapter       BlockInput        MarkdownPreview
(raw mode)      (block mode)      (preview mode)
```

All three views consume the same ViewNode tree via ViewPatch diffs. Mode switching changes the active view; the underlying data and parse tree are shared.

### Ground truth: SyncEditor, not Container

The MVP uses `SyncEditor[Block]` as sole ground truth — the same pattern as the lambda and JSON editors. `SyncEditor` owns a single text document plus the parser/memo pipeline. `@container.Document` is **not** used here.

Why: `SyncEditor` and `@container.Document` are currently separate models with no integration path. Container text sync is blocked on Phase 3. Using `SyncEditor` directly is proven (lambda, JSON) and avoids a dependency that doesn't exist yet.

Future: When Container Phase 3 ships unified sync, the Markdown editor can be upgraded to use `@container.Document` for per-block text and collaborative editing.

### Parser

The loom Markdown parser (`loom/examples/markdown/`) already exists:
- Two-level AST: Block (Document, Heading, Paragraph, UnorderedList, ListItem, CodeBlock) + Inline (Text, Bold, Italic, InlineCode, Link)
- 3 lex modes (LineStart, Inline, CodeBlock)
- Incremental re-lex with convergence
- 28 tests passing

### Projection

`lang/markdown/proj/syntax_to_proj_node.mbt` converts the Markdown CST into `ProjNode[Block]`. Each CST block node becomes a ProjNode. The projection follows the same pattern as `lang/json/proj/`.

ProjNode values carry the block's semantic type:
```moonbit
pub(all) enum Block {
  Document
  Heading(Int)          // level 1-6
  Paragraph
  UnorderedList
  ListItem
  CodeBlock(String)     // info string
  Error(String)
}
```

**MVP subset:** This enum covers the constructs the loom Markdown parser currently produces. The existing property-based block editor also supports Quote, Divider, Raw, Numbered lists, and Todo lists — those are out of scope for the MVP and will be added as the parser gains those constructs.

### ViewNode mapping

Each ProjNode maps to a ViewNode with:
- `kind_tag`: `"document"`, `"heading"`, `"paragraph"`, `"unordered_list"`, `"list_item"`, `"code_block"`
- `css_class`: `"heading-2"`, `"list-bullet"`, etc.
- `text`: block's **visible text without Markdown syntax** (e.g., `"Hello world"` for `## Hello world` — the `## ` prefix is hidden in block mode)
- `text_range`: absolute (start, end) positions in the full Markdown source — the edit bridge uses these to map visible text back to source offsets
- `editable`: true for leaf blocks (heading, paragraph, list_item)
- `children`: nested blocks (list → list_items)
- `token_spans`: syntax roles within the text (for future inline formatting display)

**Offset mapping contract:** `ViewNode.text_range` provides the source-level start/end for each block's **editable content** (excluding the Markdown prefix). When BlockInput captures a text edit at visible offset `i`, the source offset is `text_range.0 + i`. `CommitEdit` uses source offsets internally.

**Inner vs UI representation:** The incremental parser freely re-interprets the source on every keystroke — this is correct and desirable. If the user types `# hello` into a paragraph's content, the source becomes `# hello` and the parser sees a heading. The inner representation changes implicitly; the user is not disturbed because they don't see the inner representation in block mode.

The question is what the **UI** does. For MVP: the UI follows the parser. If the source becomes a heading, the block renders as a heading. This is acceptable because (a) the edge case is rare — users change block types via commands, not by typing syntax, and (b) the parser is the source of truth, and the UI should reflect it.

Future refinement: the projection can add a **UI stabilization layer** that tracks "user-intended type" vs "parsed type" and only updates the UI type on explicit commands. This would prevent the UI from jumping when text edits incidentally create Markdown patterns. This is a projection-level concern, not an edit-handler concern — the inner representation should never be constrained to protect the UI.

**Patch contract for `text_range`:** `diff_view_nodes` must include `text_range` in its comparison. Any structural edit (split, merge, heading level change, or even edits in other blocks that shift offsets) will produce ViewNodes with changed `text_range`, and the diff must emit `ReplaceNode` so the frontend gets updated offsets. Without this, the frontend holds stale `text_range` values and sends edits to wrong source positions.

### Edit operations (7 at launch)

| Op | Description | Text effect |
|----|-------------|-------------|
| `CommitEdit(node_id, new_text)` | Text change in a block | Replace editable span (text_range) in source |
| `ChangeHeadingLevel(node_id, level)` | Change heading 1-6, or convert paragraph↔heading | Add/change/remove `# ` prefix |
| `ToggleListItem(node_id)` | Toggle paragraph↔list item | Add/remove `- ` prefix |
| `Delete(node_id)` | Remove a block | Delete full block span including trailing newline |
| `InsertBlockAfter(node_id)` | Insert empty paragraph after block | Insert `\n\n` at end of block span |
| `SplitBlock(node_id, offset)` | Split block at cursor position (Enter mid-block) | Insert `\n\n` at source offset within block |
| `MergeWithPrevious(node_id)` | Merge block with previous (Backspace at start) | Remove newlines between blocks, join text |

**Split/merge semantics:**
- `SplitBlock` on a heading → second half becomes a **paragraph** (standard Notion/Google Docs behavior). The heading prefix stays with the first half.
- `SplitBlock` on a list item → second half becomes a **new list item** (new `- ` prefix inserted).
- `SplitBlock` at offset 0 → equivalent to `InsertBlockAfter` on the *previous* block (insert empty paragraph before current block).
- `SplitBlock` at end of text → equivalent to `InsertBlockAfter` (insert empty paragraph after current block).
- `MergeWithPrevious` → the merged block takes the **previous block's type**. The current block's text is appended to the previous block's text. If the previous block is a heading and the current is a paragraph, the result is a heading with the combined text.
- `MergeWithPrevious` on the first block → no-op (nothing to merge with).
- `MergeWithPrevious` on an empty list item → removes the list item and moves focus to previous block (standard list editing behavior: Enter on empty item exits the list).

Each op computes `SpanEdit`s against the Markdown source text — the same pattern as JSON/lambda edit ops. The parser re-parses incrementally after the text change.

### BlockInput — thin input layer (block mode)

**Design principle:** Canopy owns the interaction model. The browser renders; we handle input.

BlockInput is NOT a contentEditable adapter. It's a Canopy-owned input layer following the Excalidraw textarea overlay pattern.

**Reference implementations:**
- Excalidraw (`textWysiwyg.tsx`): raw `<textarea>`, absolutely positioned, transparent background, font-matched to element. ~1000 lines.
- tldraw: TipTap contenteditable inside React shape tree, pre-mounted on hover.
- Both confirm: the input surface must be **visible and correctly positioned** for IME to work.

**Key simplification over canvas editors:** Canopy blocks are vertically stacked in normal document flow, not freeform on a canvas. No rotation, no zoom transforms. `position: absolute` within the block container div is sufficient — no `getTransform()` math needed.

**Rendering:**
- Each block ViewNode → `<div class="block" data-node-id="...">` with styled text (read-only DOM)
- Block type conveyed via CSS class + ARIA role (heading → `<div role="heading" aria-level="2">`)

**Textarea overlay (Excalidraw pattern):**
- Active/focused block gets a `<textarea>` overlay, absolutely positioned within the block div
- Textarea is styled to match the block's font, size, line-height, padding exactly (`getComputedStyle` to mirror)
- Transparent background — the block div behind shows styled text; the textarea captures input
- 1.05x height buffer to prevent jumping during IME composition (Excalidraw technique)
- Textarea is pre-created for the focused block (tldraw optimization) for faster edit-start

**Text input:**
- On input: diff textarea value against the block's visible text → `CommitEdit(node_id, new_text)`
- MoonBit computes SpanEdits → CRDT → incremental reparse → ViewPatch → re-render block → re-position textarea
- IME: check `event.isComposing` before handling keyboard shortcuts (Excalidraw pattern)
- During IME composition (`isComposing = true`): **skip re-render of the active block**. The textarea owns the display during composition. Re-render on `compositionend` only. This prevents the re-render loop from destroying composition state.

**Caret restoration after re-render:**
- Before applying patches that affect the active block: save `textarea.selectionStart` / `textarea.selectionEnd`
- After DOM update: restore selection positions (adjusted if text length changed)
- If the block was replaced (`ReplaceNode`): update `text_range` from the new ViewNode, then restore caret
- If the active block was removed (e.g., merged): move textarea to the target block at the appropriate offset

**Deferred blur (Excalidraw pattern):**
- Don't set `onblur` handler immediately — wait for `pointerup` and check if the target is a toolbar/menu element
- This prevents premature commit when the user clicks a toolbar button to change block type

**Block navigation:**
- Arrow keys at block boundaries → move focus to adjacent block (move textarea overlay)
- Enter at end of block → `InsertBlockAfter(node_id)` + move focus
- Enter mid-block → `SplitBlock(node_id, cursor_offset)` + move focus to new block
- Backspace at start of block → `MergeWithPrevious(node_id)` + move focus to previous
- Tab → indent (future: list nesting)

**Command palette (explicit conversion):**
- `/` at start of empty block → show slash menu with block type options
- Toolbar buttons for heading level, list toggle
- Keyboard shortcuts: Ctrl+1–6 for heading levels, Ctrl+Shift+L for list
- Shortcuts shown in tooltips for discoverability

**Selection:**
- Single-block selection: textarea native selection, positions mapped via `text_range`
- Cross-block selection: deferred to future (single-block selection at launch)

**Future: EditContext API:**
The W3C EditContext API replaces the textarea overlay hack entirely — the app tells the OS where text is rendered, the OS handles IME. Currently Chrome-only (since Chrome 133). Worth adopting when Firefox/Safari support arrives.

### Preview mode (MarkdownPreview)

A Markdown-specific preview renderer. The existing `HTMLAdapter` renders a generic tree — it does not produce semantic HTML.

MarkdownPreview is a new, simple renderer (~80 lines) that maps ViewNode `kind_tag` to semantic HTML:
- `"heading"` → `<h1>`–`<h6>` (level from css_class)
- `"paragraph"` → `<p>`
- `"unordered_list"` → `<ul>`
- `"list_item"` → `<li>`
- `"code_block"` → `<pre><code>`

Implements the same `applyPatches(patches)` interface. Read-only — no editing, no textarea.

### View mode switching

The editor host maintains three view instances. Only one is active (attached to DOM). Switching modes:
1. Detach current view
2. Attach new view
3. Send `FullTree` patch to sync the new view's DOM

No re-parsing or state rebuild needed — the ViewNode tree is shared.

## Scope

**In:**
- `lang/markdown/` — new package (proj + edits sub-packages)
- `lang/markdown/proj/` — CST → ProjNode, populate_token_spans, memo
- `lang/markdown/edits/` — MarkdownEditOp (7 ops), handlers, bridge, SyncEditor integration
- `ffi/crdt_markdown.mbt` — FFI exports for Markdown editor
- `lib/editor-adapter/block-input.ts` — BlockInput thin input layer
- `lib/editor-adapter/markdown-preview.ts` — Semantic HTML preview renderer
- `examples/web/markdown.html` + `markdown-editor.ts` — web editor with 3 modes

**Out:**
- Inline formatting ops (bold, italic, links) — future
- Code block edit ops (`ToggleCodeBlock`, etc.) — future. Code blocks appear in projection and preview (parser produces them), but no structural edit op to create/convert them at launch
- Quote, numbered list, todo list — future (parser extensions needed)
- `@container.Document` integration — future (depends on Container Phase 3)
- Collaborative sync — future
- Retiring `examples/block-editor/` — separate cleanup (§18)
- Cross-block selection — future (single-block selection at launch)
- Autoformat (implicit conversion on typing) — future opt-in

## Sub-projects (implementation order)

### Sub-project 0: Textarea overlay spike
Standalone HTML/TS proof-of-concept that validates the textarea overlay technique **under the real re-render loop**, not just static positioning:

**Phase A — static positioning (~50 lines):**
- Render a few styled divs (heading, paragraph, list item)
- On click: position textarea overlay, match font/size
- Type, confirm IME works (test with Japanese input)
- Confirm deferred blur works with a toolbar button

**Phase B — re-render loop (~100 lines):**
- Maintain a backing text string per block
- On textarea input: update backing string → re-render block div (replace innerHTML) → restore textarea caret position
- Verify: IME composition survives the re-render cycle (composition underline, candidate window stay intact)
- Verify: typing latency is acceptable (< 16ms per cycle, measured)
- Verify: caret position is preserved after re-render

**Phase B is the critical test.** Static positioning always works; the question is whether the textarea survives DOM mutations underneath it. If Phase B fails (IME breaks on re-render, or latency is too high), we pivot to contenteditable or debounced re-render.

Exit: both phases pass, or we document what failed and adjust the design. This takes 1-2 days.

### Sub-project 1: Projection (`lang/markdown/proj/`)
- `syntax_to_proj_node.mbt` — CST → ProjNode[Block]
- `populate_token_spans.mbt` — token span extraction
- `markdown_memo.mbt` — reactive memo wrapper
- `moon.pkg` — package definition
- Tests

### Sub-project 2: Edit ops + FFI (`lang/markdown/edits/` + `ffi/`)
- `markdown_edit_op.mbt` — MarkdownEditOp enum (7 ops)
- `compute_markdown_edit.mbt` — dispatch + handlers (split/merge semantics specified above)
- `markdown_edit_bridge.mbt` — protocol bridge
- `sync_editor_markdown.mbt` — `new_markdown_editor()` constructor
- `ffi/crdt_markdown.mbt` — FFI exports (`create_markdown_editor`, `markdown_compute_view_patches_json`, `markdown_apply_edit`)
- `moon.pkg`
- Tests — verify SyncEditor round-trip: edit → reparse → projection → ViewNode

### Sub-project 3: BlockInput + MarkdownPreview (`lib/editor-adapter/`)
- `block-input.ts` — thin input layer (Excalidraw-style textarea overlay, keyboard handling, slash menu)
- `block-input.css` — block styles, textarea overlay positioning, focus ring
- `markdown-preview.ts` — semantic HTML preview renderer (~80 lines)
- Tests

### Sub-project 4: Web editor (`examples/web/`)
- `examples/web/markdown.html` — three-mode page
- `examples/web/markdown-editor.ts` — mode switching, toolbar, keyboard routing
- Vite config update

## Acceptance Criteria

- [ ] Textarea overlay spike validates the input technique (or we pivot)
- [ ] `lang/markdown/proj/` converts Markdown CST to ProjNode tree
- [ ] `lang/markdown/edits/` handles 7 edit ops via SpanEdits
- [ ] SplitBlock on heading → paragraph; on list item → new list item
- [ ] MergeWithPrevious → joined text with previous block's type
- [ ] SyncEditor[Block] works with Markdown parser + projection
- [ ] FFI exports work: create editor, compute patches, apply edit
- [ ] BlockInput renders ViewNode tree as styled block divs
- [ ] BlockInput captures text input via textarea overlay → CommitEdit
- [ ] Slash menu / toolbar / keyboard shortcuts for block type changes
- [ ] Raw mode works via CM6Adapter on the same SyncEditor
- [ ] Preview mode renders semantic HTML (h1-h6, ul, li, p, pre)
- [ ] Mode switching preserves document state
- [ ] All existing tests pass (no regression)

## Validation

```bash
moon check && moon test                          # canopy
cd loom/loom && moon test                        # loom
cd examples/web && npm run dev                   # dev server
# Visit /markdown.html, test all 3 modes
# Test with Japanese IME in block mode
```

## Risks

- **Textarea overlay font matching**: The textarea must exactly match the block div's typography. Small mismatches (sub-pixel line-height, different font rendering) cause visual jitter. Mitigated by sub-project 0 spike.
- **IME composition**: The visible textarea handles standard IME. Edge cases: dictation input, emoji pickers, screen readers. Test early with real input methods.
- **Single-document scalability**: Entire Markdown document as one text string in SyncEditor. Works for small documents. Large documents (1000+ lines) may need per-block architecture. Defer until measured.
- **Slash menu complexity**: A full slash menu (search, categories, keyboard navigation) is significant UI work. MVP can be a simple dropdown; polish later.

## References

- Excalidraw `textWysiwyg.tsx` — raw textarea overlay, ~1000 lines. Absolute position + CSS transform for canvas coordinates. Deferred blur, IME guard, height buffer.
- tldraw `RichTextArea.tsx` — TipTap contenteditable inline in shape React tree. Pre-mount on hover.
- EditContext API (W3C) — emerging standard for OS-level text input coordination. Chrome 133+. Future replacement for textarea hack.
- Notion/Linear — explicit block conversion via slash commands. No autoformat-by-parsing.

## Notes

- The Markdown parser in `loom/examples/markdown/` has 1,940 LOC and is mature (28 tests, 3 lex modes, error recovery).
- JSON editor integration (PR #100 + #104) is the direct precedent for sub-projects 1-2. Follow the same package structure and patterns.
- `examples/block-editor/` remains as-is — it's the property-based reference. Retirement tracked in TODO §18.
- When inline formatting is added later, bold/italic/links become token spans in the ViewNode. BlockInput renders them as styled `<span>`s within the block div. Selection across formatted ranges uses our own selection model (start/end offsets into the text).
- The Block enum is an MVP subset. The existing block editor supports Quote, Divider, Raw, Numbered, and Todo — these require parser extensions first, then new Block variants and edit ops.
