# Pretty-Printer ViewNode Bridge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the pretty-printer engine into the protocol layer so any language implementing `Pretty` gets syntax-highlighted formatted display through the ViewNode → ViewPatch → Adapter pipeline.

**Architecture:** `Layout[SyntaxCategory]` → `layout_to_view_tree()` produces per-line ViewNode children with token_spans → existing ViewUpdater diffs → HTMLAdapter renders syntax-highlighted lines. New files: `protocol/formatted_view.mbt`, `editor/sync_editor_pretty.mbt`, `ffi/canopy_pretty.mbt`. Small HTMLAdapter extension (~20 lines). Property-based tests validate the roundtrip.

**Tech Stack:** MoonBit (protocol, editor, FFI), TypeScript (HTMLAdapter), QuickCheck (`@qc`)

**Design spec:** `docs/plans/2026-04-02-pretty-printer-viewnode-bridge-design.md`

---

## File Structure

```
protocol/formatted_view.mbt          # NEW — layout_to_view_tree bridge
protocol/formatted_view_wbtest.mbt   # NEW — unit tests
protocol/moon.pkg                    # MODIFY — add @pretty import
editor/sync_editor_pretty.mbt        # NEW — get_pretty_view + compute_pretty_patches
ffi/canopy_pretty.mbt                # NEW — FFI exports
ffi/moon.pkg                         # MODIFY — add link exports
lib/editor-adapter/html-adapter.ts   # MODIFY — add renderTextLine + renderFormattedText
examples/web/src/editor.ts           # MODIFY — use protocol-based pretty view
loom/examples/lambda/src/ast/term_arbitrary_wbtest.mbt  # NEW — Arbitrary for Term
loom/examples/lambda/src/pretty_roundtrip_test.mbt      # NEW — property tests
loom/examples/lambda/src/moon.pkg    # MODIFY — add test imports
```

---

### Task 1: Add `@pretty` Import to Protocol Package

**Files:**
- Modify: `protocol/moon.pkg`

- [ ] **Step 1: Add the import**

In `protocol/moon.pkg`, add `"dowdiness/pretty" @pretty` to the import list:

```
import {
  "dowdiness/canopy/core" @core,
  "dowdiness/loom/core" @loomcore,
  "dowdiness/pretty" @pretty,
  "moonbitlang/core/json",
}
```

- [ ] **Step 2: Verify it compiles**

Run: `moon check`
Expected: passes (no consumers of `@pretty` yet, just the import)

- [ ] **Step 3: Commit**

```bash
git add protocol/moon.pkg
git commit -m "chore: add @pretty import to protocol package"
```

---

### Task 2: Implement `layout_to_view_tree` Bridge Function

**Files:**
- Create: `protocol/formatted_view.mbt`

- [ ] **Step 1: Create the bridge function**

Create `protocol/formatted_view.mbt`:

```moonbit
// formatted_view: Converts pretty-printer Layout into ViewNode tree.
// Each rendered line becomes a child ViewNode with text + token_spans.
// This is the text-format renderer for the multi-representation system
// (see docs/architecture/multi-representation-system.md).

///|
fn category_to_role(cat : @pretty.SyntaxCategory) -> String {
  match cat {
    Keyword => "keyword"
    Identifier => "identifier"
    Number => "number"
    StringLit => "string"
    Operator => "operator"
    Punctuation => "punctuation"
    Comment => "comment"
    Error => "error"
  }
}

///|
/// Convert a pretty-print layout into a ViewNode tree for formatted text display.
/// Each rendered line becomes a child ViewNode with text and token_spans.
/// Annotations that span line breaks are split into per-line TokenSpans.
pub fn layout_to_view_tree(
  layout : @pretty.Layout[@pretty.SyntaxCategory],
  width? : Int = 80,
) -> ViewNode {
  let cmds = @pretty.resolve(width, layout)
  let children : Array[ViewNode] = []
  let line_buf = StringBuilder::new()
  let line_spans : Array[TokenSpan] = []
  let ann_stack : Array[(@pretty.SyntaxCategory, Int)] = []
  let mut offset = 0
  let mut line_id = 1
  // flush_line: emit current line as a ViewNode child, handle cross-line spans
  fn flush_line() {
    let text = line_buf.to_string()
    if text.length() > 0 || children.length() > 0 {
      children.push(
        ViewNode(
          id=@core.NodeId::from_int(line_id),
          kind_tag="line",
          label="",
          text=Some(text),
          text_range=(0, 0),
          token_spans=line_spans.copy(),
          css_class="line",
        ),
      )
      line_id = line_id + 1
    }
    line_buf.reset()
    line_spans.clear()
    offset = 0
    // Re-open any annotations that were split across the line break
    for i = 0; i < ann_stack.length(); i = i + 1 {
      ann_stack[i] = (ann_stack[i].0, 0)
    }
  }

  for cmd in cmds {
    match cmd {
      @pretty.CText(s) => {
        line_buf.write_string(s)
        offset = offset + s.length()
      }
      @pretty.CNewline(indent) => {
        // Close any open annotations on the current line
        for i = ann_stack.length() - 1; i >= 0; i = i - 1 {
          let (cat, start) = ann_stack[i]
          if offset > start {
            line_spans.push(
              TokenSpan(role=category_to_role(cat), start~, end=offset),
            )
          }
        }
        flush_line()
        // Add indentation
        for _ = 0; _ < indent; _ = _ + 1 {
          line_buf.write_char(' ')
        }
        offset = indent
        // Re-open spans at the indent position
        for i = 0; i < ann_stack.length(); i = i + 1 {
          ann_stack[i] = (ann_stack[i].0, offset)
        }
      }
      @pretty.CAnnStart(cat) => ann_stack.push((cat, offset))
      @pretty.CAnnEnd(_) =>
        if ann_stack.pop() is Some((cat, start)) && offset > start {
          line_spans.push(
            TokenSpan(role=category_to_role(cat), start~, end=offset),
          )
        }
    }
  }
  // Flush final line (close any remaining open annotations)
  for i = ann_stack.length() - 1; i >= 0; i = i - 1 {
    let (cat, start) = ann_stack[i]
    if offset > start {
      line_spans.push(
        TokenSpan(role=category_to_role(cat), start~, end=offset),
      )
    }
  }
  flush_line()
  ViewNode(
    id=@core.NodeId::from_int(0),
    kind_tag="formatted-text",
    label="formatted-text",
    text_range=(0, 0),
    children~,
    css_class="formatted-text",
  )
}
```

- [ ] **Step 2: Run moon check**

Run: `moon check`
Expected: passes

- [ ] **Step 3: Commit**

```bash
git add protocol/formatted_view.mbt
git commit -m "feat(protocol): add layout_to_view_tree bridge function"
```

---

### Task 3: Unit Tests for `layout_to_view_tree`

**Files:**
- Create: `protocol/formatted_view_wbtest.mbt`

- [ ] **Step 1: Write unit tests**

Create `protocol/formatted_view_wbtest.mbt`:

```moonbit
///|
test "layout_to_view_tree: single line, no annotations" {
  let layout = @pretty.text("hello world")
  let view = layout_to_view_tree(layout)
  assert_eq!(view.kind_tag, "formatted-text")
  assert_eq!(view.children.length(), 1)
  assert_eq!(view.children[0].text, Some("hello world"))
  assert_eq!(view.children[0].token_spans.length(), 0)
}

///|
test "layout_to_view_tree: single line with annotation" {
  let layout = @pretty.annotate(
    @pretty.SyntaxCategory::Keyword,
    @pretty.text("let"),
  )
  let view = layout_to_view_tree(layout)
  assert_eq!(view.children.length(), 1)
  let line = view.children[0]
  assert_eq!(line.text, Some("let"))
  assert_eq!(line.token_spans.length(), 1)
  assert_eq!(line.token_spans[0].role, "keyword")
  assert_eq!(line.token_spans[0].start, 0)
  assert_eq!(line.token_spans[0].end, 3)
}

///|
test "layout_to_view_tree: multi-line with nest" {
  // "let\n  x" (keyword "let", newline, indented identifier "x")
  let layout = @pretty.concat(
    @pretty.annotate(@pretty.SyntaxCategory::Keyword, @pretty.text("let")),
    @pretty.nest(
      2,
      @pretty.concat(
        @pretty.HardLine,
        @pretty.annotate(
          @pretty.SyntaxCategory::Identifier,
          @pretty.text("x"),
        ),
      ),
    ),
  )
  let view = layout_to_view_tree(layout)
  assert_eq!(view.children.length(), 2)
  // Line 0: "let"
  let line0 = view.children[0]
  assert_eq!(line0.text, Some("let"))
  assert_eq!(line0.token_spans.length(), 1)
  assert_eq!(line0.token_spans[0].role, "keyword")
  // Line 1: "  x" (2 spaces indent + identifier)
  let line1 = view.children[1]
  assert_eq!(line1.text, Some("  x"))
  assert_eq!(line1.token_spans.length(), 1)
  assert_eq!(line1.token_spans[0].role, "identifier")
  assert_eq!(line1.token_spans[0].start, 2)
  assert_eq!(line1.token_spans[0].end, 3)
}

///|
test "layout_to_view_tree: annotation spanning line break" {
  // A keyword annotation wrapping text + hardline + text
  let inner = @pretty.concat(
    @pretty.text("if"),
    @pretty.concat(@pretty.HardLine, @pretty.text("then")),
  )
  let layout = @pretty.annotate(@pretty.SyntaxCategory::Keyword, inner)
  let view = layout_to_view_tree(layout)
  assert_eq!(view.children.length(), 2)
  // Line 0: "if" with keyword span
  let line0 = view.children[0]
  assert_eq!(line0.text, Some("if"))
  assert_eq!(line0.token_spans.length(), 1)
  assert_eq!(line0.token_spans[0].role, "keyword")
  assert_eq!(line0.token_spans[0].start, 0)
  assert_eq!(line0.token_spans[0].end, 2)
  // Line 1: "then" with keyword span (split from same annotation)
  let line1 = view.children[1]
  assert_eq!(line1.text, Some("then"))
  assert_eq!(line1.token_spans.length(), 1)
  assert_eq!(line1.token_spans[0].role, "keyword")
  assert_eq!(line1.token_spans[0].start, 0)
  assert_eq!(line1.token_spans[0].end, 4)
}

///|
test "layout_to_view_tree: mixed annotated and unannotated text" {
  // "let x = 42"
  let layout = @pretty.concat(
    @pretty.annotate(@pretty.SyntaxCategory::Keyword, @pretty.text("let")),
    @pretty.concat(
      @pretty.text(" "),
      @pretty.concat(
        @pretty.annotate(
          @pretty.SyntaxCategory::Identifier,
          @pretty.text("x"),
        ),
        @pretty.concat(
          @pretty.text(" = "),
          @pretty.annotate(
            @pretty.SyntaxCategory::Number,
            @pretty.text("42"),
          ),
        ),
      ),
    ),
  )
  let view = layout_to_view_tree(layout)
  assert_eq!(view.children.length(), 1)
  let line = view.children[0]
  assert_eq!(line.text, Some("let x = 42"))
  assert_eq!(line.token_spans.length(), 3)
  // keyword "let" at 0-3
  assert_eq!(line.token_spans[0].role, "keyword")
  assert_eq!(line.token_spans[0].start, 0)
  assert_eq!(line.token_spans[0].end, 3)
  // identifier "x" at 4-5
  assert_eq!(line.token_spans[1].role, "identifier")
  assert_eq!(line.token_spans[1].start, 4)
  assert_eq!(line.token_spans[1].end, 5)
  // number "42" at 8-10
  assert_eq!(line.token_spans[2].role, "number")
  assert_eq!(line.token_spans[2].start, 8)
  assert_eq!(line.token_spans[2].end, 10)
}

///|
test "layout_to_view_tree: empty layout" {
  let layout : @pretty.Layout[@pretty.SyntaxCategory] = @pretty.Empty
  let view = layout_to_view_tree(layout)
  assert_eq!(view.kind_tag, "formatted-text")
  assert_eq!(view.children.length(), 0)
}

///|
test "layout_to_view_tree: node IDs are sequential" {
  let layout = @pretty.concat(
    @pretty.text("a"),
    @pretty.concat(@pretty.HardLine, @pretty.text("b")),
  )
  let view = layout_to_view_tree(layout)
  assert_eq!(view.id, @core.NodeId::from_int(0))
  assert_eq!(view.children[0].id, @core.NodeId::from_int(1))
  assert_eq!(view.children[1].id, @core.NodeId::from_int(2))
}

///|
test "layout_to_view_tree: group flattening (narrow width)" {
  // Group with "a b" that should break at width=3
  let layout = @pretty.group(
    @pretty.concat(
      @pretty.text("a"),
      @pretty.concat(@pretty.Line, @pretty.text("b")),
    ),
  )
  // At width=80: fits flat → "a b" on one line
  let wide = layout_to_view_tree(layout, width=80)
  assert_eq!(wide.children.length(), 1)
  assert_eq!(wide.children[0].text, Some("a b"))
  // At width=1: breaks → "a" and "b" on separate lines
  let narrow = layout_to_view_tree(layout, width=1)
  assert_eq!(narrow.children.length(), 2)
  assert_eq!(narrow.children[0].text, Some("a"))
  assert_eq!(narrow.children[1].text, Some("b"))
}
```

- [ ] **Step 2: Run tests**

Run: `moon test -p dowdiness/canopy/protocol`
Expected: all new tests pass

- [ ] **Step 3: Commit**

```bash
git add protocol/formatted_view_wbtest.mbt
git commit -m "test(protocol): add layout_to_view_tree unit tests"
```

---

### Task 4: Editor Integration — `get_pretty_view` and `compute_pretty_patches`

**Files:**
- Create: `editor/sync_editor_pretty.mbt`

- [ ] **Step 1: Create the editor methods**

Create `editor/sync_editor_pretty.mbt`:

```moonbit
// Pretty-printer integration for SyncEditor.
// Produces ViewNode trees from the Pretty trait, enabling syntax-highlighted
// formatted display through the ViewPatch → Adapter pipeline.

///|
/// Lambda-specific: returns the pretty-printed ViewNode tree.
/// Each line becomes a child ViewNode with text + token_spans.
pub fn SyncEditor::get_pretty_view(
  self : SyncEditor[@ast.Term],
) -> @protocol.ViewNode {
  let ast = self.get_ast()
  let layout = @pretty.Pretty::to_layout(ast)
  @protocol.layout_to_view_tree(layout, width=80)
}

///|
/// Compute incremental pretty-view patches for a lambda editor.
/// Uses a separate ViewUpdateState from the structural view.
pub fn compute_pretty_patches(
  state : ViewUpdateState,
  editor : SyncEditor[@ast.Term],
) -> Array[@protocol.ViewPatch] {
  let patches : Array[@protocol.ViewPatch] = []
  let current = editor.get_pretty_view()
  match state.previous {
    None => patches.push(@protocol.ViewPatch::FullTree(root=Some(current)))
    Some(prev) => diff_view_nodes(prev, current, patches)
  }
  state.previous = Some(current)
  patches
}
```

- [ ] **Step 2: Run moon check**

Run: `moon check`
Expected: passes

- [ ] **Step 3: Commit**

```bash
git add editor/sync_editor_pretty.mbt
git commit -m "feat(editor): add get_pretty_view and compute_pretty_patches"
```

---

### Task 5: FFI Exports

**Files:**
- Create: `ffi/canopy_pretty.mbt`
- Modify: `ffi/moon.pkg`

- [ ] **Step 1: Create the FFI file**

Create `ffi/canopy_pretty.mbt`:

```moonbit
// Pretty-printer FFI — ViewNode tree and ViewPatch streams for formatted display

///|
let pretty_view_states : Map[Int, @editor.ViewUpdateState] = Map::new()

///|
/// Get the pretty-printed ViewNode tree as JSON for a lambda editor.
pub fn get_pretty_view_json(handle : Int) -> String {
  match editors.get(handle) {
    Some(ed) => ed.get_pretty_view().to_json().stringify()
    None => "null"
  }
}

///|
/// Compute incremental pretty-view patches for a lambda editor.
/// Returns a JSON array of ViewPatch objects.
pub fn compute_pretty_patches_json(handle : Int) -> String {
  match editors.get(handle) {
    Some(ed) => {
      let state = match pretty_view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::new()
          pretty_view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_pretty_patches(state, ed)
      Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}
```

- [ ] **Step 2: Add link exports to ffi/moon.pkg**

In `ffi/moon.pkg`, add the two new exports to the `link` section. Find the existing `link` object and add:

```
"get_pretty_view_json",
"compute_pretty_patches_json",
```

- [ ] **Step 3: Clean up pretty_view_states in destroy_editor**

In `ffi/canopy_lambda.mbt`, find the `destroy_editor` function and add cleanup:

```moonbit
///|
/// Destroy an editor instance and free its resources.
pub fn destroy_editor(handle : Int) -> Unit {
  editors.remove(handle)
  view_states.remove(handle)
  pretty_view_states.remove(handle)
  if last_created_handle.val == Some(handle) {
    last_created_handle.val = None
  }
}
```

- [ ] **Step 4: Run moon check**

Run: `moon check`
Expected: passes

- [ ] **Step 5: Run moon info && moon fmt**

Run: `moon info && moon fmt`
Expected: interfaces updated, code formatted

- [ ] **Step 6: Commit**

```bash
git add ffi/canopy_pretty.mbt ffi/moon.pkg ffi/canopy_lambda.mbt
git commit -m "feat(ffi): add pretty-view JSON exports"
```

---

### Task 6: HTMLAdapter — Text-Display Rendering

**Files:**
- Modify: `lib/editor-adapter/html-adapter.ts`

- [ ] **Step 1: Add renderFormattedText and renderTextLine methods**

In `html-adapter.ts`, add two private methods before the existing `renderDiagnostics` method:

```typescript
  private renderFormattedText(node: ViewNode, isRoot: boolean): HTMLElement {
    const pre = document.createElement('pre');
    pre.className = isRoot ? 'formatted-text root' : 'formatted-text';
    pre.setAttribute('data-node-id', String(node.id));
    for (let i = 0; i < node.children.length; i++) {
      pre.appendChild(this.renderNode(node.children[i], null, false));
    }
    return pre;
  }

  private renderTextLine(node: ViewNode): HTMLElement {
    const div = document.createElement('div');
    div.className = 'line';
    div.setAttribute('data-node-id', String(node.id));
    const text = node.text ?? '';
    const spans = [...node.token_spans].sort((a, b) => a.start - b.start);
    let pos = 0;
    for (const span of spans) {
      // Gap before this span: unstyled text
      if (span.start > pos) {
        div.appendChild(document.createTextNode(text.slice(pos, span.start)));
      }
      // Styled span
      const el = document.createElement('span');
      el.className = span.role;
      el.textContent = text.slice(span.start, span.end);
      div.appendChild(el);
      pos = span.end;
    }
    // Trailing unstyled text
    if (pos < text.length) {
      div.appendChild(document.createTextNode(text.slice(pos)));
    }
    return div;
  }
```

- [ ] **Step 2: Add dispatch in renderNode**

At the top of the existing `renderNode` method (before `const hasChildren = ...`), add:

```typescript
    // Formatted text display (pretty-printer output)
    if (node.kind_tag === 'formatted-text') {
      return this.renderFormattedText(node, isRoot);
    }
    if (node.text != null && node.token_spans.length > 0) {
      return this.renderTextLine(node);
    }
```

- [ ] **Step 3: Commit**

```bash
git add lib/editor-adapter/html-adapter.ts
git commit -m "feat(adapter): add text-display rendering for pretty-print ViewNodes"
```

---

### Task 7: Web Editor Integration

**Files:**
- Modify: `examples/web/src/editor.ts`

- [ ] **Step 1: Replace ad-hoc pretty output with protocol-based rendering**

Replace the full contents of `examples/web/src/editor.ts`:

```typescript
// Lambda Calculus Editor — thin DOM bridge over MoonBit CRDT backend

import * as crdt from '@moonbit/crdt';
import * as graphviz from '@moonbit/graphviz';
import { HTMLAdapter } from '../../../lib/editor-adapter/html-adapter';
import type { ViewPatch } from '../../../lib/editor-adapter/types';

export function createEditor(agentId: string) {
  const handle = crdt.create_editor(agentId);

  const editorEl = document.getElementById('editor') as HTMLDivElement;
  const astGraphEl = document.getElementById('ast-graph') as HTMLDivElement;
  const astOutputEl = document.getElementById('ast-output') as HTMLElement;
  const errorEl = document.getElementById('error-output') as HTMLUListElement;

  // Protocol-based pretty-print adapter
  const prettyAdapter = new HTMLAdapter(astOutputEl);

  let lastText = '';
  let scheduled = false;

  function updateUI() {
    const text = editorEl.textContent || '';
    if (text !== lastText) {
      crdt.set_text(handle, text);
      lastText = text;
    }

    // AST visualization (DOT → SVG via graphviz module)
    try {
      const dot = crdt.get_ast_dot_resolved(handle);
      const svg = graphviz.render_dot_to_svg(dot);
      astGraphEl.innerHTML = svg;

      // Dark theme: remove white background from SVG
      const polygon = astGraphEl.querySelector('g.graph polygon');
      if (polygon) polygon.setAttribute('fill', 'transparent');
    } catch (e) {
      astGraphEl.innerHTML = `<p style="color:#f44">Error: ${e}</p>`;
    }

    // Pretty-printed AST with syntax highlighting (via protocol)
    try {
      const patches: ViewPatch[] = JSON.parse(
        crdt.compute_pretty_patches_json(handle),
      );
      prettyAdapter.applyPatches(patches);
    } catch (e) {
      astOutputEl.textContent = `Pretty-print error: ${e}`;
    }

    // Errors
    const errors: string[] = JSON.parse(crdt.get_errors_json(handle));
    if (errors.length === 0) {
      errorEl.innerHTML = '<li>No errors</li>';
    } else {
      errorEl.innerHTML = errors
        .map(e => `<li class="error-item">${escapeHTML(e)}</li>`)
        .join('');
    }
  }

  editorEl.addEventListener('input', () => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => {
      scheduled = false;
      updateUI();
    });
  });

  return {
    handle,
    agentId,
    updateUI,
    getText: () => crdt.get_text(handle),
    setText: (text: string) => {
      editorEl.textContent = text;
      editorEl.dispatchEvent(new Event('input', { bubbles: true }));
    },
  };
}

function escapeHTML(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
```

- [ ] **Step 2: Build and verify**

Run: `moon build --target js --release && cd examples/web && npm run build`
Expected: builds without errors

- [ ] **Step 3: Commit**

```bash
git add examples/web/src/editor.ts
git commit -m "feat(web): replace ad-hoc AST display with protocol-based pretty view"
```

---

### Task 8: CSS for Syntax Highlighting

**Files:**
- Modify: `examples/web/index.html` or the relevant CSS file

- [ ] **Step 1: Find the CSS file for the lambda editor**

Check the `<style>` section in `examples/web/index.html` or any linked CSS file. Add the following syntax highlighting classes (these match the Canopy palette from `.impeccable.md`):

```css
/* Pretty-printer syntax highlighting */
.formatted-text {
  font-family: 'JetBrains Mono', monospace;
  font-size: 0.875rem;
  line-height: 1.5;
  padding: 1rem;
  margin: 0;
  overflow-x: auto;
  background: transparent;
}
.formatted-text .line {
  white-space: pre;
  min-height: 1.5em;
}
.keyword { color: #c792ea; }
.identifier { color: #82aaff; }
.number { color: #f78c6c; }
.string { color: #c3e88d; }
.operator { color: #ff5370; }
.punctuation { color: #89ddff; }
.comment { color: #546e7a; font-style: italic; }
.error { color: #ff5370; text-decoration: underline wavy; }
```

- [ ] **Step 2: Verify visually**

Run: `cd examples/web && npm run dev`
Open: `http://localhost:5173/`
Expected: the AST output panel shows syntax-highlighted formatted code instead of plain text

- [ ] **Step 3: Commit**

```bash
git add examples/web/index.html  # or the CSS file
git commit -m "style: add syntax highlighting CSS for pretty-print view"
```

---

### Task 9: Arbitrary for Term (Property Test Prerequisite)

**Files:**
- Create: `loom/examples/lambda/src/ast/term_arbitrary_wbtest.mbt`
- Modify: `loom/examples/lambda/src/ast/moon.pkg` (add `@qc` test import)

- [ ] **Step 0: Add quickcheck test import to ast package**

In `loom/examples/lambda/src/ast/moon.pkg`, add:

```
import {
  "moonbitlang/core/quickcheck" @qc,
} for "test"
```

- [ ] **Step 1: Create the Arbitrary implementation**

Create `loom/examples/lambda/src/ast/term_arbitrary_wbtest.mbt`:

```moonbit
///|
/// Bounded-depth recursive generator for well-formed lambda terms.
/// Used by property-based tests (pretty roundtrip, view tree consistency).
fn gen_term(gen : @qc.Gen, depth : Int) -> Term {
  let names = ["x", "y", "f", "n"]
  let name = names[gen.next_uint().to_int() % names.length()]
  if depth <= 0 {
    // Leaf nodes only
    match gen.next_uint().to_int() % 3 {
      0 => Int(gen.next_uint().to_int() % 100)
      1 => Var(name)
      _ => Unit
    }
  } else {
    match gen.next_uint().to_int() % 7 {
      0 => Int(gen.next_uint().to_int() % 100)
      1 => Var(name)
      2 => Lam(name, gen_term(gen, depth - 1))
      3 => App(gen_term(gen, depth - 1), gen_term(gen, depth - 1))
      4 => {
        let op : Bop = if gen.next_uint().to_int() % 2 == 0 {
          Plus
        } else {
          Minus
        }
        Bop(op, gen_term(gen, depth - 1), gen_term(gen, depth - 1))
      }
      5 =>
        If(
          gen_term(gen, depth - 1),
          gen_term(gen, depth - 1),
          gen_term(gen, depth - 1),
        )
      _ => {
        // Module with 1-3 definitions
        let num_defs = gen.next_uint().to_int() % 3 + 1
        let defs : Array[(VarName, Term)] = []
        for i = 0; i < num_defs; i = i + 1 {
          let def_name = names[i % names.length()]
          defs.push((def_name, gen_term(gen, depth - 1)))
        }
        Module(defs, gen_term(gen, depth - 1))
      }
    }
  }
}

///|
pub impl @qc.Arbitrary for Term with arbitrary(gen, _size) {
  gen_term(gen, 3)
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd loom/examples/lambda && moon check`
Expected: passes

- [ ] **Step 3: Commit**

```bash
cd loom/examples/lambda
git add src/ast/term_arbitrary_wbtest.mbt src/ast/moon.pkg
git commit -m "test(lambda): add Arbitrary impl for Term"
```

---

### Task 10: Property-Based Tests

The tests are split across two modules due to dependency boundaries:
- **Pretty roundtrip** (`parse(pretty_print(x)) == x`) lives in `dowdiness/lambda` — it only needs `@pretty` and the parser, both available in the lambda module.
- **View tree consistency** and **span coverage** tests live in `dowdiness/canopy/editor` — they need `@protocol.layout_to_view_tree` which is in the canopy module. The editor package already imports both `@pretty` and `@protocol`.

**Files:**
- Create: `loom/examples/lambda/src/pretty_roundtrip_test.mbt`
- Modify: `loom/examples/lambda/src/moon.pkg` (add `@pretty` test import)
- Create: `editor/pretty_view_test.mbt`

- [ ] **Step 1: Add `@pretty` test import to lambda module**

In `loom/examples/lambda/src/moon.pkg`, add to the existing `for "test"` block (or create one):

```
import {
  "dowdiness/pretty" @pretty,
} for "test"
```

- [ ] **Step 2: Create pretty roundtrip test in lambda module**

Create `loom/examples/lambda/src/pretty_roundtrip_test.mbt`:

```moonbit
///|
test "property: parse(pretty_print(term)) == term" {
  // Pretty roundtrip: formatting preserves semantics
  @qc.test(fn(term : @ast.Term) {
    // Skip error/unbound/hole nodes — they represent parse errors
    // and may not have parseable pretty-print output
    guard not(has_error_node(term)) else { return }
    let formatted = @pretty.pretty_print(term)
    let reparsed = parse(formatted)
    assert_eq!(reparsed, term)
  })
}

///|
fn has_error_node(term : @ast.Term) -> Bool {
  match term {
    Error(_) | Unbound(_) | Hole(_) => true
    Int(_) | Var(_) | Unit => false
    Lam(_, body) => has_error_node(body)
    App(f, x) => has_error_node(f) || has_error_node(x)
    Bop(_, l, r) => has_error_node(l) || has_error_node(r)
    If(c, t, e) => has_error_node(c) || has_error_node(t) || has_error_node(e)
    Module(defs, body) => {
      for def in defs {
        if has_error_node(def.1) {
          return true
        }
      }
      has_error_node(body)
    }
  }
}
```

- [ ] **Step 3: Run the pretty roundtrip test**

Run: `cd loom/examples/lambda && moon test -f pretty_roundtrip_test.mbt`
Expected: passes

- [ ] **Step 4: Create view tree consistency and span coverage tests in editor package**

Create `editor/pretty_view_test.mbt`:

```moonbit
///|
test "property: view tree text == render_string" {
  // layout_to_view_tree preserves the rendered text exactly
  @qc.test(fn(term : @ast.Term) {
    let layout = @pretty.Pretty::to_layout(term)
    let view = @protocol.layout_to_view_tree(layout)
    let buf = StringBuilder::new()
    for i, child in view.children {
      if i > 0 {
        buf.write_char('\n')
      }
      match child.text {
        Some(t) => buf.write_string(t)
        None => ()
      }
    }
    let view_text = buf.to_string()
    let expected = @pretty.render_string(layout)
    assert_eq!(view_text, expected)
  })
}

///|
test "property: token spans do not overlap within a line" {
  @qc.test(fn(term : @ast.Term) {
    let layout = @pretty.Pretty::to_layout(term)
    let view = @protocol.layout_to_view_tree(layout)
    for child in view.children {
      let sorted = child.token_spans.copy()
      sorted.sort_by(fn(a, b) { a.start.compare(b.start) })
      for i = 1; i < sorted.length(); i = i + 1 {
        assert_true!(sorted[i].start >= sorted[i - 1].end)
      }
    }
  })
}
```

- [ ] **Step 5: Run the editor tests**

Run: `moon test -p dowdiness/canopy/editor -f pretty_view_test.mbt`
Expected: both property tests pass

- [ ] **Step 6: Commit**

```bash
git add loom/examples/lambda/src/pretty_roundtrip_test.mbt loom/examples/lambda/src/moon.pkg editor/pretty_view_test.mbt
git commit -m "test: add property-based tests for pretty-print roundtrip and view tree"
```

---

### Task 11: Update Interfaces and Final Verification

**Files:**
- Multiple `.mbti` files (auto-generated)

- [ ] **Step 1: Update all interfaces**

Run: `moon info && moon fmt`
Expected: `.mbti` files updated with new public APIs

- [ ] **Step 2: Run full test suite**

Run: `moon test`
Expected: all tests pass

Run: `cd loom/examples/lambda && moon test`
Expected: all tests pass (including new property tests)

- [ ] **Step 3: Check API surface changes**

Run: `git diff *.mbti`
Expected: new entries for:
- `protocol/`: `layout_to_view_tree` function
- `editor/`: `get_pretty_view`, `compute_pretty_patches`
- `ffi/`: `get_pretty_view_json`, `compute_pretty_patches_json`

- [ ] **Step 4: Build JS target**

Run: `moon build --target js --release`
Expected: builds without errors

- [ ] **Step 5: Commit**

```bash
git add -A '*.mbti'
git commit -m "chore: update interfaces for pretty-printer ViewNode bridge"
```

---

### Task 12: Manual Web Verification

- [ ] **Step 1: Start dev server**

Run: `cd examples/web && npm run dev`

- [ ] **Step 2: Test lambda editor**

Open: `http://localhost:5173/`

1. Type `let x = 1 + 2` → AST panel shows syntax-highlighted formatted output
2. Type a longer expression → verify line breaks appear at width boundary
3. Verify colors: `let` in purple (#c792ea), `x` in blue (#82aaff), `1`, `2` in orange (#f78c6c), `+` in red (#ff5370)
4. Edit the expression → verify the pretty view updates incrementally

- [ ] **Step 3: Test JSON editor still works**

Open: `http://localhost:5173/json.html`
Verify: JSON tree view renders correctly (no regression from HTMLAdapter changes)
