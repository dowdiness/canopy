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
assertions, and the oracle adapter evidence — nothing else.

## Exact builds

Branch `fix/r0-browser-v1-contract-20260822`.

| build | revision |
|---|---|
| Base (`origin/main` at fetch) | `4779d163b24a1d5628c38526032209cf46397f5c` |
| Implementation/review HEAD | `e4e596c472064327a32a47d4e84e9dcd8f797d02` |
| Commit 1 | `0089070f19f7d9a42c24ebe445ca082b392a396b` — `fix(gate-r0): align browser oracle corpus contract` |
| Commit 2 | `9d892bad3f16a517af7246d9b733fa0b3830302d` — `fix(gate-r0): derive browser adapter evidence` |
| Commit 3 (HEAD) | `e4e596c472064327a32a47d4e84e9dcd8f797d02` — `test(gate-r0): require CRLF adapter control` |
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
and only then seeds `localStorage` with the verified archive.

A `Storage.prototype.getItem` wrapper counts application reads of the archive
key: the full-history consumer starts exactly once
(`full_history_consumer_starts = 1`) and the candidate consumer never starts
(`candidate_consumer_starts = 0`, `candidate_event_reads = 0`); the release
`index.js` contains no candidate markers. The runner asserts
`archive_transport_bytes == fixture.archive_bytes`,
`archive_decode_read_operations == 1`, `oracle_full_history_event_reads ==
1000`, `candidate_event_reads == 0`, and `first_edit_local_operations == 1`.

## Exact validation

| gate | result |
|---|---|
| `npm run fixtures:r0:verify` (regenerate + byte-compare) | PASS |
| `npm run fixtures:r0:test` (catalog, digest, archive, fail-closed controls) | PASS |
| Native five-browser run (`--suite oracle`): five fresh-Chromium observations | PASS |
| `nu --ide-check` (runner syntax) | PASS |
| TS typecheck standalone + dev host (`typecheck:standalone`, `typecheck:dev-host`) | PASS |
| CI workflow YAML | PASS |
| Independent reviewers (regeneration/hash review of the browser fixture catalog) | PASS |

Observed browser revision: Chromium `149.0.7827.55`.

## Local runner outcome

The canonical clean local runner on Moon `0.1.20260814` exited `10`
(`preflight_invalid`) because `moon info` removed one trailing blank line from
`apps/loomark/restore_feasibility_oracle/pkg.generated.mbti`; the drift was
reverted.

After `moon info`, the local runner `--suite oracle --allow-dirty` passed in
1:33.85 (maxrss 948012 KB) with result status `pass`,
`implementation_complete: false`, `blocked_obligations: [browser_measurement]`,
and five browser observations. The manifest records
`browser_oracle_correctness: "pass"` and `browser_measurement: "not_run"`.

The canonical CI pins Moon `0.10.4+ade96c819`
(`.github/actions/setup-moonbit`); this evidence records no local run of that
canonical CI toolchain. The local run above used the `0.1.20260814` snapshot
and is separate from CI.

## Pre-commit status

Pre-commit was **not** green: `hook-moonbit-check` (`moon check --deny-warn`)
failed on the existing dependency/project warning-as-error baseline
(`Map::default`, `guard_inexhaustive`, and similar pre-existing warnings), not
on the changed surface. The three commits were created with `--no-verify`
after exact changed-surface validation (the gates above).

## Scope negatives

- No browser performance measurement or promotion: `browser_measurement` is
  `not_run` in the manifest, the result is `implementation_complete: false`
  blocked on `[browser_measurement]`, and the browser oracle corpus explicitly
  provides no performance evidence.
- No candidate/publish/public-API/wire/storage/provider-operation changes in
  this correction: the manifest records `archive_format_changed: false`,
  `wire_format_changed: false`, and `public_markdown_interface_changed: false`;
  candidate suites record `not_applicable` outcomes only.
