# P1.4 — Semantic-changing overhead and mixed workload

**Question:** Does Term `query_eq` remain beneficial after paying structural Eq
on semantic-changing edits, and what semantic-equivalent edit rate would make
the policy break even for the measured fixtures?

**Verdict:** **PASS WITH CONSTRAINTS AS MEASUREMENT EVIDENCE; LARGE MIXED
POSITIVE ON NATIVE AND JS IN THIS RUN; PRODUCTION POLICY NOT SELECTED.**

This extends P1.3 without changing the owner graph or provider. The only graph
variable remains:

```text
A  Region::query_always_changed
B  Region::query_eq
```

Run and optionally retain evidence with:

```bash
./scripts/run-minimal-no-shadow-lambda-cutoff-mixed-benchmark.sh

./scripts/run-minimal-no-shadow-lambda-cutoff-mixed-benchmark.sh \
  --record examples/spikes/minimal_no_shadow_lambda_projection/evidence/p1_4_cutoff_mixed
```

## Scenario matrix

| Scenario | Edit | Term Eq behavior | Evaluation |
|---|---|---|---|
| whitespace positive control | toggle one trailing space | equal after full comparison | A recomputes; B green |
| early-changing | toggle `x0` literal | mismatch near first definition | both recompute |
| late-changing | toggle last definition literal | mismatch near end of definitions | both recompute |
| mixed-50 | whitespace, early change, whitespace removal, early restore | two equal + two changing edits per timed block | A recomputes four times; B twice |

Medium has 32 definitions / 128 projected nodes; large has 128 definitions /
512 projected nodes. Every semantic-changing process asserts that Term and
Evaluation compute counts advance together and Evaluation has zero green
verifications. Mixed candidate processes assert a 2:1 Term-to-Evaluation
operation count and one green verification per Evaluation recomputation.

Each target/scenario/policy gets a separate preliminary invocation. It does not
warm a recorded process's runtime. Three recorded process-level cycles use
`ABBA`, `BAAB`, then `ABBA`, producing six adjacent AB/BA paired deltas per
target and scenario. Each `moon bench` process performs its own ten
intra-process batches. Raw logs and machine-readable records are retained under
`evidence/p1_4_cutoff_mixed/`.

## Results

Negative delta favors Eq cutoff.

| Target | Scenario | Median paired delta | Paired range | Candidate wins |
|---|---|---:|---:|---:|
| native | medium whitespace | -36.74 µs | -65.41…-9.59 µs | 6/6 |
| native | large whitespace | -360 µs | -520…-190 µs | 6/6 |
| native | medium early-changing | -6.39 µs | -35.71…+56.21 µs | 4/6 |
| native | medium late-changing | +18.50 µs | +6.38…+57.94 µs | 0/6 |
| native | large early-changing | +15 µs | -320…+160 µs | 3/6 |
| native | large late-changing | +60 µs | -160…+430 µs | 2/6 |
| native | medium mixed-50 | -95 µs | -280…+10 µs | 5/6 |
| native | large mixed-50 | -680 µs | -3040…-30 µs | 6/6 |
| JS | medium whitespace | -19.70 µs | -66.18…+10.55 µs | 4/6 |
| JS | large whitespace | -180 µs | -520…+20 µs | 5/6 |
| JS | medium early-changing | -6.83 µs | -44.55…+40.70 µs | 3/6 |
| JS | medium late-changing | +0.35 µs | -32.12…+34.49 µs | 3/6 |
| JS | large early-changing | -35 µs | -170…+30 µs | 4/6 |
| JS | large late-changing | -25 µs | -100…+600 µs | 4/6 |
| JS | medium mixed-50 | -105 µs | -300…+190 µs | 5/6 |
| JS | large mixed-50 | -720 µs | -1530…-180 µs | 6/6 |

Equivalent-edit medians remain favorable, although the JS paired ranges now
cross zero. Semantic-changing overhead is smaller and mostly noisy. The one
stable unfavorable changing case is native medium late mismatch: all six pairs
favor AlwaysChanged, with a +18.50 µs median Eq overhead. Other changing ranges
cross zero. Both native and JS large mixed-50 favor the candidate in all six
pairs. Medium mixed is 5/6 on both targets but still crosses zero.

## Break-even sensitivity

For equivalent-edit benefit `B`, changing-edit overhead `H`, and
equivalent-edit rate `p`, the point equation is:

```text
p > H / (B + H)
```

The point estimate uses the larger positive median early/late overhead. Because
changing-edit ranges cross zero, it must not be treated as a confidence bound.
The sensitivity column instead uses the largest observed positive paired
changing delta.

| Target | Size | B | Point H | Point p | Observed-worst H | Sensitivity p |
|---|---|---:|---:|---:|---:|---:|
| native | medium | 36.74 µs | 18.50 µs | 33.49% | 57.94 µs | 61.20% |
| native | large | 360 µs | 60 µs | 14.29% | 430 µs | 54.43% |
| JS | medium | 19.70 µs | 0.35 µs | 1.77% | 40.70 µs | 67.38% |
| JS | large | 180 µs | 0 µs | 0.00% | 600 µs | 76.92% |

These are fixture sensitivity calculations, not production edit-distribution
thresholds. The wide point-versus-sensitivity gaps show why no threshold is
selected. The observed mixed-50 measurements are the stronger direct check:
large is positive 6/6 on native and JS in this run; medium is 5/6 but unresolved.

## Operational conclusion

P1.4 supplies a bounded selection condition rather than a policy selection:

```text
For the measured large let chains, Eq cutoff is promising at a 50%
semantic-equivalent edit mix: all six pairs favored it on native and JS.

A stable cost exists on at least one semantic-changing path (native medium late
mismatch). Medium mixed results and JS per-scenario results remain noisy, so the
current samples still do not justify a default policy or universal threshold.
```

A production decision still requires representative editor traces, more days /
machines, controlled JS allocation evidence, snapshot-value hardening, and the
existing production coherence/lifetime gates. P1.4 does not authorize more
cutoffs, fingerprints, keyed subterm Queries, prefix-cache replacement, an ADR,
or migration.
