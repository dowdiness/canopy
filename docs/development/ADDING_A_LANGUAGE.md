# Adding a Language to Canopy

This guide walks through integrating a new language into Canopy's projectional
editor framework. It assumes familiarity with MoonBit but not with Canopy
internals.

**Primary example:** Markdown (uses CstFold, 3-memo pattern, clean structure).

> **Don't follow the Lambda pattern.** Lambda predates CstFold and retains
> language-specific legacy edit policies for root binding rows and expressions.
> It now uses the generic `Language` SPI, but its historical surface remains
> more complex than a new language integration. Use Markdown as your reference;
> consult JSON where patterns differ.

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
modules/canopy/lang/<name>/
  proj/
    moon.pkg                    # imports: core, incr, loom, seam, <your-lang>
    proj_node.mbt               # CST → ProjNode[T] + 3-memo builder (Step 4)
    populate_token_spans.mbt    # token span extraction
  edits/
    moon.pkg                    # imports: editor, core, lang/<name>/proj, <your-lang>, loom
    <name>_edit_op.mbt          # edit operation enum
    compute_<name>_edit.mbt     # op → SpanEdit dispatcher
  companion/
    moon.pkg                    # imports: editor, lang/<name>/{edits,proj}, lang/runtime, incr, <your-lang>, loom
    <name>_companion.mbt        # Language + apply bridge + SyncEditor factory
```

---

## Phase 1: Grammar and AST (in loom submodule)

This work happens in the `deps/loom/` submodule — a separate git repo. You'll
commit there first, then update the submodule pointer in Canopy.

### Step 1: Define grammar, AST type, and trait impls

You need three things, co-developed iteratively:

**Grammar with `fold_node`:** Define in `deps/loom/examples/<name>/src/grammar.mbt`.
The `fold_node` function converts a CST node into your AST value. This is what
`CstFold` calls during tree folding — it must handle every node kind your
grammar produces.

**AST type:** An enum representing your language's structure. Define in
`deps/loom/examples/<name>/src/ast.mbt`. For reference, Markdown's AST:

```moonbit
pub(all) enum Block {
  Document(Array[Block])
  Heading(Int, Array[Inline])
  Paragraph(Array[Inline])
  UnorderedList(Array[Block])
  OrderedList(Array[Block], OrderedListMarker?)
  UnorderedListItem(Array[Inline])
  OrderedListItem(Array[Inline], OrderedListMarker?)
  CodeBlock(String, String)     // language, content
  Error(String)
} derive(Eq, Debug)
```

`derive(Eq)` is required, not optional: `SyncEditor`'s text-edit methods and
`Language::apply_edit` are `fn[T : Eq]`, so an AST without `Eq` fails
`moon check` the moment Phase 2 routes edits through the language. (Both
reference ASTs derive it: `deps/loom/examples/{json,markdown}/src/ast.mbt`.)

**Trait impls:** Implement `TreeNode` and `Renderable` (from `dowdiness/loom/core`)
in `deps/loom/examples/<name>/src/proj_traits.mbt`:

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

**Validate:** `cd deps/loom/examples/<name> && moon test` should pass.

Then update the submodule pointer:
```bash
cd ../../../       # back to Canopy root
git add deps/loom
git commit -m "chore: update loom submodule (add <name> parser)"
```

---

## Phase 2: Canopy integration (in main repo)

### Step 2: Projection builder

**File:** `modules/canopy/lang/<name>/proj/proj_node.mbt` (~60-120 lines)

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
      @core.ProjNode(
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
  let root = syntax_to_proj_node(syntax_node, Ref(0))
  (root, errors)
}
```

**Validate:** `moon check`

### Step 3: Token spans

**File:** `modules/canopy/lang/<name>/proj/populate_token_spans.mbt` (~80-150 lines)

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

**Checkpoint — write a whitebox test** in `modules/canopy/lang/<name>/proj/proj_node_wbtest.mbt`:

```moonbit
test "parse and project basic document" {
  let (root, errors) = parse_to_proj_node!("some source text")
  inspect(errors, content="[]")
  inspect(root.kind.kind_tag(), content="Document")
  inspect(root.children.length(), content="1")
}
```

Run: `moon test -p dowdiness/canopy/lang/<name>/proj`

### Step 4: Memo builder

**File:** end of `modules/canopy/lang/<name>/proj/proj_node.mbt` (~15 lines)

This wires the reactive pipeline: when the syntax tree changes, the
projection rebuilds incrementally. The 3-memo machinery (proj reconcile,
registry, source map) lives in `@core.build_projection_memos` — do NOT
hand-roll it. The language supplies only its two callbacks from Steps 2-3.
The `Language::project` closure delegates to this builder and returns these
three memos plus its extras value `E`. When the language supports identity
hints, it forwards the framework-owned consumer handle to the core hinted memo
builder; the language adapter never drains the handle directly.

```moonbit
pub fn build_my_projection_memos(
  parser : @loom.Parser[@mylang.MyAst],
) -> (
  @incr.Derived[@core.ProjNode[@mylang.MyAst]?],
  @incr.Derived[Map[@core.NodeId, @core.ProjNode[@mylang.MyAst]]],
  @incr.Derived[@core.SourceMap],
) {
  @core.build_projection_memos(
    parser.runtime(),
    parser.syntax_tree(),
    syntax_to_proj_node,
    populate_token_spans,
    label="my",
  )
}
```

A hint-aware projection builder also accepts
`identity_hints? : @core.IdentityHintConsumer` and delegates to
`@core.build_projection_memos_with_identity_hints`. Its reconcile callback
receives an owned `Array[IdentityTransform]` for that pass. Only the core helper
drains the opaque handle; see the Lambda and Markdown projection builders for
complete examples.

**Why reconciliation matters:** Without it, every keystroke would generate
entirely new NodeIds. The UI would lose selection, collapsed state, and
scroll position. `@core.build_projection_memos` reconciles each rebuild
against the previous tree (LCS on children with `same_kind`) to reuse old
IDs where the tree shape hasn't changed.

**Validate:** `moon check`

### Step 5: Edit operations

Three files, designed together. Start by defining the operations, then
implement the dispatcher, then wire the bridge.

#### 5a: Define the op enum

**File:** `modules/canopy/lang/<name>/edits/<name>_edit_op.mbt` (~20 lines)

Each variant represents a structural editing intent — not a text-level change.
The framework converts these to text-level `SpanEdit`s.

```moonbit
pub(all) enum MyEditOp {
  CommitEdit(node_id~ : NodeId, new_text~ : String)
  Delete(node_id~ : NodeId)
  // ... language-specific operations
} derive(Debug, Eq)
```

If the `Language.edit` adapter reports an unhandled operation through
`EditError::UnsupportedOperation` (the JSON choice), add a manual `impl Show
for MyEditOp` so `op.to_string()` exists — `derive(Show)` is deprecated
(warning [0027]); see
`modules/canopy/lang/json/edits/json_edit_op.mbt` for the pattern. An adapter
that deliberately returns `EditResult::NoEdit` needs no `Show` at all.

Design tips:
- Every language needs at least `CommitEdit` (replace a node's text content)
  and `Delete`
- Operations should be expressed in terms of NodeIds and structural intent,
  not byte offsets
- Think about what the UI needs to trigger — each button/shortcut maps to
  one operation

#### 5b: Implement the dispatcher

**File:** `modules/canopy/lang/<name>/edits/compute_<name>_edit.mbt` (~50-300 lines depending on op count)

Maps each operation to `SpanEdit`s (byte-level text changes) + a `FocusHint`:

```moonbit
pub fn compute_my_edit(
  op : MyEditOp,
  source : String,
  proj : ProjNode[@mylang.MyAst],
  source_map : SourceMap,
) -> (Array[SpanEdit], FocusHint)? raise @core.EditError {
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
- Return `None` for an operation that computes no edit
- Raise a structured `EditError` variant for invalid operations
- `FocusHint::RestoreCursor` keeps cursor where it was; `FocusHint::MoveCursor(position~)`
  moves it to a specific byte offset

#### 5c: Wire the bridge

The span-edit application machinery (reverse-document-order splicing, undo
recording, cursor reconciliation per `FocusHint`, identity-hint threading)
lives in `modules/canopy/lang/runtime` — do NOT hand-roll it. Declare a
`Language[T, Op, E]` and delegate (see
`modules/canopy/lang/json/companion/json_companion.mbt` and
`modules/canopy/lang/markdown/companion/markdown_companion.mbt`). `E` is the
language-owned extras value (companion memos, semantic attachments; `Unit`
when there are none). See
`docs/decisions/2026-08-07-generic-language-spi-deepening.md`.

**File:** `modules/canopy/lang/<name>/companion/<name>_companion.mbt`

```moonbit
let my_lang : @lang_runtime.Language[@mylang.MyAst, @my_edits.MyEditOp, Unit] =
  @lang_runtime.Language::Language(
    parse=(source_id, source, runtime) => {
      @loom.new_parser(source_id, source, @mylang.my_grammar, runtime?)
    },
    project=(parser, _hints) => {
      let memos = @my_proj.build_my_projection_memos(parser)
      (memos.0, memos.1, memos.2, ())
    },
    edit=(op, ctx) => {
      match @my_edits.compute_my_edit(op, ctx.source_text, ctx.proj_node, ctx.source_map) {
        Some((edits, focus_hint)) =>
          @lang_runtime.EditResult::Edits(edits, focus_hint, None)
        // What should this language do when compute_my_edit returns None?
        // JSON reports an error; Markdown silently no-ops. Decide explicitly.
        None =>
          raise @core.EditError::UnsupportedOperation(
            detail="unhandled edit op: " + op.to_string(),
          )
      }
    },
    capabilities=_e => @editor.LanguageCapabilities::default(),
  )

pub fn apply_my_edit(
  editor : @editor.SyncEditor[@mylang.MyAst],
  op : @my_edits.MyEditOp,
  timestamp_ms : Int,
) -> Result[Array[@core.SpanEdit], @core.EditError] {
  my_lang.apply_edit(editor, op, timestamp_ms)
}
```

Keep this MoonBit companion boundary structured. Convert `EditError` to a
legacy string or transport payload only in the language's FFI adapter.

**Validate:** `moon check`

### Step 6: SyncEditor factory and package wiring

**File:** same companion file — the factory delegates through the language:

```moonbit
pub fn new_my_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> @editor.SyncEditor[@mylang.MyAst] {
  let (editor, _) = my_lang.build(agent_id, capture_timeout_ms~, parent_runtime?)
  editor
}
```

> **The lambda exception is gone (ADR 2026-08-07).** `lang/lambda/companion`
> previously kept its own bridge because the SPI could not express typed
> errors, patch traces, or editor-owned moves. The deepened SPI absorbs all of
> these: `Language::apply_edit` returns the applied `SpanEdit` trace and
> structured `EditError`, and moves are edit-port computation
> (`compute_text_edit` / `compute_move` / `compute_move_block`). Lambda uses
> `Language`; it remains a legacy stress case, not a template. Do not fork a
> separate bridge for a new language.

**Package registration:**

`modules/canopy/lang/<name>/proj/moon.pkg`:
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

`modules/canopy/lang/<name>/edits/moon.pkg`:
```
import {
  "dowdiness/canopy/editor" @editor,
  "dowdiness/canopy/core" @core,
  "dowdiness/canopy/lang/<name>/proj" @my_proj,
  "dowdiness/<name>" @mylang,
  "dowdiness/loom" @loom,
}
```

`modules/canopy/lang/<name>/companion/moon.pkg`:
```
import {
  "dowdiness/canopy/editor",
  "dowdiness/canopy/lang/<name>/edits" @my_edits,
  "dowdiness/canopy/lang/<name>/proj" @my_proj,
  "dowdiness/canopy/lang/runtime" @lang_runtime,
  "dowdiness/incr",
  "dowdiness/<name>" @mylang,
  "dowdiness/loom",
}
```

**Validate:** `moon check && moon test`

### Step 7: Tests

Not optional. Write these alongside the code, not after.

**Projection test** (`modules/canopy/lang/<name>/proj/proj_node_wbtest.mbt`):
- Parse source text → project → verify tree shape via `inspect`
- Test edge cases: empty input, parse errors, deeply nested structures
- Verify token spans exist for key roles

**Edit round-trip test** (`modules/canopy/lang/<name>/edits/compute_<name>_edit_wbtest.mbt`):
- Create editor → insert text → apply edit op → verify resulting text
- Test each edit operation variant
- Verify FocusHint positions

**Snapshot tests:** Use `inspect` liberally — snapshot tests catch unexpected
regressions without brittle assertions. Run `moon test --update` to generate
initial snapshots, then review them.

**Validate:** `moon test -p dowdiness/canopy/lang/<name>/proj && moon test -p dowdiness/canopy/lang/<name>/edits`

---

## Optional: FFI and web integration

When you're ready to use the language in the browser, add:

**FFI entry point** (`ffi/canopy_<name>.mbt`): Handle-based API with
create/destroy/get_text/set_text/apply_edit exports. Allocate handles
through the per-language `@workspace.Coordinator` (handles are
coordinator-local `EditorId` integers starting at 0); cross-bundle
collisions are prevented architecturally because each language ships in
its own JS bundle with its own coordinator instance. Add the import to
`ffi/moon.pkg`.

**TypeScript adapter** (`@canopy/editor-adapter` package at `adapters/editor/`,
or `apps/web/src/`): Import the FFI functions, wire to your UI. Consumer projects
depend on the adapter via `"@canopy/editor-adapter": "file:../../adapters/editor"`
and import submodules like `import { HTMLAdapter } from '@canopy/editor-adapter/html-adapter'`.
See `apps/web/src/markdown-editor.ts` for the full pattern.

---

## Reference files

| Purpose | Markdown (recommended) | JSON (alternative) | Lines |
|---------|----------------------|-------------------|-------|
| Projection builder | `modules/canopy/lang/markdown/proj/proj_node.mbt` | `modules/canopy/lang/json/proj/proj_node.mbt` | ~120 / ~220 |
| Token spans | `modules/canopy/lang/markdown/proj/populate_token_spans.mbt` | `modules/canopy/lang/json/proj/populate_token_spans.mbt` | ~150 / ~110 |
| Memo builder | `modules/canopy/lang/markdown/proj/proj_node.mbt` (`build_markdown_projection_memos`) | `modules/canopy/lang/json/proj/proj_node.mbt` (`build_json_projection_memos`) | ~15 each |
| Edit ops enum | `modules/canopy/lang/markdown/edits/markdown_edit_op.mbt` | `modules/canopy/lang/json/edits/json_edit_op.mbt` | ~22 / ~28 |
| Edit dispatcher | `modules/canopy/lang/markdown/edits/compute_markdown_edit.mbt` | `modules/canopy/lang/json/edits/compute_json_edit.mbt` | ~340 / ~100+ |
| Spec + bridge + factory | `modules/canopy/lang/markdown/companion/markdown_companion.mbt` | `modules/canopy/lang/json/companion/json_companion.mbt` | ~120 / ~44 |
| FFI exports | `modules/canopy/ffi/markdown/markdown_ffi.mbt` | `modules/canopy/ffi/json/json_ffi.mbt` | ~113 / ~237 |
| proj moon.pkg | `modules/canopy/lang/markdown/proj/moon.pkg` | `modules/canopy/lang/json/proj/moon.pkg` | ~8 |
| edits moon.pkg | `modules/canopy/lang/markdown/edits/moon.pkg` | `modules/canopy/lang/json/edits/moon.pkg` | ~12 |
| Trait impls | `deps/loom/examples/markdown/src/proj_traits.mbt` | `deps/loom/examples/json/src/proj_traits.mbt` | — |
