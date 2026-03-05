# Module Structure

The codebase is organized as a **monorepo with git submodules**:

## Git Submodules (Standalone Libraries)

| Submodule | GitHub Repo | MoonBit Module |
|---|---|---|
| `event-graph-walker/` | [dowdiness/event-graph-walker](https://github.com/dowdiness/event-graph-walker) | `dowdiness/event-graph-walker` |
| `loom/` | [dowdiness/loom](https://github.com/dowdiness/loom) | `dowdiness/lambda` (examples/lambda root pkg) |
| `svg-dsl/` | [dowdiness/svg-dsl](https://github.com/dowdiness/svg-dsl) | `antisatori/svg-dsl` |
| `graphviz/` | [dowdiness/graphviz](https://github.com/dowdiness/graphviz) | `antisatori/graphviz` |
| `valtio/` | [dowdiness/valtio](https://github.com/dowdiness/valtio) | `antisatori/valtio` |

## `event-graph-walker/` Module (Core CRDT Library)

A reusable CRDT library implementing the eg-walker algorithm. Contains 5 packages:

### `causal_graph/`
Causal graph data structure for tracking operation dependencies.

- Maintains parent relationships and Lamport timestamps
- Implements transitive closure, graph diffing, and ancestry checks
- **Event graph walker** (`walker.mbt`) - Core eg-walker algorithm for topological traversal
- **Version vectors** (`version_vector.mbt`) - Compact representation of version frontiers for efficient network sync

### `oplog/`
Operation log for append-only storage of edit operations.

### `fugue/`
FugueMax tree implementation (ordered sequence CRDT).

### `branch/`
Branch/snapshot system for efficient document state reconstruction and merging.

### `document/`
CRDT document model (general-purpose text document).

**See:** [event-graph-walker/README.md](../../event-graph-walker/README.md) for detailed documentation.

## `loom/` Module (Lambda Calculus Parser + Framework)

Rabbita-style monorepo containing the incremental parser framework and lambda calculus example.
The `crdt` module uses `dowdiness/lambda` (`loom/examples/lambda/`) — the root package is aliased `@parser` in pkg files for source compatibility.

- `loom/loom/` — `dowdiness/loom`: generic parser framework (core, bridge, pipeline, incremental, viz)
- `loom/seam/` — `dowdiness/seam`: language-agnostic CST (`CstNode`, `SyntaxNode`)
- `loom/incr/` — `dowdiness/incr`: reactive signals (`Signal`, `Memo`)
- `loom/examples/lambda/` — `dowdiness/lambda`: lambda calculus tokenizer, grammar, AST, benchmarks

**See:** [loom/README.md](../../loom/README.md) for detailed documentation.

## `crdt/` Module (Lambda Calculus Editor Application)

Application layer that uses event-graph-walker and parser as path dependencies.

### `/` (root)
JavaScript FFI bindings (`crdt.mbt`) that expose the editor API to JavaScript.

### `editor/`
High-level editor abstractions (application-specific).

- `SyncEditor` - Unified facade composing TextDoc, UndoManager, and ReactiveParser with cursor tracking
- Text diff utilities for incremental parser integration

### `projection/`
Projectional editing support.

### `cmd/main/`
Command-line entry points and REPL.

## Dependencies

```
svg-dsl (independent)
   ↑
graphviz (depends on svg-dsl via path ../svg-dsl)

valtio (independent)

event-graph-walker (independent, quickcheck only)

loom (independent: loom/seam/incr/lambda submodules)

crdt (depends on event-graph-walker + dowdiness/lambda + dowdiness/loom via path deps)
```

## MoonBit Module Configuration

The root `moon.mod.json` declares path dependencies on the submodules:

```json
{
  "deps": {
    "dowdiness/event-graph-walker": { "path": "./event-graph-walker" },
    "dowdiness/lambda": { "path": "./loom/examples/lambda" },
    "dowdiness/loom": { "path": "./loom/loom" }
  }
}
```

## Run Tests

```bash
moon test                                    # crdt module
cd event-graph-walker && moon test          # CRDT library
cd loom/loom && moon test                   # Parser framework
cd loom/examples/lambda && moon test        # Lambda example
```

## Design Rationale

### Why Submodules?

1. **Reusability**: Libraries can be used independently in other projects
2. **Separation of concerns**: Core CRDT logic is independent of lambda calculus
3. **Independent versioning**: Each library can be versioned and released separately
4. **Testing**: Each library tested independently
5. **Clarity**: Makes dependencies explicit
