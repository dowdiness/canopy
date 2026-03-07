# Documentation Index

Documentation for the Lambda Calculus CRDT Editor project.

## Quick Start

- **[CLAUDE.md](../CLAUDE.md)** - Quick reference for Claude Code
- **[README.md](../README.md)** - Project overview

## Grand Design

The future vision for combining eg-walker CRDT + loom incremental parser into a collaborative projectional editor.
These documents are draft designs and explicitly call out required API additions where current public APIs are insufficient.

- **[Grand Design](design/GRAND_DESIGN.md)** — Vision, principles, and implementation order
  - [01 — Edit Bridge](design/01-edit-bridge.md) — CRDT ops → loom `Edit` without string diffing
  - [02 — Reactive Pipeline](design/02-reactive-pipeline.md) — Replace manual dirty-flags with `Signal`/`Memo`
  - [03 — Unified Editor](design/03-unified-editor.md) — Single `SyncEditor` facade
  - [04 — Awareness Protocol](design/04-awareness-protocol.md) — Peer cursors and presence
  - [05 — Tree Edit Roundtrip](design/05-tree-edit-roundtrip.md) — Structural AST edits via text CRDT
  - [Design Concerns](design/design-concerns.md) — Future considerations and open problems

## Architecture

Understand the system design and CRDT implementation.

- [Module Structure](architecture/modules.md) - Monorepo organization with git submodules
- [Projectional Editing](architecture/PROJECTIONAL_EDITING.md) - Projectional editing architecture

## Development

Guides for contributing and developing.

- [Monorepo & Submodules](development/monorepo.md) - Git submodule setup and workflows
- [Workflow](development/workflow.md) - Development process and common commands
- [Conventions](development/conventions.md) - MoonBit coding standards
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

- [Name Resolution Design](plans/2026-03-07-name-resolution-design.md)

## Archive

Historical documentation and investigations:

- [Investigation Index](archive/INVESTIGATION_INDEX.md)
- [Branch Variance Investigations](archive/investigations/branch-variance/)
- [Sync Editor Design](archive/completed-phases/2026-03-05-sync-editor-design.md) (Complete)
- [ToDot/FromDot Traits Design](archive/completed-phases/2026-03-07-todot-fromdot-traits-design.md) (Complete)

## External Resources

- [eg-walker paper](https://arxiv.org/abs/2409.14252)
- [MoonBit documentation](https://docs.moonbitlang.com)
- [FugueMax CRDT](https://arxiv.org/abs/2305.00583)
