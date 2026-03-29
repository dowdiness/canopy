# Unified Container for Block Editor

**Date:** 2026-03-29
**Status:** Design approved
**References:** Loro (global ID space + per-container state), Diamond Types (causal graph separated from content), Yjs (single StructStore), Automerge (per-object OpTree within global OpSet)

## Problem

BlockDoc wraps one TreeDoc + N independent TextDoc instances. Each owns its own CausalGraph, Lamport clock, and oplog. They share no causal history. This breaks sync (no cross-type ordering), undo (can't group tree + text ops), and concurrent delete+edit (text CRDT doesn't know its block was trashed).

## Core Principle

A Container is a single causal history that multiplexes typed operations to typed state machines. One CausalGraph, one VersionVector, one oplog. Every operation — tree move, property set, text insert, text delete — gets one LV from one shared graph.

## Breaking the LV Triple Coupling

The current text pipeline uses a single `Int` as graph LV, op ID, and Fugue item ID simultaneously. This implicit coupling prevents sharing a CausalGraph across containers.

The refactoring separates these into distinct concepts with type aliases:

```moonbit
type Lv = Int       // global causal version — assigned by shared CausalGraph
type ItemId = Int   // per-container dense item identity — assigned by FugueTree
```

Type aliases (not tuple structs) — safety comes from architectural separation (each package only uses one ID type), not from the type system. Clear naming + package boundaries + explicit conversion at bridge points. If ID confusion bugs arise in practice, upgrade to tuple structs then.

| Package | Uses | Responsibility |
|---------|------|---------------|
| `causal_graph/` | `Lv` | Versioning, causal queries |
| `fugue/` | `ItemId` | Sequence CRDT, dense storage |
| `oplog/` | `Lv` for causal ordering | Operation storage |
| `branch/` | Both — explicit conversion at the bridge | Materialized state, retreat/advance |
| `movable_tree/` | `Lv` directly (one tree, no sparseness) | Tree CRDT |
| `container/` | Both — owns the `Lv → ItemId` mapping per block | Dispatch, sync, undo |

## Architecture

```
Document
├── CausalGraph                         shared, one Lv space, all ops
├── ops: Array[LogEntry]                unified oplog, global Lvs
│   └── LogEntry = { lv: Lv, op: Op }
├── seen_ops: Map                       dedup
├── tree: MovableTree                   global Lvs directly (one tree)
├── tree_log: TreeOpLog                 Kleppmann conflict resolution
├── blocks: Map[TreeNodeId, TextBlock]  per-block text state machines
│   └── TextBlock
│       ├── oplog: OpLog                per-block ops, dense ItemIds
│       ├── branch: Branch              accepts shared CausalGraph + Lv→ItemId mapping
│       ├── fugue: FugueTree            dense ItemIds, unchanged storage model
│       └── lv_table: LvTable           Lv ↔ ItemId bidirectional mapping
├── property_state: Map                 LWW resolution
├── agent_id: String
├── lamport_clock: Int
└── next_counter: Int
```

### Why per-block dense ItemIds

FugueTree stores items as `items: Array[Item[T]?]` where index = ID. With a shared Lv space, a block's text ops have sparse Lvs like [3, 7, 12, 45] — 46-slot array for 4 items. At scale (11K total ops, 100 per block), 110x overhead. Per-block dense ItemIds avoid this.

ItemIds are **replica-local**. Different replicas may assign different ItemIds to the same global Lv. This is correct because FugueTree conflict resolution uses timestamps and origin references, not ItemIds. ItemIds are storage handles, not identity.

### Why tree uses Lvs directly

One tree. Its ops are not interleaved with another tree's ops. MovableTree and TreeOpLog use global Lvs without sparseness.

### Container composes internals directly

The Container uses MovableTree, TreeOpLog, FugueTree, Branch, OpLog, and CausalGraph directly — NOT through TreeState or TextState. Those wrappers remain as public packages for standalone single-CRDT consumers (e.g., canopy's lambda editor uses TextState alone). They are not Container internals.

## Refactoring Scope

The `graph Lv = op ID = Fugue item ID` triple coupling pervades OpLog, Branch, MergeContext, and DeleteIndex. Breaking this is a substantial refactoring of the internal text pipeline, not a single-package change.

### What changes

| Package | Change | Scope |
|---------|--------|-------|
| `causal_graph/` | Introduce `Lv` type alias in API | Small — rename Int → Lv in signatures |
| `fugue/` | Introduce `ItemId` type alias, decouple from Lv | Medium — item storage uses ItemId, not Lv |
| `oplog/` | Decouple op storage index from Lv. Accept ops with Lv for causal ordering + ItemId for Fugue references | Medium — currently assumes Lv = storage index |
| `branch/` | Accept external CausalGraph for causal queries. Convert Lv → ItemId explicitly. Refactor MergeContext and DeleteIndex. | Large — the bridge between two ID spaces |
| `movable_tree/` | None | None |
| `fractional_index/` | None | None |
| `container/` | New package | New code |

### What stays unchanged

- CausalGraph internals (already content-agnostic)
- MovableTree / TreeOpLog (uses Lv directly, no ItemId concern)
- FractionalIndex (no LV dependency)
- FugueTree merge algorithm (conflict resolution logic unchanged; only storage indexing changes)
- Branch retreat/advance algorithm (logic unchanged; only ID translation added at boundaries)

## Op Enum

Closed enum. No trait/registry. Compiler-enforced exhaustive matching.

Text ops use **Fugue-native data** — one character per op (current model splits strings into char ops). `origin_left` and `origin_right` are global Lvs. `None` sentinel for document start/end boundaries.

```moonbit
pub(all) enum Op {
  TreeMove(TreeMoveOp)
  TreeProperty(TreePropertyOp)
  TextInsert(target: TreeNodeId, origin_left: Lv?, origin_right: Lv?, content: Char)
  TextDelete(target: TreeNodeId, item_lv: Lv)
}
```

LogEntry wraps Op with metadata:
```moonbit
pub(all) struct LogEntry {
  lv: Lv
  op: Op
}
```

Transaction grouping tracked on Document as `transactions: Array[TransactionRange]` where `TransactionRange = { agent: String, start_lv: Lv, end_lv: Lv }`. Not a field on Op — transactions are metadata about LV ranges in the unified oplog.

## Text Container Lifecycle

- **Creation:** Implicit. `create_node` auto-creates a TextBlock (empty FugueTree + Branch + OpLog + LvTable).
- **Deletion:** Tree node moves to trash. TextBlock kept for undo.
- **Restoration:** Trashed block restored — TextBlock has full history.
- **Remote text on unknown block:** Container creates TextBlock eagerly. Block creation op arrives later via causal delivery.
- **Local text on trashed block:** Rejected with `DocumentError::TargetNotFound`.

## Public API

Lifecycle:
- `Document::new(replica_id) -> Document raise DocumentError`

Tree (structure):
- `create_node(parent~) -> TreeNodeId raise DocumentError`
- `create_node_after(parent~, after~) -> TreeNodeId raise DocumentError`
- `move_node(target~, new_parent~) raise DocumentError`
- `move_node_after(target~, new_parent~, after~) raise DocumentError`
- `delete_node(target) raise DocumentError`
- `children(parent) -> Array[TreeNodeId]`
- `is_alive(id) -> Bool`

Properties (LWW on tree nodes):
- `set_property(id, key, value)`
- `get_property(id, key) -> String?`

Text (per-block, one char per op):
- `insert_text(id, pos, text) raise DocumentError`
- `delete_text(id, pos) raise DocumentError`
- `replace_text(id, range, text) raise DocumentError`
- `get_text(id) -> String`
- `text_len(id) -> Int`

Sync (SyncMessage schema defined in Phase 3):
- `export_ops(since?: Version) -> SyncMessage`
- `apply_remote(SyncMessage) raise DocumentError`
- `version() -> Version`

Transactions:
- `begin_transaction()`
- `commit_transaction()`

Undo:
- `undo() -> Array[Op]`
- `redo() -> Array[Op]`

## Dispatch

Two paths: local ops (direct apply) and remote ops (merge with retreat/advance).

**Local ops** — sequential, no concurrency. Direct apply:

```moonbit
fn Document::dispatch_local(self, lv: Lv, op: Op) raise DocumentError {
  match op {
    TreeMove(m) => self.tree_log.apply(self.tree, m)
    TreeProperty(p) => self.apply_property_lww(p)
    TextInsert(target, origin_left, origin_right, content) => {
      let block = self.get_or_create_text(target)
      let local_left = block.lv_table.to_item_id(origin_left)
      let local_right = block.lv_table.to_item_id(origin_right)
      let local_id = block.lv_table.register(lv)
      block.oplog.add(local_id, local_left, local_right, content)
      block.branch.apply_insert(local_id, local_left, local_right, content)
    }
    TextDelete(target, item_lv) => {
      let block = self.get_or_create_text(target)
      let local_item = block.lv_table.to_item_id(item_lv)
      block.oplog.add_delete(local_item)
      block.branch.apply_delete(local_item)
    }
  }
}
```

**Remote ops** — potentially concurrent. Text ops go through Branch.merge (eg-walker retreat/advance on the shared CausalGraph, filtered and translated to per-block ItemIds). Tree ops go through TreeOpLog.apply (Kleppmann undo-do-redo). The shared CausalGraph provides the causal structure for both paths.

## Error Type

```moonbit
pub(all) suberror DocumentError {
  EmptyReplicaId
  TargetNotFound
  ParentNotFound
  CycleDetected
  TextBlockNotFound(id: TreeNodeId)
  Internal(detail~: String)
}
```

## Package Structure

```
container/
  document.mbt    Document struct, all mutation methods, dispatch
  types.mbt       Op, LogEntry, LvTable, Lv, ItemId
  errors.mbt      DocumentError
  sync.mbt        export/import protocol
  undo.mbt        transactions, undo/redo
```

In `event-graph-walker/container/`. Composes refactored internal packages.

## Naming Changes

| Current | New | Reason |
|---------|-----|--------|
| `text/Document` | `text/TextState` | Mutable text CRDT state; Document is now the container concept |
| `tree/TreeDoc` | `tree/TreeState` | Same pattern |
| `tree/TreeDocError` | `tree/TreeError` | Follows from TreeState rename |

TextState and TreeState remain as public packages for standalone single-CRDT consumers.

## Block Editor Integration

No BlockDoc wrapper. The block-editor uses `@container.Document` directly. Domain logic (BlockType, markdown) as free functions:

```moonbit
fn create_block(doc: @container.Document, block_type: BlockType, ..) -> TreeNodeId
fn block_doc_from_markdown(md: String, replica_id: String) -> @container.Document
fn block_doc_to_markdown(doc: @container.Document) -> String
```

JS bridge holds `Map[Int, @container.Document]` directly.

## Implementation Phases

Each phase delivers a working increment. Refactoring happens inside the phase that needs it.

| Phase | Delivers | Includes |
|-------|----------|----------|
| **0** | Rename: Document→TextState, TreeDoc→TreeState, TreeDocError→TreeError | Mechanical. Across event-graph-walker + canopy consumers. |
| **1** | Container + tree ops. Block editor switches to `@container.Document`. | Document struct, shared CausalGraph, Op enum (TreeMove + TreeProperty), DocumentError, `move_node_after`. Lv type alias introduced. |
| **2** | Per-block text in Container. Block editor drops TextDoc map. | Refactor OpLog, Branch, MergeContext, DeleteIndex to separate Lv from ItemId. LvTable. TextBlock lifecycle. TextInsert/TextDelete ops (one char per op, Fugue-native origins, Lv? for None sentinels). ItemId type alias introduced. |
| **3** | Unified sync. Two peers converge on a block document. | Fix tree causal parents (currently fabricated from frontier). One export/import protocol. Document-wide VersionVector diff. SyncMessage schema. |
| **4** | Document-level undo. Undo spans tree + text. | Transaction boundaries as (agent, start_lv, end_lv) ranges. Translation-aware undo contract. Reverse delegation to TreeOpLog and per-block text undo. |

Phase 2 is the largest — it's the internal text pipeline refactoring. Phases 3 and 4 build on the foundation from 1 and 2.

## Future Consideration

SyncEditor (projectional editing) and the block editor share a structural pattern: Editor = Document + domain-specific concerns. If a shared editor base emerges from usage, extract it then. The Document API should be editor-agnostic.

Type aliases (Lv, ItemId) can be upgraded to tuple structs if ID confusion bugs arise in practice.
