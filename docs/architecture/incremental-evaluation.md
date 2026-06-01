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

The projection pipeline is a **linear chain of 4 reactive memos**:

```
syntax_tree Signal → proj_memo (ModuleProjection)
                   → cached_proj_node (ProjNode[T])
                   → registry_memo (Map[NodeId, ProjNode])
                   → source_map_memo (SourceMap)
```

`cached_proj_node` is the **only branch point** — both registry and source_map
depend on it independently. No cycles exist. Evaluation and annotations
(eval_memo, scope_annotation) read from the pipeline but never feed back.
Edits route back through text CRDT only.

### Change Detection vs Change Propagation

The dominant cost per keystroke is **change detection** rather than change propagation.
`to_module_projection_incremental` scans all N definitions checking `physical_equal()`
on CstNode pointers, even though typically only 1 def changed. The incremental
parsing and projection that follow are efficient — but discovering *which* defs
changed requires a linear scan.

**When to revisit:** If documents routinely exceed 500 definitions, investigate
damage-guided def scanning (use the parser's damaged range to skip defs whose
byte range doesn't overlap).

### Side-Channel Between Memos

`changed_def_indices_ref` is a mutable `Ref[Array[Int]?]` shared between
`proj_memo` (writer) and `registry_memo` / `source_map_memo` (readers),
bypassing the reactive dependency graph. Revision-skew detection and a
full-rebuild fallback defend it.

The side-channel exists for performance, but benchmarks show source_map
overhead is small (18% of pipeline at 1000 defs, negligible at 320). The
coupling is a design smell whose cost is cognitive rather than runtime.

**Options if cleaning up:** (a) return changed indices as part of
`proj_memo`'s return value; (b) promote to a Signal; (c) encode semantics
as a sum type (`enum DefChange { Full; Patch(Array[Int]); None }`).

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
Lambda-specific memo setup lives in `lang/lambda/flat/projection_memo.mbt`
and `lang/lambda/eval/eval_memo.mbt`; generic memo helpers are in `core/projection_memo.mbt`.

### Platform & Responsiveness

incr compiles to all MoonBit backends (JS, WASM, native) with no
platform-specific FFI. All backends are currently single-threaded, and
Canopy's preferred target is JS.

The JS host uses `requestAnimationFrame` batching. At 320 defs the full
pipeline takes ~2 ms (well within the 16 ms frame budget); at 1000 defs
~8.5 ms (tight but workable). No Web Workers are wired up today, though
the JSON-message FFI protocol is Worker-compatible if needed.

### Strengths to Protect

- **Structural stability**: Backdating + CstNode sharing + LCS reconciliation +
  per-def patching. These compose well. Don't add shortcuts that bypass
  reconciliation.
- **Layering**: Framework genericity enforced by TestExpr proof tests. This
  enables JSON, Markdown, and future languages.
- **Granularity calibration**: 4 memos (not 400) with hand-optimized
  incrementality inside each memo. Don't split into per-node reactive cells.

### When to Re-Evaluate

- Adding a new pipeline stage (type checker, semantic analysis)
- Supporting documents with 500+ definitions routinely
- Adding multi-file or cross-editor dependencies
- Switching to a multi-threaded backend

## Benchmark Baseline

See `docs/performance/2026-04-06-pipeline-decomposition.md` for the
measurements that ground these findings.
