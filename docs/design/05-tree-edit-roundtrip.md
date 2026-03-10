# Design 05: Tree Edit Roundtrip

**Parent:** [Grand Design](./GRAND_DESIGN.md)
**Status:** Draft
**Updated:** 2026-03-10

---

## Problem

The `projection/` layer defines structural AST operations (`InsertNode`, `DeleteNode`, `MoveNode`, `UpdateLeaf`) that operate directly on the AST. But these operations:

1. **Are not CRDT operations** — they can't be synced to peers
2. **Bypass the text CRDT** — the CRDT only knows about text insert/delete
3. **Create divergence** — local AST changes that don't produce text CRDT ops will be lost on sync

For true collaborative projectional editing, tree edits must round-trip through the text CRDT:

```
Tree Edit -> Unparse -> Text Diff -> CRDT Ops -> Broadcast -> Remote: Apply -> Reparse
```

---

## Design

### The Roundtrip

```
+--------------------------------------------------------------+
|                    Tree Edit Roundtrip                        |
|                                                              |
|  1. User drags node in tree editor                           |
|     -> TreeEditOp::Drop(source, target, position)            |
|                                                              |
|  2. Apply to ProjNode tree (structurally)                    |
|     -> new_proj = apply_tree_op(old_proj, op)                |
|                                                              |
|  3. Unparse new ProjNode to text                             |
|     -> new_text = @ast.print_term(new_proj.kind)             |
|                                                              |
|  4. Diff against current CRDT text                           |
|     -> edits = text_lens_diff(old_text, new_text)            |
|                                                              |
|  5. Apply diffs as CRDT ops                                  |
|     -> for each edit: doc.delete() / doc.insert()            |
|                                                              |
|  6. Trigger reparse + reconcile                              |
|     -> parser.set_source(doc.text())                         |
|     -> ProjNode tree reconciled to preserve node IDs         |
|                                                              |
|  7. CRDT ops broadcast to peers                              |
|     -> peers apply ops -> reparse -> see updated AST         |
|                                                              |
+--------------------------------------------------------------+
```

### Why Round-Trip Through Text?

**Option A: Text CRDT only (chosen)**
- Tree edit -> unparse -> text diff -> CRDT text ops
- Simple. Leverages existing CRDT. Peers just see text changes.
- Downside: Unparse may normalize formatting.

**Option B: Tree CRDT (not chosen)**
- Structural CRDT operations on the AST directly (e.g., Fugue on tree nodes)
- Preserves tree structure across peers without reparse.
- Downside: Research-level complexity. No existing MoonBit implementation. AST conflicts are semantic, not just positional.

**Option A is correct for this project** because:
1. eg-walker's text CRDT is already battle-tested
2. Lambda calculus expressions are small enough that reparsing is cheap
3. Formatting normalization is acceptable for lambda calculus syntax, but is user-visible
4. A tree CRDT would require a fundamentally different architecture

---

## Architecture: How SyncEditor and ProjNode Relate

Per [§3](./03-unified-editor.md), `CanonicalModel` is retired. Its useful parts become derived state on `SyncEditor`:

| Old (`CanonicalModel`) | New (`SyncEditor` derived) |
|---|---|
| `ast : ProjNode?` | `Memo[ProjNode]` — built from `parser.term()` + reconciliation |
| `node_registry` | `Memo[Map[NodeId, ProjNode]]` — traversal of ProjNode tree |
| `source_map` | `Memo[SourceMap]` — built from ProjNode tree |
| `next_node_id` | Counter in `SyncEditor` |
| `edit_history` | `TextDoc.OpLog` (CRDT is the real history) |
| `dirty_projections` | Deleted — `Memo` auto-tracks |

**The ProjNode tree is the derived, ID-stable view of the AST.** It is rebuilt from `@ast.Term` (parser output) via reconciliation with the previous ProjNode tree, preserving node IDs for unchanged subtrees. This reconciliation already exists in `projection/text_lens.mbt` (`reconcile_ast` using LCS matching).

**Data flow:**

```
TextDoc (CRDT text)
  -> ReactiveParser -> @ast.Term (no node IDs)
  -> reconcile with previous ProjNode tree
  -> ProjNode tree (with stable node IDs)
  -> SourceMap, NodeRegistry (derived)
```

Tree edits flow in the reverse direction:

```
TreeEditOp
  -> modify ProjNode tree structurally
  -> @ast.print_term(modified.kind) -> new text
  -> diff -> CRDT ops -> TextDoc
  -> ReactiveParser reparses -> new @ast.Term
  -> reconcile -> updated ProjNode tree (IDs preserved)
```

---

## Components

### 1. Unparser

The unparser already exists: `@ast.print_term(term)` in `loom/examples/lambda/src/ast/ast.mbt`. It produces canonical lambda calculus text:

```
Int(42)           -> "42"
Var("x")          -> "x"
Lam("x", body)    -> "(λx. <body>)"
App(f, arg)       -> "(<f> <arg>)"
Bop(Plus, l, r)   -> "(<l> + <r>)"
If(c, t, e)       -> "if <c> then <t> else <e>"
Let("x", v, b)    -> "let x = <v> in <b>"
Unit              -> "()"
Error("msg")      -> "<error: msg>"
```

**No second unparser should be created.** Two unparse functions producing different text would cause different CRDT ops and divergence bugs. All tree-edit code must use `@ast.print_term`.

**User-visible constraint:** The first tree edit normalizes the file to `@ast.print_term` formatting (explicit parentheses around applications, lambdas, and binary ops). After that first normalization, subsequent tree edits preserve the canonical style. CST-aware unparsing (see [Future Work](#future-cst-aware-unparsing)) would eliminate this.

### 2. Tree Edit -> Text CRDT Bridge

```moonbit
/// Apply a tree edit by round-tripping through text.
/// The entire operation is synchronous within one event loop tick,
/// so no interleaving with remote ops is possible (single-threaded JS/WASM).
pub fn SyncEditor::apply_tree_edit(self : SyncEditor, op : TreeEditOp) -> Unit raise {
  let old_text = self.text()

  // 1. Get current ProjNode tree (with stable IDs) from derived Memo
  let proj = self.proj_node()  // Memo[ProjNode] — reconciled, ID-stable

  // 2. Apply tree edit structurally to produce modified ProjNode
  let modified = tree_lens_apply_edit_to_proj(proj, op)?

  // 3. Unparse via the existing @ast.print_term
  let new_text = @ast.print_term(modified.kind)

  // 4. Diff old text vs new text
  let edits = text_lens_diff(old_text, new_text)

  // 5. Apply diffs as CRDT ops
  apply_projection_edits(self, edits)

  // 6. Trigger reparse (ProjNode reconciliation happens lazily on next access)
  self.parser.set_source(self.doc.text())
}

/// Apply ProjectionEdits to the CRDT TextDoc.
fn apply_projection_edits(
  editor : SyncEditor,
  edits : Array[ProjectionEdit],
) -> Unit raise {
  // Process edits in reverse order so positions remain valid
  // (text_lens_diff produces a single contiguous edit, but this
  // handles the general case for future multi-edit support)
  for i = edits.length() - 1; i >= 0; i = i - 1 {
    match edits[i] {
      TextDelete(start~, end~) => {
        // Delete one character at a time from the end backwards.
        // Each delete at position `start` removes the next char.
        let count = end - start
        for _j = 0; _j < count; _j = _j + 1 {
          editor.doc.delete(@text.Pos::at(start))
        }
      }
      TextInsert(position~, text~) =>
        editor.doc.insert(@text.Pos::at(position), text)
      _ => ()  // NodeSelect, NodeValueChange, StructuralChange — UI-only
    }
  }
}
```

**Note on `text_lens_diff`:** The current implementation uses prefix/suffix trimming, producing at most one contiguous `TextDelete` + one `TextInsert`. This is sufficient for now but may produce suboptimal diffs for tree edits that create disjoint changes (e.g., `MoveNode` deletes from one location and inserts at another). A future optimization could use a smarter diff algorithm to produce minimal edits.

### 3. Node ID Preservation Across Roundtrip

After tree edit -> unparse -> reparse, the parser produces a fresh `@ast.Term` with no node IDs. The existing reconciliation logic in `projection/text_lens.mbt` solves this:

```
Old ProjNode (with IDs): λx[1]. (x[2] + 1[3])
Tree edit: Move 1[3] before x[2]
Unparse -> reparse: λx[?]. (1[?] + x[?])
Reconcile: LCS match children -> λx[1]. (1[3] + x[2])  // IDs preserved
```

**When reconciliation runs:** It is triggered lazily when `SyncEditor.proj_node()` is accessed after a text change. The `Memo[ProjNode]` dependency chain is:

```
Signal[String] (TextDoc text) invalidated
  -> Memo[@ast.Term] recomputes (ReactiveParser)
  -> Memo[ProjNode] recomputes (reconcile new Term with previous ProjNode)
```

The reconciliation uses `reconcile_ast(old_proj, new_proj, ...)` with LCS-based child matching (`reconcile_children`). Unchanged subtrees keep their IDs; new subtrees get fresh IDs via `assign_fresh_ids`.

---

## Supported Tree Operations

| Operation | Text roundtrip behavior |
|-----------|------------------------|
| `UpdateLeaf(id, value)` | Change a token in-place (e.g., variable name `x` -> `y`) |
| `DeleteNode(id)` | Remove the node's text span, reparse surrounding |
| `InsertNode(parent, idx, node)` | Unparse new node, insert text at parent's span |
| `ReplaceNode(id, new_node)` | Replace node's text span with unparsed new node |
| `MoveNode(id, new_parent, idx)` | Delete from old position, insert at new position |

These are `ModelOperation`s from `projection/types.mbt`. UI-level `TreeEditOp` values in `projection/tree_lens.mbt` are translated to them.

### `UpdateLeaf` Optimization

For simple leaf edits (rename variable, change number), we can skip full unparse by editing the text span directly via the `SourceMap`:

```moonbit
/// Optimized leaf update: directly edit the text span.
/// Avoids full unparse/reparse for the most common tree edit.
pub fn SyncEditor::update_leaf(
  self : SyncEditor,
  node_id : NodeId,
  new_value : String,
) -> Unit raise {
  // source_map() is a derived Memo on SyncEditor (see §3)
  let range = self.source_map().get_range(node_id)
  match range {
    Some(r) => {
      let start = r.start()
      let count = r.length()
      // Delete old text (one char at a time, always at `start`)
      for _i = 0; _i < count; _i = _i + 1 {
        self.doc.delete(@text.Pos::at(start))
      }
      // Insert new text
      self.doc.insert(@text.Pos::at(start), new_value)
      self.parser.set_source(self.doc.text())
    }
    None => raise TreeEditError("node not found: " + node_id.to_string())
  }
}
```

### Performance

The full roundtrip (unparse entire AST + diff + apply) is O(N) in AST size per tree edit. This is acceptable for lambda calculus (small expressions), but optimization directions exist:

1. **`UpdateLeaf` fast path** (above) — O(1) for the most common edit
2. **Subtree-scoped unparse** — only unparse the modified subtree and splice into the surrounding text via `SourceMap` ranges
3. **Incremental ProjNode** — reuse unchanged subtrees rather than full reconciliation

---

## Atomicity

The entire roundtrip (steps 1-6) executes synchronously within a single function call. In single-threaded JS/WASM, no remote CRDT ops can interleave. This means:

- No intermediate state is observable by the UI or network layer
- The ProjNode `Memo` sees a single text change (old text -> new text), not incremental steps
- No locking or queueing is needed

If the runtime ever becomes multi-threaded, the roundtrip would need to be wrapped in a transaction or queue.

---

## Concurrent Tree Edits

If two peers make tree edits simultaneously, both round-trip through text. The CRDT resolves the text-level conflicts (insert/delete ordering via FugueMax). The resulting merged text is then reparsed independently by each peer, producing the same AST (since parsing is deterministic).

The merged AST may not match either peer's intended structural edit — this is the same as concurrent text edits producing merged text that neither peer typed. This is acceptable and inherent to the text-CRDT approach.

---

## Future: CST-Aware Unparsing

The current unparser (`@ast.print_term`) discards original formatting because it works from `@ast.Term`, not from `SyntaxNode`. A CST-aware unparser would:

1. Walk the `SyntaxNode` tree (which includes trivia: whitespace, comments)
2. Only re-render the modified subtree
3. Preserve surrounding whitespace and formatting

This eliminates the "first tree edit normalizes formatting" problem. It requires:
- A way to map ProjNode back to the corresponding `SyntaxNode` subtree
- A `SyntaxNode` -> `String` function that preserves trivia (loom doesn't have this yet, but each `CstToken` stores its original `text`, so reconstructing is straightforward)

This is a future optimization, not required for the initial implementation.

---

## Location

| File | Content |
|------|---------|
| `editor/tree_edit_bridge.mbt` | `apply_tree_edit`, `update_leaf`, `apply_projection_edits` |
| `editor/tree_edit_bridge_test.mbt` | Roundtrip and leaf-edit tests |

The unparser is `@ast.print_term` in `loom/examples/lambda/src/ast/ast.mbt` (existing, no new file needed).

---

## Verification

1. **Roundtrip property:** For any AST, `parse(print_term(ast)) ≈ ast` (structurally equivalent, ignoring node IDs and whitespace). Already partially tested in loom's `print_term` tests.
2. **CRDT convergence:** Two peers — one edits via text, one via tree — converge to same document text and same AST.
3. **Node ID preservation:** After tree edit roundtrip, unchanged nodes keep their IDs. Verified via `reconcile_ast` outputting stable IDs for LCS-matched children.
4. **Leaf optimization:** `update_leaf("x", "y")` produces identical CRDT text as the full roundtrip of `UpdateLeaf(id, VarName("y"))`.
5. **Error node roundtrip:** `print_term(Error("msg"))` produces `"<error: msg>"` which parses back to an error recovery node. Verify the roundtrip doesn't lose or corrupt surrounding valid syntax.
6. **Atomicity:** No observable intermediate state — `proj_node()` before and after `apply_tree_edit` returns consistent ProjNode trees with no stale mix of old/new structure.
7. **Concurrent edits:** Two peers with concurrent tree edits converge to identical text after CRDT sync.

---

## Dependencies

- **Depends on:** [§3 Unified Editor](./03-unified-editor.md) (`SyncEditor` with `proj_node()`, `source_map()` Memos)
- **Depends on:** `@ast.print_term` in `loom/examples/lambda/src/ast/ast.mbt` (existing unparser)
- **Depends on:** `projection/text_lens.mbt` (`text_lens_diff`, `reconcile_ast`)
- **Depends on:** `projection/tree_lens.mbt` (`tree_lens_apply_edit` / tree edit ops)
- **Depends on:** `projection/source_map.mbt` (node -> text range, for `update_leaf`)
- **Depended on by:** None (leaf node)
