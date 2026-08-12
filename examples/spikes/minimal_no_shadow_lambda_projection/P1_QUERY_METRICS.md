# P1.1 — Query reuse measurement

**Question:** What incremental work does the unchanged #462 provider actually
avoid in P1, without adding cutoff/backdating or another feature?

This is counter evidence, not a timing benchmark and not an optimization. It
uses the provider's existing `QueryDebug` and `memo_debug(())` interfaces. The
table records the P1.1 #462-provider run before P1.2 introduced #464 cutoff.
See [P1_2_EVAL_GREEN_PATH.md](P1_2_EVAL_GREEN_PATH.md) for the first edit-time
green path. The P1.1 table is reproducible from commit `691c155b`; the current
branch's one-command harness runs the P1.2 extension.

Every stage prints:

```text
compute_count
cache_hits
green_verifications
memo_count
trace_length
```

for Registry, SourceMap, Evaluation, and AnnotationMap.

## Observed matrix

| Stage | Registry | SourceMap | Evaluation | AnnotationMap |
|---|---|---|---|---|
| structural-batch | `c0/h0/g0/m0/t-` | `c0/h0/g0/m0/t-` | `c0/h0/g0/m0/t-` | `c0/h0/g0/m0/t-` |
| demand-annotations | `c0/h0/g0/m0/t-` | `c1/h1/g0/m1/t1` | `c1/h0/g0/m1/t1` | `c1/h1/g0/m1/t3` |
| demand-registry | `c1/h1/g0/m1/t1` | `c1/h1/g0/m1/t1` | `c1/h0/g0/m1/t1` | `c1/h1/g0/m1/t3` |
| demand-source-map | `c1/h1/g0/m1/t1` | `c1/h3/g0/m1/t1` | `c1/h0/g0/m1/t1` | `c1/h1/g0/m1/t3` |
| evaluation-edit | `c1/h1/g0/m1/t1` | `c2/h5/g0/m1/t1` | `c2/h1/g0/m1/t1` | `c2/h1/g0/m1/t3` |
| close | all memo tables cleared | all memo tables cleared | all memo tables cleared | all memo tables cleared |

Legend: `c=compute_count`, `h=cache_hits`, `g=green_verifications`,
`m=memo_count`, `t=direct trace length`, `-=no memo`.

All values are cumulative at the named stage, not operation-local deltas. The
direct trace length counts dependencies installed on that Query memo; it is not
the transitive dependency closure or actual verify-call count. For example,
SourceMap's first cache hit is observed after annotation computation when the
separate `annotation_view` helper reads SourceMap, and the source-range stage
adds two more direct reads.

## Interpretation

The measurement positively shows:

- all four Queries remain absent until demanded;
- repeated reads in one epoch are same-epoch cache hits;
- AnnotationMap has exactly three dependencies: exact ProjectionCommit,
  Evaluation, and SourceMap;
- Evaluation and SourceMap each have exactly one ProjectionCommit dependency;
- annotation demand computes SourceMap once;
- the later source-range consumer reuses that same SourceMap memo: its cache-hit
  count rises while compute count remains one;
- undemanded Registry does no edit-time work;
- close clears all four memo tables, and the post-close read executes no Query.

The measurement also positively shows what P1 does **not** provide:

- after a changed ProjectionCommit, demanded Evaluation, SourceMap, and
  AnnotationMap each recompute;
- `green_verifications` remains zero for every Query in this workload;
- no cutoff/backdating stops equal-result propagation;
- `eval_term` does not reuse current production's unchanged Module definition
  prefix.

Therefore P1 demonstrates lazy ownership, same-epoch reuse, and cross-consumer
memo sharing. It does not demonstrate fine-grained edit-time incremental work
avoidance.

## Remaining production constraints

- `AnnotationMap` is a mutable `Map` returned from a memo; production needs an
  immutable snapshot, read-only facade, or defensive copy boundary.
- The evidence `annotation_view` performs separate root reads; production
  publication needs one coherent Query/result boundary for commit, annotations,
  source map, and `ViewNode`.
- shell `ProjectionState` advances before Source publication; production needs
  an atomic reducer/publication protocol.
- nested production semantic batches remain unproven.
- Tier-2 escalation and full lifetime closure remain out of scope.

No #464 cutoff integration or optimization is selected by this measurement.
