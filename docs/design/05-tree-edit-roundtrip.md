# Design 05: Tree Edit Roundtrip

**Parent:** [Grand Design](./GRAND_DESIGN.md)
**Status:** Draft
**Updated:** 2026-03-05

---

## Problem

The `projection/` layer defines structural AST operations (`InsertNode`, `DeleteNode`, `MoveNode`, `UpdateLeaf`) that operate directly on the AST. But these operations:

1. **Are not CRDT operations** — they can't be synced to peers
2. **Bypass the text CRDT** — the CRDT only knows about text insert/delete
3. **Create divergence** — local AST changes that don't produce text CRDT ops will be lost on sync

For true collaborative projectional editing, tree edits must round-trip through the text CRDT:

```
Tree Edit → Unparse → Text Diff → CRDT Ops → Broadcast → Remote: Apply → Reparse
```

---

## Design

### The Roundtrip

```
┌──────────────────────────────────────────────────────────────┐
│                    Tree Edit Roundtrip                        │
│                                                              │
│  1. User drags node in tree editor                           │
│     → TreeEditOp::Drop(source, target, position)             │
│                                                              │
│  2. Apply to AST (locally, optimistically)                   │
│     → new_ast = apply_tree_op(old_ast, op)                   │
│                                                              │
│  3. Unparse new AST to text                                  │
│     → new_text = unparse(new_ast)                            │
│                                                              │
│  4. Diff against current CRDT text                           │
│     → edits = text_lens_diff(old_text, new_text)             │
│                                                              │
│  5. Apply diffs as CRDT ops                                  │
│     → for each edit: doc.delete() / doc.insert()             │
│                                                              │
│  6. CRDT ops broadcast to peers                              │
│     → peers apply ops → reparse → see updated AST            │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Why Round-Trip Through Text?

**Option A: Text CRDT only (chosen)**
- Tree edit → unparse → text diff → CRDT text ops
- Simple. Leverages existing CRDT. Peers just see text changes.
- Downside: Unparse is lossy; formatting may change.

**Option B: Tree CRDT (not chosen)**
- Structural CRDT operations on the AST directly (e.g., Fugue on tree nodes)
- Preserves tree structure across peers without reparse.
- Downside: Research-level complexity. No existing MoonBit implementation. AST conflicts are semantic, not just positional.

**Option A is correct for this project** because:
1. eg-walker's text CRDT is already battle-tested
2. Lambda calculus expressions are small enough that reparsing is cheap
3. Formatting loss is acceptable for lambda calculus syntax, but is user-visible
4. A tree CRDT would require a fundamentally different architecture

---

## Components

### 1. Unparser (AST → Text)

Convert an AST back to text. This must produce syntactically valid lambda calculus:

```moonbit
/// Unparse an AST node to text
pub fn unparse(ast : Ast) -> String {
  match ast {
    Int(n) => n.to_string()
    Var(name) => name
    Lam(param, body) => "λ" + param + "." + unparse(body)
    App(func, arg) => "(" + unparse(func) + " " + unparse(arg) + ")"
    Bop(op, left, right) => unparse(left) + op.to_string() + unparse(right)
    If(cond, then_, else_) =>
      "if " + unparse(cond) + " then " + unparse(then_) + " else " + unparse(else_)
    Let(name, value, body) =>
      "let " + name + " = " + unparse(value) + " in " + unparse(body)
    Error(_) => "???"  // Placeholder for error nodes
  }
}
```

**Future improvement:** Use loom's CST (`SyntaxNode`) for whitespace-preserving unparse. The CST contains trivia (whitespace, comments) that the AST discards. With CST-aware unparsing, the roundtrip preserves formatting.

**User-visible constraint (current behavior):** the first tree edit can "snap" the file
to canonical unparser formatting because AST unparsing discards original trivia.
After that first normalization, subsequent tree edits operate on the normalized style.

### 2. Tree Edit → Text CRDT Bridge

```moonbit
/// Apply a tree edit by round-tripping through text
/// (uses existing projection diff shape: TextInsert/TextDelete(start,end))
pub fn SyncEditor::apply_tree_edit(self : SyncEditor, op : TreeEditOp) -> Unit raise {
  let old_text = self.text()

  // Build a temporary canonical model, apply tree edit, then render to text.
  // Exact model<->AST plumbing is finalized in §3.
  // NOTE: this full rebuild is O(N) in AST size per tree edit.
  let model = CanonicalModel::from_ast(self.ast())
  let updated = match tree_lens_apply_edit(model, op) {
    Ok(m) => m
    Err(msg) => abort(msg)
  }
  let new_text = match text_lens_get(updated) {
    Ok(s) => s
    Err(msg) => abort(msg)
  }

  let edits = text_lens_diff(old_text, new_text)
  for edit in edits {
    match edit {
      TextDelete(start~, end~) =>
        for i = start; i < end; i = i + 1 {
          self.doc.delete(Pos::at(start))
        }
      TextInsert(position~, text~) =>
        self.doc.insert(Pos::at(position), text)
      _ => ()
    }
  }

  self.parser.set_source(self.doc.text())
}
```

### 2.1 Performance Note: Full Model Rebuild Is O(N)

The baseline implementation above does a full `CanonicalModel::from_ast(self.ast())`
for every tree edit. That makes each edit at least O(N) in document/AST size before
diffing and CRDT application, and is expected to become a bottleneck on larger files.

This is acceptable as a correctness-first phase, but should be optimized after
behavior stabilizes.

Planned optimization directions:

1. Reuse an incremental tree model between edits instead of rebuilding from AST.
2. Fast-path `UpdateLeaf` (already sketched below) for common rename/value edits.
3. Prefer source-map-targeted edits where possible to reduce unparse+diff scope.

### 3. Node ID Preservation Across Roundtrip

The critical challenge: after tree edit → unparse → reparse, AST node IDs will
be different. The existing reconciliation logic in
`projection/text_lens.mbt` (used by text/tree lens puts) solves this by
matching nodes structurally and preserving IDs:

```
Old AST (with IDs): λx[1]. (x[2] + 1[3])
Tree edit: Move 1[3] before x[2]
New AST (unparsed→reparsed): λx[?]. (1[?] + x[?])
Reconcile: Match structure → λx[1]. (1[3] + x[2])  // IDs preserved
```

This reconciliation already exists in the codebase. The roundtrip should reuse
that logic rather than introducing a second ID-preservation algorithm.

---

## Supported Tree Operations

| Operation | Text roundtrip behavior |
|-----------|------------------------|
| `UpdateLeaf(id, value)` | Change a token in-place (e.g., variable name `x` → `y`) |
| `DeleteNode(id)` | Remove the node's text span, reparse surrounding |
| `InsertNode(parent, idx, node)` | Unparse new node, insert text at parent's span |
| `ReplaceNode(id, new_node)` | Replace node's text span with unparsed new node |
| `MoveNode(id, new_parent, idx)` | Delete from old position, insert at new position |

These are `ModelOperation`s from `projection/types.mbt`. UI-level
`TreeEditOp` values in `projection/tree_lens.mbt` are translated to them.

### `UpdateLeaf` Optimization

For simple leaf edits (rename variable, change number), we can skip full unparse:

```moonbit
/// Optimized leaf update: directly edit the text span
pub fn SyncEditor::update_leaf(
  self : SyncEditor,
  node_id : NodeId,
  new_value : String,
) -> Unit raise {
  let range = self.source_map().get_range(node_id)
  match range {
    Some(r) => {
      let start = source_map_start(r) // helper: expose Range start from SourceMap API
      // Delete old text
      let n = r.length()
      for i = 0; i < n; i = i + 1 {
        self.doc.delete(Pos::at(start))
      }
      // Insert new text
      self.doc.insert(Pos::at(start), new_value)
    }
    None => raise TextError::NodeNotFound(node_id)
  }
}
```

This avoids full unparse/reparse for the most common tree edit operation.

---

## Location

| File | Content |
|------|---------|
| `editor/unparser.mbt` | `unparse(ast) -> String` |
| `editor/unparser_test.mbt` | Roundtrip property tests |
| `editor/tree_edit_bridge.mbt` | `apply_tree_edit`, `update_leaf` |

---

## Verification

1. **Roundtrip property:** For any AST, `parse(unparse(ast)) ≈ ast` (structurally equivalent, ignoring IDs and whitespace).
2. **CRDT convergence:** Two peers — one edits via text, one via tree — converge to same document.
3. **Node ID preservation:** After tree edit roundtrip, unchanged nodes keep their IDs.
4. **Leaf optimization:** `update_leaf` produces identical result to full roundtrip.

---

## Open Questions

1. **Whitespace preservation:** Unparsing loses the original formatting. Should we use CST-aware unparsing (via `SyntaxNode`) to preserve whitespace? This is important for larger languages but may be overkill for lambda calculus.

2. **Concurrent tree edits:** If two peers make tree edits simultaneously, both round-trip through text. The CRDT resolves text conflicts, but the resulting AST may not match either peer's intended tree edit. Is this acceptable? (Yes — same as concurrent text edits.)

3. **Error node handling:** What text does `unparse(Error("msg"))` produce? Using `???` as a placeholder preserves document structure but introduces invalid syntax. Alternative: omit error nodes entirely.

---

## Dependencies

- **Depends on:** [§3 Unified Editor](./03-unified-editor.md) (SyncEditor API)
- **Depends on:** `projection/tree_lens.mbt` (tree edit operations)
- **Depends on:** `projection/text_lens.mbt` (diff + reconciliation logic)
- **Depends on:** `projection/source_map.mbt` (node → text range, existing)
- **Depended on by:** None (leaf node)
