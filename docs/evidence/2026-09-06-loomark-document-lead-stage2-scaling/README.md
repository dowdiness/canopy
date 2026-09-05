# Loomark DocumentLead Stage 2 isolated scaling evidence

**Final evidence.** This report contains 84 complete fixture-phase groups: 14 corpus/size cells × 3 phases × separate cold and warm runs. It is exploratory measurement, not an SLA and not browser acceptance evidence.

## Deterministic selection

- `isolated-small.log`: all 1K, 10K, and 50K groups.
- `isolated-large.log`: all 100K, 250K, and 500K groups, plus ordinary 1.27M; structure 1.27M IR/extract are excluded.
- `isolated-final.log`: structure 1.27M IR and extract, replacing those excluded groups.
- No partial groups are pooled. Cold is three independent processes (`n=3`); warm is one process after 20 warmups (`n=20`). Statistics are median, linearly interpolated p95, and max, in milliseconds.

## Reproduction

Each group was run in an isolated JS release process: cold repetitions used `--cold-reps 3 --warmups 0 --samples 1`; warm used `--warmups 20 --samples 20`. Each process had a 300-second timeout. The bounded capture was stopped by a **1,200-second timeout around the whole command**, not a 300-second timeout per process; it stopped during structure 1.27M IR cold-2. The final file completed structure 1.27M IR and extract. The parser first call has no warm setup. IR calls explicitly report `setup=parser-prerequisite`; that prerequisite parse is outside the IR timer.

```sh
timeout 1200s python3 scripts/run-loomark-stage2-scaling.py --cold-reps 3 --warmups 20 --samples 20 --timeout 300 > /tmp/isolated-capture.log
python3 scripts/loomark-stage2-scaling-report.py docs/evidence/2026-09-06-loomark-document-lead-stage2-scaling/isolated-small.log docs/evidence/2026-09-06-loomark-document-lead-stage2-scaling/isolated-large.log docs/evidence/2026-09-06-loomark-document-lead-stage2-scaling/isolated-final.log
```

## Final timings

| corpus | target | bytes | phase | cold: median / p95 / max (ms), n=3 | warm: median / p95 / max (ms), n=20 |
|---|---:|---:|---|---:|---:|
| ordinary | 1000 | 1002 | parse | 81.879 / 81.925 / 81.930 | 2.891 / 6.055 / 7.522 |
| ordinary | 1000 | 1002 | ir | 26.412 / 28.843 / 29.113 | 1.138 / 2.162 / 2.354 |
| ordinary | 1000 | 1002 | extract | 89.127 / 93.252 / 93.710 | 4.730 / 6.798 / 8.735 |
| ordinary | 10000 | 10027 | parse | 132.711 / 145.205 / 146.593 | 17.978 / 22.652 / 23.675 |
| ordinary | 10000 | 10027 | ir | 41.717 / 52.599 / 53.808 | 7.659 / 11.290 / 11.711 |
| ordinary | 10000 | 10027 | extract | 193.627 / 215.868 / 218.339 | 21.211 / 26.760 / 28.093 |
| ordinary | 50000 | 50017 | parse | 277.221 / 292.251 / 293.921 | 67.099 / 78.163 / 79.050 |
| ordinary | 50000 | 50017 | ir | 134.468 / 139.584 / 140.153 | 24.221 / 52.157 / 53.811 |
| ordinary | 50000 | 50017 | extract | 437.781 / 453.957 / 455.754 | 106.470 / 122.252 / 128.787 |
| ordinary | 100000 | 100034 | parse | 536.616 / 643.211 / 655.054 | 178.597 / 204.835 / 213.941 |
| ordinary | 100000 | 100034 | ir | 316.826 / 321.700 / 322.242 | 113.347 / 129.374 / 142.690 |
| ordinary | 100000 | 100034 | extract | 696.314 / 887.301 / 908.522 | 294.290 / 339.317 / 345.986 |
| ordinary | 250000 | 250058 | parse | 908.920 / 1016.722 / 1028.700 | 402.369 / 446.644 / 468.254 |
| ordinary | 250000 | 250058 | ir | 405.530 / 432.207 / 435.171 | 61.130 / 67.792 / 80.468 |
| ordinary | 250000 | 250058 | extract | 428.984 / 465.609 / 469.679 | 241.747 / 406.855 / 464.594 |
| ordinary | 500000 | 500004 | parse | 544.281 / 570.394 / 573.295 | 315.866 / 442.570 / 457.188 |
| ordinary | 500000 | 500004 | ir | 263.754 / 271.836 / 272.734 | 135.003 / 151.064 / 171.768 |
| ordinary | 500000 | 500004 | extract | 744.168 / 767.245 / 769.809 | 425.829 / 450.989 / 454.990 |
| ordinary | 1270000 | 1270060 | parse | 864.430 / 867.235 / 867.546 | 1344.049 / 1550.168 / 1665.214 |
| ordinary | 1270000 | 1270060 | ir | 1212.227 / 1423.600 / 1447.086 | 1170.832 / 1409.821 / 1522.189 |
| ordinary | 1270000 | 1270060 | extract | 4065.748 / 4195.247 / 4209.636 | 1216.595 / 1426.143 / 1527.371 |
| structure | 1000 | 1050 | parse | 87.202 / 96.781 / 97.846 | 2.747 / 6.731 / 9.746 |
| structure | 1000 | 1050 | ir | 28.041 / 32.194 / 32.655 | 2.816 / 4.170 / 5.473 |
| structure | 1000 | 1050 | extract | 101.894 / 112.646 / 113.841 | 5.341 / 9.177 / 10.529 |
| structure | 10000 | 10025 | parse | 174.991 / 301.977 / 316.087 | 19.464 / 30.481 / 32.214 |
| structure | 10000 | 10025 | ir | 67.960 / 83.636 / 85.378 | 12.024 / 26.738 / 29.154 |
| structure | 10000 | 10025 | extract | 274.136 / 300.761 / 303.719 | 33.433 / 53.829 / 54.338 |
| structure | 50000 | 50010 | parse | 397.470 / 429.012 / 432.517 | 87.469 / 105.183 / 128.867 |
| structure | 50000 | 50010 | ir | 178.859 / 181.163 / 181.420 | 47.056 / 77.503 / 90.652 |
| structure | 50000 | 50010 | extract | 515.571 / 523.989 / 524.924 | 136.835 / 160.959 / 189.711 |
| structure | 100000 | 100090 | parse | 198.129 / 266.182 / 273.743 | 65.218 / 83.189 / 88.166 |
| structure | 100000 | 100090 | ir | 103.079 / 317.046 / 340.821 | 96.561 / 151.756 / 153.217 |
| structure | 100000 | 100090 | extract | 1463.052 / 1475.206 / 1476.556 | 277.555 / 326.713 / 382.561 |
| structure | 250000 | 250035 | parse | 1093.265 / 1249.289 / 1266.625 | 716.139 / 1059.272 / 1211.649 |
| structure | 250000 | 250035 | ir | 691.294 / 787.974 / 798.716 | 320.366 / 471.418 / 494.889 |
| structure | 250000 | 250035 | extract | 2017.177 / 2090.123 / 2098.229 | 1452.997 / 2258.425 / 2463.134 |
| structure | 500000 | 500010 | parse | 1814.953 / 2486.498 / 2561.114 | 1028.711 / 1328.355 / 1405.915 |
| structure | 500000 | 500010 | ir | 1246.899 / 1407.122 / 1424.924 | 669.756 / 980.791 / 1060.460 |
| structure | 500000 | 500010 | extract | 3675.472 / 3752.856 / 3761.454 | 1598.503 / 1849.960 / 1858.588 |
| structure | 1270000 | 1270065 | parse | 4785.089 / 7639.802 / 7956.992 | 3274.050 / 3946.894 / 4479.763 |
| structure | 1270000 | 1270065 | ir | 2567.214 / 2573.575 / 2574.282 | 1906.297 / 2129.641 / 2134.736 |
| structure | 1270000 | 1270065 | extract | 7107.404 / 7359.342 / 7387.335 | 4531.894 / 5724.398 / 6075.393 |

## Fixture manifest

`lines` counts actual newline characters in the exact UTF-8 fixture; `blocks` is the top-level block count; `nodes` is recursive IR-node count; `sha256` hashes the exact fixture bytes. The recipe repeats complete blocks until the byte target is reached; it never splits a block and never inserts the two characters `\` and `n` as a newline.

```text
# Ordinary heading {index}

A paragraph with **inline** text and a [link](https://example.com).

```

````text
# Structure heading {index}

- [ ] task item {index}
  - nested child {index}
    - third level child

> quoted block {index}

```moonbit
let value = {index}
let next = value
```

````

| corpus | target | bytes | lines | blocks | nodes | sha256 |
|---|---:|---:|---:|---:|---:|---|
| ordinary | 1000 | 1002 | 44 | 22 | 111 | `a9c153c1107052062af02fddcbc4d4c5c8a0520c7800ff8e903ab77795bebcca` |
| ordinary | 10000 | 10027 | 436 | 218 | 1091 | `7d22b59dfc5780e196a77829e5cc10f680763e02b03d962dbebfb0c113adbbc9` |
| ordinary | 50000 | 50017 | 2156 | 1078 | 5391 | `6d6e0a686e1123cf83bf31fce91d4193992d75327443556d7ec8a9a5a475184b` |
| ordinary | 100000 | 100034 | 4304 | 2152 | 10761 | `29dbd4425ce328633a37b44d8fa590c0a9aaadfc733254d2b73f08f77879b642` |
| ordinary | 250000 | 250058 | 10688 | 5344 | 26721 | `0598e111e84b2d1288d020aaf706d86cc27a6224f70db0196acb066fc1baf8c8` |
| ordinary | 500000 | 500004 | 21324 | 10662 | 53311 | `21cca2942469a475e66af68c635355663580746f2318d16a0345a85f5e4a6617` |
| ordinary | 1270000 | 1270060 | 53944 | 26972 | 134861 | `284aa28334d5530d9828b928576d75e57cf0f33cd15459c6146f4a2f2a69bc0e` |
| structure | 1000 | 1050 | 91 | 28 | 127 | `eeed481d193770fb3a7d42a817f89295c699960f2265d2e9aaac173161b35adb` |
| structure | 10000 | 10025 | 845 | 260 | 1171 | `b99c59ae1907ddec93986ae7c494ad79aa3ec5d2d0119e62e1adffb818f5211d` |
| structure | 50000 | 50010 | 4108 | 1264 | 5689 | `a8d8e9fd5dcea57b5a5a14d474320932c14cadaaecf83b3d985e55bd4b5c4218` |
| structure | 100000 | 100090 | 8177 | 2516 | 11323 | `5beaa486e225a9c582f459ecf913039bf74cb4332685f1a441a87c253367e5c3` |
| structure | 250000 | 250035 | 20137 | 6196 | 27883 | `068c3d69e22aec68c82516e86393580c5a95fcd937f4660f30a1f6807f249b5d` |
| structure | 500000 | 500010 | 39832 | 12256 | 55153 | `9864f99e917fd093cc1a0e6e95633ac8633daaf25b6a66b29965686b39e8eed6` |
| structure | 1270000 | 1270065 | 100503 | 30924 | 139159 | `0ad563d6434d0ac9a7f339db51ba04d7669c41dfaed2d66baf6bb64f5ea452c0` |

The 1 KB ordinary fixture repeats its recipe 11 times (44 LF delimiters,
22 top-level blocks); structure repeats 7 times (91 LF delimiters, 28 blocks).
Recipe repetition counts and Markdown block counts are not interchangeable.

## Provenance

- Baseline checkout: `9fc86e7cda11df549b894b9aecdc677806e79d20`.
- Current harness source SHA-256 (unchanged since `isolated-small.log`): `8a9feea82ee08f91588ea5825aa1404b33582c58650ef66514336a3d42ef8003` (`stage2_scaling_measurement_wbtest.mbt`). Runner SHA-256: `b2a4dd72923e72401f78181e45aca9d3c6825d2292dd73f34bf92b67f09af65a`.
- Runtime: moon `0.1.20260819 (fc2a4ee 2026-08-19)`, Node `v24.14.1`, npm `11.11.0`.
- Timings exclude fixture construction, checksum, UI, browser, persistence, workers, and async completion. Historical contaminated logs remain outside this evidence tree under `/tmp`; only the three isolated logs are normative here.
