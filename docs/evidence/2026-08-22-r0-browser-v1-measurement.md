<!-- textlint-disable slopless/coleman-liau slopless/flesch-kincaid slopless/gunning-fog slopless/paragraph-length slopless/colon-dramatic -->

# Gate R0 browser oracle v1 measurement

> Evidence record. This report characterizes the fixed full-history browser
> oracle/control lane. It does not establish candidate browser performance,
> choose a production restore design, or set a performance budget.

## Scope and revisions

The measured code is commit
`d17da6b4671901171afe56cfb5384c38462bf9e4`, based on
`main@588ab1beedac892c0bc647fc972e5d11bb0a5f54` after the per-document
local durability queue in #1337. The checked-out EGW revision is
`9d71c86699322ca1d365e46f33b3ca71fd209859`.

The browser is pinned to Chromium `149.0.7827.55`. The immutable browser
fixture catalog SHA-256 is
`c664b138653cf976482be772458eeff07e8c85d48c7fe57ee841d50ce286dee8`.
The lane changes no production public API, archive, wire format, or storage
operation.

## Build and procedure

The canonical runner executes the required release sequence:

```bash
NEW_MOON_MOD=0 moon build --target js --release
./scripts/install-local-warren.sh
(cd apps/loomark && ../../_build/tools/bin/warren build)
```

The two release Worker entries are staged beside Warren's generated static
site. For each of the five fixed complete-v1 archives, one navigation warms the
browser/build cache. Each of 20 measured samples then:

1. restores the original checked and browser-verified archive bytes to the
   production IndexedDB slot;
2. reloads the release Warren page and waits for the exact browser-normalized
   expected text;
3. appends U+005A at the restored textarea's UTF-16 end;
4. waits until the production persistence path commits a complete archive with
   the expected post-edit text and exactly 1,001 operations.

The browser context is fresh per fixture. The archive is reset before every
measured reload, so an earlier edit cannot grow a later sample's history.
Raw values are retained in `candidate-results.json`; nearest-rank p50 selects
rank 10 and p95 rank 19 for `n = 20`.

## Clock boundaries

| Clock | Browser-owned boundary |
|---|---|
| `storage_read_ms` | production archive-store readonly transaction creation through transaction completion |
| `archive_open_ms` | storage-read completion through exact expected-text observation |
| `restore_to_text_observed_ms` | navigation performance time origin through exact expected-text observation |
| `first_edit_ms` | immediately before the real keyboard edit through observation of its committed complete archive |
| `first_edit_storage_write_ms` | first-edit archive readwrite transaction creation through transaction completion |
| `restore_plus_first_edit_ms` | navigation performance time origin through observation of the committed first edit |

`archive_open_ms` is deliberately a black-box remainder. It includes archive
decode, full-history admission/materialization, model adoption, and presentation
to the observed textarea; it does not claim a new public
`MarkdownEditor::open` lifecycle milestone. Observation-only IndexedDB reads
are separately classified and excluded from the application read interval.

All five source fixtures are valid archives, so no recovery screen is expected
and fallback/error timing is recorded as
`not_applicable: valid_fixture_no_recovery`. A missing applicable clock,
invalid interval ordering, incomplete read/write transaction, timeout, or
sample-count mismatch is `measurement_failure` and exits 40.

## Full-history oracle result

Times are milliseconds.

| fixture | storage p50 / p95 | archive-open p50 / p95 | restore-text p50 / p95 | first-edit p50 / p95 | edit-write p50 / p95 | restore+edit p50 / p95 |
|---|---:|---:|---:|---:|---:|---:|
| `S-linear-1000` | 2.7 / 6.0 | 151.5 / 242.5 | 229.7 / 320.3 | 143.6 / 176.2 | 5.5 / 22.3 | 395.8 / 495.9 |
| `S-distributed-1000` | 2.6 / 5.7 | 160.8 / 272.4 | 238.8 / 365.6 | 157.8 / 174.3 | 5.8 / 7.9 | 416.6 / 565.6 |
| `S-tombstone-1000` | 2.1 / 5.1 | 128.2 / 239.6 | 204.6 / 325.8 | 146.2 / 162.3 | 5.8 / 14.9 | 363.3 / 478.1 |
| `S-replacement-1000` | 2.3 / 5.7 | 203.2 / 220.6 | 284.2 / 299.9 | 135.0 / 159.5 | 5.7 / 21.7 | 431.4 / 469.3 |
| `S-unicode-1000` | 2.6 / 4.9 | 152.4 / 243.9 | 226.9 / 326.8 | 144.2 / 152.8 | 5.5 / 7.4 | 408.4 / 487.6 |

IndexedDB transaction time is small relative to the black-box archive-open
remainder. This measurement therefore remains consistent with the earlier
finding that full-history decode/admission/materialization, rather than the
storage read itself, dominates restored readiness. The table is a control
baseline. It cannot decompose every operation inside `archive_open_ms`.

## Candidate and gate outcome

`candidate-results.json` contains five full-history oracle measurement rows and
five rows each for Candidate A and Candidate C. A/C rows contain no fabricated
samples and are explicitly:

```text
outcome: not_applicable
reason: product_restore_seam_absent
```

The run passed with exactly the canonical ten artifacts,
`implementation_complete: true`, and `blocked_obligations: []`. This completes
the browser-measurement obligation owned by #1289; it does not make Candidate
A or C promotable and does not authorize a production restore seam.

Selected local artifact hashes:

| artifact | SHA-256 |
|---|---|
| `manifest.json` | `4b6be0dc346445bda7ced3244a61d11c599938b03f55de57949625b0cf2e0e17` |
| `result.json` | `3d3ce380f6a834f40fff43c570f530f02bf1ee86f798e4b198cac68206a98721` |
| `candidate-results.json` | `77bcbb02a9228a90b7a797e8092e56e5f82f3ee1a40cef1688b88b6dff3f7859` |
| `operation-matrix.jsonl` | `5e60d460875b595546aaa066aa3ce55fd875123860de3669cad5401a2e6f48ab` |
| `validation.log` | `b072b2cb5227c26b81a1812bd53d4d7c963b3c9f2537db22f1c95e22384348e1` |

The targeted clean run completed in 2:19.53 with whole-runner maximum RSS
976,196 KiB. That process-tree value is supplementary harness evidence and is
not a candidate consumer `peak_rss_bytes` sample.

## Validation and reuse

- five fixtures × one warm-up + 20 measured restore/edit samples: pass;
- exact-ten artifact inventory: pass;
- browser measurement schema and interval-order unit tests: pass;
- standalone and development-host TypeScript checks: pass;
- canonical artifact contract tests: pass;
- Nushell IDE parse check: pass;
- independent post-#1337 review: pass.

The browser shell reuses the existing production IndexedDB database/store/key,
Warren build, `performance.now()`, IndexedDB transaction completion, and exact
archive/text/history verification. No MoonBit definition or generated
interface changed. Remaining imperative code is limited to browser navigation,
storage instrumentation, keyboard input, and persistence observation; summary
validation and nearest-rank selection are deterministic functions with focused
unit tests.

The repository pre-commit MoonBit check still fails on the existing 22 vendored
deprecation warnings promoted to errors in `deps/alga`, `deps/loom`, and
`deps/svg-dsl`; no changed file contributes a MoonBit warning.

<!-- textlint-enable slopless/coleman-liau slopless/flesch-kincaid slopless/gunning-fog slopless/paragraph-length slopless/colon-dramatic -->
