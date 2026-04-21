# Documentation Index

Documentation for **Canopy** — an incremental projectional editor with CRDT
collaboration, built in MoonBit.

If this is your first time here, read the pages in order: **Start Here →
Learning Path → API / Reference**. Contributor, deep-design, and historical
material is grouped at the bottom and is not required reading.

---

## Start Here

- **[Project README](../README.md)** — what Canopy is, what it looks like, and
  the Quick Start (clone, `moon test`, run the web demo).
- **[Live demo](https://canopy-ideal.pages.dev)** — try the editor in your
  browser before diving into internals.
- **[日本語版紹介 (Japanese introduction)](japanese-introduction.md)** —
  product overview in Japanese.

## Learning Path

Read in order to build a mental model of the system.

1. **[Product Vision](architecture/product-vision.md)** — what Canopy is trying
   to be: write, auto-structure, surface.
2. **[The Projectional Bridge](architecture/vision-projectional-bridge.md)** —
   why: syntax → semantics → intent → mental model.
3. **[System Architecture Diagram](architecture/ARCHITECTURE_DIAGRAM.md)** —
   high-level data flow: Text CRDT → Incremental Parse → Projection → Rendering.
4. **[Module Structure](architecture/modules.md)** — how the monorepo and
   submodules map onto that pipeline.
5. **[Projectional Editing](architecture/PROJECTIONAL_EDITING.md)** — what
   projectional editing means in Canopy specifically.
6. **[Incremental Hylomorphism](architecture/Incremental-Hylomorphism.md)** —
   the compositional engine underneath.
7. **[Multi-Representation System](architecture/multi-representation-system.md)**
   — the `Printable` trait family (Show, Debug, Source, Pretty).

Further architecture notes live in [docs/architecture/](architecture/).

## API / Reference

For users calling Canopy from MoonBit or JavaScript.

- **[API Reference](development/API_REFERENCE.md)** — high-level MoonBit API
  overview (`SyncEditor`, `ProjNode`, etc.).
- **[JS Integration Guide](development/JS_INTEGRATION.md)** — using the editor
  from JavaScript / the web.
- **[Tree Editing Manual](development/TREE_EDIT_MANUAL.md)** — structural
  projectional editing reference.
- **[Adding a Language](development/ADDING_A_LANGUAGE.md)** — integrate a new
  language into the framework (uses Markdown as the reference implementation).

Per-module READMEs:

- [event-graph-walker](../event-graph-walker/README.md) — CRDT engine.
- [loom](../loom/README.md) — incremental parser framework.

---

## Contributor / Development

Only needed if you are modifying Canopy itself.

- **[Workflow](development/workflow.md)** — development process and common commands.
- **[Conventions](development/conventions.md)** — MoonBit coding standards.
- **[Testing](development/testing.md)** — testing guide and best practices.
- **[Monorepo & Submodules](development/monorepo.md)** — git submodule setup and
  daily cheat sheet.
- **[Task Tracking](development/task-tracking.md)** — rules for TODOs, plans,
  and issues.
- **[Technical Debt](development/technical-debt.md)** — where debt should be
  fixed and how to retire old paths.
- **[Formal Verification](development/formal-verification.md)** — Why3 / z3
  proof workflow.
- **[Documentation Doctrine](development/documentation-doctrine.md)** — how docs
  in this repo are written and maintained.

**Backlog and active work:**

- [TODO](TODO.md) — active backlog index.
- [docs/plans/](plans/) — executable plans (use
  [plans/TEMPLATE.md](plans/TEMPLATE.md) when adding a new one).

**Performance:**

- [Benchmark Redesign](performance/BENCHMARK_REDESIGN.md)
- [Performance Analysis](performance/PERFORMANCE_ANALYSIS.md)
- [Performance Results](performance/PERFORMANCE_RESULTS.md)

**Infrastructure:**

- [CI/CD](CI_CD.md)

## Deep Design (Grand Design)

Long-range design explorations. Treat as **direction, not implemented
behavior** — check the code before relying on any specific detail.

- **[Grand Design](design/GRAND_DESIGN.md)** — vision, principles, and
  implementation order.
  - [01 — Edit Bridge](design/01-edit-bridge.md)
  - [02 — Reactive Pipeline](design/02-reactive-pipeline.md)
  - [03 — Unified Editor](design/03-unified-editor.md)
  - [04 — Ephemeral Store](design/04-ephemeral-store.md)
  - [05 — Tree Edit Roundtrip](design/05-tree-edit-roundtrip.md)
- [Design Concerns](design/design-concerns.md) — open problems and future
  considerations.
- [Decisions Needed](decisions-needed.md) — open architectural questions.

**Architectural Decision Records (ADRs):**

- [Framework Genericity Contract](decisions/2026-03-29-framework-genericity-contract.md)
  — why `framework/` and `core/` must stay language-agnostic.

## Historical / Archive

> Do not treat files in this section as current guidance. They record decisions
> and plans that have since shipped, been superseded, or been abandoned. Read
> only when you need historical context.

- [docs/archive/](archive/) — completed plans and superseded designs.
- [Investigation Index](archive/INVESTIGATION_INDEX.md) — earlier investigations.
- [Branch Variance Investigations](archive/investigations/branch-variance/) —
  historical perf investigations.

Recently completed (for quick reference):

- [Lambda Annotation Plumbing — Design](archive/completed-phases/2026-04-18-lambda-annotation-plumbing-design.md)
- [Lambda Annotation Plumbing — Impl](archive/completed-phases/2026-04-18-lambda-annotation-plumbing-impl.md)
- [Framework Extraction — Design](archive/2026-03-18-framework-extraction-design.md)
  · [Impl](archive/2026-03-28-framework-extraction-impl.md)
  · [Phase 4](archive/2026-03-28-framework-extraction-phase4.md)
- [JSON Editor — Design](archive/2026-03-29-json-projectional-editor-design.md)
  · [Impl](archive/2026-03-29-json-projectional-editor-impl.md)
- [Block Editor 1b/1c/1d](archive/2026-03-28-block-editor-1b-document.md)
  · [Markdown](archive/2026-03-28-block-editor-1c-markdown.md)
  · [Web](archive/2026-03-28-block-editor-1d-web.md)
- [AST Zipper — Design](archive/2026-03-28-ast-zipper-design.md)
- [Ideal Editor — Impl](archive/completed-phases/2026-03-19-ideal-editor-impl.md)

## External Resources

- [eg-walker paper](https://arxiv.org/abs/2409.14252) — the CRDT algorithm.
- [FugueMax CRDT](https://arxiv.org/abs/2305.00583) — the sequence CRDT underneath.
- [MoonBit documentation](https://docs.moonbitlang.com).

---

## For AI Agents

`AGENTS.md` at the repo root is the canonical agent guidance file. `CLAUDE.md`
is a compatibility symlink and should not be edited directly.
