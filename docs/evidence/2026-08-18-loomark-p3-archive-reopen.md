# Loomark P3 archive reopen evidence

> Measurement record. This report does not authorize checkpointing, history
> compaction, or a performance budget by itself.

## Scope and exact builds

This is a paired production measurement of local archive reopen before and after
P3 Text admission integration. It is not a remote-sync measurement.

| build | Canopy | EGW gitlink |
|---|---|---|
| Before | `21745e9c0b4c087ac2c9649a6a8eab40d5fc9e25` | `c0da9cec41be0f8f0edbb8b91d0dc3ccddd39d31` |
| After | `2f27a4d4b272423d3df432b744e413c8b12dd290` | `9dee515f755a59f76bacab6ff582284ab1fbe7cf` |

Environment: Node `v24.14.1`, npm `11.11.0`, Playwright Chromium
`149.0.7827.55`, Moon `0.1.20260713`. The user-visible measurements use the
Warren release standalone site and the existing
`apps/loomark/examples/vanilla/bench-startup.mjs` archive mode. Each case has
10 reload samples in a fresh browser context after seeding the archive.

## Fixture

The final value is the repository-authored `apps/loomark/README.md`:

- final portable Markdown: 2,885 bytes;
- one full source replacement, then real one-character append + Backspace
  pairs;
- operation counts: 1, 5, 21, and 41 history-changing operations;
- all four fixtures use the same final text and document identity.

Archive and history sizes, plus fixture SHA-256 values, are recorded in
`2026-08-18-loomark-p3-archive-reopen-scaling.json` and
`2026-08-18-loomark-p3-archive-fixture-sha256sums.txt`.

## Production reload results

`reloadRestoredDocument` is the time until the restored editor value is
observed. Values are p50 / p95.

| History-changing operations | History bytes | Archive bytes | Before (ms) | After (ms) |
|---:|---:|---:|---:|---:|
| 1 | 1,067,072 | 1,168,359 | 788.6 / 848.9 | 231.3 / 263.1 |
| 5 | 1,068,558 | 1,169,977 | 797.9 / 865.4 | 226.1 / 242.8 |
| 21 | 1,075,988 | 1,178,067 | 787.0 / 871.2 | 222.7 / 252.2 |
| 41 | 1,090,848 | 1,194,247 | 830.9 / 900.6 | 231.3 / 247.2 |

For the 41-operation fixture, P3 reduces p50 by 72.2% (3.59x) and p95 by
72.5% (3.64x). The compact one-character history shape does not produce a
monotonic reload curve; it must not be treated as a universal model of history
size or operation count.

## Phase decomposition

Phase runs use the same 41-operation fixture and 10 samples per build. They use
direct Moon JS release output with measure-only browser marks, not Warren's
minified artifact. Therefore the phase intervals are diagnostic comparisons;
the production Warren results above are the user-visible totals.

The marker pairs are:

| phase | marker interval |
|---|---|
| storage read | `restore-start` → `storage-read-complete` |
| outer JSON parse | `archive-outer-json-start` → `archive-outer-json-complete` |
| envelope validation | `archive-outer-json-complete` → `history-json-start` |
| history JSON decode | `history-json-start` → `history-json-complete` |
| semantic editor construction | `semantic-editor-start` → `semantic-editor-complete` |
| history admission | `history-admission-start` → `history-admission-complete` |
| projection refresh | `projection-refresh-start` → `projection-refresh-complete` |
| semantic reopen total | `semantic-reopen-start` → `semantic-reopen-complete` |
| portable verification | `portable-verification-start` → `portable-verification-complete` |
| mount call | `mount-start` → `mount-return` |

Median phase intervals:

| phase | Before (ms) | After (ms) |
|---|---:|---:|
| outer JSON parse | 30.6 | 27.5 |
| history JSON decode | 88.3 | 86.5 |
| semantic editor construction | 9.5 | 9.3 |
| history admission | 661.9 | 115.3 |
| projection refresh | 2.4 | 2.3 |
| portable verification | 2.9 | 3.1 |
| mount call | 9.4 | 9.5 |

The phase intervals are not a replacement for a single end-to-end clock. They
identify where the measured time is spent: P3 removes the dominant repeated
admission work, while the remaining substantial phases are history JSON decode
and one admission/replay pass. Projection refresh is not the next archive
reopen bottleneck in this fixture.

## Decision

Do not implement checkpoint/materialized-state or Plain projection as the next
archive-reopen optimization from this evidence alone.

The remaining admission time could depend on operation count, serialized bytes,
payload scalar count, RLE runs, tombstones, undeletes, full-document
replacement shape, allocations, or Fugue reconstruction. One compact 41-event
fixture cannot distinguish those factors. A checkpoint would also require a
persistent format, frontier and suffix-replay rules, corruption fallback, and
migration policy.

The next measurement should separate these axes:

1. same final text with 1 / 10 / 100 / 1,000 operations and approximately fixed
   total inserted payload;
2. same operation count with scalar, 32-scalar, and 1-KB payloads;
3. similar archive bytes with append-only, distributed edits,
   insert/delete-heavy, full-replacement, tombstone-heavy, and undelete
   histories.

Each fixture should record archive bytes, outer JSON bytes, history JSON bytes,
canonical operation count, RLE run count, inserted scalar count, delete and
undelete counts, and final text bytes.

The standalone app currently has no wired `SyncEditor`, `apply_sync`, WebSocket
peer admission, pending drain, or collaboration session. Remote 1/10/100,
duplicate-only, pending-drain, reconnect, and active-editor measurements
therefore remain blocked until a production-equivalent browser harness or
transport seam exists. Local editing and remote/sync results must remain
separate.

## Evidence files

- `2026-08-18-loomark-p3-archive-reopen-scaling.json` — production raw samples,
  summaries, fixture metadata, and exact build/environment metadata.
- `2026-08-18-loomark-p3-archive-reopen-phase-before.json` and
  `2026-08-18-loomark-p3-archive-reopen-phase-after.json` — raw phase runs and
  marker observations.
- `fixtures/1-ops.json`, `fixtures/5-ops.json`, `fixtures/21-ops.json`, and
  `fixtures/41-ops.json` inside the raw bundle — exact archive inputs.
- `2026-08-18-loomark-p3-archive-reopen-raw.tar.gz` — compressed raw bundle
  containing those fixtures, JSONL-like command logs, phase runs, and
  environment metadata.
- `2026-08-18-loomark-p3-archive-reopen-raw.tar.gz.sha256` — bundle digest.

The raw JSON records preserve the individual reload samples; the compressed
bundle preserves the generated archive inputs and command output used for the
paired run.
