# EGW P3.0: Text ingress baseline

## Scope and provenance

This is a pre-cutover characterization baseline for the Text façade, not a
before/after performance claim.

- EGW merge content: `91aaffc6679b2e1864b80ef6cc505d1d3b9aa548`
- Runtime: native, release
- Command:
  `NEW_MOON_MOD=0 moon test --package text --target native --release --filter '*P3.0 temporary Text ingress baseline matrix*' --no-parallelize`
- Raw CSV: [2026-08-17-egw-p3-text-ingress-baseline.csv](./2026-08-17-egw-p3-text-ingress-baseline.csv)
- Raw CSV SHA-256:
  `a4d40bf3bade04b5aaafd2a8e4fb6c40957cb3fb21456ef7bc5348a8099a2467`
- Samples: one timed ingress call per case; `inner_us` is a single observation,
  not a statistically stable benchmark summary.

The temporary white-box probe was deleted after the run. The resident H-sized
fixture was seeded outside the timed region through the already-validated P2
`Document::admit_remote` batch seam. The measured operation was the current
`TextState::sync().apply` path, so setup does not contaminate the ingress
measurement. In-memory probe messages used `encoded_size=None`; the measured
current path therefore includes its fallback `to_json_string()` and UTF-8 byte
length calculation. This is a decoded/in-memory admission characterization,
not a known-size wire-ingress-only measurement. The result characterizes the
current H-dependent Text admission boundary; it does not claim that the old
Text path was used to build the resident fixture.

The current path's structural counters are fixed by source inspection:

```text
get_all_ops calls:             1 per measured apply
outer prepare_sync calls:     1
Document::admit_remote calls:  0
Typed commit_admission calls: 0
Document::apply_remote calls: applicable operation count
Batch finalizations:          0
Outer pending owner:          1 TextState array
```

The `conflicting-identity` H=0 rows are a non-applicable fixture: an empty
receiver has no resident identity to conflict with. The `partial` lane is not
an ordinary public Text result in the current path; it requires an injected
core failure or model trace in P3.3.

## Observations

- Complete, duplicate-only, pending-only, and dependency-drain rows are
  present for H = 0, 1k, 10k, and 100k.
- The pending-only rows retain the expected M pending operations.
- Dependency-drain rows start with one pending operation and finish with zero.
- H=100k remains measurable for every non-partial lane; the observations are
  intentionally not promoted to an optimization claim until the P3 after-path
  uses the same fixture and measurement boundary.
- This is native-only evidence. It does not characterize wasm-gc/JS browser
  runtime, editor input-to-paint, main-thread blocking, or Loomark perceived
  speed.
- The admission-path `get_all_ops()` scan is included in the current timings;
  separate `export_all`/`export_since` scans remain outside P3.

## Raw observations

```text
P3BASE,h,m,scenario,inner_us,applied,duplicates,pending,pending_before,pending_after
P3BASE,0,1,complete,53.49,1,0,0,0,0
P3BASE,0,1,duplicate-only,8.369,0,1,0,0,0
P3BASE,0,1,pending-only,17.16,0,0,1,0,1
P3BASE,0,1,conflicting-identity,0,-,-,-,0,0
P3BASE,0,10,complete,177.859,10,0,0,0,0
P3BASE,0,10,duplicate-only,58.397,0,10,0,0,0
P3BASE,0,10,pending-only,77.72200000000001,0,0,10,0,10
P3BASE,0,10,conflicting-identity,0,-,-,-,0,0
P3BASE,0,100,complete,1609.676,100,0,0,0,0
P3BASE,0,100,duplicate-only,580.265,0,100,0,0,0
P3BASE,0,100,pending-only,801.628,0,0,100,0,100
P3BASE,0,100,conflicting-identity,0,-,-,-,0,0
P3BASE,0,1,dependency-drain,29.919,2,0,0,1,0
P3BASE,1000,1,complete,1389.592,1,0,0,0,0
P3BASE,1000,1,duplicate-only,1271.067,0,1,0,0,0
P3BASE,1000,1,pending-only,1232.202,0,0,1,0,1
P3BASE,1000,1,conflicting-identity,1024.042,-,-,-,0,0
P3BASE,1000,10,complete,1407.288,10,0,0,0,0
P3BASE,1000,10,duplicate-only,1256.71,0,10,0,0,0
P3BASE,1000,10,pending-only,1313.53,0,0,10,0,10
P3BASE,1000,10,conflicting-identity,991.865,-,-,-,0,0
P3BASE,1000,100,complete,3004.556,100,0,0,0,0
P3BASE,1000,100,duplicate-only,1909.358,0,100,0,0,0
P3BASE,1000,100,pending-only,2092.824,0,0,100,0,100
P3BASE,1000,100,conflicting-identity,1011.025,-,-,-,0,0
P3BASE,1000,1,dependency-drain,1312.727,2,0,0,1,0
P3BASE,10000,1,complete,19768.438000000002,1,0,0,0,0
P3BASE,10000,1,duplicate-only,13754.869,0,1,0,0,0
P3BASE,10000,1,pending-only,18596.219,0,0,1,0,1
P3BASE,10000,1,conflicting-identity,12668.655,-,-,-,0,0
P3BASE,10000,10,complete,15986.057,10,0,0,0,0
P3BASE,10000,10,duplicate-only,17253.231,0,10,0,0,0
P3BASE,10000,10,pending-only,18806.100000000002,0,0,10,0,10
P3BASE,10000,10,conflicting-identity,12703.738,-,-,-,0,0
P3BASE,10000,100,complete,21829.865,100,0,0,0,0
P3BASE,10000,100,duplicate-only,17174.761,0,100,0,0,0
P3BASE,10000,100,pending-only,17613.953,0,0,100,0,100
P3BASE,10000,100,conflicting-identity,11566.523,-,-,-,0,0
P3BASE,10000,1,dependency-drain,18061.226,2,0,0,1,0
P3BASE,100000,1,complete,229196.741,1,0,0,0,0
P3BASE,100000,1,duplicate-only,220026.49300000002,0,1,0,0,0
P3BASE,100000,1,pending-only,237741.89,0,0,1,0,1
P3BASE,100000,1,conflicting-identity,191545.711,-,-,-,0,0
P3BASE,100000,10,complete,231981.05800000002,10,0,0,0,0
P3BASE,100000,10,duplicate-only,207631.169,0,10,0,0,0
P3BASE,100000,10,pending-only,233669.78100000002,0,0,10,0,10
P3BASE,100000,10,conflicting-identity,198109.041,-,-,-,0,0
P3BASE,100000,100,complete,233051.68600000002,100,0,0,0,0
P3BASE,100000,100,duplicate-only,219193.462,0,100,0,0,0
P3BASE,100000,100,pending-only,255929.766,0,0,100,0,100
P3BASE,100000,100,conflicting-identity,228407.318,-,-,-,0,0
P3BASE,100000,1,dependency-drain,223667.788,2,0,0,1,0
P3BASE,partial,unsupported,current Text path has no ordinary typed partial result
```

The same matrix must be rerun after P3 cutover before any improvement
percentage is reported.
