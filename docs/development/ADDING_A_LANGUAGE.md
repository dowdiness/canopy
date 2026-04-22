# Adding a Language to Canopy

This guide walks through integrating a new language into Canopy's projectional
editor framework. It assumes familiarity with MoonBit but not with Canopy
internals.

**Primary example:** Markdown (uses CstFold, 3-memo pattern, clean structure).

> **Don't follow the Lambda pattern.** Lambda predates CstFold, uses a 4-memo
> FlatProj pipeline, and hand-builds AST values from view casts. It's the
> oldest language integration and carries historical complexity. Use Markdown
> as your reference; consult JSON where patterns differ.

## How it fits together

```
Grammar → Parser → CST → CstFold → AST → ProjNode[T] → ViewNode → Renderer
                                     ↑                      ↑
                               Your AST type          Protocol layer
                          (TreeNode + Renderable)    (language-agnostic)
```

The framework is generic over `T` (your AST type). You provide:
- A grammar and parser (in the loom submodule)
- An AST type `T` with `TreeNode` and `Renderable` trait impls
- A projection builder: CST → `ProjNode[T]`
- Token spans: which text ranges map to which roles ("text", "marker", etc.)
- A memo builder: wires the reactive pipeline (3 memos)
- Edit operations: structural intents → text-level `SpanEdit`s
- A `SyncEditor` factory: ~14 lines of wiring

Everything after `ProjNode[T]` is handled by the framework — reconciliation,
view diffing, cursor tracking, undo, CRDT sync.

## Package layout

```
lang/<name>/
  proj/
    moon.pkg                    # imports: core, incr, loom, seam, <your-lang>
    proj_node.mbt               # CST → ProjNode[T]
    populate_token_spans.mbt    # token span extraction
    <name>_memo.mbt             # 3-memo builder
  edits/
    moon.pkg                    # imports: editor, core, lang/<name>/proj, <your-lang>, loom
    <name>_edit_op.mbt          # edit operation enum
    compute_<name>_edit.mbt     # op → SpanEdit dispatcher
    <name>_edit_bridge.mbt      # bridge: applies SpanEdits to SyncEditor
    sync_editor_<name>.mbt      # SyncEditor constructor
```

---

## Phase 1: Grammar and AST (in loom submodule)

This work happens in the `loom/` submodule — a separate git repo. You'll
commit there first, then update the submodule pointer in canopy.

### Step 1: Define grammar, AST type, and trait impls

You need three things, co-developed iteratively:

**Grammar with `fold_node`:** Define in `loom/examples/<name>/src/grammar.mbt`.
The `fold_node` function converts a CST node into your AST value. This is what
`CstFold` calls during tree folding — it must handle every node kind your
grammar produces.

**AST type:** An enum representing your language's structure. Define in
`loom/examples/<name>/src/ast.mbt`. For reference, Markdown's AST:

```moonbit
pub(all) enum Block {
  Document(Array[Block])
  Heading(Int, Array[Inline])
  Paragraph(Array[Inline])
  UnorderedList(Array[Block])
  ListItem(Array[Inline])
  CodeBlock(String, String)     // language, content
  Error(String)
}
```

**Trait impls:** Implement `TreeNode` and `Renderable` (from `dowdiness/loom/core`)
in `loom/examples/<name>/src/proj_traits.mbt`:

```moonbit
// TreeNode — tells the framework how to traverse your AST
pub impl @loomcore.TreeNode for MyAst with children(self) -> Array[MyAst] {
  // Return child AST nodes (for container types)
  // Leaf nodes return []
}

pub impl @loomcore.TreeNode for MyAst with same_kind(self, other) -> Bool {
  // Structural equality (same variant, same arity)
  // Used by reconciliation to decide whether to reuse a NodeId
}

// Renderable — tells the framework how to display your AST
pub impl @loomcore.Renderable for MyAst with kind_tag(self) -> String {
  // Short tag for the node kind: "Heading", "Paragraph", "CodeBlock", etc.
}

pub impl @loomcore.Renderable for MyAst with label(self) -> String {
  // User-facing label shown in the projection tree
}

pub impl @loomcore.Renderable for MyAst with placeholder(self) -> String {
  // Default text when creating a new empty node of this kind
}

pub impl @loomcore.Renderable for MyAst with unparse(self) -> String {
  // Serialize back to source text
}
```

**Validate:** `cd loom/examples/<name> && moon test` should pass.

Then update the submodule pointer:
```bash
cd ../..           # back to canopy root
git add loom
git commit -m "chore: update loom submodule (add <name> parser)"
```

---

## Phase 2: Canopy integration (in main repo)

### Step 2: Projection builder

**File:** `lang/<name>/proj/proj_node.mbt` (~60-120 lines)

Converts a CST `SyntaxNode` into a `ProjNode[T]` tree. Use `CstFold` to get
your fully-populated AST value, then build the `ProjNode` structure from it:

```moonbit
pub fn syntax_to_proj_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@mylang.MyAst] {
  let fold = @loomcore.CstFold::new(@mylang.my_fold_node)
  let ast = fold.fold(node)
  build_proj_tree(node, ast, counter)
}
```

`build_proj_tree` pattern-matches on the AST type. For container nodes (those
with children), you need to parallel-walk the syntax children and AST children:

```moonbit
fn build_proj_tree(
  syntax_node : @seam.SyntaxNode,
  ast : @mylang.MyAst,
  counter : Ref[Int],
) -> @core.ProjNode[@mylang.MyAst] {
  match ast {
    // Container: recurse into children
    Document(blocks) =>
      build_container(syntax_node, ast, collect_block_children(syntax_node), counter)
    // Leaf: no children
    _ =>
      @core.ProjNode::new(
        ast,
        syntax_node.start(),
        syntax_node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
  }
}
```

Also add a convenience function for tests:

```moonbit
pub fn parse_to_proj_node(
  text : String,
) -> (@core.ProjNode[@mylang.MyAst], Array[String]) raise @loomcore.LexError {
  let (cst, diagnostics) = @mylang.parse_cst(text)
  let syntax_node = @seam.SyntaxNode::from_cst(cst)
  let errors = diagnostics.map(fn(d) { d.message })
  let root = syntax_to_proj_node(syntax_node, Ref::new(0))
  (root, errors)
}
```

**Validate:** `moon check`

### Step 3: Token spans

**File:** `lang/<name>/proj/populate_token_spans.mbt` (~80-150 lines)

Token spans tell the framework which byte ranges within a node correspond to
which semantic roles. Edit operations use these to know *where* to make text
changes.

```moonbit
pub fn populate_token_spans(
  source_map : @core.SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : @core.ProjNode[@mylang.MyAst],
) -> Unit {
  populate_node(source_map, syntax_root, proj_root)
}
```

Define role conventions for your language. Examples from Markdown:

| Role | Meaning | Example |
|------|---------|---------|
| `"text"` | Editable inline content | Paragraph text, heading text |
| `"marker"` | Structural prefix | `#` in headings, `-` in list items |
| `"code"` | Code content | Text between code fences |
| `"fence_open"` | Opening delimiter | Opening ``` |
| `"fence_close"` | Closing delimiter | Closing ``` |

The implementation parallel-walks the syntax tree and projection tree, calling
`source_map.set_token_span(proj_id, role, range)` for each span.

**Validate:** `moon check`

**Checkpoint — write a whitebox test** in `lang/<name>/proj/proj_node_wbtest.mbt`:

```moonbit
test "parse and project basic document" {
  let (root, errors) = parse_to_proj_node!("some source text")
  inspect!(errors, content="[]")
  inspect!(root.kind.kind_tag(), content="Document")
  inspect!(root.children.length(), content="1")
}
```

Run: `moon test -p dowdiness/canopy/lang/<name>/proj`

### Step 4: Memo builder

**File:** `lang/<name>/proj/<name>_memo.mbt` (~65 lines)

This wires the reactive pipeline: when the syntax tree changes, the projection
rebuilds incrementally. Returns 3 memos that the `SyncEditor` consumes.

Copy from `lang/markdown/proj/markdown_memo.mbt` and replace types. The
structure is always the same:

1. **proj_memo** — calls `syntax_to_proj_node`, then `reconcile` against the
   previous tree to preserve NodeIds where the AST shape matches
2. **registry_memo** — builds `Map[NodeId, ProjNode[T]]` from the current tree
   for O(1) lookup
3. **source_map_memo** — builds `SourceMap` with token spans

```moonbit
pub fn build_my_projection_memos(
  rt : @incr.Runtime,
  _source_text : @incr.Signal[String],
  syntax_tree : @incr.Signal[@seam.SyntaxNode?],
  _parser : @loom.ImperativeParser[@mylang.MyAst],
) -> (
  @incr.Memo[@core.ProjNode[@mylang.MyAst]?],
  @incr.Memo[Map[@core.NodeId, @core.ProjNode[@mylang.MyAst]]],
  @incr.Memo[@core.SourceMap],
) {
  let counter : Ref[Int] = Ref::new(0)
  let prev_proj_ref : Ref[@core.ProjNode[@mylang.MyAst]?] = Ref::new(None)

  let proj_memo = @incr.Memo::new_no_backdate(rt, fn() {
    match syntax_tree.get() {
      None => { prev_proj_ref.val = None; None }
      Some(syntax_root) => {
        let new_proj = syntax_to_proj_node(syntax_root, counter)
        let result = match prev_proj_ref.val {
          Some(old) => @core.reconcile(old, new_proj, counter)
          None => new_proj
        }
        prev_proj_ref.val = Some(result)
        Some(result)
      }
    }
  }, label="my_proj")

  let registry_memo = @incr.Memo::new_no_backdate(rt, fn() {
    let reg : Map[@core.NodeId, @core.ProjNode[@mylang.MyAst]] = {}
    match proj_memo.get() {
      Some(root) => @core.collect_registry(root, reg)
      None => ()
    }
    reg
  }, label="my_registry")

  let source_map_memo = @incr.Memo::new_no_backdate(rt, fn() {
    match (proj_memo.get(), syntax_tree.get()) {
      (Some(proj_root), Some(syntax_root)) => {
        let sm = @core.SourceMap::from_ast(proj_root)
        populate_token_spans(sm, syntax_root, proj_root)
        sm
      }
      _ => @core.SourceMap::new()
    }
  }, label="my_source_map")

  (proj_memo, registry_memo, source_map_memo)
}
```

**Why reconciliation matters:** Without it, every keystroke would generate
entirely new NodeIds. The UI would lose selection, collapsed state, and
scroll position. `reconcile` uses LCS on children with `same_kind` to
reuse old IDs where the tree shape hasn't changed.

**Validate:** `moon check`

### Step 5: Edit operations

Three files, designed together. Start by defining the operations, then
implement the dispatcher, then wire the bridge.

#### 5a: Define the op enum

**File:** `lang/<name>/edits/<name>_edit_op.mbt` (~20 lines)

Each variant represents a structural editing intent — not a text-level change.
The framework converts these to text-level `SpanEdit`s.

```moonbit
pub(all) enum MyEditOp {
  CommitEdit(node_id~ : NodeId, new_text~ : String)
  Delete(node_id~ : NodeId)
  // ... language-specific operations
} derive(Show, Eq)
```

Design tips:
- Every language needs at least `CommitEdit` (replace a node's text content)
  and `Delete`
- Operations should be expressed in terms of NodeIds and structural intent,
  not byte offsets
- Think about what the UI needs to trigger — each button/shortcut maps to
  one operation

#### 5b: Implement the dispatcher

**File:** `lang/<name>/edits/compute_<name>_edit.mbt` (~50-300 lines depending on op count)

Maps each operation to `SpanEdit`s (byte-level text changes) + a `FocusHint`:

```moonbit
pub fn compute_my_edit(
  op : MyEditOp,
  source : String,
  proj : ProjNode[@mylang.MyAst],
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  match op {
    CommitEdit(node_id~, new_text~) =>
      compute_commit_edit(source_map, node_id, new_text)
    Delete(node_id~) =>
      compute_delete(source_map, node_id)
  }
}
```

Key rules:
- Use `source_map.get_token_span(node_id, role)` to find the byte range for a
  role, then construct a `SpanEdit` targeting that range
- Return `Ok(None)` for no-ops (e.g., merge on first block)
- Return `Err(msg)` for invalid operations
- `FocusHint::RestoreCursor` keeps cursor where it was; `FocusHint::MoveCursor(position~)`
  moves it to a specific byte offset

#### 5c: Wire the bridge

**File:** `lang/<name>/edits/<name>_edit_bridge.mbt` (~40 lines)

Applies computed `SpanEdit`s to the `SyncEditor`. This is boilerplate — the
pattern is identical across languages:

```moonbit
pub fn apply_my_edit(
  editor : @editor.SyncEditor[@mylang.MyAst],
  op : MyEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let source = editor.get_text()
  let proj = match editor.get_proj_node() {
    Some(p) => p
    None => return Err("no projection available")
  }
  let source_map = editor.get_source_map()
  match compute_my_edit(op, source, proj, source_map) {
    Ok(Some((edits, focus_hint))) => {
      if edits.is_empty() { return Ok(()) }
      let sorted = edits.copy()
      sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
      let old_cursor = editor.get_cursor()
      for edit in sorted {
        editor.apply_text_edit_internal(
          edit.start, edit.delete_len, edit.inserted,
          timestamp_ms, true, false,
        )
      }
      match focus_hint {
        @core.FocusHint::RestoreCursor => editor.move_cursor(old_cursor)
        @core.FocusHint::MoveCursor(position~) => editor.move_cursor(position)
      }
      Ok(())
    }
    Ok(None) => Ok(())
    Err(msg) => Err(msg)
  }
}
```

**Why reverse document order:** SpanEdits are sorted by descending start
position so earlier edits don't shift the byte offsets of later ones.

**Validate:** `moon check`

### Step 6: SyncEditor factory and package wiring

**File:** `lang/<name>/edits/sync_editor_<name>.mbt` (~14 lines)

```moonbit
pub fn new_my_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> @editor.SyncEditor[@mylang.MyAst] {
  @editor.SyncEditor::new_generic(
    agent_id,
    fn(s) { @loom.new_imperative_parser(s, @mylang.my_grammar) },
    @my_proj.build_my_projection_memos,
    capture_timeout_ms~,
  )
}
```

**Package registration:**

`lang/<name>/proj/moon.pkg`:
```
import {
  "dowdiness/canopy/core" @core,
  "dowdiness/incr" @incr,
  "dowdiness/<name>" @mylang,
  "dowdiness/loom" @loom,
  "dowdiness/loom/core" @loomcore,
  "dowdiness/seam" @seam,
}
```

`lang/<name>/edits/moon.pkg`:
```
import {
  "dowdiness/canopy/editor" @editor,
  "dowdiness/canopy/core" @core,
  "dowdiness/canopy/lang/<name>/proj" @my_proj,
  "dowdiness/<name>" @mylang,
  "dowdiness/loom" @loom,
}
```

**Validate:** `moon check && moon test`

### Step 7: Tests

Not optional. Write these alongside the code, not after.

**Projection test** (`lang/<name>/proj/proj_node_wbtest.mbt`):
- Parse source text → project → verify tree shape via `inspect!`
- Test edge cases: empty input, parse errors, deeply nested structures
- Verify token spans exist for key roles

**Edit round-trip test** (`lang/<name>/edits/compute_<name>_edit_wbtest.mbt`):
- Create editor → insert text → apply edit op → verify resulting text
- Test each edit operation variant
- Verify FocusHint positions

**Snapshot tests:** Use `inspect!` liberally — snapshot tests catch unexpected
regressions without brittle assertions. Run `moon test --update` to generate
initial snapshots, then review them.

**Validate:** `moon test -p dowdiness/canopy/lang/<name>/proj && moon test -p dowdiness/canopy/lang/<name>/edits`

---

## Optional: FFI and web integration

When you're ready to use the language in the browser, add:

**FFI entry point** (`ffi/canopy_<name>.mbt`): Handle-based API with
create/destroy/get_text/set_text/apply_edit exports. Use a handle range
that doesn't collide with existing languages (Lambda: 0-9999, JSON: 10000+,
Markdown: 20000+). Add the import to `ffi/moon.pkg`.

**TypeScript adapter** (`@canopy/editor-adapter` package at `adapters/editor-adapter/`,
or `examples/web/src/`): Import the FFI functions, wire to your UI. Consumer projects
depend on the adapter via `"@canopy/editor-adapter": "file:../../adapters/editor-adapter"`
and import submodules like `import { HTMLAdapter } from '@canopy/editor-adapter/html-adapter'`.
See `examples/web/src/markdown-editor.ts` for the full pattern.

---

## Reference files

| Purpose | Markdown (recommended) | JSON (alternative) | Lines |
|---------|----------------------|-------------------|-------|
| Projection builder | `lang/markdown/proj/proj_node.mbt` | `lang/json/proj/proj_node.mbt` | ~120 / ~220 |
| Token spans | `lang/markdown/proj/populate_token_spans.mbt` | `lang/json/proj/populate_token_spans.mbt` | ~150 / ~110 |
| Memo builder | `lang/markdown/proj/markdown_memo.mbt` | `lang/json/proj/json_memo.mbt` | ~65 / ~70 |
| Edit ops enum | `lang/markdown/edits/markdown_edit_op.mbt` | `lang/json/edits/json_edit_op.mbt` | ~22 / ~28 |
| Edit dispatcher | `lang/markdown/edits/compute_markdown_edit.mbt` | `lang/json/edits/compute_json_edit.mbt` | ~340 / ~100+ |
| Edit bridge | `lang/markdown/edits/markdown_edit_bridge.mbt` | `lang/json/edits/json_edit_bridge.mbt` | ~43 / ~45 |
| SyncEditor factory | `lang/markdown/edits/sync_editor_markdown.mbt` | `lang/json/edits/sync_editor_json.mbt` | ~14 / ~16 |
| FFI exports | `ffi/canopy_markdown.mbt` | `ffi/canopy_json.mbt` | ~113 / ~237 |
| proj moon.pkg | `lang/markdown/proj/moon.pkg` | `lang/json/proj/moon.pkg` | ~8 |
| edits moon.pkg | `lang/markdown/edits/moon.pkg` | `lang/json/edits/moon.pkg` | ~12 |
| Trait impls | `loom/examples/markdown/src/proj_traits.mbt` | `loom/examples/json/src/proj_traits.mbt` | — |
