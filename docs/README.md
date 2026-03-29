# Documentation Index

Documentation for Canopy — an incremental projectional editor with CRDT collaboration.

## Quick Start

- **[CLAUDE.md](../CLAUDE.md)** - Quick reference for Claude Code
- **[README.md](../README.md)** - Project overview

## Grand Design

The long-range vision for combining eg-walker CRDT + loom incremental parser
into a collaborative projectional editor.

- **[Grand Design](design/GRAND_DESIGN.md)** — Vision, principles, and implementation order
  - [01 — Edit Bridge](design/01-edit-bridge.md) — CRDT ops → loom `Edit` without string diffing
  - [02 — Reactive Pipeline](design/02-reactive-pipeline.md) — Replace manual dirty-flags with `Signal`/`Memo`
  - [03 — Unified Editor](design/03-unified-editor.md) — Single `SyncEditor` facade
  - [04 — Ephemeral Store](design/04-ephemeral-store.md) — Peer cursors and presence
  - [05 — Tree Edit Roundtrip](design/05-tree-edit-roundtrip.md) — Structural AST edits via text CRDT
  - [Design Concerns](design/design-concerns.md) — Future considerations and open problems

## Architecture

Understand the system design and CRDT implementation.

- [System Architecture](architecture/ARCHITECTURE_DIAGRAM.md) - High-level data flow diagram
- [Module Structure](architecture/modules.md) - Monorepo organization with git submodules
- [Projectional Editing](architecture/PROJECTIONAL_EDITING.md) - Projectional editing architecture

## Decisions

Architectural Decision Records (ADRs) for significant design choices.

- [Framework Genericity Contract](decisions/2026-03-29-framework-genericity-contract.md) — TestExpr proof: why framework/core/ must stay language-agnostic

## Development

Guides for contributing and developing.

- [API Reference](development/API_REFERENCE.md) - High-level MoonBit API overview
- [JS Integration Guide](development/JS_INTEGRATION.md) - How to use the editor from JavaScript/Web
- [Tree Editing Manual](development/TREE_EDIT_MANUAL.md) - Structural projectional editing reference
- [Monorepo & Submodules](development/monorepo.md) - Git submodule setup, daily cheat sheet, and workflows
- [Workflow](development/workflow.md) - Development process and common commands
- [Conventions](development/conventions.md) - MoonBit coding standards
- [Paying Technical Debt](development/technical-debt.md) - Where debt should be fixed and how to retire old paths
- [Testing](development/testing.md) - Testing guide and best practices

## Performance

Benchmarking and optimization documentation.

- [Benchmark Redesign](performance/BENCHMARK_REDESIGN.md) - Benchmark methodology
- [Performance Analysis](performance/PERFORMANCE_ANALYSIS.md) - Performance analysis
- [Performance Results](performance/PERFORMANCE_RESULTS.md) - Benchmark results

## Module Documentation

Detailed documentation for each module:

- **[event-graph-walker](../event-graph-walker/README.md)** - Core CRDT library
- **[loom](../loom/README.md)** - Incremental parser framework

## Active Plans

- [Block Editor Design](plans/2026-03-28-block-editor-design.md) — Block-based document editor vision
- [Block Editor 1b](plans/2026-03-28-block-editor-1b-document.md) — BlockDoc CRUD
- [Block Editor 1c](plans/2026-03-28-block-editor-1c-markdown.md) — Markdown import/export
- [Block Editor 1d](plans/2026-03-28-block-editor-1d-web.md) — JS bridge + web shell
- [AST Zipper Design](plans/2026-03-28-ast-zipper-design.md) — Structural cursor + typed holes
- [BFT Adapter](plans/2026-03-19-bft-adapter-design.md) — Byzantine Fault Tolerance (deferred)
- [Ideal Editor](plans/2026-03-19-ideal-editor-impl.md) — Rabbita host + Web Component unified editor
- [Rabbita Web Component Interop](plans/2026-03-20-rabbita-web-component-interop-design.md) — Export Rabbita cells as custom elements

## Archive

Historical documentation, completed plans, and investigations.

### Completed Plans (2026-03)

- [Framework Extraction Design](archive/2026-03-18-framework-extraction-design.md) — Generic `ProjNode[T]` + `TreeNode`/`Renderable` traits
- [Framework Extraction Impl](archive/2026-03-28-framework-extraction-impl.md) — Phases 1–4 implementation
- [Framework Extraction Phase 4](archive/2026-03-28-framework-extraction-phase4.md) — Traits to loom, lambda code to lang/lambda/
- [Memo-Derived ProjNode Design](archive/2026-03-10-memo-derived-projnode-design.md) — CanonicalModel retired, memo-derived projections on SyncEditor
- [Rabbita Projection Editor Performance Plan](archive/2026-03-11-rabbita-projection-editor-performance-plan.md) — Edit-based APIs, incremental parser, UI/structural split
- [Tree Editor Subtree Reuse Design](archive/2026-03-11-tree-editor-subtree-reuse-design.md) — InteractiveChildren Loaded/Elided, structural indexes
- [Rabbita Perf Harness Redesign](archive/2026-03-11-rabbita-perf-harness-redesign.md) — BenchmarkMeasurement, phase timing, timeout-aware results
- [Projection Incremental Updates (FlatProj)](archive/2026-03-15-projection-incremental-updates.md) — FlatProj replaces nested Let spine
- [RLE Library Integration](archive/2026-03-15-rle-library-integration.md) — 4-phase RLE compression plan (all phases complete)
- [Text-Delta Tree Edit](archive/2026-03-18-projectional-edit-text-delta-plan.md) — SpanEdit via source map
- [Two-Layer Architecture](archive/completed-phases/2026-03-28-two-layer-architecture-design.md) — TermSym Finally Tagless (Complete)
- [MovableTree CRDT](archive/completed-phases/2026-03-28-movable-tree-crdt-impl.md) — Kleppmann's move algorithm (Complete)

### Earlier Archive

- [Investigation Index](archive/INVESTIGATION_INDEX.md)
- [Branch Variance Investigations](archive/investigations/branch-variance/)

## External Resources

- [eg-walker paper](https://arxiv.org/abs/2409.14252)
- [MoonBit documentation](https://docs.moonbitlang.com)
- [FugueMax CRDT](https://arxiv.org/abs/2305.00583)
