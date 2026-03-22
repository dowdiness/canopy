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

- [System Architecture](architecture/ARCHITECTURE_DIAGRAM.md) - High-level data flow diagram
- [Module Structure](architecture/modules.md) - Monorepo organization with git submodules
- [Projectional Editing](architecture/PROJECTIONAL_EDITING.md) - Projectional editing architecture

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

- [Framework Extraction Design](plans/2026-03-18-framework-extraction-design.md) — Generic `ProjNode[T]` + `TreeNode`/`Renderable` traits (deferred)
- [BFT Adapter — Byzantine Fault Tolerance](plans/2026-03-19-bft-adapter-design.md) — Design only, implement after sync working (deferred)
- [Ideal Editor Implementation](plans/2026-03-19-ideal-editor-impl.md) — Rabbita host + PM/CM6 Web Component unified editor
- [Rabbita Web Component Interop Design](plans/2026-03-20-rabbita-web-component-interop-design.md) — Export Rabbita cells as custom elements
- [Rabbita Web Component Interop Impl](plans/2026-03-20-rabbita-web-component-interop-impl.md) — Step-by-step implementation
- [Framework Extraction Phase 1](plans/2026-03-21-framework-extraction-phase1.md) — Parameterize ProjNode[T] (deferred)
- [Structural Editing UI Impl](plans/2026-03-21-structural-editing-ui-impl.md)
- [Incremental SourceMap & Registry](plans/2026-03-22-incremental-sourcemap-registry.md) — Active worktree, not merged

## Archive

Historical documentation, completed plans, and investigations.

### Completed Plans (2026-03)

- [Memo-Derived ProjNode Design](archive/2026-03-10-memo-derived-projnode-design.md) — CanonicalModel retired, memo-derived projections on SyncEditor
- [Rabbita Projection Editor Performance Plan](archive/2026-03-11-rabbita-projection-editor-performance-plan.md) — Edit-based APIs, incremental parser, UI/structural split
- [Tree Editor Subtree Reuse Design](archive/2026-03-11-tree-editor-subtree-reuse-design.md) — InteractiveChildren Loaded/Elided, structural indexes
- [Rabbita Perf Harness Redesign](archive/2026-03-11-rabbita-perf-harness-redesign.md) — BenchmarkMeasurement, phase timing, timeout-aware results
- [Projection Incremental Updates (FlatProj)](archive/2026-03-15-projection-incremental-updates.md) — FlatProj replaces nested Let spine
- [RLE Library Integration](archive/2026-03-15-rle-library-integration.md) — 4-phase RLE compression plan (all phases complete)
- [RLE Phase 0: Replace Internal RLE](archive/2026-03-17-rle-phase0-replace-internal-rle.md)
- [RLE Phase 1: OpRun Compression](archive/2026-03-17-rle-phase1-oprun-compression.md)
- [RLE Phase 2: VisibleRun Compression](archive/2026-03-17-rle-phase2-visiblerun-compression.md)
- [RLE Phase 3: LvRange Compression](archive/2026-03-17-rle-phase3-lvrange-compression.md)
- [CRDT Append Performance](archive/2026-03-18-crdt-append-performance.md) — Children index, cursor fast-path, batch invalidation, LCA index
- [CRDT Append Performance Impl](archive/2026-03-18-crdt-append-performance-impl.md)
- [LWW Delete/Undelete](archive/2026-03-18-lww-delete-undelete.md) — Convergent delete with Lamport timestamps
- [Text-Delta Tree Edit](archive/2026-03-18-projectional-edit-text-delta-plan.md) — SpanEdit via source map, old tree edit path removed
- [ProseMirror + CodeMirror 6 Design](archive/2026-03-18-prosemirror-codemirror-integration-design.md) — PM structural shell + CM6 inline leaf editors
- [ProseMirror + CodeMirror 6 Impl](archive/2026-03-18-prosemirror-codemirror-integration-impl.md)
- [Ephemeral Store v2 Design](archive/2026-03-19-ephemeral-store-v2-design.md) — Hub, namespaces, sync protocol
- [Ephemeral Store v2 Impl](archive/2026-03-19-ephemeral-store-v2-impl.md)
- [WebSocket Transport Design](archive/2026-03-19-websocket-transport-design.md) — MoonBit-first relay + client, CF Durable Objects
- [WebSocket Transport Impl](archive/2026-03-19-websocket-transport-impl.md)
- [Lazy Incremental Tree Refresh Design](archive/completed-phases/2026-03-20-lazy-incremental-tree-refresh-design.md) (Complete)
- [Lazy Incremental Tree Refresh Impl](archive/completed-phases/2026-03-20-lazy-incremental-tree-refresh-impl.md) (Complete)
- [Refactoring Plans: File Decomposition](archive/completed-phases/2026-03-22-refactoring-plans.md) (Complete)
- [Incremental Parser Optimization Design](archive/completed-phases/2026-03-21-incremental-parser-optimization-design.md) (Complete)
- [Incremental Parser Optimization Impl](archive/completed-phases/2026-03-21-incremental-parser-optimization-impl.md) (Complete)
- [Structural Editing Actions Design](archive/completed-phases/2026-03-21-structural-editing-actions-design.md) (Complete)
- [Structural Editing Actions Impl](archive/completed-phases/2026-03-21-structural-editing-actions-impl.md) (Complete)

### Earlier Archive

- [Investigation Index](archive/INVESTIGATION_INDEX.md)
- [Branch Variance Investigations](archive/investigations/branch-variance/)
- [Sync Editor Design](archive/completed-phases/2026-03-05-sync-editor-design.md) (Complete)
- [ToDot/FromDot Traits Design](archive/completed-phases/2026-03-07-todot-fromdot-traits-design.md) (Complete)
- [Name Resolution Design](archive/completed-phases/2026-03-07-name-resolution-design.md) (Complete)
- [Name Resolution Implementation](archive/completed-phases/2026-03-07-name-resolution-implementation.md) (Complete)
- [Simplify Web Integration](archive/completed-phases/2026-03-08-simplify-web-integration.md) (Complete)
- [Boundary Correction And Cross-Module Deduplication](archive/completed-phases/2026-03-15-boundary-correction-and-dedup-plan.md) (Complete)

## External Resources

- [eg-walker paper](https://arxiv.org/abs/2409.14252)
- [MoonBit documentation](https://docs.moonbitlang.com)
- [FugueMax CRDT](https://arxiv.org/abs/2305.00583)
