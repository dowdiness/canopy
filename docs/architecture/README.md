# Architecture

Principles, structure, and design background for Canopy. Start with the
[Architecture Overview](../architecture.md) for orientation, or use the
[Documentation Index](../README.md) to choose guidance for a change.
Accepted decisions have a separate [ADR index](../decisions/README.md).

## Pipeline and structure

- **[System Architecture Diagram](ARCHITECTURE_DIAGRAM.md)** — high-level data
  flow: Text CRDT → Incremental Parse → Projection → Rendering.
- **[Module Structure](modules.md)** — how the monorepo and git submodules map
  onto that pipeline.
- **[Responsibility Map and Extension Priorities](responsibility-map.md)** —
  ownership boundaries, reuse-first APIs, and the follow-up issue sequence for
  new language, semantic, collaboration, and MoonDsp work.
- **[Edit Action Progression](edit-action-progression.md)** — how edits flow
  from user input down through the pipeline.

## Theory and principles

- **[Functional Core / Imperative Shell](functional-core-imperative-shell.md)** —
  deterministic domain decisions and effect ownership.
- **[Incremental Hylomorphism](Incremental-Hylomorphism.md)** — cata/ana
  asymmetry, structural independence, memoized algebras, hylomorphism chains.
- **[Anamorphism Discipline](anamorphism-discipline.md)** — actionable design
  guide: four properties, boundary audit, anti-patterns.
- **[Extensible ASTs](extensible-asts.md)** — how AST extensibility is handled.
- **[Zipper Roundtrip Invariants](zipper-roundtrip-invariants.md)** — invariants
  that structural cursors must preserve.
- **[Grove and Structural Identity](grove-and-structural-identity.md)** — the
  collaborative structure-editing calculus applied here.
- **[Multi-Representation System](multi-representation-system.md)** — how the
  `Printable` trait family (Show, Debug, Source, Pretty) solves the expression
  problem for output formats.
- **[Incremental Evaluation](incremental-evaluation.md)** — framework for
  evaluating the query-based incremental architecture; 15 criteria and when to
  re-evaluate.
- **[Cognition Runtime](cognition-runtime.md)** — minimal incremental graph for
  AI coding context artifacts: dependencies, revisions, dirty propagation, and
  selective recomputation.

## Vision

- **[Product Vision](product-vision.md)** — the full product: write, negotiate
  structure, and surface context.
- **[Personal Knowledge Environment Direction](personal-knowledge-environment-direction.md)** —
  near-term primary product direction: human-centered personal knowledge
  environment where past agent activity participates in present thinking
  through Trace, Shape, and Meaning scales.
- **[Human-centered product principles](human-centered-product-principles.md)**
  — canonical behavior invariants for authority, negotiable structure,
  orientation, accessible equivalence, and product gates.
- **[Coding Agent Direction](coding-agent-direction.md)** — deferred boundary
  for external agent engines, revision-bound proposals, and host-owned effects.
- **[The Projectional Bridge](vision-projectional-bridge.md)** — bridging
  syntax → semantics → intent → mental model.
- **[Structure-Format Research](structure-format-research.md)** — PL research
  survey (Trees That Grow, Cofree, Finally Tagless, MLIR, Attributed Grammars,
  Ornaments) and how it informs the semantic-model approach.

## Design Explorations

Long-range design explorations. Treat as **direction, not implemented
behavior** — check the code before relying on any specific detail.

- **[Grand Design](../design/GRAND_DESIGN.md)** — vision, principles, and
  implementation order.
  - [01 — Edit Bridge](../design/01-edit-bridge.md)
  - [02 — Reactive Pipeline](../design/02-reactive-pipeline.md)
  - [03 — Unified Editor](../design/03-unified-editor.md)
  - [04 — Ephemeral Store](../design/04-ephemeral-store.md)
  - [05 — Tree Edit Roundtrip](../design/05-tree-edit-roundtrip.md)
- [Analysis Query Layer](../design/analysis-query-layer.md) — conservative design
  for ast-grep-style syntax search, `moon ide`-style semantic queries, and
  previewable refactors through snapshot-bound internal facts.
- [Local-first Document Ownership](../design/local-first-document-ownership.md) —
  direction for owning a document on the user's device: persisting operation
  history rather than text, the archive envelope boundary, durability states,
  and the requirements an editing path must meet before archives exist.
- [Stable Document Entity Graph](../design/stable-document-entity-graph.md) —
  direction for growing a stable editing-entity layer from the existing
  projection identity pipeline.
- [Incremental Generative UI document engine](../design/incremental-generative-ui-document-engine.md) —
  semantic authority, operation, identity, and recovery direction for generated
  documents.
- [Typed spreadsheet room and join UX](../superpowers/specs/2026-07-22-typed-spreadsheet-room-join-ux.md)
  — share-link, temporary-room, offline, reconnect, and local-draft behavior for
  the collaboration product pilot.
- [Design Concerns](../design/design-concerns.md) — open problems and future
  considerations.
- [Decisions Needed](../decisions-needed.md) — open architectural questions.

## References

- [eg-walker paper](https://arxiv.org/abs/2409.14252) — the CRDT algorithm.
- [event-graph-walker README](../../deps/event-graph-walker/README.md) — the CRDT
  implementation.
- [loom README](../../deps/loom/README.md) — the incremental parser framework.

- [FugueMax paper](https://arxiv.org/abs/2305.00583) — the sequence CRDT.
