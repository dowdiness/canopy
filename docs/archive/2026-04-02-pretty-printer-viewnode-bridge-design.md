# Pretty-Printer ViewNode Bridge — Design Spec

## Why

The pretty-printer engine is complete (`loom/pretty/`) with two language
integrations (lambda, JSON), but its output doesn't flow through the
framework's protocol layer. The web editor displays AST output as plain text
in a `<pre>` via the ad-hoc `get_ast_pretty()` → `textContent` path. This
bypasses ViewNode, ViewPatch, and the adapter system entirely.

Meanwhile, the `Pretty` trait is the text-format half of the
multi-representation system (see
`docs/architecture/multi-representation-system.md`). Any language implementing
`Pretty` should get syntax-highlighted formatted display for free — through
the same ViewNode → ViewPatch → Adapter pipeline used by the structural view.

## Scope

**In:**

- `protocol/formatted_view.mbt` — `layout_to_view_tree` bridge function
- `editor/sync_editor_pretty.mbt` — generic `get_pretty_view` + `compute_pretty_patches`
- `ffi/canopy_pretty.mbt` — FFI exports (pretty view JSON, pretty patches JSON)
- `lib/editor-adapter/html-adapter.ts` — ~20 lines for text-display ViewNode rendering
- `examples/web/src/editor.ts` — replace ad-hoc `textContent` with protocol-based rendering
- Property-based tests: `Arbitrary` for `Term`, pretty roundtrip, view tree consistency, span coverage
- `protocol/moon.pkg` — add `@pretty` dependency

**Out:**

- ViewMode enum / mode-switching UI (future — recorded in architecture doc)
- Structure-format renderer family (separate TODO item)
- `render_ansi` for terminal colors
- Πe cost-factory extension
- Per-node format preview / hover tooltips
- REPL changes (already works with `pretty_print`)

## Current State

### Pretty-printer engine (`loom/pretty/`)

- `Layout[A]` document AST with `Group`, `Nest`, `Annotate`, `Line`, `HardLine`
- `resolve(width, layout) -> Array[Cmd[A]]` — Wadler-Lindig resolution
- `render_string(layout, width?) -> String` — plain text
- `render_spans(layout, width?) -> Array[(Span, A)]` — annotated spans
- `SyntaxCategory` enum: `Keyword | Identifier | Number | StringLit | Operator | Punctuation | Comment | Error`
- `Pretty` trait: `to_layout(Self) -> Layout[SyntaxCategory]`
- `pretty_print(T : Pretty, width?) -> String` — convenience wrapper
- `pretty_spans(T : Pretty, width?) -> Array[(Span, SyntaxCategory)]` — convenience wrapper

### Lambda integration (`loom/examples/lambda/src/ast/pretty_traits.mbt`)

- `PrettyLayout` wrapper with precedence tracking (0-5)
- `TermSym` Finally Tagless impl producing annotated layouts
- `Pretty for Term` via `replay(term).layout`

### JSON integration (`loom/examples/json/src/pretty_traits.mbt`)

- `json_to_layout` with string escaping, `softline`/`group`/`nest` for objects/arrays
- `Pretty for JsonValue`

### Protocol layer (`protocol/`)

- `ViewNode` with `text: String?` and `token_spans: Array[TokenSpan]` fields — already designed for annotated text but currently unused for display
- `ViewPatch` with `FullTree`, `ReplaceNode`, `InsertChild`, `RemoveChild`, `UpdateNode`
- `proj_to_view_node` — structural view bridge (Renderable → ViewNode)
- `protocol/moon.pkg` imports `@core`, `@loomcore` — does NOT yet import `@pretty`

### View updater (`editor/view_updater.mbt`)

- `ViewUpdateState` holds previous ViewNode tree
- `compute_view_patches` diffs old vs new → `Array[ViewPatch]`
- `diff_view_nodes` matches children positionally (index-based), detects label/text/css_class changes
- Insert/remove at tail handled (insert appends, remove from end for stable indices)

### Current web integration (`examples/web/src/editor.ts`)

- `astOutputEl.textContent = crdt.get_ast_pretty(handle)` — plain text, no highlighting
- HTMLAdapter exists for JSON editor tree view (`json-editor.ts`)
- HTMLAdapter ignores `text` and `token_spans` fields — renders `kind_tag`/`label` as tree nodes

## Design

### 1. `layout_to_view_tree` — Bridge Function

**File:** `protocol/formatted_view.mbt`

```moonbit
pub fn layout_to_view_tree(
  layout : @pretty.Layout[@pretty.SyntaxCategory],
  width? : Int = 80,
) -> ViewNode
```

**Algorithm:**

1. Call `@pretty.resolve(width, layout)` to get `Array[Cmd[SyntaxCategory]]`
2. Walk the command stream, accumulating per-line state:
   - `line_text: StringBuilder` — current line's text content
   - `line_spans: Array[TokenSpan]` — current line's token spans
   - `ann_stack: Array[(SyntaxCategory, Int)]` — open annotation start positions (line-relative offset)
   - `offset: Int` — current position within the line
3. On `CText(s)`: append to `line_text`, advance `offset`
4. On `CAnnStart(cat)`: push `(cat, offset)` onto `ann_stack`
5. On `CAnnEnd(_)`: pop from `ann_stack`, create `TokenSpan(role=category_to_role(cat), start, end=offset)`
6. On `CNewline(indent)`: flush current line as a child ViewNode, then:
   - Split any open annotations: close them on the current line, re-open on the new line at offset 0
   - Start new line with `indent` spaces prepended
7. After the loop: flush the final line

**Output structure:**

```
ViewNode(
  id = NodeId(0),
  kind_tag = "formatted-text",
  label = "formatted-text",
  text = None,
  text_range = (0, 0),
  children = [
    ViewNode(id=NodeId(1), kind_tag="line", label="", text=Some("let fact = λn."), token_spans=[...]),
    ViewNode(id=NodeId(2), kind_tag="line", label="", text=Some("  if n == 0"),    token_spans=[...]),
    ...
  ]
)
```

**NodeId assignment:** Sequential integers. `NodeId(0)` for root, `NodeId(1..N)` for lines. These are stable enough for positional diffing — the ViewUpdater matches children by index.

**SyntaxCategory → role string:**

| SyntaxCategory | TokenSpan role  |
|----------------|-----------------|
| Keyword        | `"keyword"`     |
| Identifier     | `"identifier"`  |
| Number         | `"number"`      |
| StringLit      | `"string"`      |
| Operator       | `"operator"`    |
| Punctuation    | `"punctuation"` |
| Comment        | `"comment"`     |
| Error          | `"error"`       |

**Dependency change:** `protocol/moon.pkg` adds `"dowdiness/pretty" @pretty`.

### 2. Editor Integration

**File:** `editor/sync_editor_pretty.mbt`

Generic method alongside existing `get_view_tree`:

```moonbit
pub fn SyncEditor::get_pretty_view[T : @pretty.Pretty](
  self : SyncEditor[T],
) -> @protocol.ViewNode {
  let ast = self.get_ast()
  let layout = @pretty.Pretty::to_layout(ast)
  @protocol.layout_to_view_tree(layout, width=80)
}
```

Incremental patching with its own `ViewUpdateState`:

```moonbit
pub fn compute_pretty_patches[T : @pretty.Pretty](
  state : ViewUpdateState,
  editor : SyncEditor[T],
) -> Array[@protocol.ViewPatch] {
  let patches : Array[@protocol.ViewPatch] = []
  let current = Some(editor.get_pretty_view())
  match (state.previous, current) {
    (None, Some(curr)) =>
      patches.push(@protocol.ViewPatch::FullTree(root=Some(curr)))
    (Some(prev), Some(curr)) =>
      diff_view_nodes(prev, curr, patches)
    _ =>
      patches.push(@protocol.ViewPatch::FullTree(root=None))
  }
  state.previous = current
  patches
}
```

**Note on `get_ast` genericity:** Currently `get_ast()` is defined only on
`SyncEditor[@ast.Term]`. For this implementation, the FFI layer
(`ffi/canopy_pretty.mbt`) calls `editor.get_ast()` on the concrete
`SyncEditor[@ast.Term]` and then calls `@pretty.Pretty::to_layout(ast)`.
The bridge function `layout_to_view_tree` is fully generic and works for
JSON too. Generalizing `get_ast` to all `SyncEditor[T]` is a separate
concern that would be addressed when adding pretty view for JSON.

### 3. FFI Exports

**File:** `ffi/canopy_pretty.mbt`

```moonbit
pub fn get_pretty_view_json(handle : Int) -> String
pub fn compute_pretty_patches_json(handle : Int) -> String
```

Each handle's state gains a `pretty_view_state: ViewUpdateState` for
diffing across calls. Registered alongside the existing
`view_update_state`.

Added to `ffi/moon.pkg` link exports.

### 4. HTMLAdapter Text-Display Rendering

**File:** `lib/editor-adapter/html-adapter.ts`

In `renderNode`, detect text-display nodes:

```typescript
private renderNode(node: ViewNode, edgeLabel: string | null, isRoot: boolean): HTMLElement {
  // Text-display node: has text content + token spans
  if (node.text != null && node.token_spans.length > 0) {
    return this.renderTextLine(node);
  }
  // Formatted-text container: render as <pre> with line children
  if (node.kind_tag === 'formatted-text') {
    return this.renderFormattedText(node, isRoot);
  }
  // ... existing tree rendering ...
}
```

`renderFormattedText` creates a `<pre class="formatted-text">` and appends
each child via `renderNode` (which hits `renderTextLine` for line children).

`renderTextLine` creates a `<div class="line">` and walks `token_spans`
sorted by `start`, filling:
- Unstyled text for gaps between spans
- `<span class="${role}">` for each span

CSS classes map to the existing Canopy palette:
- `.keyword { color: #c792ea; }`
- `.identifier { color: #82aaff; }`
- `.number { color: #f78c6c; }`
- `.string { color: #c3e88d; }`
- `.operator { color: #ff5370; }`
- `.punctuation { color: #89ddff; }`
- `.comment { color: #546e7a; font-style: italic; }`
- `.error { color: #ff5370; text-decoration: underline wavy; }`

### 5. Web Editor Change

**File:** `examples/web/src/editor.ts`

Replace:

```typescript
astOutputEl.textContent = crdt.get_ast_pretty(handle);
```

With:

```typescript
const patches: ViewPatch[] = JSON.parse(crdt.compute_pretty_patches_json(handle));
prettyAdapter.applyPatches(patches);
```

Where `prettyAdapter` is an `HTMLAdapter` instance targeting the `ast-output`
element (or a replacement container), initialized once at editor creation.

### 6. Property-Based Tests

**File:** `loom/examples/lambda/src/ast/arbitrary.mbt` (or `arbitrary_wbtest.mbt`)

**Prerequisite: `Arbitrary` for `Term`**

Bounded-depth recursive generator (~30-40 lines). Produces well-formed terms:
- Leaf: `Int(n)`, `Var(name)`, `Unit`
- Unary: `Lam(name, body)`
- Binary: `App(f, x)`, `Bop(op, l, r)`
- Ternary: `If(cond, then, else)`
- Compound: `Module(defs, body)` (small def count)

Depth limit prevents divergence. Variable names drawn from a small pool
(`"x"`, `"y"`, `"f"`, `"n"`) for realistic output.

**Property 1: Pretty roundtrip**

```moonbit
test "parse(pretty_print(term)) == term" {
  @qc.test(fn(term : Term) {
    let formatted = @pretty.pretty_print(term)
    let reparsed = parse(formatted)
    assert_eq!(reparsed, term)
  })
}
```

Validates the commuting diagram from
`docs/architecture/multi-representation-system.md`.

**Property 2: View tree text consistency**

```moonbit
test "view tree text == render_string" {
  @qc.test(fn(term : Term) {
    let layout = @pretty.Pretty::to_layout(term)
    let view = @protocol.layout_to_view_tree(layout)
    let view_text = join_line_texts(view)
    let expected = @pretty.render_string(layout)
    assert_eq!(view_text, expected)
  })
}
```

Ensures `layout_to_view_tree` preserves the rendered text exactly.

**Property 3: Span coverage — no overlaps**

```moonbit
test "token spans do not overlap within a line" {
  @qc.test(fn(term : Term) {
    let layout = @pretty.Pretty::to_layout(term)
    let view = @protocol.layout_to_view_tree(layout)
    for line in view.children {
      let sorted = line.token_spans.copy()
      sorted.sort_by(fn(a, b) { a.start.compare(b.start) })
      for i = 1; i < sorted.length(); i = i + 1 {
        assert_true!(sorted[i].start >= sorted[i - 1].end)
      }
    }
  })
}
```

## Validation

- `moon check` passes with new `@pretty` dependency in `protocol/`
- `moon test` — all existing tests green + new property tests pass
- `moon test -p dowdiness/canopy/protocol` — `layout_to_view_tree` unit tests
- `moon test -p dowdiness/lambda` — property tests (pretty roundtrip, view tree consistency, span coverage)
- `cd examples/web && npm run dev` — formatted AST panel shows syntax-highlighted output
- Manual: edit lambda expression → pretty view updates incrementally
- `moon info && moon fmt` — interfaces and formatting clean
