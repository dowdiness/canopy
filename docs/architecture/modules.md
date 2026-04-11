# Module Structure

The codebase is organized as a **monorepo with git submodules**:

## Git Submodules (Standalone Libraries)

| Submodule | GitHub Repo | MoonBit Module |
|---|---|---|
| `event-graph-walker/` | [dowdiness/event-graph-walker](https://github.com/dowdiness/event-graph-walker) | `dowdiness/event-graph-walker` |
| `loom/` | [dowdiness/loom](https://github.com/dowdiness/loom) | `dowdiness/loom`, `dowdiness/seam`, `dowdiness/incr`, `dowdiness/lambda` |
| `svg-dsl/` | [dowdiness/svg-dsl](https://github.com/dowdiness/svg-dsl) | `antisatori/svg-dsl` |
| `graphviz/` | [dowdiness/graphviz](https://github.com/dowdiness/graphviz) | `antisatori/graphviz` |
| `valtio/` | [dowdiness/valtio](https://github.com/dowdiness/valtio) | `antisatori/valtio` |
| `rle/` | [dowdiness/rle](https://github.com/dowdiness/rle) | `dowdiness/rle` |

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

Monorepo containing the incremental parser framework and lambda calculus example.
The `crdt` module depends on `dowdiness/lambda` (`loom/examples/lambda/`) and `dowdiness/loom` (`loom/loom/`).

- `loom/loom/` — `dowdiness/loom`: generic parser framework (core, bridge, pipeline, incremental, viz)
- `loom/seam/` — `dowdiness/seam`: language-agnostic CST (`CstNode`, `SyntaxNode`)
- `loom/incr/` — `dowdiness/incr`: reactive signals (`Signal`, `Memo`)
- `loom/examples/lambda/` — `dowdiness/lambda`: lambda calculus tokenizer, grammar, AST, benchmarks

**See:** [loom/README.md](../../loom/README.md) for detailed documentation.

## `crdt/` Module (Canopy — Projectional Editor Application)

Application layer that uses event-graph-walker and parser as path dependencies.

### `/` (root)
JavaScript FFI bindings that expose the editor API to JavaScript.

### `lib/text-change/`
Leaf MoonBit module with the pure contiguous `TextChange` algorithm shared by
`crdt`, `loom`, and `valtio`.
Inside this monorepo it is consumed via path dependencies; standalone packaging
is deferred until the shared API shape settles.

### `framework/core/`
Generic projectional editing primitives, independent of any language.

- NodeId, ProjNode[T], SourceMap, reconcile, assign_fresh_ids, get_node_in_tree
- ToJson for ProjNode and SourceMap
- Zero dependencies on `@ast` or `@lambda` — the acid test for framework genericity
- Uses `TreeNode`/`Renderable` traits from `dowdiness/loom/core`

### `editor/`
High-level editor abstractions.

- `SyncEditor[T]` — generic facade composing `TextState`, `UndoManager`, `ImperativeParser`, and memo-derived projection views
- Lambda-specific wiring: projection memo builder, tree edit bridge, tree edit JSON

### `projection/`
Interactive tree editor state and projection UI logic.

- `TreeEditorState[T]` — interactive tree UI state, refresh/reuse algorithm
- `InteractiveTreeNode[T]` — decorated tree node for UI rendering

### `lang/*/proj/`
Projection builders — CST-to-ProjNode conversion, token span extraction, memo pipeline setup. One per language (lambda, json, markdown). Depends on core + parser.

### `lang/*/edits/`
Pure edit computation — edit op enums and span-edit calculators. No editor dependency; takes source text + ProjNode + SourceMap, returns SpanEdits. One per language.

### `lang/*/companion/`
Editor bridge — factory functions and edit application. Depends on editor + edits + proj. Delegates to `SyncEditor::apply_span_edits()` after computing edits. One per language.

### `lang/lambda/flat/`
Incremental FlatProj wrapper — memo-based incremental projection updates for lambda.

### `cmd/main/`
Command-line entry points and REPL.

### Trait placement

`TreeNode` and `Renderable` are defined in `dowdiness/loom/core` (the parser framework
defines how editors inspect ASTs). `dowdiness/lambda/ast` implements them for `Term`
(the type owner imports the traits). This resolves MoonBit's orphan rule cleanly:
neither side is "foreign" at the impl site.

## Dependencies

```
svg-dsl (independent)
   ↑
graphviz (depends on svg-dsl via path ../svg-dsl)
   ↑
   ├── loom/viz (depends on graphviz via path ../../graphviz)

text-change (leaf module, independent)
   ↑
   ├── loom/core (depends on text-change via path ../../lib/text-change)
   ├── valtio (depends on text-change via path ../lib/text-change)
   └── crdt (depends on text-change via path ./lib/text-change)

rle (independent, quickcheck only)
   ↑
event-graph-walker (depends on rle + quickcheck)

crdt (depends on event-graph-walker + dowdiness/lambda + dowdiness/json + dowdiness/loom + dowdiness/text_change via path deps)
  ├── framework/core (depends on loom/core — generic types + traits + SpanEdit + FocusHint)
  ├── lang/lambda/proj (depends on framework/core + lambda + seam)
  ├── lang/lambda/edits (depends on core + lang/lambda/proj + lambda)
  ├── lang/lambda/companion (depends on core + editor + lang/lambda/edits + lang/lambda/proj + lang/lambda/flat + lang/lambda/eval + incr + lambda + loom + seam)
  ├── lang/lambda/flat (depends on projection + incr)
  ├── lang/json/proj (depends on framework/core + json + loom + seam + incr)
  ├── lang/json/edits (depends on core + lang/json/proj + json)
  ├── lang/json/companion (depends on editor + lang/json/edits + lang/json/proj + json + loom)
  ├── lang/markdown/edits (depends on core + markdown)
  ├── lang/markdown/companion (depends on editor + lang/markdown/edits + lang/markdown/proj + markdown + loom)
  ├── projection (interactive tree UI state: depends on core + loom/core)
  └── editor (depends on core + loom/core + event-graph-walker + loom + incr)
```

## MoonBit Module Configuration

The root `moon.mod.json` declares path dependencies on the submodules:

```json
{
  "deps": {
    "dowdiness/event-graph-walker": { "path": "./event-graph-walker" },
    "dowdiness/text_change": { "path": "./lib/text-change" },
    "dowdiness/lambda": { "path": "./loom/examples/lambda" },
    "dowdiness/loom": { "path": "./loom/loom" }
  }
}
```

## Run Tests

```bash
cd lib/text-change && moon test               # Shared text-change leaf
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
