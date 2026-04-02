# Canopy

**Write. It structures itself.**

<!-- TODO: Replace with a GIF showing: type code → tree updates → scope colors → evaluation result appears inline → second peer edits simultaneously -->

Canopy is an editor that understands your program, not just your characters. As you type, it parses incrementally, shows you scope and types, evaluates expressions live, and formats your code — all without leaving the flow. Two people can edit the same document simultaneously, with no server. Edits merge automatically.

[Try the live demo](https://lambda-editor.koji-ishimoto.workers.dev/) · [Architecture](docs/architecture/) · [eg-walker paper](https://arxiv.org/abs/2409.14252)

## Why

Most editors treat source code as flat text. You type characters, and the tool does its best to guess what you meant — syntax highlighting, auto-complete, error squiggles — all reconstructed after the fact from dead text.

Canopy treats your program as a living structure. Text and syntax tree are **two synchronized views** of the same document. Type in one, the other updates. Restructure in one, the other follows. The editor doesn't guess what your code means — it knows, because it maintains the meaning incrementally as you type.

The goal: **close the gap between what you think and what the tool understands.** When the editor holds the same mental model you do — scope, types, values, dependencies — it can show you what matters, when it matters, without you having to search for it.

## What It Looks Like

The demo language is lambda calculus — small enough to understand fully, rich enough to exercise the full pipeline:

```
let double = λx. x + x
let result = double 5
if result then result else 0
```

As you type this, Canopy:
- Parses incrementally (one character change → one subtree reparse)
- Resolves scope (knows `x` is bound by `λ`, `double` refers to the definition above)
- Formats with syntax highlighting through the pretty-printer
- Evaluates `double 5 → 10` and `if result then result else 0 → 10`
- Synchronizes with any connected peer via CRDT

## How It Works

Four stages, each incremental:

```
Text CRDT → Incremental Parse → Projection → Rendering
    ↑                                            │
    └────── structural edits feed back ──────────┘
```

1. **Text CRDT** ([event-graph-walker](event-graph-walker/)) — The document lives in a FugueMax sequence CRDT. All edits — keystrokes, remote operations, undo/redo — enter here. Peers sync directly, no central server.

2. **Incremental parsing** ([loom](loom/)) — Only the affected region is reparsed. Unchanged subtrees are reused from the previous parse through position-independent CST nodes.

3. **Projection** — The syntax tree maps to a projection tree with stable node IDs and source spans. Node identity survives reparses, so UI state (selection, scroll) is preserved.

4. **Rendering** — The protocol layer computes incremental view patches. Only changed nodes reach the frontend. Multiple representations — formatted text, tree view, graph visualization — render from the same projection.

## The Bigger Picture

Canopy is a framework, not just an editor. Define a grammar for your language, implement a few traits, and you get incremental parsing, structural editing, pretty-printing, and CRDT collaboration out of the box.

But the long-term vision goes further. The code editor is a vertical slice of something larger: **a system where you write freely, structure emerges automatically, and the right information surfaces when you need it.** Every layer of the editor — incremental computation, semantic analysis, reactive projections, peer-to-peer sync — is a building block for that system.

Read more: [Product Vision](docs/architecture/product-vision.md) · [The Projectional Bridge](docs/architecture/vision-projectional-bridge.md) · [Multi-Representation System](docs/architecture/multi-representation-system.md)

## Framework Design

**Text is ground truth, structure is derived.** The text CRDT stores the document; everything else is computed. This means collaboration operates on a proven data structure, and the pipeline from text to view is a deterministic function of document state.

**Language support is data, not code.** Adding a new language means providing a grammar and a projection mapping. The framework handles parsing, reconciliation, undo/redo, and collaboration generically. Lambda calculus and JSON share the same core.

**Multiple representations from one source.** The [Printable trait family](docs/architecture/multi-representation-system.md) (Show, Debug, Source, Pretty) gives every language four text representations. `Source` guarantees `parse(to_source(x)) == x`. `Pretty` produces width-aware, syntax-annotated formatted output. Adding a new text format = adding a render function, not changing language code.

**Incremental by construction.** Every stage — parsing, projection, rendering — recomputes only what changed. This isn't bolted-on caching; it's the [architectural principle](docs/architecture/Incremental-Hylomorphism.md) the framework is built around.

## Repository Structure

**Core libraries:**

| Library | Purpose |
|---------|---------|
| [event-graph-walker](event-graph-walker/) | CRDT engine — eg-walker with FugueMax, O(log n) ancestor queries |
| [loom](loom/) | Incremental parser framework, CST library, reactive signals, pretty-printer |
| [editor](editor/) | SyncEditor — wires CRDT, parser, projection, undo, collaboration |
| [protocol](protocol/) | ViewPatch, ViewNode, UserIntent — framework-agnostic frontend protocol |
| [core](core/) | ProjNode[T], NodeId, SourceMap, reconciliation |
| [projection](projection/) | TreeEditorState, interactive tree operations |

**Language packages:**

| Package | Language |
|---------|----------|
| [lang/lambda](lang/lambda/) | Lambda calculus with arithmetic, conditionals, let-bindings |
| [lang/json](lang/json/) | JSON structural editing |

**Examples:**

| Example | Description |
|---------|-------------|
| [web](examples/web/) | Canonical demo — lambda + JSON editors with syntax-highlighted pretty-print |
| [ideal](examples/ideal/) | Full-featured editor with inspector, benchmarks |
| [prosemirror](examples/prosemirror/) | ProseMirror structural editing integration |
| [canvas](examples/canvas/) | Infinite canvas (experimental) |
| [block-editor](examples/block-editor/) | Block-based structural editing |

## Quick Start

**Prerequisites:** [MoonBit](https://www.moonbitlang.com/download/) and [Node.js](https://nodejs.org/)

```sh
git clone --recursive https://github.com/dowdiness/canopy.git
cd canopy
moon test                                    # 684+ tests
moon build --target js
cd examples/web && npm install && npm run dev  # localhost:5173
```

## What to Read Next

**Vision and architecture:**
- [Product Vision](docs/architecture/product-vision.md) — the full picture: write, auto-structure, surface
- [The Projectional Bridge](docs/architecture/vision-projectional-bridge.md) — why: syntax → semantics → intent → mental model
- [Multi-Representation System](docs/architecture/multi-representation-system.md) — the Printable trait family and expression problem
- [Incremental Hylomorphism](docs/architecture/Incremental-Hylomorphism.md) — the compositional engine underneath

**Development:**
- [Development Workflow](docs/development/workflow.md) — how to make changes, run tests, manage submodules
- [Conventions](docs/development/conventions.md) — MoonBit coding patterns
- [TODO](docs/TODO.md) — active backlog

## Contributing

```sh
moon test                    # run all tests
moon info && moon fmt        # update interfaces and format
moon bench --release         # benchmarks (always use --release)
```

See the [Development Guide](docs/development/) for details.

## References

- [Eg-walker: CRDTs for Truly Concurrent Sequence Editing](https://arxiv.org/abs/2409.14252) — the CRDT algorithm
- [MoonBit](https://www.moonbitlang.com/) — the implementation language

## License

[Apache-2.0](LICENSE)
