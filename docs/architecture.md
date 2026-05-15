# Canopy Architecture

Single-page summary of how Canopy is structured. Each section names the
packages and types involved so that code remains the source of truth; longer
prose lives under [docs/architecture/](architecture/).

> If a claim here disagrees with the code, the code wins. Update this file
> rather than the code.

## Pipeline

```
Text CRDT ─► Incremental parse ─► Projection ─► View patches ─► Frontend
   ▲                                                                 │
   └────────────── structural edits feed back ───────────────────────┘
```

1. The document is stored in a FugueMax sequence CRDT
   (submodule [`event-graph-walker`](../event-graph-walker/)).
2. The incremental parser
   (submodule [`loom`](../loom/)) reparses only affected regions.
3. The [`projection/`](../projection/) layer maps the parse tree to projection
   nodes with stable identity.
4. The [`protocol/`](../protocol/) layer computes patches the frontend can
   apply.
5. Structural edits go back through the CRDT as text edits, closing the loop.

## Package responsibility map (canopy module)

| Package | Owns |
|---------|------|
| [`core/`](../core/) | Tree-projection primitives: `NodeId`, `ProjNode[T]`, `SourceMap`, `SpanEdit`, `GenericTreeOp` |
| [`editor/`](../editor/) | `SyncEditor[T]`, view-patch computation, undo, ephemeral cursors, websocket plumbing |
| [`protocol/`](../protocol/) | Wire-format types: `ViewPatch`, `ViewNode`, `UserIntent`, `Decoration`, `Diagnostic` |
| [`projection/`](../projection/) | `TreeEditorState[T]`, `InteractiveTreeNode[T]`, interactive tree edits |
| [`relay/`](../relay/) | Minimal byte-buffer relay used by `editor/` collaboration |
| [`ffi/lambda`](../ffi/lambda/), [`ffi/json`](../ffi/json/), [`ffi/markdown`](../ffi/markdown/) | JS export surfaces (JS target only) |
| [`lang/lambda/*`](../lang/lambda/) | Lambda calculus pipeline (`proj`, `edits`, `eval`, `flat`, `companion`) |
| [`lang/json/*`](../lang/json/) | JSON projectional editor (`proj`, `edits`, `companion`) |
| [`lang/markdown/*`](../lang/markdown/) | Markdown projectional editor (`proj`, `edits`, `companion`) |
| [`llm/`](../llm/) | Optional fetch-based LLM client (JS only); consumed by `ffi/lambda` |
| [`cmd/main/`](../cmd/main/) | Native CLI entry point |
| [`echo/`](../echo/), [`echo/tokenizer/`](../echo/tokenizer/) | Tokenisation + similarity engine for the echo experiment |

### Workspace libraries (`moon.work` members)

| Package | Role |
|---------|------|
| [`lib/btree/`](../lib/btree/) | Counted B+ tree, O(log n) position lookup |
| [`lib/moji/`](../lib/moji/) | UAX #29 grapheme- and word-boundary segmentation |
| [`lib/zipper/`](../lib/zipper/) | Rose-tree zipper |
| [`lib/text-change/`](../lib/text-change/) | Text-mutation primitives |

[`lib/semantic/`](../lib/semantic/) (with `lib/semantic/proof/`) is in-tree but
*not* a workspace member; it must be tested and proved separately.

### Submodules

Submodules are independent repositories pulled in via path dependencies. See
[`development/monorepo.md`](development/monorepo.md) for the daily workflow.

| Path | Role |
|------|------|
| `event-graph-walker/` | CRDT engine (eg-walker, FugueMax) |
| `loom/` | Incremental parser framework, CST library (`loom/seam`), reactive signals (`loom/incr`), pretty-printer (`loom/pretty`), example languages, egglog/egraph |
| `rle/` | Run-length encoded sequence |
| `order-tree/` | Counted tree |
| `graphviz/`, `svg-dsl/` | Visualisation in the inspector |
| `valtio/` | JS state management glue |
| `alga/` | Graph algebra |

## Key types and invariants

These are framework-level invariants. Specific field names belong in the code,
not here.

- **Text is ground truth.** The CRDT's text content is authoritative;
  everything else is computed. Structural edits are first translated into text
  edits before they enter the CRDT.
- **Projection identity is stable across reparses.** `NodeId` survives
  reparsing, so UI state (selection, scroll, drag) does not flicker when the
  underlying tree changes. Reconciliation lives in `core/`.
- **CST nodes are position-independent.** The parser stores relative widths,
  not absolute positions; unchanged subtrees are reused on reparse.
- **Protocol types are JSON-serialisable.** Anything that crosses the FFI is
  declared in [`protocol/`](../protocol/); the TypeScript counterpart lives in
  [`adapters/editor-adapter/types.ts`](../adapters/editor-adapter/types.ts).
- **Cross-package struct construction needs `pub(all)` or a named constructor.**
  Plain `pub struct` is read-only outside the defining package.

## Extension points

- **Adding a language** — implement a parser in a `loom/examples/<lang>/`
  module and a projection layer in `lang/<lang>/proj/`, then a JS FFI in
  `ffi/<lang>/`. The reference implementation is Markdown; see
  [`development/ADDING_A_LANGUAGE.md`](development/ADDING_A_LANGUAGE.md).
- **Adding an editor frontend** — implement an adapter in
  [`adapters/editor-adapter/`](../adapters/editor-adapter/) against the
  `ViewPatch`/`UserIntent` protocol. CM6, ProseMirror, and HTML adapters
  already exist.
- **Adding a representation** — the `Printable` family
  ([`docs/architecture/multi-representation-system.md`](architecture/multi-representation-system.md))
  describes how new text formats (`Show`, `Source`, `Pretty`) are added per
  language.

## Known limitations

- **WebAssembly is not a supported build target.** Build and CI only cover
  JavaScript and native. See `docs/TODO.md` §1.
- **The JS FFI surface is unstable.** `ffi/{lambda,json,markdown}` together
  export roughly a hundred functions; the wire-format contract lives in
  [`protocol/`](../protocol/) and
  [`adapters/editor-adapter/`](../adapters/editor-adapter/), not in the raw FFI
  layer. Where possible, frontends should consume the editor through the
  adapter.
- **WebSocket recovery is incomplete.** Malformed or incompatible CRDT ops can
  diverge peers silently; recovery is tracked in
  `docs/plans/2026-03-29-sync-recovery-followup.md`.

## Non-goals

Inferred from the absence of supporting code and from `docs/TODO.md`:

- The framework is not a general-purpose IDE — there is no language-server
  protocol, debugger, or workspace concept.
- The CRDT engine is not optimised for documents with hundreds of thousands of
  operations without lazy loading (see TODO §5).
- The projection layer does not implement collaborative cursor *prediction* —
  ephemeral cursors are broadcast as-is.

## Where to read next

- [`docs/architecture/ARCHITECTURE_DIAGRAM.md`](architecture/ARCHITECTURE_DIAGRAM.md)
  — pipeline diagram.
- [`docs/architecture/Incremental-Hylomorphism.md`](architecture/Incremental-Hylomorphism.md)
  — the compositional engine underneath.
- [`docs/architecture/multi-representation-system.md`](architecture/multi-representation-system.md)
  — the `Printable` trait family.
- [`docs/development/ADDING_A_LANGUAGE.md`](development/ADDING_A_LANGUAGE.md)
  — step-by-step to integrate a new language.
- [`docs/development/monorepo.md`](development/monorepo.md) — submodule daily
  workflow.
