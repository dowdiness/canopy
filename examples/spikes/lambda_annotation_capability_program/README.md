# Lambda annotation capability through a Formula

- **Reader:** Canopy and Incr maintainers reviewing a typed annotation seam.
- **Decision:** Evaluate whether the existing closure annotation callback has exact parity with a shadow `Program`/`Formula` over typed snapshots.
- **Keep until:** This evidence receives review or is superseded.
- **Disposition:** Keep this executable spike as provisional evidence; move a durable decision to an ADR or remove the spike after review.

## Verdict

**Pass with constraints.** For the finite workloads in the disabled
white-box test, the Formula result equals the production closure's full
`ViewNode` annotation map. This does not authorize a production migration.

The production closure remains the oracle. The test calls `editor.get_view_tree`
and recursively collects each non-empty `ViewNode.annotations` array. The
shadow is an evidence-only facade over the exact Incr Next #465 kernel and #469
Formula APIs. No #469 source is copied into Canopy.

## Evidence shape

The bridge is an imperative shell. It reads one snapshot from
`LambdaCompanion::get_eval_results`, `SyncEditor::get_proj_node`, and
`SyncEditor::get_source_map`, then stages all three typed Sources in one
`Store::transaction`:

1. `eval : Array[EvalResult]`
2. `projection : ProjNode[Term]?`
3. `source-map : SourceMap`

The Formula is the deterministic core. It declares exactly those three ports
in that order. It reads eval and projection first. A `None` projection returns
the eval map without reading source-map. A `Some` projection reads source-map,
builds `build_semantic_projection`, and calls the package-private
`AnalysisProjection::annotations`.

Empty Canopy publishes `Some(Unit)`, so the oracle-parity workload preserves
that value and observes all three reads. A separate synthetic `None` snapshot
exercises the two-read branch before transitioning to a real `Some` editor
projection. No production projection is normalized or reclassified.

The Formula and its typed export stay in one local pair. Formula debug exposes
the FormulaId and Formula-local Manifest; the export exposes its ExportId. The
Program and Region are distinct: a Program scopes port, Formula, and export
identity to a Region, while the kernel Region remains the lifecycle capability.
All three sources and the Formula share that Region and Store.

The callback purity boundary is caller-owned. This test callback captures only
three declared reads and performs deterministic annotation work. It does not
allocate ports, builders, exports, or lifecycle objects during evaluation.

## Workloads

The test uses real editor states and edits: empty input, `5`, `missing`, `?`,
three top-level definitions, `5` to `42`, `WrapInLambda`, incomplete `foo(`
and recovery to `5`, the `None` to `Some` branch, one three-source transaction,
manifest order, and FormulaId/ExportId provenance.

It checks full-map equality, Value/Stuck/Suppressed behavior, child NodeId
mapping, observations `2 -> 3`, staged count `3`, and one revision advance.
The sequential stale-before-sync read and post-transaction read establish no
mixed snapshot in these workloads; they do not claim concurrency.

The spike intentionally contains no decorations, diagnostics, pretty output,
Mount, effects, actions, resources, runtime auto-sync, generic provenance, or
consumer package. The exact limitations are: not runtime auto-sync; no
concurrency proof; no generic provenance; Result-depth open.

## Existing API First

Project candidates checked were `build_eval_annotations`,
`AnalysisProjection::annotations`, `build_semantic_projection`, and
`SyncEditor::get_view_tree`. The first two are package-private and are used by
the white-box candidate; the latter two are the public semantic and oracle
seams. Existing `Map`, `Array`, `Option`, `Result`, `Ref`, and `Eq` APIs cover
the typed maps, ordered observations, branch values, error channels, and
counters. `String`/`StringView`, `Bytes`/`BytesView`, `Buffer`, and `cmp` were
checked and are not needed by this evidence. `Set` and erased registries were
also rejected. No production helper or API is added.

## Harness

Run from the repository root:

```bash
bash examples/spikes/lambda_annotation_capability_program/run.sh
```

The harness formats only a temporary copy of the disabled candidate, creates a
disposable Canopy worktree, recursively initializes the recorded submodules,
archives the exact #465/#469 trees from commit
`66a160f557f01f53e6e721016cf12d75b3d4fca4`, appends only those module roots to
the disposable `moon.work`, and injects the test plus test-only imports into
the disposable companion package. `moon info` runs only there. Native checks
and tests, wasm-gc checks/tests when the Canopy dependency supports that
backend, generated-interface privacy, exact source/tree guards, production diff
allowlisting, and blocking `npx slopless` are part of the harness.
