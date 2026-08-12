# P1.4 semantic-changing and mixed cutoff results

Cycles: 3; six adjacent AB/BA pairs per target/scenario. Preliminary invocations use separate processes; every recorded moon bench process performs its own intra-process batches.

| Target | Scenario | Baseline median | Candidate median | Median paired delta | Median pair % | Range | Wins |
|---|---|---:|---:|---:|---:|---:|---:|
| native | medium/whitespace | 515.80 µs | 497.78 µs | -36.74 µs | -7.10% | -65.41…-9.59 µs | 6/6 |
| native | large/whitespace | 2520.00 µs | 2155.00 µs | -360.00 µs | -14.01% | -520.00…-190.00 µs | 6/6 |
| native | medium/early-changing | 516.09 µs | 502.42 µs | -6.39 µs | -1.26% | -35.71…+56.21 µs | 4/6 |
| native | medium/late-changing | 506.64 µs | 529.80 µs | +18.50 µs | +3.71% | +6.38…+57.94 µs | 0/6 |
| native | large/early-changing | 2765.00 µs | 2585.00 µs | +15.00 µs | +0.50% | -320.00…+160.00 µs | 3/6 |
| native | large/late-changing | 2505.00 µs | 2585.00 µs | +60.00 µs | +2.32% | -160.00…+430.00 µs | 2/6 |
| native | medium/mixed-50 | 2130.00 µs | 2060.00 µs | -95.00 µs | -4.46% | -280.00…+10.00 µs | 5/6 |
| native | large/mixed-50 | 11730.00 µs | 9830.00 µs | -680.00 µs | -6.39% | -3040.00…-30.00 µs | 6/6 |
| js | medium/whitespace | 469.44 µs | 455.83 µs | -19.70 µs | -3.48% | -66.18…+10.55 µs | 4/6 |
| js | large/whitespace | 2320.00 µs | 2100.00 µs | -180.00 µs | -8.32% | -520.00…+20.00 µs | 5/6 |
| js | medium/early-changing | 455.75 µs | 451.73 µs | -6.83 µs | -1.38% | -44.55…+40.70 µs | 3/6 |
| js | medium/late-changing | 460.96 µs | 466.26 µs | +0.35 µs | +0.09% | -32.12…+34.49 µs | 3/6 |
| js | large/early-changing | 2250.00 µs | 2215.00 µs | -35.00 µs | -1.53% | -170.00…+30.00 µs | 4/6 |
| js | large/late-changing | 2290.00 µs | 2370.00 µs | -25.00 µs | -1.11% | -100.00…+600.00 µs | 4/6 |
| js | medium/mixed-50 | 2095.00 µs | 2020.00 µs | -105.00 µs | -4.64% | -300.00…+190.00 µs | 5/6 |
| js | large/mixed-50 | 9805.00 µs | 9200.00 µs | -720.00 µs | -7.34% | -1530.00…-180.00 µs | 6/6 |

## Break-even sensitivity

Uses p > H / (B + H). The point estimate uses the larger positive median changing overhead. The observed-worst sensitivity uses the largest positive paired changing delta. Neither is a confidence bound or production edit distribution.

| Target | Size | B | Early median H | Late median H | Point p | Observed-worst H | Sensitivity p | Mixed-50 delta | Mixed wins |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| native | medium | 36.74 µs | -6.39 µs | +18.50 µs | 33.49% | 57.94 µs | 61.20% | -95.00 µs | 5/6 |
| native | large | 360.00 µs | +15.00 µs | +60.00 µs | 14.29% | 430.00 µs | 54.43% | -680.00 µs | 6/6 |
| js | medium | 19.70 µs | -6.83 µs | +0.35 µs | 1.77% | 40.70 µs | 67.38% | -105.00 µs | 5/6 |
| js | large | 180.00 µs | -35.00 µs | -25.00 µs | 0.00% | 600.00 µs | 76.92% | -720.00 µs | 6/6 |
