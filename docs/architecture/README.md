# Architecture

Architecture notes for Canopy. For the overall reading order across all docs,
see the main **[Documentation Index](../README.md)** — this page only indexes
the files inside `docs/architecture/`.

## Pipeline and structure

- **[System Architecture Diagram](ARCHITECTURE_DIAGRAM.md)** — high-level data
  flow: Text CRDT → Incremental Parse → Projection → Rendering.
- **[Module Structure](modules.md)** — how the monorepo and git submodules map
  onto that pipeline.
- **[Responsibility Map and Extension Priorities](responsibility-map.md)** —
  ownership boundaries, reuse-first APIs, and the follow-up issue sequence for
  new language, semantic, collaboration, and MoonDsp work.
- **[Projectional Editing](PROJECTIONAL_EDITING.md)** — what projectional
  editing means in Canopy specifically.
- **[Edit Action Progression](edit-action-progression.md)** — how edits flow
  from user input down through the pipeline.

## Theory and principles

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

## References

- [eg-walker paper](https://arxiv.org/abs/2409.14252) — the CRDT algorithm.
- [event-graph-walker README](../../event-graph-walker/README.md) — the CRDT
  implementation.
- [loom README](../../loom/README.md) — the incremental parser framework.
