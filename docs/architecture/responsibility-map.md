# Responsibility Map and Extension Priorities

This note records the practical architecture conclusions from the 2026-05-31
cross-repository audit of Canopy, `dowdiness/incr`, `dowdiness/moondsp`, and
Canopy's parser/CRDT submodules.

It is not a full package inventory. For the detailed module list, see
[Module Structure](modules.md). This document answers a narrower question:
which layer should own new work, which existing APIs should be reused first,
and which follow-up issues should be handled before larger feature work.

## Current Stance

- Canopy is currently text-first: text CRDT state is the durable document, while
  CST, projection, semantic data, and rendered views are derived.
- `NodeId`, `ProjNode`, and `SourceMap` are the main extension anchors for
  projection, semantic annotations, structural edits, and UI overlays.
- `protocol.ViewNode` and `ViewPatch` are the UI boundary. New renderers should
  consume protocol output instead of inventing a parallel view tree.
- `dowdiness/incr` is the intended computation model for semantic passes,
  projection caches, long-lived editor subscriptions, and future cognition
  pipelines.
- `event-graph-walker` owns CRDT semantics. Canopy should compose its text,
  tree, container, undo, and history APIs rather than reimplementing them.
- `loom` and `seam` own lossless CST, parser recovery, syntax nodes, and parser
  reuse. Canopy owns app-level projection identity and language behavior.
- MoonDsp should remain owner of DSP runtime safety, `CompiledTemplate`, voice
  scheduling, and audio-thread constraints. Any Canopy integration must be an
  authoring/editor shell boundary, not a runtime rewrite.

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

## Priority Issues

The audit led to these Canopy issues:

1. [#413](https://github.com/dowdiness/canopy/issues/413) - codify this
   responsibility map and extension points.
2. [#414](https://github.com/dowdiness/canopy/issues/414) - centralize
   projection construction and `SourceMap` helper APIs.
3. [#416](https://github.com/dowdiness/canopy/issues/416) - define semantic
   annotation flow over `NodeId` side tables and `@incr`.
4. [#418](https://github.com/dowdiness/canopy/issues/418) - plan migration
   from `incr` 0.5.x to the 0.6 target facade.
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
  or side-channel caches.
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

## Anti-Patterns

- Creating a second view representation beside `protocol.ViewNode`.
- Passing raw `Int` positions across package boundaries without stating the
  unit and ownership contract.
- Reimplementing CRDT behavior in Canopy instead of using `event-graph-walker`.
- Adding language-specific state to generic editor/core packages.
- Building MoonDsp audio-runtime assumptions into Canopy editor packages.
- Optimizing incremental behavior before profiling or before the dependency
  graph shape is stable.
