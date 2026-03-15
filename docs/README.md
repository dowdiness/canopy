# Documentation Index

Documentation for the Lambda Calculus CRDT Editor project.

## Quick Start

- **[CLAUDE.md](../CLAUDE.md)** - Quick reference for Claude Code
- **[README.md](../README.md)** - Project overview

## Grand Design

The long-range vision for combining eg-walker CRDT + loom incremental parser
into a collaborative projectional editor. Some parts of this stack are already
implemented in the root MoonBit packages and the `examples/rabbita` app; these
design docs describe the remaining target architecture and intended cleanup.

- **[Grand Design](design/GRAND_DESIGN.md)** — Vision, principles, and implementation order
  - [01 — Edit Bridge](design/01-edit-bridge.md) — CRDT ops → loom `Edit` without string diffing
  - [02 — Reactive Pipeline](design/02-reactive-pipeline.md) — Replace manual dirty-flags with `Signal`/`Memo`
  - [03 — Unified Editor](design/03-unified-editor.md) — Single `SyncEditor` facade
  - [04 — Ephemeral Store](design/04-ephemeral-store.md) — Peer cursors and presence
  - [05 — Tree Edit Roundtrip](design/05-tree-edit-roundtrip.md) — Structural AST edits via text CRDT
  - [Design Concerns](design/design-concerns.md) — Future considerations and open problems

## Architecture

Understand the system design and CRDT implementation.

- [Module Structure](architecture/modules.md) - Monorepo organization with git submodules
- [Projectional Editing](architecture/PROJECTIONAL_EDITING.md) - Projectional editing architecture

## Development

Guides for contributing and developing.

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

- [Memo-Derived ProjNode Design](plans/2026-03-10-memo-derived-projnode-design.md)
- [Tree Editor Subtree Reuse Design](plans/2026-03-11-tree-editor-subtree-reuse-design.md)
- [Rabbita Projection Editor Performance Plan](plans/2026-03-11-rabbita-projection-editor-performance-plan.md)
- [Rabbita Perf Harness Redesign](plans/2026-03-11-rabbita-perf-harness-redesign.md)
- [Boundary Correction And Cross-Module Deduplication](plans/2026-03-15-boundary-correction-and-dedup-plan.md)

## Archive

Historical documentation and investigations:

- [Investigation Index](archive/INVESTIGATION_INDEX.md)
- [Branch Variance Investigations](archive/investigations/branch-variance/)
- [Sync Editor Design](archive/completed-phases/2026-03-05-sync-editor-design.md) (Complete)
- [ToDot/FromDot Traits Design](archive/completed-phases/2026-03-07-todot-fromdot-traits-design.md) (Complete)
- [Name Resolution Design](archive/completed-phases/2026-03-07-name-resolution-design.md) (Complete)
- [Name Resolution Implementation](archive/completed-phases/2026-03-07-name-resolution-implementation.md) (Complete)
- [Simplify Web Integration](archive/completed-phases/2026-03-08-simplify-web-integration.md) (Complete)

## External Resources

- [eg-walker paper](https://arxiv.org/abs/2409.14252)
- [MoonBit documentation](https://docs.moonbitlang.com)
- [FugueMax CRDT](https://arxiv.org/abs/2305.00583)
