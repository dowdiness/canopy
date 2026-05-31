# Responsibility Map and Extension Priorities

This note records the practical architecture conclusions from the 2026-05-31
cross-repository audit of Canopy, `dowdiness/incr`, `dowdiness/moondsp`, and
Canopy's parser/CRDT submodules.

It is the **ownership decision guide**: which layer should own new work, which
existing APIs should be reused first, and which follow-up issues should be
handled before larger feature work. For the full package inventory, pipeline
overview, extension points, and non-goals, see [Architecture](../architecture.md).
For a reuse index of public APIs, see [API Map](../api-map.md). For the detailed
module list, see [Module Structure](modules.md).

## Current Stance

### Implemented (code-backed)

- Canopy is currently text-first: text CRDT state is the durable document, while
  CST, projection, semantic data, and rendered views are derived.
- `NodeId`, `ProjNode`, and `SourceMap` are the main extension anchors for
  projection, semantic annotations, structural edits, and UI overlays.
- `protocol.ViewNode` and `ViewPatch` are the UI boundary. New renderers should
  consume protocol output instead of inventing a parallel view tree.
- `event-graph-walker` owns CRDT semantics. Canopy should compose its text,
  tree, container, undo, and history APIs rather than reimplementing them.
- `loom` and `seam` own lossless CST, parser recovery, syntax nodes, and parser
  reuse. Canopy owns app-level projection identity and language behavior.
- `dowdiness/incr` backs incremental projection today: memo-based `FlatProj`
  updates in `editor` and `lang/lambda/flat`. Reuse its `Input`, `Derived`,
  `DerivedMap`, `ReachableDerived`, and `Watch` primitives for incremental work.
- MoonDsp should remain owner of DSP runtime safety, `CompiledTemplate`, voice
  scheduling, and audio-thread constraints. Any Canopy integration must be an
  authoring/editor shell boundary, not a runtime rewrite.

### Planned / Aspirational

These directions are supported by design notes but are not yet implemented:

- Expanding `@incr` from today's incremental projection to a general
  semantic-annotation pipeline (see #416) and future cognition pipelines —
  informed by [extensible ASTs](extensible-asts.md), [multi-representation system](multi-representation-system.md),
  [anamorphism discipline](anamorphism-discipline.md).
- AST-as-source-of-truth promotion once the semantic pipeline is stable (see
  [product vision](product-vision.md), [projectional bridge](vision-projectional-bridge.md)).

### Source of Truth on Drift

When docs and code diverge, **the code and generated `.mbti` interface files
are authoritative**. `../api-map.md` is a reuse index, not authority over
implementation.

## Owner Selection / Reuse First

Before opening code, answer "where should this feature live?" in order:

1. Consult this responsibility map (boundaries table below).
2. Check `../api-map.md` for existing public APIs to reuse.
3. Inspect implementation files or `moon ide` output for concrete types.

## Responsibility Boundaries

| Owner | Owns | Reuse first | Does not own |
|---|---|---|---|
| `core` | `NodeId`, `ProjNode`, `SourceMap`, generic tree edit vocabulary | Projection constructors, source-map registration helpers | Language semantics, wire protocol, CRDT state |
| `editor` | `SyncEditor`, parser/projection wiring, undo, ephemeral/editor state | `event-graph-walker/text`, `@loom.Parser`, `@incr` | CRDT algorithms, language-specific edit calculation |
| `protocol` | `ViewNode`, `ViewPatch`, `UserIntent`, diagnostics/decorations | `layout_to_view_tree`, token spans, diagnostics | Parser internals or language ASTs |
| `projection` | Interactive tree UI state, selection, drag/collapse state | `ProjNode`, `GenericTreeOp` | Parser or CRDT mutation |
| `lang/*/proj` | CST/AST to projection and token spans | `core`, `SourceMap`, Loom syntax helpers | Editor transport, CRDT sync |
| `lang/*/edits` | Language-specific structural edit to text span edits | `SourceMap`, language AST/CST APIs, text-change helpers | Global editor state |
| `lang/*/companion` | Language factory and edit application glue | `SyncEditor`, language `proj` and `edits` packages | New generic editor behavior |
| adapters | Rendering and input adapters around `ViewPatch` / `UserIntent` | Protocol types and stable JSON contracts | Parsing, CRDT, semantic analysis |
| `event-graph-walker` | Text/tree/container CRDT, undo, causal history | Published text/tree/container APIs | Projection, UI, language semantics |
| `loom` / `seam` | Incremental parser, lossless CST, diagnostics, syntax nodes | `Parser`, `SyntaxNode`, `CstFold`, direct shape helpers | Canopy UI identity semantics |
| `dowdiness/incr` | Incremental runtime and lifecycle primitives | `Input`, `Derived`, `DerivedMap`, `ReachableDerived`, `Watch` | Canopy-specific semantic data shapes |
| `dowdiness/moondsp` | Pattern engine, DSP graph, `CompiledTemplate`, scheduler, voice pool | Authoring docs and stable domain IDs | Canopy view protocol or editor shell |

## Supporting Libraries and Submodule Boundaries

The git submodules (repository boundaries, per `.gitmodules`) are:
`event-graph-walker`, `loom`, `svg-dsl`, `graphviz`, `rle`, `order-tree`,
`alga`, and `rabbita`. `event-graph-walker` and `loom`/`seam` are covered in the
Responsibility Boundaries table above. **`loom` is itself a submodule** that
contains `seam`, `incr`, `text-change`, `moji`, `pretty`, and `lambda` as
packages — update those through the `loom` submodule, not separate repositories.

The libraries below are all implemented and wired into Canopy. The "Repository"
column is the actual update boundary; "Integration" is where Canopy consumes it.

**Group A — Direct dependencies** (in canopy root `moon.mod.json`):

| Library | Responsibility | Repository | Integration |
|---|---|---|---|
| `text-change` (`dowdiness/text_change`) | Pure contiguous text-change utilities | package in `loom` submodule | `editor`, `lang/*` |
| `moji` (`dowdiness/moji`) | UAX #29 grapheme-cluster and word-boundary segmentation, UTF-16 indexed | package in `loom` submodule | `editor`, `lang/*` |
| `pretty` (`dowdiness/pretty`) | Wadler-Lindig pretty-printer, generic `Layout[A]` + annotation support | package in `loom` submodule | `lang/*`, formatting passes |
| `order-tree` (`dowdiness/order-tree`) | Order-statistic B-tree, O(log n) position-indexed operations | standalone submodule | root dep; backs `event-graph-walker` |

**Group B — CRDT internals** (pulled in via `event-graph-walker`):

| Library | Responsibility | Repository | Integration |
|---|---|---|---|
| `rle` (`dowdiness/rle`) | Generic run-length-encoded sequence, O(log n) position lookup | standalone submodule | backs `event-graph-walker`, `order-tree`, btree |
| `alga` (`dowdiness/alga`) | Algebraic graphs — directed graph trait + algorithms | standalone submodule | `event-graph-walker`, `graphviz`, visualizer |

**Group C — Visualization / UI tooling** (not on the core editor runtime path):

| Library | Responsibility | Repository | Integration |
|---|---|---|---|
| `graphviz` (`dowdiness/graphviz`) | DOT parser + layout engine + SVG renderer | standalone submodule | loom viz, `lib/visualizer`, `examples/ideal`; depends on `svg-dsl` |
| `svg-dsl` (`dowdiness/svg-dsl`) | Programmatic SVG generation DSL | standalone submodule | base layer under `graphviz` |
| `rabbita` (`moonbit-community/rabbita`) | Functional Web UI framework (TEA) for MoonBit; submodule also holds `warren` | standalone submodule (vendored community lib) | `lib/rabbita_codemirror` adapter + `examples/*` |

## Priority Issues

The audit led to these Canopy issues:

1. [#413](https://github.com/dowdiness/canopy/issues/413) - codify this
   responsibility map and extension points.
2. [#414](https://github.com/dowdiness/canopy/issues/414) - centralize
   projection construction and `SourceMap` helper APIs.
3. [#416](https://github.com/dowdiness/canopy/issues/416) - define semantic
   annotation flow over `NodeId` side tables and `@incr`. *(planned)*
4. [#418](https://github.com/dowdiness/canopy/issues/418) - plan migration
   from `incr` 0.5.x to the 0.6 target facade. *(planned)*
5. [#417](https://github.com/dowdiness/canopy/issues/417) - specify
   WebSocket recovery and text/tree CRDT boundaries.
6. [#415](https://github.com/dowdiness/canopy/issues/415) - inventory and
   possibly introduce shared range/span primitives.
7. [#419](https://github.com/dowdiness/canopy/issues/419) - evaluate Canopy as
   a structural editor shell for MoonDsp.

Recommended order:

1. Do #413 and #414 before adding another substantial language or editor mode.
2. Decide #418 before implementing the general semantic pipeline in #416.
3. Treat #415 as an inventory and unit-contract task first; avoid a broad type
   migration until the shared boundary is proven.
4. Handle #417 before concurrent structural editing becomes product-critical.
5. Keep #419 as a spike until Canopy's projection and semantic contracts are
   stable enough to host MoonDsp authoring without leaking DSP runtime details.

## Design Rules for New Work

When adding a language:

- Start from the guide in [Adding a Language](../development/ADDING_A_LANGUAGE.md).
- Prefer Markdown as the reference implementation.
- Keep grammar/CST/AST in the parser layer, projection in `lang/<name>/proj`,
  text edit calculation in `lang/<name>/edits`, and editor wiring in
  `lang/<name>/companion`.

When adding semantic overlays:

- Store semantic facts in side tables keyed by `NodeId` or source spans.
- Do not add a new field to `ProjNode` for every annotation category.
- Schedule nontrivial derived facts through `@incr`; avoid bespoke dirty flags
  or side-channel caches. *(semantic pipeline via `@incr` is planned — see #416)*
- Treat parse errors and incomplete CSTs as normal input states.

When adding collaboration features:

- Use `event-graph-walker/text` for text collaboration and
  `event-graph-walker/tree` or `container` when structure itself needs CRDT
  semantics.
- Keep `relay` as a transport layer. It should not interpret CRDT operations.
- Define reconnect and recovery behavior before adding UI affordances around
  collaboration state.

When exploring MoonDsp integration:

- Keep MoonDsp domain IDs (`GraphNodeId`, `PatternNodeId`, section IDs) owned
  by MoonDsp.
- Treat Canopy `NodeId` as projection/view identity unless a stronger domain
  contract is explicitly designed.
- Preserve the MoonDsp runtime boundary: authoring changes should cross through
  `CompiledTemplate`, scheduler snapshots, or documented control APIs.
  *(Canopy-as-MoonDsp-shell is a planned spike — see #419)*

## Anti-Patterns

- Creating a second view representation beside `protocol.ViewNode`.
- Passing raw `Int` positions across package boundaries without stating the
  unit and ownership contract.
- Reimplementing CRDT behavior in Canopy instead of using `event-graph-walker`.
- Adding language-specific state to generic editor/core packages.
- Building MoonDsp audio-runtime assumptions into Canopy editor packages.
- Optimizing incremental behavior before profiling or before the dependency
  graph shape is stable. *(incr 0.6 migration tracked in #418 — planned)*
