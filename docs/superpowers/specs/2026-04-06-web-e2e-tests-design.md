# Web E2E Tests — Lambda & JSON Editors

**Date:** 2026-04-06
**Scope:** Playwright E2E tests for `examples/web/` Lambda and JSON editors
**Approach:** Two-layer (Foundation + Ad-hoc) per editor, one file per editor

## Context

The `examples/web/` directory has four HTML entry points. Only the Markdown
block editor (`markdown.html`) has Playwright coverage. The Lambda editor
(`index.html`) and JSON editor (`json.html`) are untested. The existing
`playwright.config.ts` (port 5190, Chromium, `./tests` dir) and the markdown
spec provide the infrastructure and conventions.

## Architecture

```
tests/
  lambda-editor.spec.ts    # Foundation only (thin interaction surface)
  json-editor.spec.ts      # Foundation + Ad-hoc (rich toolbar/tree interactions)
  markdown-editor.spec.ts  # (existing, unchanged)
```

Approach A: one file per editor, layers as `describe` blocks. Matches the
existing flat structure. Ad-hoc tests accumulate over time as regressions
are found.

## Layer Definitions

**Foundation** — things that should never break. Page loads, examples populate
the editor, typing produces output, no JS errors, basic parse→render pipeline
works. Stable selectors, unlikely to need updating.

**Ad-hoc** — specific behaviors that exercise interesting code paths. Tests
current behavior and may need updating as the UI evolves. Catches regressions
in the MoonBit↔JS boundary. New tests added when bugs surface.

## lambda-editor.spec.ts

Single `describe('Lambda Editor — Foundation')` block.

The Lambda editor is a text-in, visualization-out pipeline. No structural
editing, no tree selection, no toolbar operations. The ad-hoc layer would be
forced — real ad-hoc tests come from bug fixes.

### Tests

1. **Page loads without errors** — navigate to `/`, status element shows
   "Ready!", capture `pageerror` events and assert none fired.

2. **Editor is visible and focusable** — `#editor` (contenteditable) is
   visible on the page.

3. **Example buttons populate editor** — click each of the 5 example buttons
   (Basics, Composition, Currying, Conditional, Pipeline), verify `#editor`
   has non-empty text content after each click.

4. **Typing triggers AST graph** — type a simple valid expression into
   `#editor`, verify `#ast-graph svg` appears.

5. **Pretty-print updates** — load an example, verify `#ast-output` contains
   structured content (not the initial "Waiting for input..." placeholder).

6. **Valid input shows no errors** — load an example, `#error-output` shows
   "No errors" (no `.error-item` elements).

### Selectors

| Element | Selector |
|---------|----------|
| Editor | `#editor` |
| Status | `#status` |
| AST graph | `#ast-graph` |
| AST output | `#ast-output` |
| Error list | `#error-output` |
| Example buttons | `.example-btn` |
| Error items | `.error-item` |

## json-editor.spec.ts

Two `describe` blocks: Foundation and Ad-hoc.

The JSON editor has a rich interaction surface: contenteditable input, tree
view with node selection, 7 toolbar operations, inline forms, and parse error
display. The structural edits exercise the MoonBit CRDT backend through the
`json_apply_edit` → `syncTextFromModel` → `refresh` pipeline.

### Foundation Tests

1. **Page loads without errors** — navigate to `/json.html`, capture
   `pageerror` events and assert none fired.

2. **Editor and tree view visible** — `#json-input` and `#tree-view` both
   present on the page.

3. **Default JSON renders tree** — on initial load, tree view contains
   `.node-row` elements (the fallback `{"hello": "world"}` populates).

4. **Example buttons populate editor and tree** — click each of the 4 example
   buttons (Simple, Object, Array, Nested), verify `#json-input` has text
   content and `.node-row` count changes appropriately.

5. **Valid JSON shows no parse errors** — load an example, `#parse-errors`
   contains no `.error-item` elements.

### Ad-hoc Tests

6. **Tree node selection and toolbar state** — click a `.node-row`, verify it
   receives `.selected` class. Check that toolbar buttons enable/disable
   correctly based on the selected node type (e.g. "+ Member" enabled for
   objects, disabled otherwise).

7. **Structural edit round-trips through text** — load Array example, select
   the array root node, click "+ Element", verify tree gains a child node AND
   `#json-input` text content reflects the addition.

8. **Inline form lifecycle** — click "+ Member" on an object node, verify
   inline form (`.inline-form.visible`) appears. Fill key input, submit →
   form hides, tree has new member. Open form again, press Escape → form
   hides without changes.

9. **Parse error lifecycle** — clear editor and type broken JSON (e.g. `{bad`),
   verify `.error-item` appears. Fix the input to valid JSON, verify errors
   clear.

10. **Example switching resets state** — load one example, perform an edit,
    load a different example, verify editor text and tree reflect the new
    example cleanly (no leftover state).

### Selectors

| Element | Selector |
|---------|----------|
| Editor | `#json-input` |
| Tree view | `#tree-view` |
| Tree nodes | `.node-row` |
| Selected node | `.node-row.selected` |
| Parse errors list | `#parse-errors` |
| Error items | `.error-item` |
| Example buttons | `.example-btn` |
| Toolbar buttons | `#add-member-btn`, `#add-element-btn`, `#wrap-array-btn`, `#wrap-object-btn`, `#change-type-btn`, `#delete-btn`, `#unwrap-btn` |
| Inline form | `#toolbar-inline-form` |
| Inline input | `#toolbar-inline-input` |
| Inline submit | `#toolbar-inline-submit` |
| Inline cancel | `#toolbar-inline-cancel` |

## Conventions

Matching the existing `markdown-editor.spec.ts` patterns:

- `test.beforeEach` navigates to the page and waits for initial render
- Helper functions for repeated actions (load example, get tree node count)
- `page.on('pageerror', ...)` captures JS errors for assertion
- Selectors use IDs and classes from the HTML (no test-ids)
- Tests assert on observable DOM state, not internal model
- `page.waitForTimeout` used sparingly; prefer `expect(...).toBeVisible()`

## Worktree

Implementation happens in an isolated git worktree on a feature branch
(`feat/web-e2e-tests`).
