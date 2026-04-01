# Canopy

**An incremental projectional editor with real-time CRDT collaboration, built in [MoonBit](https://www.moonbitlang.com/).**

Canopy keeps text and syntax trees synchronized. Type in a text editor and watch the AST update instantly. Restructure a node in the tree view and see the source code regenerate. Both directions work, and multiple users can edit the same document concurrently through CRDTs — no central server required.

The naming follows an organic metaphor: **loom** weaves structure from text, **seam** joins layers of representation, and the **canopy** emerges above the trees as the surface you interact with.

[Try the live demo](https://rabbita.koji-ishimoto.workers.dev/) · [Architecture docs](docs/architecture/) · [eg-walker paper](https://arxiv.org/abs/2409.14252)

## Why Canopy?

Most editors treat source code as flat text and derive structure as an afterthought. Canopy treats text and tree as two synchronized views of the same document.

**Bidirectional text-tree editing.** The text CRDT is the source of truth. Parsing produces a syntax tree; projection derives structured editor state. Edits can enter from either side — a text change triggers an incremental reparse, and a tree restructuring generates the corresponding text change — keeping both views consistent at all times.

**Real-time collaboration through CRDTs.** Canopy uses the [eg-walker](https://arxiv.org/abs/2409.14252) algorithm with FugueMax, a sequence CRDT that preserves user intent under concurrent edits. Peers synchronize directly. There is no operational transform and no conflict resolution layer — the CRDT handles convergence.

**Incremental by construction.** The parser framework ([loom](loom/)) achieves subtree reuse through position-independent CST nodes. Editing one character reparses one subtree; the rest is shared from the previous parse. Projection and rendering follow the same principle — only the changed portion of the tree is recomputed.

**Language-agnostic framework.** Canopy is not hard-coded to one language. The core framework (parsing, projection, reconciliation, editing) is generic. Language support is added by providing a grammar and a projection mapping. The repository currently includes lambda calculus and JSON as working examples.

## How It Works

Canopy's pipeline has four stages:

1. **Text CRDT** — The document lives in a FugueMax sequence CRDT ([event-graph-walker](event-graph-walker/)). All edits — local keystrokes, remote peer operations, undo/redo — enter here. This is the single source of truth.

2. **Incremental parsing** — When text changes, the parser framework ([loom](loom/)) incrementally reparses only the affected region, producing a concrete syntax tree. Unchanged subtrees are reused from the previous parse.

3. **Projection** — The CST is mapped to a projection tree (`ProjNode[T]`) carrying language-specific AST nodes, stable node IDs, and source spans. A reconciliation step preserves node identity across reparses so that UI state (selection, collapse, scroll position) survives edits.

4. **Rendering** — The projection tree drives the UI. The protocol layer computes incremental view patches — only the nodes that actually changed are sent to the frontend.

Tree-to-text edits work in reverse: a structural operation (wrap in lambda, delete node, rename binding) computes the corresponding text diff, which feeds back into the text CRDT at stage 1.

## Framework Philosophy

Canopy is built around a few design ideas that distinguish it from typical editor projects.

**Text is ground truth, structure is derived.** Rather than storing an AST and serializing it to text, Canopy stores text in a CRDT and derives structure through parsing. This means the text representation is always well-defined, collaboration operates on a proven CRDT data structure, and the full pipeline from text to tree to view is a deterministic function of the document state.

**Incremental hylomorphism.** The pipeline from text to rendered view is structured as an unfold (parsing text into trees) followed by a fold (collapsing trees into views). Both halves are incremental — they recompute only what changed. This pattern, described in detail in the [architecture docs](docs/architecture/Incremental-Hylomorphism.md), gives the framework its compositional structure.

**Language support is data, not code.** Adding a new language means providing a grammar for loom and a projection mapping. The framework handles incremental parsing, node ID reconciliation, source mapping, undo/redo, and collaboration generically. The lambda calculus and JSON editors share the same core infrastructure.

**Principled intermediate representations.** Representations at pipeline boundaries follow an [anamorphism discipline](docs/architecture/anamorphism-discipline.md): they must be complete (no information loss), context-free (fragment identity doesn't depend on position), uniform in error handling, and structurally transparent. These properties make each pipeline stage independently testable and composable.

## What's in This Repository

Canopy is a monorepo with reusable libraries extracted as git submodules.

**Core libraries:**

- **[event-graph-walker](event-graph-walker/)** — The CRDT engine. Implements the eg-walker algorithm with FugueMax sequence CRDT and binary-lifting jump pointers for O(log n) ancestor queries. This is the collaboration layer.
- **[loom](loom/)** — Incremental parser framework. Includes the parser core (`loom/loom/`), a language-agnostic CST library (`loom/seam/`), reactive signals for incremental computation (`loom/incr/`), and a pretty-printer (`loom/pretty/`).
- **[editor](editor/)** — `SyncEditor`, the main coordination type. Wires together the text CRDT, parser, projection, undo manager, and collaboration protocol. Also provides `EphemeralHub` for cursor and presence tracking.
- **[projection](projection/)** — Language-agnostic projection layer. `TreeEditorState` manages interactive tree state (selection, collapse, drag). Reconciliation preserves node identity across reparses.
- **[core](core/)** — Generic types shared across the framework: `ProjNode[T]`, `NodeId`, `SourceMap`, and the reconciliation algorithm.
- **[protocol](protocol/)** — The `EditorProtocol` integration layer: `ViewPatch`, `ViewNode`, and `UserIntent` for framework-agnostic frontend communication.

**Language packages:**

- **[lang/lambda](lang/lambda/)** — Lambda calculus with arithmetic, conditionals, and let-bindings. The primary test language.
- **[lang/json](lang/json/)** — JSON editing support.

**Examples (start here):**

- **[rabbita](examples/rabbita/)** — The main demo. A tree-first projectional editor built with the [Rabbita](https://github.com/moonbit-community/rabbita) UI framework. This is the best place to see Canopy in action.
- **[web](examples/web/)** — Text-focused editors for lambda calculus and JSON with syntax highlighting. Shows dual-language support.
- **[ideal](examples/ideal/)** — Extended version of rabbita with an inspector panel and benchmarks.
- **[demo-react](examples/demo-react/)** — React 19 integration with undo/redo and collaboration.
- **[prosemirror](examples/prosemirror/)** — ProseMirror + CodeMirror integration.
- **[relay-server](examples/relay-server/)** — Cloudflare Workers relay for peer-to-peer CRDT sync across browsers.

## Example Language

The demo language is lambda calculus with arithmetic — small enough to understand fully, rich enough to exercise the full pipeline:

```
λx.x                  -- identity
(λf.λx.f x) 5         -- application
1 + 2 - 3             -- arithmetic
if x then 1 else 0    -- conditionals
let double = λx.x + x -- definitions
double 5
```

## Quick Start

**Prerequisites:** [MoonBit](https://www.moonbitlang.com/download/) and [Node.js](https://nodejs.org/)

```sh
git clone --recursive https://github.com/dowdiness/canopy.git
cd canopy
moon test
```

Run the projectional editor locally:

```sh
moon build --target js
cd examples/rabbita && npm install && npm run dev
```

Opens at `localhost:5173`. The [web example](examples/web/) (`npm run dev` from `examples/web/`) provides a text-focused editor at the same port.

## What to Read Next

**To understand the architecture:**
- [Incremental Hylomorphism](docs/architecture/Incremental-Hylomorphism.md) — the core compositional pattern
- [Projectional Editing](docs/architecture/PROJECTIONAL_EDITING.md) — the text-tree synchronization model
- [Anamorphism Discipline](docs/architecture/anamorphism-discipline.md) — design rules for intermediate representations
- [Module Structure](docs/architecture/modules.md) — how packages relate to each other

**To contribute:**
- [Development Workflow](docs/development/workflow.md) — how to make changes, run tests, manage submodules
- [Conventions](docs/development/conventions.md) — MoonBit coding patterns used in this project
- [Testing](docs/development/testing.md) — test strategy and how to write tests

**To study performance:**
- [Performance docs](docs/performance/) — dated benchmark snapshots and optimization notes

## Contributing

```sh
moon test                    # run all tests
moon info && moon fmt        # update interfaces and format
moon bench --release         # benchmarks (always use --release)
```

See the [Development Guide](docs/development/) for submodule management, commit conventions, and the full workflow.

## References

- [Eg-walker: CRDTs for Truly Concurrent Sequence Editing](https://arxiv.org/abs/2409.14252) — the CRDT algorithm Canopy uses
- [MoonBit](https://www.moonbitlang.com/) — the language Canopy is built in

## License

[Apache-2.0](LICENSE)
