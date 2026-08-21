# Gate R0: Editable Branch Restore Feasibility

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/1288>

The issue owns active status and backlog membership. This plan owns the test-only execution contract and links back to the issue above.

Related issue: [#1281 — avoid full text snapshots during remote admission reconciliation](https://github.com/dowdiness/canopy/issues/1281).

The relationship is coordination, not a dependency: #1281 covers resident-authority remote admission; this gate covers cold archive restore and editable-branch hydration. Both must reuse any accepted authority-owned effect/receipt boundary rather than inventing parallel Markdown-side authority logic.

## Authoritative decision sources

This plan is ready for #1319's decision-complete handoff review; implementation begins only after that review passes. All architectural vocabulary, candidate roles, matrix rows, morphology corpus, resource profile, accounting contract, artifact ownership, measurement procedure, outcome rules, and selection rules are owned by the accepted R0 research contracts. This plan states the executable acceptance contract, copies the exact runner schema/process details that #1317 assigns to #1318, partitions the implementation slices, and links larger decision proofs to their authoritative sections.

| Contract | Wayfinder | Owns |
|---|---|---|
| [Restore architecture reassessment](../research/2026-08-19-egwalker-r0-restore-architecture-reassessment.md) | #1311 | PaperBranch state, ordinary/concurrent two-path design, Candidate B as legacy control only |
| [Capture receipt reassessment](../research/2026-08-20-r0-capture-receipt-reassessment.md) | #1312 | `R0SnapshotCommitV2`, content-addressed snapshot commit, mutable `R0PublicationRefV1`, event/graph/snapshot digest framing |
| [Cold event-graph capability boundary](../research/2026-08-20-r0-cold-event-graph-capability-boundary.md) | #1313 | Three-tier provider, `EventMetaV2`, `R0HeadRecordV2`, `WriterCommitmentV2`, MMR framing, authenticated metadata, accounting, strict-forward classification |
| [Canonical positional event/Unicode contract](../research/2026-08-20-r0-canonical-positional-event-unicode-contract.md) | #1314 | Scalar positions, UTF-16 adapter seam, `CanonicalTextEventBodyV1` algebra |
| [Concurrency replay-base proof](../research/2026-08-21-r0-concurrency-replay-base-proof.md) | #1315 | L11 one-colour waterline scan, `causal_rank_timestamp`, disposable placeholder tracker, scan counters |
| [Undelete after paper-branch restore](../research/2026-08-21-r0-undelete-after-paper-branch-restore.md) | #1316 | Target-seeded union replay, original Insert identity as planner seed, winner reproduction |
| [Evidence/performance decision contract](../research/2026-08-21-r0-evidence-performance-decision-contract.md) | #1317 | D1–D12: matrix, morphologies, resource profile, accounting, artifacts, measurement, outcome/selection rules, FC/IS |

## Why

Loomark archive reopen is dominated by history decode and causal admission, but the current production `Document` has not proved that plain text plus an exact frontier can restore an editable branch. Before choosing a checkpoint, persistent branch, active-store schema, or public Markdown API, the project needs an evidence gate that identifies the minimum authority capability and projection state required for real edits and causal admission.

## Scope

In:
- `deps/event-graph-walker/internal/{core,causal_graph,oplog}/` for package-local authority, rank, frontier, and admission evidence imported by the probe;
- `deps/event-graph-walker/internal/{document,branch,fugue}/` for production `Document`, `DeleteIndex`, and winner oracle/control evidence only; any new cross-package visibility is reviewed and must not become a production-facing API;
- `deps/event-graph-walker/internal/restore_feasibility_probe/` for one test-only executable package after a minimal preflight proves executable-package syntax in the legacy EGW module; the same package runs as native authority producer and as a fresh Node/JS candidate consumer, with no shared process or object aliases; if executable/probe/crypto exclusion cannot be proved, do not create a substitute package or widen exports: complete oracle/control artifacts remain required, A/C record `negative: capture_capability_absent` and `negative: js_consumer_capability_absent`, and candidate `moon run` commands do not run;
- `modules/canopy/editor/markdown/` for package-owned full-history façade/oracle adapters only; the current façade cannot consume a paper branch/frontier;
- `apps/loomark/archive/` and `apps/loomark/examples/vanilla/` for the true public-façade black-box restore harness;
- `scripts/test-loomark-editable-branch-restore-feasibility.nu` as the canonical Nushell gate runner;
- `scripts/README.md` and `.github/workflows/ci.yml` for the fixed runner contract and Nushell validation routing;
- fixed gate artifacts: `manifest.json`, `result.json`, `capability-ledger.json`, `candidate-captures.jsonl`, `candidate-results.json`, `operation-matrix.jsonl`, `oracle-differential.jsonl`, `cold-history.jsonl`, `negative-results.json`, and `validation.log`.

Out:
- production checkpoint/materialized-state persistence;
- portable archive, wire, public API, IndexedDB, or OPFS changes;
- history trimming, remote transport, collaboration UX, and restart undo;
- production `Verified BaseBranch` types or persistent position-to-identity tables.

## Current State

- The accepted Causal Authority residency architecture separates durable history, current text, and temporary merge state, but explicitly records implementation as incomplete.
- The current local archive is a complete v1 envelope whose history is decoded and admitted on reopen.
- The Markdown facade does not expose EGW pending identities, partial admission details, or cold-history segment reads.
- The accepted PaperBranch architecture ([#1311](../research/2026-08-19-egwalker-r0-restore-architecture-reassessment.md)) collapses the previous competing Candidate A/B/C into two runtime paths of one design: **ordinary** (direct positional editing, zero provider reads) and **concurrent** (bounded critical-region replay with disposable placeholder tracker). Candidate B remains only as measured legacy migration control.
- The accepted canonical event algebra ([#1314](../research/2026-08-20-r0-canonical-positional-event-unicode-contract.md)) uses scalar positions with UTF-16 only at the editor/capture adapter.
- The varied-history measurement shows history decode/admission dominates the measured local reopen path.

## Desired State

A test-only gate compares a full-history Markdown/EGW restore oracle with serialized candidates through two explicit seams: Markdown black-box behavior and EGW white-box authority evidence. The result identifies whether the PaperBranch ordinary path, the concurrent extension, or neither can restore an editable branch without hot-loading full history, or records a bounded negative result and the exact missing capability. Candidate B is measured as legacy control only and is never selected as canonical retained state. It also records whether any later additive opaque Markdown API is justified.

## Architecture summary

The single retained state is:

```text
PaperBranch {
  document_text                        // validated plain text, UTF-8 bytes
  event_graph_frontier                 // exact ranked heads from SyncMessage.heads
  validated_capture_receipt            // R0SnapshotCommitV2 (test-only content-addressed commit)
}
```

`validated_capture_receipt` is the accepted `R0SnapshotCommitV2` from [#1312](../research/2026-08-20-r0-capture-receipt-reassessment.md): exact ranked head records and writer commitments remain O(heads + writers) resident so the first local event can allocate its causal rank without a provider read. The normal branch contains no per-character causal IDs, tombstone table, Fugue tree, or IndexedState.

Two runtime paths share this state:

- **Ordinary path (Candidate A):** plain text plus frontier, with direct positional event generation/application. Zero provider reads for receipt validation, first local edits, and fully hot strict-forward admission. See [#1311 §2–§3](../research/2026-08-19-egwalker-r0-restore-architecture-reassessment.md).
- **Concurrent path (Candidate C):** critical-version/conflict-zone partial replay with disposable internal state. Bounded authenticated metadata and payload reads. See [#1315](../research/2026-08-21-r0-concurrency-replay-base-proof.md) for the replay-base proof and [#1316](../research/2026-08-21-r0-undelete-after-paper-branch-restore.md) for undelete after restore.

Candidate B remains a bytes-only disposable legacy Fugue/IndexedState cache, measured as control evidence only. It cannot be promoted to canonical retained state.

`ClosedTail` and persistent position-to-identity tables are removed from the canonical vocabulary. Strict-forward classification requires semantic-reference coverage ([#1313](../research/2026-08-20-r0-cold-event-graph-capability-boundary.md)); concurrency uses bounded replay from a proven critical base.

## Fixed runner schema and process contract

The runner owns these exact v1 artifact fields; candidate/oracle streams remain separate.

| Artifact | Required content |
|---|---|
| `manifest.json` | source/submodule/tool/browser revisions; clean base; fixture catalog, `r0-codec-golden-vectors.json`, and browser-fixture catalog/archive revisions/hashes (missing/mismatch is nonzero `harness_failure`/`evidence_missing`, never a candidate negative) and per-fixture `fixture_seed` (`"none"` for the formula generator); resource profile; samples/warm-ups; target/runtime; `shared_effect_boundary`; measurement capabilities; baseline failures; `selected_hash_boundary`; EGW configured-origin reachability and parent gitlink; preflight records: exact executable syntax/commands, native+JS crypto/vector result, source/tool/crypto versions, pass/fail |
| `result.json` | `schema_version: 1`; gate status; fixed failure class/exit code; candidate/path outcomes; selected paths or `none`; artifact paths and SHA-256 values |
| `capability-ledger.json` | each expanded matrix row → minimum authority tier, projection state, expected path/reads, demonstrated result |
| `candidate-captures.jsonl` | native-owned capture envelope; content/publication IDs; component byte counts/hashes; canonical candidate bytes; capture/rebuild/maintenance timing; producer revision; no handles |
| `candidate-results.json` | raw native/JS/browser samples; p50/p95/max and selected rank; pair/order; ratios; size/RSS summaries; pass/negative/not-applicable; deterministic selection |
| `operation-matrix.jsonl` | one expanded row/sample with expected/actual classification, observation hashes, counters, and outcome |
| `oracle-differential.jsonl` | seam-owned candidate/oracle observations, normalized fields, equality, detected-before-mutation flag |
| `cold-history.jsonl` | provider-call records and phase totals with separate candidate/oracle streams, all #1317 D6 counters/fallback fields, and positive controls |
| `negative-results.json` | fixed negative reason, first failed obligation, fallback evidence, missing capability, observed/limit values, reproducible case/command |
| `validation.log` | raw preflight (exact executable syntax/commands, native+JS crypto vector result, source/tool/crypto versions, pass/fail), hash/catalog review, Nushell, EGW native/JS/publish, MoonBit, browser/TS, `.mbti`, submodule reachability, final-gate, and independent-review evidence |

The runner accepts `--suite self-test|oracle|ordinary|concurrency|legacy|all`; default is `all`. Every suite still writes the complete artifact set, marking unrelated rows `not_applicable` with reason. Mapping is fixed: CI=`self-test`, #1289=`self-test` + `oracle`, #1291=`ordinary`, #1292=`concurrency`, #1290=`legacy`, #1293=`all`.

The canonical fixture source is:

```text
deps/event-graph-walker/internal/restore_feasibility_probe/fixtures/fixture-catalog-v1.json
```

The runner resolves this path from repository root; canonical runs provide no override. `fixture-catalog-v1.json` is checked-in source input, not an eleventh run artifact. Catalog review runs the exact command below, compares bytes, and records checked-in/regenerated SHA-256, generator/source revision, reviewer identity, verdict, and candidate-slice blocking status in #1289 and `validation.log`. Any mismatch keeps #1290/#1291/#1292 blocked.

```bash
cd deps/event-graph-walker
NEW_MOON_MOD=0 moon run --quiet --release --target native \
  internal/restore_feasibility_probe -- generate-catalog \
  --output /tmp/fixture-catalog-v1.regenerated.json
cmp internal/restore_feasibility_probe/fixtures/fixture-catalog-v1.json \
  /tmp/fixture-catalog-v1.regenerated.json
sha256sum internal/restore_feasibility_probe/fixtures/fixture-catalog-v1.json \
  /tmp/fixture-catalog-v1.regenerated.json
```

The probe command contract is:

```bash
cd deps/event-graph-walker
NEW_MOON_MOD=0 moon run --quiet --release --target native \
  internal/restore_feasibility_probe -- produce \
  --catalog internal/restore_feasibility_probe/fixtures/fixture-catalog-v1.json \
  --case-id <case>

NEW_MOON_MOD=0 moon run --quiet --release --target js \
  internal/restore_feasibility_probe -- consume \
  --capture-jsonl <output-dir>/candidate-captures.jsonl \
  --catalog internal/restore_feasibility_probe/fixtures/fixture-catalog-v1.json \
  --case-id <case>
```

The runner invokes these `moon run --release` commands directly; separate `moon build --release` validation only prebuilds/checks artifacts and never substitutes a hand-written generated-JS path. The native process must exit successfully before Nushell validates and atomically appends its stdout record; only then may the fresh JS process start. Protocol stdout contains JSONL only; diagnostics use stderr and any non-JSON stdout is `harness_failure`. Each `candidate-captures.jsonl` case record carries `candidate_bytes_base64` (RFC 4648, no whitespace), `candidate_byte_length`, SHA-256, `snapshot_commit_id`, and record-schema tag plus distinct `provider_fixture_bytes_base64`, byte-length, and SHA-256 fields; the verification projection is validation-only and never enters the artifact. The JS process reads only that file/case plus the pinned read-only fixture catalog (`--catalog internal/restore_feasibility_probe/fixtures/fixture-catalog-v1.json`) and emits observations to stdout; Nushell validates/routes them into the fixed artifacts. The catalog SHA is bound in `manifest.json`; a missing or mismatched catalog is a nonzero `harness_failure`/`evidence_missing`, never a candidate negative. The pinned catalog and provider fixture are test inputs, exempt from `resident_candidate_bytes`; provider data is reachable only through the provider shell/API. The catalog verifier compares completed candidate-core observations with expected bytes/hashes and never supplies planner inputs or expected results to that core. An in-process substitute is supplementary only.

The native producer's stdout owns the final candidate bytes, the separate provider fixture bytes, a verification projection, and the lengths/hashes/`snapshot_commit_id`. Nushell validates and reconstructs the exact producer bytes, writes `candidate-captures.jsonl` without the verification projection, and advances the publication ref last. There is no final-byte ownership ambiguity: native produces the exact bytes, Nushell validates and routes them without rewriting, and the fresh JS consumer receives the published bytes unchanged.

The fixture generator constructs `CanonicalTextEventV1` / `CanonicalTextEventBodyV1` records directly from the #1314 positional algebra. It must not derive canonical bodies from current Fugue-origin `Op`. For oracle comparison only, this plan registers the test-only name `LegacyOracleEventV1`, owned by #1289; the native producer lowers each canonical event at its declared parent frontier through that separately tagged adapter backed by the current production `Document`; Fugue origins remain adapter-only and never enter canonical bytes/digests. The catalog commits canonical bytes and the expected adapter observation hashes.

`selected_hash_boundary` is fixed to `executable_crypto_dependency`: the probe uses `moonbitlang/x/crypto` on native and JS, while Nushell independently recomputes SHA-256 from emitted canonical records. The one-archive, probe/crypto-exclusion, extracted-`--frozen` publish proof is mandatory before any positive candidate evidence is accepted; until it passes, candidate slices record bounded negatives. If it cannot be proved, do not move hashing solely to Nushell or widen production packages; #1289 records `capture_capability_absent`/`js_consumer_capability_absent`, and candidate slices produce bounded negatives.

Nushell owns publication order: independently reconstruct and byte-compare the native-owned immutable V2 commit/sidecar records, write the producer bytes unchanged, read them back, then advance `R0PublicationRefV1` last with expected-old compare-and-swap semantics. Three repeated captures must produce identical immutable bytes/content IDs; publication sequence/provenance is compared separately. #1291 consumes and validates this lifecycle but does not redefine it.

## Implementation partition

Implementation proceeds in six slices with explicit dependencies. Each slice maps to a child issue.

### Slice 1: Runner + independent oracle → #1289

**Precondition:** #1319 has verified this rewritten handoff is decision-complete. #1289 is blocked by #1319.

Build the canonical Nushell runner, the bytes-only process boundary, the full-history oracle, positive controls (X-01–X-05), and the fixed artifact set. This slice establishes the measurement infrastructure that all subsequent slices depend on.

**Acceptance:**
- Runner writes exactly the fixed artifact filenames and exits non-zero for the fixed failure classes.
- Full-history oracle produces deterministic text, frontier, and operation observations.
- Positive controls prove that provider read counters, `scan_records_visited`, and byte counters record known-positive reads before any zero-read assertion can pass.
- Bytes-only boundary: candidate state crosses a process/Worker boundary with no source object or mutable authority alias retained.
- `internal/restore_feasibility_probe/fixtures/fixture-catalog-v1.json` generated from #1317 D4's byte-complete `fixture_id`/document/writer/sequence/parent/body/position/target/merge/replay-order rules, with fully expanded canonical event bytes, legacy-adapter observation hashes, and SHA-256 values.
- An independent catalog review recorded in #1289 verifies every generated identity, parent, position, body, scale, and hash against `r0_fixture_generator_v1`; Slices 2–4 remain blocked until that review passes.
- Checked-in `apps/loomark/examples/vanilla/fixtures/r0-browser-v1/browser-fixture-catalog-v1.json` plus its five fixed complete-v1 archive files records exact paths, archive/text hashes, `disposition: "valid"`, and append-U+005A first-edit expectations; independent regeneration/hash review passes before browser measurement.
- Checked-in `internal/restore_feasibility_probe/fixtures/r0-codec-golden-vectors.json` (codec primitives/body/meta/MMR/snapshot/candidate/provider empty and nonempty vectors, per the [cold capability boundary](../research/2026-08-20-r0-cold-event-graph-capability-boundary.md#provider-fixture)) byte/hash-matches on native, fresh JS, and independent Nushell before catalog generation; `manifest.json` and `validation.log` record the exact preflight executable syntax/commands, native+JS crypto vector result, source/tool/crypto versions, and pass/fail.

### Slice 2: PaperBranch ordinary restore → #1291

**Dependencies:** Slice 1

Evaluate the ordinary paper-branch path: capture validated text + exact ranked heads + writer commitments, restore, local edits, strict-forward admission.

**Acceptance:**
- Receipt validation rows R-01–R-04 pass: valid/empty, corrupt, stale/mixed publication, bytes-only destruction and two fresh consumers.
- R-05 (duplicate declared parent) records canonical-profile negative.
- First local insert/delete rows L-01–L-03 pass with zero provider reads across all required Unicode forms.
- L-04 (rank exhaustion) records pure `rank_exhausted` negative.
- L-05 (pre-capture undo without receipt) records [#1316](../research/2026-08-21-r0-undelete-after-paper-branch-restore.md) bounded negative.
- Hot strict-forward rows F-01–F-02 pass with zero existing-provider reads; F-04 uses authenticated metadata only and zero payload/full-history reads. F-03 hot undelete belongs to Slice 3 because zero cold reads still require the C tracker/winner machinery.
- D-01 proves Tier-0 non-membership with no provider call; D-02–D-06 use only the exact authenticated metadata permitted by their row and zero payload/full-history reads.
- All ordinary rows execute on both native and JS; missing JS is `negative: js_consumer_capability_absent`.

### Slice 3: Bounded concurrency + cold undelete → #1292

**Dependencies:** Slices 1, 2; catalog review must already pass

Evaluate the concurrent extension: waterline scan, disposable tracker, colour classification, resource fuses, and target-seeded undelete replay. Concurrency and undelete remain separate C/U matrix groups inside this one ticket because #1316 deliberately reuses #1315's same target-seeded union scan and tracker.

**Acceptance:**
- F-03 hot undelete executes the same disposable tracker/winner machinery with zero existing-provider reads when complete hot replay evidence is supplied.
- Concurrency rows C-01–C-10 execute bounded replay or record their specified negative/fallback.
- At least `C-short` 10k, `A-long` 10% conflict, and U-01/U-02/U-03 execute the tracker rather than full fallback.
- Replay-required U-01–U-04 execute the tracker; U-05–U-07 follow their specified semantic-reject, pending/fallback, indexed-replay, or negative outcomes per [#1316](../research/2026-08-21-r0-undelete-after-paper-branch-restore.md).
- Resource fuses (`r0_resource_profile_v1`) are wired independently; C-09 exact-cap succeeds where otherwise valid and cap+1 falls back. Canonical runs may lower a limit only in C-09 fault-injection rows and never raise one through CLI/environment overrides; C-09 injects exact monotonic elapsed values directly into the reducer, while real wall-clock scheduling is used only for ordinary measurements.
- Above-base replay uses the #1315 Kahn order over declared-parent edges with a canonical-raw-identity ready queue; expected/actual ordered IDs match the fixture catalog/oracle, and destination LV/admission order is never used.
- Below-base payload canary (C-10) proves no below-base payload is requested.
- Every genuine-concurrency row that falls back on every fixture is a Candidate C negative, not a pass.

### Slice 4: Legacy control → #1290

**Dependencies:** Slices 1–3; catalog review must already pass

After the paper paths are characterized, preflight whether a package-owned versioned codec/reconstructor can cross the fresh-JS boundary without exposing private `Document`/`FugueTree`/`IndexedState` fields. If not, record the registered `legacy_control_unavailable` negative and do not add a production/internal public serialization API merely to make B pass.

**Acceptance:**
- Positive B, if feasible, reproduces required semantic rows through bytes-only disposal and alias destruction.
- Planner-specific C-06–C-10 are explicitly `not_applicable` to B; all other R/L/F/D/C-01–C-05/U rows are required or have a fixed row-specific negative.
- Missing private reconstruction seam, JS consumer, or owned codec is a reproducible Candidate B negative.
- Candidate B is `not_applicable` for canonical promotion regardless of measured performance.
- Results are control evidence only; they never justify production persistence or API exposure of `FugueTree`, `IndexedState`, `OpLog`, or destination-local IDs.

### Slice 5: Decision + comparison → #1293

**Dependencies:** Slices 1–4

Produce the capability ledger, candidate comparison, negative-result ledger, path-specific selection, and API-boundary decision.

**Acceptance:**
- `capability-ledger.json` maps every [#1317 D3](../research/2026-08-21-r0-evidence-performance-decision-contract.md) matrix row to its minimum authority tier, projection state, expected path, required reads, and demonstrated result.
- Selection follows [#1317 D10](../research/2026-08-21-r0-evidence-performance-decision-contract.md) path-specific deterministic rules.
- The recommendation selects the PaperBranch ordinary path, its concurrent extension, or `no_viable_candidate`; Candidate B is reported as control evidence and is never a selectable canonical path.
- API-boundary decision records whether a later additive opaque Markdown API is justified; raw EGW state is never public.
- Re-check #1281's accepted effect/receipt boundary; record `shared_effect_boundary` as `present` or `absent`.

### Slice 6: Parent coordination → #1288

**Dependencies:** Slices 1–5

Parent issue tracks overall gate completion, cross-slice integration, submodule push order, and final validation.

## Steps

1. Add the EGW package-local capability, pending, partial-admission, and canonical-history read probes without exposing production symbols.
2. Add the EGW-local probe modes and bytes-only JSONL handoff: native authority producer, fresh Node/JS candidate consumer, full-history Markdown oracle, and runner. The Markdown/browser harness never consumes candidate frontier bytes.
3. Add the PaperBranch (ordinary + concurrent) and legacy Candidate B capture and bytes-only restore fixtures; do not extend the v1 archive envelope.
4. Add the Markdown black-box oracle and first-edit/recovery parity cases.
5. Re-check #1281's accepted effect/receipt boundary. If it has not landed, record `shared_effect_boundary: absent` and proceed without inventing a Markdown-side substitute.
6. Run the complete [#1317 D3](../research/2026-08-21-r0-evidence-performance-decision-contract.md) operation matrix, differential comparison, cold-read accounting, and measurement suite per [#1317 D8](../research/2026-08-21-r0-evidence-performance-decision-contract.md).
7. Write the capability ledger, candidate comparison, negative-result ledger, raw traces, API-boundary decision, and validation evidence per [#1317 D7](../research/2026-08-21-r0-evidence-performance-decision-contract.md).
8. Review generated interfaces and validate the EGW submodule independently before any parent pointer change.

## Acceptance Criteria

- [ ] Candidate state crosses a bytes-only Worker/process boundary; no source object or mutable authority alias is retained.
- [ ] Full-history restore remains the oracle and candidate behavior matches for text, frontier, fresh-writer distinctness, normalized next-operation behavior, target visibility, pending/duplicate/conflict outcomes, and recovery classification per [#1317 D2](../research/2026-08-21-r0-evidence-performance-decision-contract.md).
- [ ] EGW white-box tests cover partial admission, pending membership, missing parent/origin/target, semantic-reference coverage, and cold-history provider reads per [#1317 D3](../research/2026-08-21-r0-evidence-performance-decision-contract.md).
- [ ] Canonical events use scalar positions; UTF-16 conversion occurs only at the Markdown façade seam per [#1314](../research/2026-08-20-r0-canonical-positional-event-unicode-contract.md); non-BMP cases verify conversion at the adapter and never reuse destination-local LV or item-space integers.
- [ ] Markdown black-box tests cover `open_succeeded_with_expected_text`, one real local edit after full-history oracle open, source-equal behavior where the existing façade owns it, and exact public archive/open errors. They do not invent separate text-ready/editable states or consume candidate frontier bytes.
- [ ] Receipt validation, first-local, and fully hot strict-forward rows record zero provider reads; indexed-forward/duplicate/conflict rows permit authenticated metadata only; concurrent rows record bounded authenticated metadata and exact selected payload reads per [#1317 D5–D6](../research/2026-08-21-r0-evidence-performance-decision-contract.md). In-memory scans are measured separately.
- [ ] Concurrent path executes bounded replay with disposable tracker or records bounded negative with missing capability; every genuine-concurrency row falling back on every fixture is a Candidate C negative.
- [ ] The capability ledger maps every [#1317 D3](../research/2026-08-21-r0-evidence-performance-decision-contract.md) matrix row to its minimum authority tier and projection level.
- [ ] A later Markdown API recommendation, if any, is opaque and additive; no raw EGW state becomes public.
- [ ] The canonical runner writes the fixed artifact set and exits non-zero for missing evidence, unexplained reads, oracle mismatch, harness failure, or generated-interface drift. A valid candidate-negative result exits zero and is recorded as evidence.
- [ ] EGW changes follow independent submodule review/push order, the EGW package archive remains one verified publish artifact with the probe's visibility classified, and all affected `.mbti` files are reviewed.
- [ ] Resource fuses (`r0_resource_profile_v1`) are wired independently per [#1317 D5](../research/2026-08-21-r0-evidence-performance-decision-contract.md); exceeding any bound produces explicit full-history fallback and a reproducible Candidate negative.
- [ ] Performance promotion requires the [#1317 D10](../research/2026-08-21-r0-evidence-performance-decision-contract.md) thresholds: 75% material-win on restore/first-edit p95, 110% non-regression envelope, size bounds.

## Existing API First / reuse check

The implementation must reuse and cite:

- `AdmissionReceipt::{committed,frontier_before,frontier_after,pending_after_count}` and `AdmissionOutcome::{Complete,Partial}` for committed sidecar/frontier evidence;
- `OpLog::{get_frontier_raw,get_op,get_ops,get_ops_rle}` for exact heads and selected payloads without `get_all_ops`;
- `CausalGraph::{raw_to_lv,lv_to_raw,get_entry,is_ancestor,graph_diff,diff_frontiers_lvs}` and `GraphEntry.timestamp` for oracle/rank evidence (`diff_frontiers_lvs` is defined in `internal/causal_graph/walker.mbt`);
- `Op::parents_iter`, `Op::get_delete_target`, `should_win_delete`, `DeleteIndex::recompute_winner`, and `Document::undelete_if_deleted` for dependency/undelete oracle behavior;
- MoonBit `PriorityQueue`, `HashSet`, `Map`, `Array::sort_by`, `Buffer`, `Bytes`/`BytesView`, `String`/`StringView`, `Option`/`Result`, and strict UTF-8 APIs for the matching data shapes, after `moon ide doc` confirmation.

Checked but prohibited on candidate fast paths: `@text.Version` as exact frontier; `SyncSession::export_all`, `OpLog::get_all_ops`, `CausalSnapshot`, `OpLog::causal_graph`, `walk_and_collect`, `diff_and_collect`, `Branch::checkout`, `FugueTree`, and `IndexedState`. They are oracle/fallback or Candidate-B-only evidence. `String::compare` is not canonical UTF-8 identity ordering.

Unavoidable new helpers remain executable-local and single-purpose: V2 constructors/canonicalization, the L11 scan, the splitting-placeholder tracker, and strict fixture Unicode preflight. No helper may widen a production `.mbti` surface.

## Validation

```bash
# Runner and evidence
nu --ide-check 100 scripts/test-loomark-editable-branch-restore-feasibility.nu
nu scripts/test-loomark-editable-branch-restore-feasibility.nu --suite self-test --output-dir /tmp/loomark-r0-self-test
nu scripts/test-loomark-editable-branch-restore-feasibility.nu --suite all --output-dir artifacts/loomark-editable-branch-restore-feasibility

# EGW submodule: probe/API/JS/publish boundary
cd deps/event-graph-walker
NEW_MOON_MOD=0 moon ide outline dowdiness/event-graph-walker/internal/oplog
NEW_MOON_MOD=0 moon ide outline dowdiness/event-graph-walker/internal/causal_graph
NEW_MOON_MOD=0 moon ide doc "moonbitlang/x/crypto"
NEW_MOON_MOD=0 moon check --target all --fmt --deny-warn --frozen
NEW_MOON_MOD=0 moon test --target all --frozen
NEW_MOON_MOD=0 moon info --frozen
NEW_MOON_MOD=0 moon build --release --target native internal/restore_feasibility_probe
NEW_MOON_MOD=0 moon build --release --target js internal/restore_feasibility_probe
just ci  # after #1289 extends verify-publish-package.nu: one archive, explicit probe/crypto exclusion, extracted --frozen check

# Parent Markdown/Loomark/JS surfaces
cd ../..
NEW_MOON_MOD=0 moon check modules/canopy/editor/markdown
NEW_MOON_MOD=0 moon test -p dowdiness/canopy/editor/markdown
NEW_MOON_MOD=0 moon build --release --target js
./scripts/test-loomark-dev-host-e2e.sh
./scripts/test-loomark-standalone-e2e.sh
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
```

Inspect every generated `.mbti` change for public or trait-bound drift. Independently review the EGW patch, push its commit before updating the Canopy gitlink, verify configured-origin reachability, then run `./scripts/validate-pr-ready.sh --target <package-path>` for every affected package on a clean current-base HEAD. The gate is evidence-only and must not introduce a production public API or archive schema change.

## Risks

- The Markdown facade and EGW internals cannot satisfy the entire gate through one seam; the split evidence contract must remain explicit.
- Candidate B may serialize legacy layout that is too large or unstable; it is a bridge only, never canonical history.
- The concurrent path may be non-executable until authenticated metadata indexes exist; a negative result is valid evidence.
- The existing workspace may have unrelated dependency/toolchain failures; gate evidence must distinguish those from candidate failures.
- The current public Markdown façade cannot ingest a paper branch with its exact frontier; browser candidate timing remains `not_applicable: product_restore_seam_absent` until a separately reviewed opaque product seam exists.

## Implementation Decisions

- This is a test-only feasibility slice. It does not implement `Verified BaseBranch`, checkpointing, materialized-state persistence, history compaction, or a new production restore path.
- The Markdown/Loomark seam is the black-box product oracle. The true black-box consumer lives in the archive/standalone harness and imports only the public Markdown façade; package-local Markdown tests may supply typed contract adapters but are not claimed as black-box.
- The EGW seam is package-local and white-box. It verifies authority hydration, identity membership, pending registration/drain, semantic-target lookup, partial admission, and candidate-specific history access; legacy Fugue origin lookup appears only in oracle/control evidence. `GraphEntry` values obtained from `CausalGraph::get_entry` are read-only evidence in the probe even though the internal type is `pub(all)`. It must not be shared through a production public API.
- The EGW probe is one test-only executable package at `internal/restore_feasibility_probe/` only after preflight confirms executable syntax for the legacy EGW module. It runs native producer and fresh JS consumer modes; the processes share bytes only. #1289 must extend `verify-publish-package.nu` to inspect archive contents/dependencies, explicitly reject the probe and its crypto dependency from the production archive, require exactly one archive, and run the extracted check with `--frozen`. If that proof cannot be implemented, positive candidate support stops with bounded negatives rather than widening published packages.
- Evidence processes are joined by serialized records, not shared types or storage handles. The EGW-local native producer emits candidate/provider bytes and observations; a fresh Node/JS mode of the probe consumes only those candidate bytes; the Markdown/browser harness independently opens only the complete v1 full-history oracle archive. Nushell captures and joins all records by `run_id` and `case_id` without reconstructing causal semantics.
- The JSONL handoff envelope is `{ schema_version, run_id, case_id, producer, status, payload }`; producer values are `egw_authority_native`, `egw_candidate_js`, `markdown_oracle`, or `runner`. Provider-call/phase records additionally carry the #1317 D6 `candidate`, `phase`, query, counter, and fallback fields; `producer` names the emitting process while `candidate` names the evaluated path/control. Package-local tests never import this DTO; only executable probe modes, the Markdown oracle harness, and Nushell exchange it.
- `manifest.json` records `shared_effect_boundary` as `present` with the consumed contract and source revision, or `absent` when #1281 has not landed/been accepted.
- Candidate state must cross a bytes-only serialization boundary. The final acceptance suite must run a producer and consumer as separate processes, or use a Worker with a bytes-only `postMessage` boundary and no object transfer.
- Candidate serialization is a test fixture/sidecar. The current v1 portable archive remains the full-history oracle and is not extended with unknown candidate fields.
- The authority-capability ledger uses ordered tiers: resident receipt/exact heads/writer commitments, authenticated point metadata, selected payloads, and explicit full history. The projection ledger uses validated plain text/direct positional shell, disposable splitting-placeholder tracker, and Candidate-B-only disposable legacy materializer. No persistent position/identity tier or canonical retained CRDT branch is reintroduced.
- A candidate is not accepted because its visible text matches. Acceptance requires behavioral equivalence per [#1317 D2](../research/2026-08-21-r0-evidence-performance-decision-contract.md).
- Writer allocation is restore-time behavior, not captured active state. Every restored instance receives a fresh writer identity.
- The gate classifies three paths: ordinary (zero provider reads), concurrent (bounded authenticated reads), and fallback (explicit full-history). Only fully hot-resolved strict-forward work is zero-read.
- A cold-history read means a call into the test-only canonical-history/segment provider. It is distinct from scanning an already-loaded in-memory candidate. The probe records provider reads; runtime scans are measured separately.
- The full canonical history remains available and authoritative throughout the gate. A candidate state is an accelerator and may never promote unverified text or mutate causal authority.
- Integrity checks may use checksums or equivalent test metadata, but semantic integrity requires differential comparison with the full-history oracle.
- The gate covers a local archive restore into an editable Markdown document and the causal operations needed immediately after restore. It does not introduce a new active-store schema.
- No public archive version, wire version, generated interface, public checkpoint/restore API, or production document lifecycle is changed by this slice.
- Gate R0 fixes `selected_hash_boundary = executable_crypto_dependency`: native/JS probe code uses `moonbitlang/x/crypto` because JS must extend/verify digests for first-local events, and Nushell independently verifies canonical-record hashes. A Nushell-only candidate hash boundary is not permitted. Publish preflight must prove the probe dependency is absent from the production archive.
- The current Markdown façade limitation is explicit: no text import is causal candidate evidence, and browser candidate timing is `not_applicable` without a later reviewed opaque seam.

## Testing Decisions

- Tests verify externally observable behavior and capability boundaries, not private field layout.
- The full-history restore path is the reference-model oracle per [#1317 D2](../research/2026-08-21-r0-evidence-performance-decision-contract.md).
- Before any zero-read assertion is accepted, a known-positive control performs one canonical-history provider read and proves that provider read count, operation count, and byte count all record it (X-01–X-05).
- The [#1317 D3](../research/2026-08-21-r0-evidence-performance-decision-contract.md) operation matrix is the required conformance suite. Every row is required unless explicitly marked Candidate-specific.
- The [#1317 D4](../research/2026-08-21-r0-evidence-performance-decision-contract.md) byte-complete generator fixes `fixture_id`/document ID, every writer/sequence/parent/body/position/target/merge rule, and stable replay order before #1289 expands the immutable catalog. Its scaled corpus provides performance evidence: S-linear, S-distributed, S-tombstone, S-replacement, S-unicode at 1k/10k; C-short 10k; A-long 10k at r=0.01/0.10/0.50; U-mixed 1k/10k; C-multiroot 4+1k; S-linear 100k native-only structural scaling.
- The [#1317 D5](../research/2026-08-21-r0-evidence-performance-decision-contract.md) resource profile `r0_resource_profile_v1` is the fixed safety fuse: 16,384 metadata nodes, 16 MiB proof, 8,192 payload events, 16 MiB payload, 5,000,000 µs elapsed.
- The [#1317 D6](../research/2026-08-21-r0-evidence-performance-decision-contract.md) accounting contract defines all required phase-local counters.
- The [#1317 D7](../research/2026-08-21-r0-evidence-performance-decision-contract.md) fixed runner artifact filenames are the sole run output; checked-in `fixture-catalog-v1.json` is versioned source input, not an extra run artifact.
- The [#1317 D8](../research/2026-08-21-r0-evidence-performance-decision-contract.md) measurement procedure requires 5 untimed warm-up + 30 measured pairs per fixture/candidate/path, even/odd ordering, fresh consumer and reset cold provider per arm; capture/rebuild and incremental sidecar-maintenance timings use 10 warm-ups and 50 measured iterations over preconstructed deterministic inputs. Percentiles use nearest-rank selection (`rank = ceil(p*n)`, one-based); every summary emits `n`, the one-based selected rank, and the selected raw sorted value (p95 rank 29 for n=30; rank 48 for n=50).
- The S-linear 100k native-only structural scale is generated once by #1289 and measured by #1291 as one warm-up plus five descriptive full-overlay rebuild samples reporting raw values only, with no p50/p95 and no promotion use.
- #1289 owns the Chromium oracle/control lane and checked-in `browser-fixture-catalog-v1.json`: five fixed 1k v1 archives (linear, distributed, tombstone, replacement, Unicode), exact archive/text hashes, and the same exact first edit after each restore (append U+005A at the UTF-16 end). It uses release Warren/static output, pinned Chromium, one navigation warm-up, 20 full-history reloads per valid fixture, and storage/archive-open/expected-text/first-edit/fallback-error intervals; exact sequence is `NEW_MOON_MOD=0 moon build --target js --release`; `./scripts/install-local-warren.sh`; `(cd apps/loomark && ../../_build/tools/bin/warren build)`; then `LOOMARK_STARTUP_SAMPLES=20 LOOMARK_STARTUP_ARCHIVES=<generated-dir> npm --prefix apps/loomark/examples/vanilla run bench:startup`, and a harness extension is needed for first-edit/interval clocks before positive oracle evidence. Missing an applicable clock is `measurement_failure`; quota/timeout is a storage/harness limitation, never a candidate timing sample; candidate timing remains `product_restore_seam_absent`.
- Release paired measurements pin RSS with GNU `/usr/bin/time -v` under `LC_ALL=C` over the whole single-process consumer lifetime; consumer commands may not spawn descendants, and candidate and oracle use the same runtime command/input mode.
- The [#1317 D9](../research/2026-08-21-r0-evidence-performance-decision-contract.md) outcome rules define evaluation order and fixed negative reasons.
- The [#1317 D10](../research/2026-08-21-r0-evidence-performance-decision-contract.md) selection rules are path-specific and deterministic: 75% material-win threshold, 110% non-regression envelope, size bounds.
- One canonical Nushell runner, `nu scripts/test-loomark-editable-branch-restore-feasibility.nu --suite all --output-dir <dir>`, owns the gate exit status and must write exactly the fixed artifact set.
- Fixed failure classes are `preflight_invalid`, `toolchain_failure`, `submodule_failure`, `harness_failure`, `oracle_mismatch`, `causal_semantics_mismatch`, `unexpected_cold_read`, `evidence_missing`, `interface_drift`, `measurement_failure`, and `runner_failure`. Exit codes: 10, 20, 21, 30, 31, 32, 33, 34, 35, 40, 50.
- The runner returns exit code `0` only when all required suites and artifacts complete, even if one or more candidates are negative.
- Runner preflight requires a clean worktree and records the baseline hashes of affected `.mbti` files.
- `.github/workflows/ci.yml` adds a `gate-r0-runner` path-filtered job for the runner, probe, fixture catalog, plan, and Loomark/Markdown harness. It runs `nu --ide-check` and `--suite self-test`, and is added to `All Checks Passed`; EGW `just ci` remains the frozen all-target/publish gate.
- No test requires a public test-only API. EGW instrumentation remains package-local `*_wbtest` evidence; Markdown integration remains black-box.
- The acceptance checklist is satisfied only when `result.json.status == "pass"`, every candidate has `pass`, `negative`, or explicit `not_applicable` outcome evidence, and the submodule/interface/review criteria are recorded in `manifest.json` and `validation.log`.

## Out of Scope

- Implementing a production `Verified BaseBranch` type or persistent position-to-identity table.
- Choosing or implementing a checkpoint cadence, snapshot compaction policy, or history-trimming policy.
- Replacing canonical history with a snapshot or discarding cold history.
- Changing the portable archive envelope, archive version, wire version, or sync protocol.
- Changing the production `Document`, `TextState`, `MarkdownEditor`, `FugueTree`, `OpLog`, or `IndexedState` ownership model.
- Implementing any public restore, checkpoint, branch, history-reader, or cold-history API.
- Designing or migrating an IndexedDB or OPFS active store.
- Splitting active runtime storage from portable archive storage in production.
- Implementing a new normal projection, Plain projection, or projection-placement optimization.
- Implementing remote synchronization, relay behavior, peer presence, or collaboration UX.
- Changing undo/redo semantics across restart.
- Proving that every cold reopen completes within a 16 ms budget.
- Treating the Eg-walker paper's target state separation as an implementation contract for current production code.
- Making the test-only canonical TextEvent prototype the production operation model.
- Publishing a production migration plan before the capability gate identifies the minimum editable state.
- Updating the existing local archive repository contract delivered by the completed local persistence work.

## Further Notes

- The Loomark varied-history measurements establish the motivation: replay cost grows with serialized history and history shape, while projection refresh is small. They do not prove that any particular retained-state format is editable.
- The accepted Causal Authority residency architecture already supports the direction of cold text/frontier presentation with durable history and explicit fallback. This gate supplies the missing proof for the current production EGW implementation.
- The accepted architecture requires local event generation to remain disabled until a text/frontier candidate has been validated against authority.
- The completed local archive repository owns a complete local archive and explicit recovery classification today. This gate must not silently change that durable contract.
- Before publishing the API-boundary decision, re-check #1281. If its authority-owned effect/receipt boundary has landed and passed review, record the exact consumed contract; otherwise record that the shared boundary is absent.
- The expected outcomes are intentionally asymmetric: ordinary path (A) is the preferred result; concurrent extension (C) is the migration direction for genuine concurrency and cold undelete; Candidate B remains measured legacy control evidence only and is never canonical selection or an authorized production bridge.
- Any EGW white-box change follows submodule ownership rules: commit and validate it in the EGW repository, push it through its own review, and update the Canopy pointer only after the referenced commit is reachable. The gate evidence must identify both repository revisions.
