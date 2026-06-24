# Incremental Architecture Evaluation

A reusable framework for evaluating Canopy's query-based incremental architecture.
Use these criteria and structural findings when making architectural decisions,
adding new pipeline stages, or investigating performance.

## Evaluation Criteria

These 15 criteria apply to any dependency-tracked incremental computation system.
Re-evaluate when the architecture changes significantly (new pipeline stages,
multi-file support, new languages).

1. **Dependency Structure** — Are dependencies local, hierarchical, or global?
2. **Change Propagation Shape** — Does a small change remain localized or cascade?
3. **Avalanche Risk** — Can small changes force large recomputation?
4. **Incrementality Effectiveness** — Does incremental computation reduce work in practice?
5. **Language/Problem Constraints** — Does the domain require global dependency tracking?
6. **Decomposability** — Can the system be split into independent units?
7. **Query Necessity** — Is query-based architecture required, or just convenient?
8. **Granularity** — Are computation units too fine-grained (high overhead)?
9. **Parallelizability** — Can work be parallelized efficiently?
10. **Cancellation & Responsiveness** — Can computation be interrupted safely?
11. **Structural Stability** — Do most outputs remain stable under small changes?
12. **Complexity Cost** — What is the cognitive + runtime cost of the system?
13. **Debuggability** — Can developers understand and trace behavior?
14. **Layering Quality** — Are concerns separated (analysis vs presentation vs execution)?
15. **Simpler Alternative** — Could a non-query architecture be equally effective?

## Structural Findings (2026-04-06)

These describe architectural properties of the system rather than
performance numbers, and they remain valid as long as the pipeline
topology is unchanged.

### Pipeline Topology

The editor-facing projection pipeline is a **3-memo generic stack**:

```
syntax_tree Derived → proj_memo (ProjNode[T]?)
                    ├→ registry_memo (Map[NodeId, ProjNode])
                    └→ source_map_memo (SourceMap)
```

`proj_memo` is the branch point — registry and source_map depend on it
independently, and source_map also reads the syntax tree to populate token spans.
No cycles exist. Evaluation and annotations read from the pipeline but never feed
back. Edits route back through text CRDT only.

### Change Detection vs Change Propagation

The generic editor-facing path rebuilds registry and source-map views from the
reconciled projection tree. Lambda now has only a small root-`Module` reconcile
hook over `ProjNode` rows; the old flat module projection helper and its
incremental side-channel are gone.

**When to revisit:** If current measurements show projection rebuilds dominate
keystroke latency on large Lambda documents, reproduce the bottleneck in a
microbenchmark before reintroducing language-specific diffing.

### Removed Lambda Memo Side-Channel

Lambda's former editor-facing stack used a mutable changed-index side-channel
between projection, registry, and source-map memos. #633 removed that stack in
favor of `@core.build_projection_memos`, so new editor-facing projection work
should start from the generic helper rather than recreating the side-channel.

### Branching for Future Features

The pipeline is linear today, but the reactive framework becomes *necessary*
(not just convenient) when it branches. Natural branch points:

- **Type checking**: New memo reading `cached_proj_node`, returning type errors.
  Follows the `eval_memo` pattern.
- **Semantic highlighting**: New memo reading `cached_proj_node` + type results.
  Protocol already has `annotations` field.
- **Multi-file**: Each file gets its own SyncEditor. Cross-file dependencies
  (imports) would be a new Signal connecting editors.

Document how to add a new memo consumer when the first branch is added.
Lambda-specific projection wiring lives in `lang/lambda/proj/projection_memo.mbt`
and eval wiring in `lang/lambda/eval/eval_memo.mbt`; the shared projection helper
is `core/projection_memo.mbt`.

### Platform & Responsiveness

incr compiles to all MoonBit backends (JS, WASM, native) with no
platform-specific FFI. All backends are currently single-threaded, and
Canopy's preferred target is JS.

The JS host uses `requestAnimationFrame` batching. At 320 defs the full
pipeline takes ~2 ms (well within the 16 ms frame budget); at 1000 defs
~8.5 ms (tight but workable). No Web Workers are wired up today, though
the JSON-message FFI protocol is Worker-compatible if needed.

### Strengths to Protect

- **Structural stability**: CstNode sharing + projection reconciliation. These
  compose well. Don't add shortcuts that bypass reconciliation.
- **Layering**: Framework genericity enforced by TestExpr proof tests. This
  enables JSON, Markdown, and future languages.
- **Granularity calibration**: a small fixed memo stack (not per-node reactive
  cells). Don't split into per-node reactive cells without evidence.

### When to Re-Evaluate

- Adding a new pipeline stage (type checker, semantic analysis)
- Supporting documents with 500+ definitions routinely
- Adding multi-file or cross-editor dependencies
- Switching to a multi-threaded backend

## Benchmark Baseline

See `docs/performance/2026-04-06-pipeline-decomposition.md` for the
measurements that ground these findings.
