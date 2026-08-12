# P1.5 test-derived trace replay results

Whole-session timing includes shell construction, initial root demand, every publication, final root demand, and close. Three ABBA/BAAB cycles produce six adjacent pairs per target/trace.

| Target | Trace | Baseline median | Candidate median | Median paired delta | Median pair % | Range | Wins |
|---|---|---:|---:|---:|---:|---:|---:|
| native | whitespace-view | 48.58 µs | 47.86 µs | -0.86 µs | -1.74% | -11.68…+0.33 µs | 5/6 |
| native | binding-view | 54.44 µs | 55.70 µs | +1.50 µs | +2.75% | -3.01…+8.53 µs | 3/6 |
| native | tail-definition-operations | 136.81 µs | 137.23 µs | -0.23 µs | -0.17% | -22.39…+9.72 µs | 3/6 |
| native | expression-source-map-operations | 25.08 µs | 25.02 µs | -0.20 µs | -0.78% | -7.47…+0.21 µs | 5/6 |
| js | whitespace-view | 49.02 µs | 45.77 µs | -2.61 µs | -5.80% | -46.69…+132.72 µs | 5/6 |
| js | binding-view | 53.14 µs | 66.69 µs | +1.39 µs | +2.65% | -21.43…+46.40 µs | 2/6 |
| js | tail-definition-operations | 161.15 µs | 172.62 µs | +11.90 µs | +7.43% | -3.49…+306.15 µs | 1/6 |
| js | expression-source-map-operations | 21.98 µs | 29.85 µs | +11.71 µs | +63.43% | -4.90…+107.40 µs | 2/6 |

Allocation, GC, mismatch visited-node count, fan-out, and real-user edit frequencies are not measured.
