# P1.2 — Term cutoff makes Evaluation green

**Question:** When a new `ProjectionCommit` changes only source whitespace, can
a typed Eq-cutoff Term selector preserve its semantic `changed_at` so Evaluation
verifies green without recomputing?

**Verdict:** **PASS WITH CONSTRAINTS.** This is graph-level counter evidence,
not a timing benchmark and not production authorization.

Run:

```bash
./scripts/run-minimal-no-shadow-lambda-projection.sh
```

## Provider

P1.2 materializes the incremental provider from Incr #464 commit:

```text
c640f65124b2a0eb362f3f08a1b6220e6647b6b7
```

The #464 spike uses documented symlinks to #462/#463 provider files. P1.2
resolves those links to the exact files at the same commit and hashes every
materialized source. It adds only a prototype-local MoonBit module adapter and
does not add a Canopy-specific kernel policy.

The selected existing API is:

```moonbit
Region::query_eq(compute) // V : Eq
```

`query_type_owned` was checked but rejected: Lambda `Term` already has the exact
structural `Eq` needed for this whitespace workload. `query_always_changed` and
the compatibility `query` cannot preserve `changed_at` after an equal result.

## Graph

```text
ProjectionCommit Source
        │
        ├──────────────→ SourceMap Query
        │
        └─→ Term Query[Eq cutoff]
                 │
                 └─→ Evaluation Query

ProjectionCommit + Evaluation + SourceMap
        └─→ AnnotationMap Query
```

The graph retains:

```text
application owner         1
Store                     1
Region                    1
canonical Source          1
cross-runtime bridge      0
current Runtime objects   0
```

It adds one Query, not another Source or state owner.

## Workload

After P1 establishes `((z, y) => z - y) 5 2` with evaluation annotation `→ 3`,
P1.2 appends one trailing space:

```text
before  "((z, y) => z - y) 5 2"
after   "((z, y) => z - y) 5 2 "
```

The parser snapshot and projection publication change. SourceMap recomputes and
the AlwaysChanged baseline conservatively marks that memo changed; P1.2 does
not compare old and new SourceMap values. The projected Lambda `Term` remains
equal under structural `Eq`.

## Counter evidence

Immediately before and after the whitespace edit demand:

```text
Term selector
  compute_count          2 → 3
  cutoff_calls           1 → 2
  changed_at             preserved
  verified_at            advanced
  direct_trace_length    1  (ProjectionCommit)

Evaluation
  compute_count          2 → 2
  green_verifications    0 → 1
  direct_trace_length    1  (Term selector)

SourceMap
  compute_count          2 → 3

AnnotationMap
  compute_count          2 → 3
  direct_trace_length    3  (ProjectionCommit, Evaluation, SourceMap)

Registry
  compute_count          1 → 1  (undemanded after edit)
```

This proves that a changed coarse commit can be narrowed through a semantic
selector and stopped before Evaluation. AnnotationMap still recomputes because
it correctly reads the changed commit and SourceMap directly.

All debug counters are cumulative values at the named stage, not per-stage
deltas. `direct_trace_length` is the number of forward dependencies installed
on that memo, not the transitive dependency closure or the number of verify
calls. `cutoff_calls` counts policy invocation after successful recomputation:
it also increments for the AlwaysChanged policy. Term `changed_at` preservation,
not `cutoff_calls` alone, proves that the Eq cutoff classified this result as
unchanged.

## Constraints

P1.2 does not prove:

- that all whitespace forms preserve `Term` equality;
- cutoff/backdating for Registry, SourceMap, or AnnotationMap;
- unchanged Module-definition prefix reuse inside evaluation;
- timing or allocation improvement;
- mutable memo-result safety;
- coherent whole-`ViewNode` publication across one result boundary;
- atomic shell ProjectionState/publication;
- nested production semantic batches;
- Tier-2 escalation or production lifetime closure.

No wall-clock optimization, LRU, Mount, dependency representation change, ADR,
or production migration follows from this spike.
