# Inspector Panel — Rich Node Details

**Date:** 2026-04-01
**Status:** Active

## Why

The ideal editor inspector panel shows Kind, Label, Children, and ID but omits
source range, source text, and token spans — all of which are already available
on `InteractiveTreeNode` and `SourceMap`. The TODO §10 acceptance criteria
require reliable outline→inspector population with source range and clean
degradation for missing/elided nodes.

## Scope

**In:** `view_inspector.mbt`, `source_map.mbt` accessor, `editor.css` additions.
**Out:** New structural editing features, redesign of overall layout, syntax
highlighting in the source preview.

## Design

### Layout: Integrated Node Card

All node details live in a single NODE section (no separate TOKENS or SOURCE
sections). The section renders, in order:

1. **Kind** — existing row, colored by kind class
2. **Label** — existing row
3. **Children** — existing row (count)
4. **ID** — existing row
5. **Range** — new row, `start..end` format, omitted when `start == end`
6. **Source preview** — new monospace block showing raw text slice, omitted when
   range is zero-length, truncated to 120 chars with `"…"` suffix
7. **Token spans** — new inline rows (role, range, text slice), omitted when no
   spans exist for the node

### Data plumbing

- `view_node_details(node)` → `view_node_details(node, model)` to access source
  text via `model.editor.get_text()` and token spans via
  `model.editor.get_source_map()`.
- Add `SourceMap::get_all_token_spans(node_id) -> Array[(String, Range)]` to
  `framework/core/source_map.mbt`. Returns an array of `(role, range)` pairs
  sorted by range start position. Returns empty array when no spans exist.
  Array avoids leaking mutable `Map` internals from the framework API.
- Source text slicing must clamp `range.end` to `text.length()` before
  extracting the substring, in case the source map and text are momentarily
  out of sync during an edit cycle.
- `Range` is `pub(all) struct` in `loom/core` and transitively accessible from
  the ideal editor via `dowdiness/canopy`. No new module dependencies needed.

### Edge cases

- **No selection:** "Click a node in the outline or editor to inspect it" (unchanged).
- **Stale selection (node not found):** Show "Node not found" in the NODE
  section. In `view_inspector_content`, when `resolve_selected_node` returns
  `None`, the existing "No matching node" text is sufficient — no model
  mutation needed. The selection clears naturally when the user clicks
  another node or the outline re-renders.
- **Zero-length range (`start == end`):** Omit Range row and source preview.
  Kind, Label, Children, ID still render.

### CSS additions

Two new classes in the Inspector Panel section of `editor.css`:

- **`.source-preview`** — `--canopy-surface` background, `--radius-sm`,
  `white-space: pre; overflow-x: auto;`, `max-height: 4.5em; overflow-y: auto;`
  (caps at ~3 lines).
- **`.token-span-row`** — flex row at `--text-caption` size, visually
  subordinate to main node properties.

No new design tokens.

## Files changed

| File | Change |
|------|--------|
| `framework/core/source_map.mbt` | Add `get_all_token_spans` accessor |
| `examples/ideal/main/view_inspector.mbt` | Extend `view_node_details` with range, source preview, token spans |
| `examples/ideal/web/styles/editor.css` | Add `.source-preview` and `.token-span-row` classes |
| `docs/plans/2026-03-29-ideal-inspector-panel.md` | Archive (superseded by this spec) |
| `docs/TODO.md` | Update §10 inspector item to point to this plan |

## Acceptance criteria

- [ ] Outline selection populates the inspector reliably
- [ ] Inspector NODE section includes source range (start..end)
- [ ] Inspector NODE section shows source text preview (truncated at 120 chars)
- [ ] Inspector NODE section shows token spans when available
- [ ] Zero-length range omits range row and source preview
- [ ] Missing node shows "Node not found" and clears on next refresh
- [ ] `get_all_token_spans` returns sorted pairs and empty array for no spans
- [ ] Source text slice clamped to text length (no out-of-bounds)
- [ ] `moon check` and `moon test` pass

## Validation

```bash
moon check
moon test
cd examples/web && npm run dev  # manual: click nodes, verify inspector
```
