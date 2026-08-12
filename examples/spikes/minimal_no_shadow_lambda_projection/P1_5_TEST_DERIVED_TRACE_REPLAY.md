# P1.5 — Test-derived logical trace replay

**Question:** What changes when ordered edit and demand cadence from existing
production Lambda editor integration tests is replayed through the P1 graph
under `AlwaysChanged` and Term `EqCutoff`?

**Verdict:** **PASS WITH CONSTRAINTS AS DEMAND-SEMANTICS EVIDENCE; TIMING
INCONCLUSIVE; NOT REPRESENTATIVE USER-SESSION EVIDENCE.**

No captured user editing trace exists in the repository. P1.5 therefore does
not call its inputs representative production traces. It transcribes four
ordered logical traces from tests that exercise the production Lambda editor,
then replays them offline through the existing prototype. Production code and
current-Incr integration remain unchanged.

Run and optionally retain evidence with:

```bash
./scripts/run-minimal-no-shadow-lambda-trace-replay.sh

./scripts/run-minimal-no-shadow-lambda-trace-replay.sh \
  --record examples/spikes/minimal_no_shadow_lambda_projection/evidence/p1_5_trace_replay
```

## Reuse and boundary

P1.5 reuses:

- `MinimalLambdaProjectionShell` and its existing semantic batch/edit/read API;
- the single `ProjectionCommit` Source and P1.2 Term selector policy axis;
- production parser, projection, reconciliation, SourceMap, Evaluation, and
  annotation algorithms;
- `Query::debug()` counters and production `ProjNode::walk_preorder`;
- MoonBit `Array`, `String`, `Map`, `Option`, `Result`, and `Ref` APIs.

New private recipe types only encode ordered edits and the demanded root. They
do not add a provider API, Source, Query, owner, runtime bridge, or kernel
feature. Allocation/GC and structural-Eq visited-node instrumentation do not
exist at this boundary and were not invented for the prototype.

## Trace provenance

The exact provenance and demand qualification are retained in
`evidence/p1_5_trace_replay/trace-manifest.json`.

| Trace | Production integration-test source | Operations / publications between reads | Replay demand |
|---|---|---:|---|
| `whitespace-view` | stale pattern decorations test: `(x) => x` → `(x) => x ` | 1 | AnnotationMap overlay for view-patch demand |
| `binding-view` | unresolved-reference clear test: `(x) => y` → `(x) => x` | 1 | AnnotationMap overlay for view-patch demand |
| `tail-definition-operations` | cursor before `0`: backspace removes its preceding space, insert `9`, producing `90` | 2 operations / 2 publications | AnnotationMap overlay; no intermediate read |
| `expression-source-map-operations` | cursor zero: two no-op backspaces, then two inserts, producing `9942` | 4 operations / 2 publications | exact SourceMap demand class; no intermediate read |

`Overlay` is deliberate: the source integration tests demand production view
patches or projection APIs, while P1.5 demands the prototype's AnnotationMap to
exercise the Evaluation path. The expression trace is a negative control that
demands SourceMap only. P1.5 does not claim exact UI session replay.

## Behavioral evidence

Counters are deterministic on native and JS.

```text
whitespace-view
  publications after initial state       1
  AlwaysChanged Evaluation computes      2
  EqCutoff Evaluation computes           1
  EqCutoff green verifications           1

binding-view
  publications after initial state       1
  Evaluation computes                    2 under both policies
  green verifications                    0

tail-definition-operations
  operations / publications              2 / 2
  root reads                             initial + final only
  Term computes                          2, not 3
  Evaluation computes                    2 under both policies

expression-source-map-operations
  operations / publications              4 / 2
  SourceMap computes                     2
  Term / Evaluation / Annotation computes 0 under both policies
```

This adds two load-bearing observations beyond P1.4:

1. **Operation cadence, publication cadence, and demand cadence are distinct.**
   No-op editor operations publish nothing. Multiple effective publications do
   not force lazy Query work for intermediate states when no root reads them.
   The next demand verifies/recomputes against the latest publication only.
2. **The policy has no semantic-path cost when that path is undemanded.** The
   SourceMap-only trace performs no Term Eq invocation and no Evaluation work
   under either policy. Cutoff profitability cannot be modeled from edit
   frequency alone; the demanded root set is part of the workload.

The whitespace trace repeats the semantic-boundary result on a source
transition copied from a production integration test: Term recomputes, Eq
backdates it, and Evaluation verifies green. The binding and tail-definition
traces preserve normal recomputation for semantic changes.

## Whole-session timing

Each timed operation includes shell construction, initial demand, all
publications, final demand, and close. Separate preliminary invocations precede
three process-level `ABBA`, `BAAB`, `ABBA` cycles, yielding six adjacent pairs
per target and trace. Negative delta favors Eq cutoff.

| Target | Trace | Median paired delta | Paired range | Candidate wins |
|---|---|---:|---:|---:|
| native | whitespace-view | -0.86 µs | -11.68…+0.33 µs | 5/6 |
| native | binding-view | +1.50 µs | -3.01…+8.53 µs | 3/6 |
| native | tail-definition-operations | -0.23 µs | -22.39…+9.72 µs | 3/6 |
| native | expression-source-map-operations | -0.20 µs | -7.47…+0.21 µs | 5/6 |
| JS | whitespace-view | -2.61 µs | -46.69…+132.72 µs | 5/6 |
| JS | binding-view | +1.39 µs | -21.43…+46.40 µs | 2/6 |
| JS | tail-definition-operations | +11.90 µs | -3.49…+306.15 µs | 1/6 |
| JS | expression-source-map-operations | +11.71 µs | -4.90…+107.40 µs | 2/6 |

Every range crosses zero. JS also shows severe process-level outliers in this
run. These small traces are dominated by whole-session setup, common
parser/projection/SourceMap work, and runtime noise. P1.5 establishes no timing
win or loss and computes no break-even rate. Assigning equal weight to four test
traces would fabricate an edit distribution.

## What remains unmeasured

```text
real-user edit-class and Term-size distribution
actual root-demand cadence and demand sets
semantic batch size distribution
downstream fan-out
allocation and GC
structural Eq visited-node or mismatch position cost
p50 / p95 session latency across days and machines
```

The next production-facing evidence step requires an explicitly approved,
privacy-safe logical trace boundary that records source/edit content or a
content-free equivalent classification, batch boundaries, and demanded roots.
Until such traces exist, more synthetic weighting would add precision without
representativeness.

P1.5 does not select a production policy, size threshold, fingerprint, keyed
subterm graph, prefix-cache replacement, migration, or ADR.
