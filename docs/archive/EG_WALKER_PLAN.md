# Eg-Walker CRDT Editor in MoonBit - Architecture & Implementation Plan

## Overview

This document outlines the architecture and implementation plan for an eg-walker CRDT (Conflict-free Replicated Data Type) editor in MoonBit. The implementation will use the **FugueMax** algorithm for sequence operations and the **retreat-advance-apply** merge strategy for handling concurrent edits.

## User Requirements

- **Interface**: CLI/Terminal-based editor
- **Algorithm**: FugueMax for deterministic concurrent insert ordering
- **Features**: Basic insert/delete operations and merge/sync capabilities
- **Approach**: Start simple, add optimizations (RLE, critical versions) later

---

## Architecture

### Module Structure

```
crdt/
├── causal_graph/          # Version tracking and causal dependencies
│   ├── graph.mbt          # CausalGraph structure and operations
│   ├── version.mbt        # LV/RawVersion types
│   └── frontier.mbt       # Frontier management
│
├── oplog/                 # Operation log
│   ├── operation.mbt      # Operation types (Insert/Delete)
│   └── oplog.mbt          # OpLog structure
│
├── fugue/                 # FugueMax tree algorithm
│   ├── item.mbt           # Item structure
│   ├── tree.mbt           # FugueTree structure
│   └── integrate.mbt      # Integration algorithm
│
├── merge/                 # Three-phase merge
│   ├── retreat.mbt        # Remove operations
│   ├── advance.mbt        # Replay operations
│   └── apply.mbt          # Coordinate merge
│
├── editor/                # User-facing API
│   ├── document.mbt       # Document state
│   └── editor.mbt         # Editor with cursor
│
├── crdt.mbt              # Public API re-exports
└── cmd/main/
    ├── main.mbt          # CLI entry point
    └── repl.mbt          # REPL commands
```

### Dependency Graph

```
cmd/main → editor → merge → fugue
                  ↓         ↓
                oplog → causal_graph
```

---

## Core Concepts

### 1. CausalGraph - Version Tracking

**Purpose**: Track operation dependencies and causal ordering

**Key Types**:
- `LV` (Local Version): Integer index for operations (0, 1, 2...)
- `RawVersion`: `(agent_id, sequence_number)` - globally unique ID
- `GraphEntry`: Stores parents, agent, seq, Lamport timestamp

**Key Operations**:
- `add_version`: Create new version with causal parents
- `update_frontier`: Maintain set of latest operations
- `graph_diff`: Calculate retreat/advance sets for merge

### 2. OpLog - Operation Storage

**Purpose**: Store append-only list of operations with causal metadata

**Operation Types**:
- `Insert(position, text)`: Insert text at position
- `Delete(position)`: Delete character at position

**Metadata**:
- `lv`: This operation's local version
- `parents`: Causal dependencies (frontier when created)
- `origin_left`/`origin_right`: FugueMax tree positioning

### 3. FugueMax Tree - Sequence CRDT

**Purpose**: Maintain ordered sequence with deterministic concurrent insert resolution

**Key Algorithm - integrate()**:
Finds correct parent for new item by:
1. Starting at `origin_left`
2. Walking up tree until finding valid parent
3. Valid = ancestor of all items between it and `origin_right`
4. Concurrent inserts at same position use tree structure + agent ID tie-breaking

**Result**: Two editors inserting "A" and "B" at position 0 concurrently will converge to same order (e.g., "AB" or "BA") deterministically

### 4. Merge Algorithm - Retreat-Advance-Apply

**Purpose**: Integrate concurrent edits from multiple replicas

**Three Phases**:

1. **Retreat**: Given current frontier and target frontier, calculate which operations to temporarily remove
2. **Advance**: Replay operations to reach the target frontier state
3. **Apply**: Integrate new operations into the tree

**Why this works**: By retreating/advancing, we transform the document to match the exact state when the new operation was created, so we can use its original position.

---

## Critical Files & Algorithms

### 1. causal_graph/graph.mbt
**Most Critical**: Foundation for all causal reasoning

**Key Algorithms**:
- `lv_to_raw()`: Convert LV → (agent, seq)
- `raw_to_lv()`: Convert (agent, seq) → LV
- `add_version()`: Create new version with Lamport timestamp
- `graph_diff()`: Calculate retreat/advance sets using transitive closure

### 2. fugue/integrate.mbt
**Core CRDT Logic**: Determines ordering for concurrent edits

**Key Algorithms**:
- `find_parent()`: Walk up tree to find valid parent
- `integrate()`: Insert item with correct parent
- `to_text()`: In-order tree traversal for rendering

### 3. merge/apply.mbt
**Merge Coordinator**: Brings everything together

**Key Algorithm**:
```
merge(local_frontier, remote_frontier, remote_ops):
  (retreat_set, advance_set) = graph_diff(local_frontier, remote_frontier)
  tree' = retreat(tree, retreat_set)
  tree'' = advance(tree', advance_set)
  return tree''
```

### 4. editor/document.mbt
**Position Mapping**: Bridge between user positions and LV locations

**Key Operations**:
- `local_insert(pos, text)`: Create insert operation at cursor position
- `local_delete(pos)`: Create delete operation
- `apply_remote(op)`: Integrate remote operation

### 5. oplog/operation.mbt
**Data Model**: Serializable operation structure

**Structure**:
```moonbit
struct Op {
  lv: LV
  parents: Array[LV]
  content: OpContent  // Insert(String) | Delete
  origin_left: LV
  origin_right: Option[LV]
}
```

---

## Implementation Phases

### Phase 1: Foundation - CausalGraph
**Files**: `causal_graph/graph.mbt`, `version.mbt`, `frontier.mbt`

**Tasks**:
1. Define LV, RawVersion, GraphEntry types
2. Implement CausalGraph with version maps
3. Implement add_version with Lamport timestamps
4. Implement frontier update/merge
5. Implement graph_diff algorithm
6. Write comprehensive tests

**Success**: Can create versions, track dependencies, calculate diff

### Phase 2: OpLog
**Files**: `oplog/operation.mbt`, `oplog.mbt`

**Tasks**:
1. Define Op and OpContent types
2. Implement OpLog structure
3. Implement operation creation with metadata
4. Write tests

**Success**: Can create and store operations

### Phase 3: FugueMax Tree
**Files**: `fugue/item.mbt`, `tree.mbt`, `integrate.mbt`

**Tasks**:
1. Define Item and TreeNode types
2. Implement FugueTree structure
3. Implement find_parent algorithm
4. Implement integrate algorithm
5. Implement to_text rendering
6. Write concurrent insert tests

**Success**: Concurrent inserts have deterministic order, text renders correctly

### Phase 4: Merge Algorithm
**Files**: `merge/retreat.mbt`, `advance.mbt`, `apply.mbt`

**Tasks**:
1. Implement retreat phase
2. Implement advance phase
3. Implement merge coordination
4. Write convergence tests

**Success**: Merge produces correct results, convergence verified

### Phase 5: Document & Editor
**Files**: `editor/document.mbt`, `editor.mbt`, update `crdt.mbt`

**Tasks**:
1. Implement Document with position-based ops
2. Implement Editor with cursor
3. Map positions to LV locations
4. Implement public API
5. Write integration tests

**Success**: Can perform edits, position mapping works

### Phase 6: CLI/REPL
**Files**: `cmd/main/main.mbt`, `cmd/main/repl.mbt`

**Tasks**:
1. Create REPL loop
2. Implement commands: insert, delete, show, merge, export
3. Add file save/load
4. Add multi-agent simulation

**Commands**:
- `insert <pos> <text>` - Insert text
- `delete <pos>` - Delete character
- `move <pos>` - Move cursor
- `show` - Display text
- `export` - Export state
- `merge <data>` - Merge operations
- `quit` - Exit

**Success**: Can use editor via CLI, simulate multi-agent scenario

---

## Testing Strategy

### Unit Tests
- **CausalGraph**: Version conversion, frontier management, graph diff
- **FugueTree**: Parent finding, integration, rendering
- **Merge**: Retreat, advance, full merge

### Integration Tests
- **Document**: Position-based operations
- **Editor**: Cursor tracking, multi-operation sequences

### Convergence Tests (Critical)
```moonbit
test "concurrent inserts converge" {
  // Agent 1 inserts "A" at pos 0
  // Agent 2 inserts "B" at pos 0
  // Cross-merge
  // Assert: both converge to same text
}
```

---

## Key Data Structures

### CausalGraph
```moonbit
struct CausalGraph {
  entries: Map[LV, GraphEntry]           // LV → entry
  version_map: Map[RawVersion, LV]       // (agent,seq) → LV
  next_lv: LV                            // Next available LV
  frontier: Array[LV]                    // Current heads
  agent_seqs: Map[AgentId, Int]          // Per-agent sequence
}
```

### Op (Operation)
```moonbit
struct Op {
  lv: LV                                 // This operation's LV
  parents: Array[LV]                     // Causal dependencies
  content: OpContent                     // Insert | Delete
  origin_left: LV                        // FugueMax: left context
  origin_right: Option[LV]               // FugueMax: right context
}
```

### Item (FugueMax Tree Node)
```moonbit
struct Item {
  id: LV                                 // Operation that created this
  content: String                        // The character(s)
  parent: Option[LV]                     // Tree parent (from origin_left)
  deleted: Bool                          // Tombstone
  timestamp: Int                         // Lamport for tie-breaking
}
```

### Editor
```moonbit
struct Editor {
  doc: Document                          // The CRDT document
  cursor: Int                            // Current cursor position
  agent_id: AgentId                      // This replica's ID
}
```

---

## MoonBit-Specific Notes

1. **Immutability**: Use `@immut/hashmap.Map` for graphs, return new instances
2. **Pattern Matching**: Use `match` for OpContent (Insert/Delete)
3. **Error Handling**: Use `Option`/`Result` types
4. **Testing**: Use `inspect()` with `moon test --update` for snapshot tests
5. **Formatting**: Run `moon fmt` after changes
6. **Type Info**: Check `.mbti` files with `moon info`

---

## Success Criteria

- [ ] All `moon test` pass
- [ ] All `moon check` pass
- [ ] Can insert/delete text
- [ ] Can merge concurrent edits
- [ ] Convergence property verified
- [ ] CLI provides usable interface
- [ ] Code formatted and documented

---

## Future Optimizations (Not in MVP)

- Run-length encoding (RLE) for consecutive characters
- Critical versions for frontier compression
- Efficient position lookup with cached counts
- Binary serialization format
- Undo/redo support
- Rich text metadata
- Network sync protocol

---

## References

- [eg-walker paper](https://arxiv.org/abs/2409.14252)
- [eg-walker reference implementation](https://github.com/josephg/eg-walker-reference)
- [FugueMax algorithm](https://arxiv.org/abs/2305.00583)
- [Joseph Gentle's explanation video](https://www.youtube.com/watch?v=_lQ2Q4Kzi1I)
