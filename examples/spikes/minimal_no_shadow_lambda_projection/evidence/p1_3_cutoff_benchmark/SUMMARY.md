# P1.3 process-level AB/BA results

Cycles: 2; order alternates ABBA then BAAB; each size/policy gets a separate preliminary invocation. Every recorded moon bench process performs its own intra-process batches.

| Target | Size | Baseline median | Candidate median | Median paired delta | Paired range | Wins |
|---|---|---:|---:|---:|---:|---:|
| native | small | 21.41 µs | 20.08 µs | -1.29 µs (-6.00%) | -2.07…-0.84 µs | 4/4 |
| native | medium | 538.74 µs | 496.12 µs | -45.45 µs (-8.44%) | -64.22…-16.02 µs | 4/4 |
| native | large | 2405.00 µs | 2215.00 µs | -235.00 µs (-9.77%) | -370.00…-180.00 µs | 4/4 |
| js | small | 19.85 µs | 19.59 µs | -0.28 µs (-1.39%) | -1.32…+0.57 µs | 2/4 |
| js | medium | 531.46 µs | 482.03 µs | -63.06 µs (-11.86%) | -122.95…+133.01 µs | 3/4 |
| js | large | 2470.00 µs | 2210.00 µs | -240.00 µs (-9.72%) | -600.00…-50.00 µs | 4/4 |
