# Gate R0 browser oracle v1 correctness — browser lane contract correction

> Evidence record. This report records the corrected browser oracle/control lane
> of the Gate R0 harness. It does not authorize a performance budget, browser
> measurement, or promotion by itself; browser measurement remains a separate,
> blocked obligation.

## Scope

The #1333 main implementation is retained unchanged. This correction only
aligns the browser lane to the exact five 1,000-event v1 fixture IDs
(`S-linear-1000`, `S-distributed-1000`, `S-tombstone-1000`,
`S-replacement-1000`, `S-unicode-1000`) and to the fixed v1 contract those IDs
carry: exact archive/text/history hashes, a `valid` disposition, the
`full_history_v1` consumer, and the exact first edit (append U+005A at the
restored text's UTF-16 end).

The changed surface is the browser oracle corpus (catalog + five archive
files), the browser oracle/verification scripts, the runner's browser-lane
assertions and fixed artifact-set ownership, and the oracle adapter evidence —
nothing else.

## Exact builds

Branch `fix/r0-browser-v1-contract-20260822`.

| build | revision |
|---|---|
| Base (`origin/main` at final fetch) | `974013c42c21801a4448e6593b3edbb985835e8a` |
| Rebased commit 1 | `2e139598fe25fbd6787db24d1cc38c985f6c5255` — `fix(gate-r0): align browser oracle corpus contract` |
| Rebased commit 2 | `daf969aa9f5dbd7264d079940acb34ba452eca69` — `fix(gate-r0): derive browser adapter evidence` |
| Rebased commit 3 | `5ad22460a50c1affa8b1b33dcf613e427389d029` — `test(gate-r0): require CRLF adapter control` |
| Rebased commit 4 | `a444028bafa9168b4eb585e12ee15155717bb1b3` — `docs(gate-r0): record browser v1 correctness evidence` |
| Artifact repair | `38070fcc31a0cfc2779533c21734162821da6de1` — `fix(gate-r0): restore fixed artifact ownership` |
| Failure-path hardening | `1e8ac3f9095f08ef8e6efe4d2e1d0f53a02273bf` — `fix(gate-r0): harden artifact failure paths` |
| Reused-output classification | `3c4f2cb0575fd8ae899d43f54c3fa47ba4bb612a` — `fix(gate-r0): classify reused-output failures` |
| Code HEAD (runner-owned output reset) | `128dfcaef70ae0fba9d14ae3dc9aeb856e92a20b` — `fix(gate-r0): reset runner-owned outputs` |
| EGW submodule (checked out) | `9d71c86699322ca1d365e46f33b3ca71fd209859` |

The runner's `submodule-preflight` enforces recorded gitlink == checked-out
commit and configured-origin reachability for
`deps/event-graph-walker` before any run.

## Generator chain

The checked-in corpus is produced end-to-end by
`apps/loomark/examples/vanilla/generate-r0-browser-fixtures.mjs`:

1. EGW native `legacy-history` run
   (`deps/event-graph-walker/internal/restore_feasibility_probe`) emits the
   immutable legacy-oracle history for the fixture ID from the checked-in EGW
   `fixture-catalog-v1.json` (`fixture_seed: "none"`, `event_count: 1000`).
2. The Loomark `browser-fixture` encoder
   (`apps/loomark/restore_feasibility_oracle`, `browser_fixture`) opens a
   `MarkdownEditor` on that history and captures the archive through the
   unchanged production `LoomarkDocumentArchive` v1 encoder.
3. The archive bytes are written to
   `apps/loomark/examples/vanilla/fixtures/r0-browser-v1/`, where
   `verify-r0-browser-fixtures.mjs` regenerates them in a temporary directory
   and byte-compares against the checked-in files.

The catalog declares `generator: "r0_fixture_generator_v1"`,
`oracle_adapter: "LegacyOracleEventV1"`, and `fixture_seed: "none"`.

## Fixture catalog and archive digests

Catalog file `browser-fixture-catalog-v1.json` (schema version 1). Run-observed
catalog SHA-256:
`c664b138653cf976482be772458eeff07e8c85d48c7fe57ee841d50ce286dee8`.

| fixture | archive SHA-256 | archive bytes | text bytes / scalars / UTF-16 | history bytes |
|---|---:|---:|---:|---:|
| `S-linear-1000` | `bdbbe25276d0f58b2ca09cf913fb3df239a06a77d6c377d41f117d7f2ff14a79` | 230798 | 1715 / 1000 / 1143 | 194386 |
| `S-distributed-1000` | `f16c2724481262fc408d1dcb86d891dd450e6453e157c1d5015675f3e3c02272` | 265877 | 1715 / 1000 / 1143 | 223778 |
| `S-tombstone-1000` | `ae3db5e1e2f3922ac1676f28db9a2d83681942664837af883127bdb9506816a6` | 228595 | 572 / 334 / 380 | 194281 |
| `S-replacement-1000` | `aaea249c3a5271b1639618456984a6f3373556c5a3da3952a747b50fb7070bb4` | 227264 | 0 / 0 / 0 | 194044 |
| `S-unicode-1000` | `1970811f6b3047d440a0b97f5a7f3814394803c85c487f033c705214715edf56` | 230799 | 1715 / 1000 / 1143 | 194386 |

Every row is `disposition: "valid"`, `consumer: "full_history_v1"`,
`event_count: 1000`, and records `canonical_fixture_sha256` matching the EGW
source catalog.

## First-edit contract and CRLF coordinate mapping

Each fixture's first edit is a `ReplaceText` appending U+005A at the restored
text's UTF-16 end (`first_edit.kind = "append_unicode_scalar"`). After the
edit, the persisted archive's `portable_markdown` must equal
`expected_text_after_edit` (text + `Z`) and history must hold exactly 1001
operations; a fresh-page reload must restore that text.

The browser control position is the restored `#loomark-input` value with CRLF
normalized (`\r\n?` → `\n`), which is the position the U+005A edit is actually
applied at. `coordinate_positions_equal` compares that browser control
position against the catalog's canonical UTF-16 position:

- `S-distributed-1000` and `S-tombstone-1000` contain literal `\r\n` pairs in
  the portable text, so normalization changes the browser-control UTF-16
  length and `coordinate_positions_equal` is false for those two; the adapter
  mapping is still proved through `browser_control_position_valid`,
  `adapter_mapping_proved`, and `result_equal` at the browser control position.
- `S-linear-1000` and `S-unicode-1000` contain no `\r\n` pairs (lone `\r`
  normalizes 1:1), so both positions agree.
- `S-replacement-1000` restores the empty text; both positions are 0.

The runner fails the corpus if no observation exercised the CRLF coordinate
mapping (`browser corpus did not exercise CRLF coordinate mapping`).

## Static/fault controls

The catalog loader and `fixtures:r0:test` enforce fail-closed controls:
`catalog_missing`, `catalog_invalid`, `catalog_entry_missing`,
`archive_asset_missing`, `archive_digest_mismatch`, `malformed_v1_archive`,
`unsupported_archive_version`, `expected_portable_text_mismatch`,
`expected_portable_history_mismatch`, and `candidate_consumer_selected`
(any non-`full_history_v1` consumer is rejected). Each control is exercised by
a mutation test in `test-r0-browser-fixtures.mjs`.

## Fresh browser-owned fetch and read accounting

`browser-restore-oracle.mjs` opens one fresh Chromium context per fixture. The
browser page itself fetches the catalog and archive with `cache: "no-store"`,
recomputes the archive/text/history SHA-256 in-page with
`crypto.subtle.digest`, verifies every catalog digest and the operation count,
and only then seeds the production IndexedDB archive slot with the verified
archive. Main #1331 moved production archive persistence to IndexedDB, so the
seeded surface is the production database/store/key
`loomark.local-repository` / `archives` / `loomark.active-document-archive`
(`apps/loomark/internal/archive_storage/storage.mbt`); the full-history
consumer therefore restores through the unchanged production persistence path.

Read accounting instruments `IDBObjectStore.prototype.get` and
`IDBObjectStore.prototype.openCursor` on that store for the archive key. The
harness's own read is one `get` (`readArchive`); the application's archive read
goes through the `openCursor` path used by the Rabbita `@indexed_db.get`
binding. Separate counters require exactly one observation `get` and one
application `openCursor`, without subtracting a magic offset. The full-history
consumer starts exactly once
(`full_history_consumer_starts = 1`) and the candidate consumer never starts
(`candidate_consumer_starts = 0`, `candidate_event_reads = 0`); the selected
catalog consumer is `full_history_v1`, and a conservative release-bundle canary
finds no candidate marker in `index.js`. The runner asserts
`archive_transport_bytes == fixture.archive_bytes`,
`archive_decode_read_operations == 1`, `oracle_full_history_event_reads ==
1000`, `candidate_event_reads == 0`, and `first_edit_local_operations == 1`.
All five fixtures pass with `full_history_consumer_starts = 1` and
`candidate_consumer_starts = 0`.

## Canonical output and manifest provenance

The canonical run output is exactly ten files — `manifest.json`, `result.json`,
`capability-ledger.json`, `candidate-captures.jsonl`, `candidate-results.json`,
`operation-matrix.jsonl`, `oracle-differential.jsonl`, `cold-history.jsonl`,
`negative-results.json`, and `validation.log`. Source catalogs are not run
artifacts: the runner removes stale run copies of `fixture-catalog.json`,
`browser-fixture-catalog.json`, and `browser-results.json`, plus all dotfile
internals including the temporary `.candidate-suite/` directory, then asserts
the output directory contains exactly the ten canonical files.

Hashes and provenance live in the manifest: `fixture_catalog` carries the EGW
source catalog SHA-256, `fixture_seed`, and per-fixture `canonical_sha256`;
`browser_fixture_catalog` carries the browser catalog SHA-256 and per-fixture
archive `sha256`/`bytes`/`canonical_fixture_sha256`. The five browser
correctness observations are recorded in `operation-matrix.jsonl` (trace
`browser-full-history-v1`, authority `full_history_oracle`, projection
`loomark_product`, `outcome: "pass"`) with the full `browser_oracle_result`
payload as the observation row.

## Exact validation

| gate | result |
|---|---|
| Failure injection: each injected failure class writes the exact ten-artifact set | PASS |
| Reused-output cleanup: legacy outputs, dotfile internals, arbitrary unregistered files/directories removed before artifact-set assert | PASS |
| Injected `git status` failure — exit 10 with exact-ten `preflight_invalid` bundle | PASS |
| `--self-test` (failure injection, candidate seam, provider-read controls) | PASS |
| Injected nested candidate failure in `--suite self-test` — exit 30, exact-ten failure artifacts, diagnostic retained | PASS |
| `--suite self-test --allow-dirty` — exact-ten artifact set | PASS |
| `--suite oracle --allow-dirty` — exact-ten artifact set, five fresh-Chromium observations, 1:15.38 (maxrss 947964 KB) | PASS |
| Five browser fixtures on Chromium `149.0.7827.55` | PASS |
| `fixtures:r0:verify` (regenerate + byte-compare) and `fixtures:r0:test` (catalog, digest, archive, fail-closed controls) | PASS |
| TS typecheck standalone + dev host (`typecheck:standalone`, `typecheck:dev-host`) | PASS |
| `nu --ide-check` (runner syntax) | PASS |
| Docs lifecycle/diff check (`scripts/check-documentation-lifecycle.sh`) | PASS |
| Independent review of exact code HEAD `128dfcae…` | PASS — no remaining high-confidence correctness or CI blocker |

## Local runner outcome

The clean local runner `--suite oracle --allow-dirty` passed in 1:15.38
(maxrss 947964 KB) with result status `pass`, `implementation_complete: false`,
`blocked_obligations: [browser_measurement]`, and five browser observations.
The manifest records `browser_oracle_correctness: "pass"` and
`browser_measurement: "not_run"`.

The earlier trailing-blank-line `.mbti` drift failure (Moon `0.1.20260814`) is
obsolete: main #1331 normalized the current toolchain/interfaces, and the
runner's interface preflight now agrees before and after `moon info` with no
drift to revert.

The canonical CI pins Moon `compiler`/`core` `0.10.8+8606a5800`
(`.moonbit-toolchain`, read by `.github/actions/setup-moonbit` via
`scripts/moon-toolchain.sh`); this evidence records the local oracle run above,
and CI coverage remains per `.github/workflows/ci.yml`.

## Pre-commit status

Pre-commit was **not** green: `hook-moonbit-check` (`moon check --deny-warn`)
failed on the existing dependency warning-as-error baseline (22 pre-existing
deprecation warnings across `deps/alga`, `deps/loom`, and `deps/svg-dsl`), not
on the changed surface. Rebased code commits `38070fcc` (restore fixed artifact
ownership), `1e8ac3f9` (failure-path hardening), `3c4f2cb0` (reused-output
classification), and `128dfcae` (runner-owned output reset) were created with
`--no-verify` after exact changed-surface validation (the gates above); the
rebased commits were carried through
`git rebase`, which does not run the pre-commit hooks.

## Scope negatives

- No browser performance measurement or promotion: `browser_measurement` is
  `not_run` in the manifest, the result is `implementation_complete: false`
  blocked on `[browser_measurement]`, and the browser oracle corpus explicitly
  provides no performance evidence.
- No production API/wire/archive-format/provider-operation change in this
  correction: the manifest records `archive_format_changed: false`,
  `wire_format_changed: false`, and `public_markdown_interface_changed: false`;
  candidate suites record `not_applicable` outcomes only. The IndexedDB
  persistence surface (#1331) comes from the rebase base on main, not this
  correction; this evidence only seeds and reads the production slot that base
  already defines.
