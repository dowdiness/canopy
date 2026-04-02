# Inspector Panel — Rich Node Details — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the ideal editor inspector panel to show source range, source text preview, and token spans for the selected node.

**Architecture:** Add a `get_all_token_spans` accessor to `SourceMap`, extend `view_node_details` to render range/source/tokens inside the NODE section, add two CSS classes. No new files, no model changes.

**Tech Stack:** MoonBit (view code, framework accessor), CSS (inspector styles)

**Spec:** `docs/plans/2026-04-01-inspector-panel-design.md`

---

### Task 1: Add `get_all_token_spans` accessor to SourceMap

**Files:**
- Modify: `framework/core/source_map.mbt:264` (append after `get_token_span`)
- Modify: `framework/core/pkg.generated.mbti` (via `moon info`)

- [ ] **Step 1: Write the test**

Create `framework/core/source_map_wbtest.mbt`:

```moonbit
///|
test "get_all_token_spans returns sorted pairs" {
  let sm = SourceMap::new()
  let nid = NodeId::from_int(1)
  sm.set_token_span(nid, "param", @loomcore.Range::new(5, 8))
  sm.set_token_span(nid, "name", @loomcore.Range::new(1, 3))
  let spans = sm.get_all_token_spans(nid)
  // Should be sorted by range start: name(1..3) before param(5..8)
  inspect!(spans.length(), content="2")
  inspect!(spans[0].0, content="name")
  inspect!(spans[0].1.start, content="1")
  inspect!(spans[1].0, content="param")
  inspect!(spans[1].1.start, content="5")
}

///|
test "get_all_token_spans returns empty for unknown node" {
  let sm = SourceMap::new()
  let nid = NodeId::from_int(99)
  let spans = sm.get_all_token_spans(nid)
  inspect!(spans.length(), content="0")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/canopy/framework/core -f source_map_wbtest.mbt`
Expected: FAIL — `get_all_token_spans` is not defined.

- [ ] **Step 3: Implement `get_all_token_spans`**

Append to `framework/core/source_map.mbt` after line 264:

```moonbit
///|
/// Get all token-level spans for a node as (role, range) pairs sorted by
/// range start position. Returns an empty array if no spans are recorded.
pub fn SourceMap::get_all_token_spans(
  self : SourceMap,
  node_id : NodeId,
) -> Array[(String, Range)] {
  match self.token_spans.get(node_id) {
    Some(roles) => {
      let pairs : Array[(String, Range)] = []
      for role, range in roles {
        pairs.push((role, range))
      }
      pairs.sort_by(fn(a, b) { a.1.start.compare(b.1.start) })
      pairs
    }
    None => []
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/canopy/framework/core -f source_map_wbtest.mbt`
Expected: PASS (both tests)

- [ ] **Step 5: Update interface and format**

Run: `moon info && moon fmt`

Verify `pkg.generated.mbti` now includes:
```
pub fn SourceMap::get_all_token_spans(Self, NodeId) -> Array[(String, @dowdiness/loom/core.Range)]
```

- [ ] **Step 6: Run full check**

Run: `moon check && moon test`
Expected: all pass, no regressions.

- [ ] **Step 7: Commit**

```bash
git add framework/core/source_map.mbt framework/core/source_map_wbtest.mbt framework/core/pkg.generated.mbti
git commit -m "feat(framework): add SourceMap::get_all_token_spans accessor"
```

---

### Task 2: Add CSS classes for source preview and token spans

**Files:**
- Modify: `examples/ideal/web/styles/editor.css:533` (append after `.action-btn.danger:hover`)

- [ ] **Step 1: Add `.source-preview` and `.token-span-row` classes**

Insert after the `.action-btn.danger:hover` block (line 533) in `examples/ideal/web/styles/editor.css`:

```css
.source-preview {
  background: var(--canopy-surface);
  border-radius: var(--radius-sm);
  padding: var(--space-sm) var(--space-md);
  margin-top: var(--space-sm);
  font-family: var(--canopy-font-mono);
  font-size: var(--text-caption);
  line-height: var(--leading-normal);
  color: var(--canopy-fg);
  white-space: pre;
  overflow-x: auto;
  max-height: 4.5em;
  overflow-y: auto;
}

.token-span-row {
  display: flex;
  gap: var(--space-sm);
  padding: 2px 0;
  line-height: var(--leading-normal);
  font-size: var(--text-caption);
}

.token-span-role {
  color: var(--canopy-muted);
  font-family: var(--canopy-font-mono);
  min-width: 52px;
  flex-shrink: 0;
}

.token-span-range {
  color: var(--canopy-text-dim);
  font-family: var(--canopy-font-mono);
  min-width: 44px;
  flex-shrink: 0;
  font-variant-numeric: tabular-nums;
}

.token-span-text {
  color: var(--canopy-identifier);
  font-family: var(--canopy-font-mono);
}
```

- [ ] **Step 2: Commit**

```bash
git add examples/ideal/web/styles/editor.css
git commit -m "style(ideal): add source-preview and token-span-row CSS classes"
```

---

### Task 3: Extend `view_node_details` with range, source preview, and token spans

**Files:**
- Modify: `examples/ideal/main/view_inspector.mbt:65-87` (replace `view_node_details`)
- Modify: `examples/ideal/main/view_inspector.mbt:143-145` (update call site)

- [ ] **Step 1: Replace `view_node_details` function**

Replace lines 65–87 of `examples/ideal/main/view_inspector.mbt` (the entire `view_node_details` function) with:

```moonbit
///|
/// Render the node details section of the inspector.
/// Includes source range, source text preview, and token spans.
fn view_node_details(
  node : @proj.InteractiveTreeNode[@ast.Term],
  model : Model,
) -> Html {
  let kind = kind_of(node.label)
  let count = children_count(node)
  let items : Array[Html] = [
    span(class="panel-label", [text("NODE")]),
    div(class="inspector-row", [
      span(class="inspector-key", [text("Kind")]),
      span(class="inspector-value kind-\{kind}", [text(kind)]),
    ]),
    div(class="inspector-row", [
      span(class="inspector-key", [text("Label")]),
      span(class="inspector-value", [text(node.label)]),
    ]),
    div(class="inspector-row", [
      span(class="inspector-key", [text("Children")]),
      span(class="inspector-value", [text(count.to_string())]),
    ]),
    div(class="inspector-row", [
      span(class="inspector-key", [text("ID")]),
      span(class="inspector-value", [text(node_id_to_string(node.id))]),
    ]),
  ]
  // Range row + source preview (omitted for zero-length ranges)
  let range_start = node.text_range.start
  let range_end = node.text_range.end
  if range_start != range_end {
    items.push(
      div(class="inspector-row", [
        span(class="inspector-key", [text("Range")]),
        span(class="inspector-value", [
          text("\{range_start}..\{range_end}"),
        ]),
      ]),
    )
    // Source text preview, clamped and truncated
    let source = model.editor.get_text()
    let clamped_end = if range_end > source.length() {
      source.length()
    } else {
      range_end
    }
    if clamped_end > range_start {
      let slice = source.substring(start=range_start, end=clamped_end)
      let preview = if slice.length() > 120 {
        slice.substring(end=120) + "\u{2026}"
      } else {
        slice
      }
      items.push(div(class="source-preview", [text(preview)]))
    }
  }
  // Token spans (omitted when none exist)
  let token_spans = model.editor.get_source_map().get_all_token_spans(node.id)
  if token_spans.length() > 0 {
    let source = model.editor.get_text()
    for pair in token_spans {
      let role = pair.0
      let span_range = pair.1
      let span_start = span_range.start
      let span_end = if span_range.end > source.length() {
        source.length()
      } else {
        span_range.end
      }
      let span_text = if span_end > span_start {
        "\"" + source.substring(start=span_start, end=span_end) + "\""
      } else {
        ""
      }
      items.push(
        div(class="token-span-row", [
          span(class="token-span-role", [text(role)]),
          span(class="token-span-range", [
            text("\{span_start}..\{span_end}"),
          ]),
          span(class="token-span-text", [text(span_text)]),
        ]),
      )
    }
  }
  div(class="panel-section", items)
}
```

- [ ] **Step 2: Update the call site in `view_inspector_content`**

In `view_inspector_content` (line 144), change:

```moonbit
            view_node_details(node),
```

to:

```moonbit
            view_node_details(node, model),
```

- [ ] **Step 3: Run `moon check`**

Run: `moon check`
Expected: no errors. This verifies the `Range` type is transitively accessible and the `get_all_token_spans` call compiles.

- [ ] **Step 4: Run full test suite**

Run: `moon test`
Expected: all pass.

- [ ] **Step 5: Update interface and format**

Run: `moon info && moon fmt`

- [ ] **Step 6: Commit**

```bash
git add examples/ideal/main/view_inspector.mbt
git commit -m "feat(ideal): show source range, text preview, and token spans in inspector"
```

---

### Task 4: Archive old plan and update TODO

**Files:**
- Move: `docs/plans/2026-03-29-ideal-inspector-panel.md` → `docs/archive/2026-03-29-ideal-inspector-panel.md`
- Modify: `docs/TODO.md:249-252` (update §10 inspector item)

- [ ] **Step 1: Archive old plan**

```bash
git mv docs/plans/2026-03-29-ideal-inspector-panel.md docs/archive/2026-03-29-ideal-inspector-panel.md
```

- [ ] **Step 2: Update TODO §10 inspector item**

In `docs/TODO.md`, replace lines 249–252:

```markdown
- [ ] Inspector panel
  Why: the Ideal editor already has partial inspector UI, but the backlog item is still unfinished until outline selection reliably shows the intended node details, including source range.
  Plan: `docs/plans/2026-03-29-ideal-inspector-panel.md`
  Exit: outline click reliably populates the inspector with kind/type, source range, and child information.
```

with:

```markdown
- [x] Inspector panel
  Why: the Ideal editor already has partial inspector UI, but the backlog item is still unfinished until outline selection reliably shows the intended node details, including source range.
  Plan: `docs/plans/2026-04-01-inspector-panel-design.md`
  Exit: outline click reliably populates the inspector with kind/type, source range, source text preview, token spans, and child information.
```

- [ ] **Step 3: Commit**

```bash
git add docs/plans/2026-03-29-ideal-inspector-panel.md docs/archive/2026-03-29-ideal-inspector-panel.md docs/TODO.md
git commit -m "docs: archive old inspector plan, mark TODO §10 inspector as done"
```

---

### Task 5: Manual validation

- [ ] **Step 1: Start dev server**

Run: `cd examples/web && npm run dev`
Open: `http://localhost:5173/`

- [ ] **Step 2: Verify inspector with lambda node**

1. Type `λx.x+1` in the editor
2. Click the `λx` node in the outline
3. Verify the inspector NODE section shows:
   - Kind: `lambda`
   - Label: `λx`
   - Children: `1`
   - ID: (some number)
   - Range: `0..6`
   - Source preview block: `λx.x+1`
   - Token span row: `param  1..2  "x"`

- [ ] **Step 3: Verify inspector with let binding**

1. Type `let f = λx.x` in the editor
2. Click the Module node in the outline
3. Verify the inspector shows:
   - Range: `0..14`
   - Source preview: `let f = λx.x`
   - Token span row: `name:0  4..5  "f"`

- [ ] **Step 4: Verify edge cases**

1. Click a leaf node (integer literal) — no token spans should appear (section absent)
2. Select a node, then delete it via editor — inspector should show "No matching node"
3. Click another node after deletion — inspector should update normally

- [ ] **Step 5: Final check**

Run: `moon check && moon test`
Expected: all pass.
