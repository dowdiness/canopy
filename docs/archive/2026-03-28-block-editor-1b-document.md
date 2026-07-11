# Block Editor — 1b: BlockDoc

**Outcome:** `BlockDoc` CRUD is tested and passes. Insertion order is correct.

**Prereq:** [1a-scaffold.md](../archive/2026-03-28-block-editor-1a-scaffold.md) complete.
**Next plan:** [1c-markdown.md](2026-03-28-block-editor-1c-markdown.md)

---

## Files

- `main/block_doc.mbt` — BlockDoc struct + methods
- `main/block_doc_wbtest.mbt` — whitebox tests

---

## BlockDoc struct

```moonbit
pub struct BlockDoc {
  priv tree        : @tree.TreeDoc
  priv texts       : Map[BlockId, @text.TextDoc]
  priv mut order   : Array[BlockId]   // display order for root children (V1)
  priv replica_id  : String
}

pub type BlockId = @tree.TreeNodeId
pub let root_block_id : BlockId = @tree.root_id
```

**Why `order`:** `TreeDoc` does not expose `create_node_after`. Phase 2 replaces
this with fractional-index ordering once the API is extended.

---

## Public API

```moonbit
BlockDoc::new(replica_id) -> BlockDoc
BlockDoc::create_block(block_type, parent~) -> BlockId   // appends to order
BlockDoc::create_block_after(after_id, block_type) -> BlockId
BlockDoc::delete_block(id)            // removes from tree + order
BlockDoc::move_block(id, new_parent~)
BlockDoc::children(parent) -> Array[BlockId]
  // root_block_id → returns order (filtered for alive)
  // other         → delegates to tree.children (Phase 2 nesting)
BlockDoc::is_alive(id) -> Bool
BlockDoc::get_type(id) -> BlockType
BlockDoc::set_type(id, BlockType)
BlockDoc::get_text(id) -> String
BlockDoc::set_text(id, text)          // delete-all + insert (CRDT bulk replace)
BlockDoc::insert_char(id, pos, ch)    // incremental, preferred for typing
BlockDoc::delete_char(id, pos)
BlockDoc::get_checked(id) -> Bool     // todo list items
BlockDoc::set_checked(id, Bool)
```

---

## Required tests (write first)

```
"create paragraph and read text"
"create heading with level"
"children order is insertion order"
"delete block removes from children"
"change block type preserves text"
"list item style and checked"
"create_block_after inserts at correct position"
  a, b created; c = create_block_after(a) → order: [a, c, b]
"create_block_after appends when after_id is last"
```

---

## Checks

- [ ] All tests pass (`moon test`)
- [ ] `moon check` clean
- [ ] Commit: `feat(block-editor): BlockDoc CRUD with order tracking`
