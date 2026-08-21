# Gate R0 evidence and performance decision contract

**Date:** 2026-08-21

**Status:** accepted

**Wayfinder:** [#1317](https://github.com/dowdiness/canopy/issues/1317)

**Depends on:** [restore architecture](2026-08-19-egwalker-r0-restore-architecture-reassessment.md), [capture receipt](2026-08-20-r0-capture-receipt-reassessment.md), [cold event-graph boundary](2026-08-20-r0-cold-event-graph-capability-boundary.md), [canonical positional/Unicode contract](2026-08-20-r0-canonical-positional-event-unicode-contract.md), [concurrency replay-base proof](2026-08-21-r0-concurrency-replay-base-proof.md), and [undelete after restore](2026-08-21-r0-undelete-after-paper-branch-restore.md)

## Question

Which operation matrix, paper-style trace morphologies, artifacts, read counters, measurements, and relative pass/negative rules are sufficient to choose the fastest correct Gate R0 result without hiding first-edit replay or concurrent cold work?

## Decision summary

Gate R0 uses a **correctness-first, path-specific evidence contract**.

1. Candidate A and Candidate C are not mutually exclusive whole-document alternatives. Candidate A is the ordinary paper-branch path: validated text plus exact ranked heads and writer commitments, first local edits, and fully hot-resolved strict-forward admission. Candidate C is the bounded concurrency and cold-semantic-reference extension over the same paper branch. Candidate B is a disposable legacy control only and cannot be selected as canonical retained state.
2. Correctness and resource/read admissibility are absolute gates. Timing never excuses an oracle mismatch, an unexpected read, an unauthenticated lookup, or hidden full replay.
3. The matrix has two layers: small deterministic conformance graphs that falsify semantic claims, and scaled S/C/A morphology traces that measure history shape. The S/C/A labels mirror the Eg-walker paper's sequential, short-lived concurrent, and long-running asynchronous categories; the generated R0 traces are scaled deterministic analogues, not copies of the paper corpus and must not be reported as paper benchmark results.
4. The standard boundary is native EGW producer → versioned JSONL/stdout → Nushell → fresh separate JS test consumer. A positive A/C result requires the candidate codec, receipt verifier, planner, and tracker portions it uses to execute on JS; native-only evidence is a bounded capability negative. The current public Markdown façade cannot ingest a paper branch with its exact frontier, so the release-browser lane remains an oracle/plain-text product control and candidate timing is `not_applicable` until a separately reviewed opaque product seam exists. Browser/Worker runs never replace the bytes-only process boundary.
5. Every candidate phase has fresh accounting. Zero-read paths require literal zeros. Genuine concurrency may read only authenticated metadata selected by the planner and exactly the above-base payload set. Sequential cold scans remain zero in every non-fallback candidate path.
6. The canonical resource fuse is fixed for R0: at most 16,384 metadata events, 16 MiB proof bytes, 8,192 payload events, 16 MiB payload bytes, and 5,000 ms elapsed planner/shell time. Exceeding any one bound produces explicit full-history fallback and a reproducible Candidate negative. These are test-gate limits, not production service-level objectives.
7. A candidate is R0-promotable evidence only after correctness passes and it demonstrates a material relative win in the native/JS feasibility seam. Restore and restore-plus-first-edit p95 must each be at most 75% of full-history oracle p95 on required history-heavy rows; no required ordinary/admission lane may regress beyond 110% of its matched oracle/baseline. Structural bytes and cold-read bounds also apply. This selects the next test-backed production investigation, not a production API or deployment path.
8. Gate R0 itself passes when all required evidence is complete and every candidate has reproducible `pass`, `negative`, or `not_applicable` evidence. Candidate success is not required. A candidate that leaks incorrect behavior is a gate failure; a candidate that detects its inability, discards itself, and falls back is valid negative evidence.

## D1 — Decision units and candidate roles

The unit of selection is a **behavioral path on a fixture**, not one global weighted Candidate A/B/C score.

| Decision unit | Candidate role | Required positive capability | Permitted negative/fallback |
|---|---|---|---|
| Receipt validation/read-only text | A/C shared paper branch | O(text + heads + writers), zero provider reads | invalid/corrupt/mixed receipt rejects before editability |
| First local insert/delete | A ordinary path | fresh writer, ranked parent frontier, zero provider reads | missing canonical positional implementation |
| Fully hot strict-forward | A ordinary path | exact head coverage and hot semantic evidence, zero existing-provider reads | reclassify to indexed/concurrent/fallback before mutation |
| Indexed forward/duplicate/conflict | A authority extension | authenticated metadata only, zero payload/full-history reads | proof unavailable/corrupt → fallback/negative |
| Genuine concurrency | C concurrent extension | union-critical base, exact above-base replay, disposable splitting placeholders | no base/proof/budget/tracker → fallback/negative |
| Cold undelete | C semantic-reference extension | target-seeded union replay and exact EGW winner ordering | missing target proof/budget/tracker → pending or fallback/negative |
| Legacy compatibility | B control | bytes-only disposable cache reproduces oracle | any result remains control evidence; never canonical selection |
| Full history | Oracle/fallback | complete current v1 history and production behavior | oracle failure is gate failure |

Candidate A may pass ordinary rows while recording bounded negatives for concurrency. Candidate C is evaluated only if at least one genuine-concurrency row and replay-required cold-undelete rows U-01–U-04 execute the tracker; falling back on every genuine-concurrency row is a Candidate C negative, not a pass. U-05–U-07 retain their explicit reject/pending/fallback/negative outcomes. Candidate B may be fastest in a measured lane, but the architecture decision still bars promotion because it persists legacy merge materialization.

## D2 — Oracle equality contract

For each matrix row the full-history oracle and candidate receive the same canonical initial history and deterministic event trace. The candidate is accepted only if the observations owned by each seam agree.

### EGW white-box observations

- exact raw frontier;
- committed canonical identities, declared parents, implicit predecessor, kind, body digest, payload, and rank;
- normalized fresh-writer next event: normalize only the newly allocated writer identity, never historical identities or sequence;
- admission result (`Complete`, committed partial prefix, pending remainder, duplicate, conflict, semantic reject, or fallback);
- pending count and exact pending/missing identity where package-local authority exposes it;
- replay base, above-base replay identity set, current/shared/incoming classification, transformed effects, target visibility, and delete/undelete winner;
- rank values used by the candidate versus independently rebuilt `GraphEntry.timestamp` values;
- fallback reason and whether the accelerator was discarded before authority/text mutation.

### Markdown/Loomark black-box observations

- exact portable text bytes and Unicode scalar length;
- `open_succeeded_with_expected_text` through the existing all-or-nothing public façade;
- one real local edit after a full-history oracle open and the subsequent public text;
- source-equal causal advance with no fabricated visible effect where the existing façade can exercise it;
- the exact public archive/open error variant.

The current `MarkdownEditor::open` surface exposes neither a distinct text-ready milestone nor a candidate paper-branch/frontier restore input. Therefore the black-box harness must not synthesize such a public lifecycle. Candidate receipt validation, exact frontier, editability, and first-event semantics are joined from the fresh JS test consumer and EGW evidence. Browser candidate restore/first-edit timing is `not_applicable` with `product_restore_seam_absent` until a separate reviewed opaque façade exists; importing text “with no past” is never treated as equivalent evidence.

The Markdown consumer never decodes pending identities, LVs, replay state, or cold-provider handles. Internal representation equality is not required.

A mismatch has two possible outcomes:

- If the candidate detects the mismatch before exposing editable state or mutating canonical authority, discards the candidate, invokes explicit full-history fallback, and then matches the oracle, record Candidate `negative: semantic_mismatch_detected`.
- If incorrect candidate behavior escapes, mutation occurs before rejection, fallback is hidden, or the oracle itself is inconsistent, fail the gate with `oracle_mismatch` or `causal_semantics_mismatch`. This cannot be downgraded to a Candidate negative.

Gate-level `editable_ready` is emitted only after the independent oracle row for the same `run_id` and `case_id` passes. Candidate timing excludes oracle execution but the raw oracle timing remains in evidence.

## D3 — Required conformance operation matrix

Every row is required unless explicitly marked Candidate-specific. Parameters in braces expand into separate `operation-matrix.jsonl` records rather than one aggregate assertion.

| ID | Trace/parameters | Expected path and read contract | Required assertion |
|---|---|---|---|
| R-01 | valid empty and non-empty `R0SnapshotCommitV2` | receipt; all provider/full-history counters 0 | text, heads, graph root, writer tips, lengths/hashes, commit ID |
| R-02 | corrupt `{text, text length, head set, head rank, writer root, graph root, snapshot ID}` | reject before editability; 0 payload/full-history | exact detector and no mixed-state acceptance |
| R-03 | stale/mixed `R0PublicationRefV1` and snapshot components | reject before editability | content identity remains separate from publication provenance |
| R-04 | bytes-only producer destruction and two fresh consumers | restore | no source alias; equal content commit; distinct fresh writers |
| R-05 | duplicate declared-parent identity | canonical-profile negative + explicit oracle path | no sort/dedup digest alias |
| L-01 | first Insert at `{start,middle,end}` on `{empty,BMP,astral,combining,CRLF}` text | A ordinary; zero provider reads | scalar position, UTF-16 adapter rejection at surrogate split, text/frontier/event parity |
| L-02 | first Delete at `{start,middle,end}` on the same Unicode forms | A ordinary; zero provider reads | scalar target position and text/frontier parity |
| L-03 | two sequential local edits after restore | A ordinary; zero existing-provider reads | rank increments, predecessor/parent continuity, fresh writer sequence |
| L-04 | first-local maximum head rank `0x7fff_ffff` | pure `rank_exhausted` negative; no event emitted | no overflow and no provider read |
| L-05 | pre-capture undo request without target receipt | #1316 bounded negative | target is never guessed from resident text |
| F-01 | hot strict-forward `{1,10,100}` inserts/deletes | A ordinary; 0 existing metadata/payload/full-history | coverage of every resident head, exact effect/frontier |
| F-02 | source-equal causal advance | A ordinary; zero existing-provider read | frontier advances; text/cursor/parser/projection unchanged |
| F-03 | hot undelete with target and complete hot replay evidence | A/C hot; zero existing-provider read | target kind, winner, effect, frontier |
| F-04 | indexed-forward parent proof needed but no body needed | authenticated metadata only | zero payload/full-history and complete predecessor closure |
| D-01 | out-of-range/absent writer identity | Tier-0 non-membership; no provider call | exact non-membership classification |
| D-02 | exact duplicate delivery | authenticated metadata only | duplicate, no payload/full-history |
| D-03 | same identity with `{body,parent,predecessor,semantic-reference,rank}` conflict | authenticated metadata only | exact conflict/reject; no payload |
| D-04 | child-before-parent then parent arrival | pending then drain | exact missing identity, committed prefix/frontier/pending transition |
| D-05 | batch with valid prefix and unresolved suffix | partial admission | committed prefix sidecar update only; capture remains disabled while pending |
| D-06 | implicit predecessor present but unreachable through declared closure | reject/pending/fallback per oracle | predecessor is not silently added as graph edge |
| C-01 | two-writer diamond, inserts at different positions | C bounded replay | critical base and exact above-base payload set |
| C-02 | concurrent inserts at same position and non-interleaving sequence runs | C bounded replay | oracle text/order and transformed offsets |
| C-03 | concurrent insert/delete and double delete | C bounded replay | no-op/delete transformation parity |
| C-04 | repeated short fork/merge | C bounded replay | dedup, classification, tracker disposal |
| C-05 | long-running asynchronous fork at conflict ratios `{1%,10%,50%}` | C bounded replay or bounded negative | no below-base payload; relative cost recorded per ratio |
| C-06 | redundant entry paths to the same raw event | C bounded replay | `scan_dedups > 0`; replay set unchanged |
| C-07 | independent roots / no acceptable single-head critical base | explicit full-history fallback | `root_death`/`no_critical_base`; no candidate payload read before fallback |
| C-08 | metadata `{Unavailable,Corrupt,MissingInAuthenticatedRange}`, bad rank monotonicity, missing payload | explicit fallback | provider/verification `fallback_reason` plus any scan reason; candidate discarded |
| C-09 | each resource at exact limit and limit + 1 using injected accounting/elapsed inputs | limit succeeds if otherwise valid; +1 falls back | all five pure fuses are wired independently; real clocks are not used to hit exact microseconds |
| C-10 | below-base payload canary and extra-payload provider | C bounded replay | base/below-base payload never requested; amplification is detected |
| U-01 | cold target currently visible | C target-seeded replay | empty visible effect, frontier advances |
| U-02 | cold target deleted, undelete wins | C target-seeded replay | scalar restored and exact winner tuple |
| U-03 | cold target deleted, concurrent higher-rank delete wins | C target-seeded replay | empty visible effect and exact winner tuple |
| U-04 | root Insert target | C target-seeded replay with empty base | target is expanded, not accepted as base |
| U-05 | target proven non-Insert | semantic reject confirmed by oracle | no visible mutation |
| U-06 | target unresolved hot and cold | pending/fallback per oracle | never unconditional unauthenticated reject/accept |
| U-07 | post-restore target receipt without complete hot replay evidence | indexed replay or bounded negative | not mislabeled zero-read |
| B-01 | Candidate B bytes-only legacy control over every applicable R/L/F/D/C/U row | legacy control, reads fully accounted | oracle reproduction, alias destruction, size/time; never canonical promotion |
| X-01 | known-positive metadata/proof read | control | logical/physical/record/byte counters all nonzero as applicable |
| X-02 | known-positive payload batch | control | requested identities and payload bytes counted exactly |
| X-03 | deliberately non-compliant implementation of the same named metadata operation that scans cold records | control only, not a fourth provider operation | `scan_records_visited > 0` and candidate rejection |
| X-04 | explicit `read_full_history` | control | full-history events/bytes visible only under this query kind |
| X-05 | resident UTF-16↔scalar conversion | control | code-unit and scalar visit counters wired separately |

The matrix supersedes the old plan's assertion that every “closed-concurrent” case must be zero-read. Only fully hot-resolved strict-forward work is zero-read. Genuine concurrency and cold undelete use bounded authenticated reads; “ClosedTail” is removed from the canonical vocabulary.

## D4 — Scaled trace morphology corpus

The conformance matrix proves semantics on small graphs. Performance uses `r0_fixture_generator_v1`, not an implementation-selected corpus. Identities use agents `r0-a`, `r0-b`, and `r0-merge`, each with contiguous zero-based sequences; all unspecified events parent the immediately preceding frontier and all scalar bodies use the positional/Unicode contract. No random source is permitted.

Canonical generator rules:

- `S-linear(n)`: append `n` scalars at the visible end; writer changes every 64 events in round-robin `r0-a`, `r0-b`, but the graph remains one chain.
- `S-distributed(n)`: insert scalar `scalar_pattern[i mod len]` at `(i * 2654435761) mod (current_scalar_length + 1)` on one causal chain.
- `S-tombstone(n)`: append `ceil(2n/3)` scalars, then delete `n - ceil(2n/3)` visible positions selected by the same multiplicative index modulo current length, leaving approximately half of inserted scalars.
- `S-replacement(n)`: first append 50 scalars; then repeat 50 deletes from the visible end followed by 50 deterministic inserts, truncating the final block exactly at event `n`. Final text therefore stays at or below 50 scalars while history/runs grow.
- `S-unicode(n)`: append the exact repeating scalar sequence `[U+0061, U+00E9, U+0065, U+0301, U+1F642, U+000A, U+000D]` with no normalization or line-ending conversion.
- `C-short(10000)`: repeat a block consisting of two 8-event append branches from one shared frontier (`r0-a` and `r0-b`) followed by one `r0-merge` event parented by both branch tips; use 588 full 17-event blocks and finish with four linear merge-writer events.
- `A-long(10000,r)`: let `branch_total = floor(10000 * r)`, `a_len = floor(branch_total / 2)`, `b_len = branch_total - a_len`; generate `9999 - branch_total` shared-prefix events, concurrent A/B append branches of those lengths, then one merge event parented by both tips. Required `r` values are exactly `0.01`, `0.10`, and `0.50`.
- `U-mixed(n)`: repeat `[Insert x, Insert y, DeleteScalar(position of x), Undelete(identity of x)]`; required scales are divisible by four.
- `C-multiroot(n)`: two independent root chains of `floor(n/2)` and `n - floor(n/2)` events with no merge.

`scalar_pattern` is the seven-scalar `S-unicode` sequence above. Delete/undelete rows retain the exact selected identity in generator evidence. Parent/frontier and body records are emitted in a checked-in `fixture-catalog-v1.json` during #1289; the catalog contains the fully expanded canonical event bytes and expected SHA-256 for every required scale. Native and JS consumers must compare against that immutable catalog. #1289 may mechanically compute the hashes from these rules, but may not change an event, position, parent, writer, scale, or seed to improve a result. #1319 verifies these generation rules are decision-complete before implementation; after #1289 emits the initial catalog, a separate independent catalog review recorded in #1289 must pass before #1291/#1292 paper-path work or #1290 legacy-control measurement starts. `manifest.json` records the catalog revision/hash, each generated graph hash, and `fixture_seed: "none"` for every formula-generated fixture (no random source is permitted).

### Required native/JS morphologies

| Morphology | Shape | Required scales/events | Purpose |
|---|---|---:|---|
| `S-linear` | one writer or taking turns; one critical chain | 1k, 10k, 100k | restore independence from history; direct events |
| `S-distributed` | sequential edits spread across document positions | 1k, 10k | position/scalar traversal versus append-only |
| `S-tombstone` | insert phase followed by deterministic delete phase, approximately 50% inserted scalars remaining | 1k, 10k | tombstone-heavy oracle without resident tombstone state |
| `S-replacement` | repeated whole-source replacement yielding small final text and many runs | 1k, 10k | history-heavy/small-text reopen stress |
| `S-unicode` | deterministic BMP, astral, combining sequence, LF/CRLF/CR with no normalization | 1k, 10k | scalar/UTF-16 boundary and byte accounting |
| `C-short` | two writers, repeated 8-event fork/merge runs | 10k | paper-style short-lived concurrency and repeated critical versions |
| `A-long` | two writers fork after shared base; conflict region 1%, 10%, or 50% of 10k events | 10k | paper-style long-running asynchronous branches and replay scaling |
| `U-mixed` | 50% inserts, 25% deletes, 25% undeletes with deterministic contenders | 1k, 10k | target-seeded replay and winner cost |
| `C-multiroot` | independent roots | 4 + 1k | required fallback/no-single-head control |

Each fixture records at least: event count, writer count, exact head count, graph run count, maximum/mean parent count, maximum causal rank, inserted scalars/bytes, deletes, undeletes, tombstoned scalars, final UTF-8 bytes/scalars/UTF-16 units, canonical body bytes, full-history bytes, snapshot bytes, V2 metadata/index bytes, reconstructed replay-region events, and seed/hash.

The 100k scale is required only for native producer/oracle and sidecar structural scaling. The fresh JS consumer is required through 10k. The 100k scale is structural-size/rebuild evidence only: generate once for canonical bytes/size and run five descriptive full-overlay rebuild samples after one warm-up, reporting every raw value without p50/p95 or promotion use. It does not use the 30-sample latency procedure. Browser product timing uses only fixtures that fit the unchanged v1 archive/storage boundary and records `QuotaExceededError` or timeout as a storage/harness limitation, never as a candidate timing sample.

### Required Chromium product fixtures

The release-browser black-box oracle/control slice uses at least these valid archive shapes with the same final Markdown where practical:

1. append-only;
2. distributed edits;
3. insert/delete-heavy;
4. replacement-heavy small final text;
5. Unicode/non-BMP;
6. one ordinary first edit immediately after each restore.

The current browser surface times only full-history oracle open and public plain-text/edit behavior. Candidate paper-branch timing is `not_applicable: product_restore_seam_absent`; a text import with no causal past is not a candidate. Concurrency/undelete remote timing remains EGW native/JS evidence until Loomark has a production-equivalent sync seam. The runner must not label a package-local remote probe as browser collaboration evidence.

The Eg-walker paper's S1–S3, C1–C2, and A1–A2 traces remain primary morphology precedent: sequential histories have no concurrency, concurrent traces have many short-lived branches, and asynchronous Git-derived traces have fewer long-running branches. R0's generated fixtures preserve those graph distinctions at bounded scales but do not reproduce the source documents or event distributions.

## D5 — Fixed R0 resource profile

Every concurrent/undelete planner invocation receives the following immutable `r0_resource_profile_v1` values:

```text
max_planner_metadata_nodes_visited = 16_384
max_proof_bytes = 16 * 1024 * 1024
max_payload_events = 8_192
max_payload_bytes = 16 * 1024 * 1024
max_elapsed_us = 5_000_000
```

Rules:

- `max_planner_metadata_nodes_visited` limits the registered `planner_metadata_nodes_visited` counter. Metadata identity count is known before a request. `max_payload_events` is charged from the fixed replay identity set. `max_payload_bytes` is precharged from authenticated `EventMetaV2.payload_byte_length`. MMR framing makes inclusion-proof length deterministic from writer leaf count, requested position, peak set, hash width, and canonical varints, so `max_proof_bytes` is precharged from the verifier's exact planned-proof length before the request. A returned length that differs is corruption, not an uncharged over-limit response.
- Counters and exact planned charges are checked before issuing the next batch. The batch that would exceed a limit is not issued; the pure decision is `FallbackRequired(resource_bound)` and names the dimension, observed value, limit, and next requested amount.
- Elapsed time is supplied by the shell after each completed batch; the deterministic core never reads a clock. Timeout causes fallback before another request or text mutation. C-09 injects exact monotonic elapsed values directly into the reducer; real wall-clock scheduling is used only for ordinary measurements.
- Canonical runs may lower a limit only in C-09 fault-injection rows. They may never raise one through CLI/environment overrides.
- A positive bounded replay must fetch exactly the unique verified metadata requested by the planner (including selected-base metadata and any distinct target verification) and exactly the replay-set payloads. A root critical base may make metadata visits equal the full event count; an empty undelete base may make payload events equal it. Those are semantically valid conformance results, but they qualify for performance promotion only in a **cold provider sample** (`cache_status = miss` after a fresh provider/process reset) where candidate `physical_bytes < oracle_full_history_bytes` and the relative latency rule passes. `oracle_full_history_bytes` is the exact physical byte length returned by one matched `read_full_history`; it is also the sole denominator for resident/accelerator ratios. Extra metadata/payload identities are `unexpected_cold_read`; equal-or-larger cold bytes are `negative: read_not_bounded`. Cache-hit rows are conformance evidence only and never enter promotion.
- Candidate metadata/payload operations require `scan_records_visited == 0`. A storage backend that can answer only by scanning is a Candidate negative.
- Full-history fallback starts a new phase with fresh accounting. Candidate partial reads remain visible and are not subtracted from fallback cost.

The event/byte caps use powers of two and the elapsed cap is exactly five seconds; together they form a finite R0 safety fuse and make cap/cap+1 tests deterministic. They do not claim that 16,384 events, 16 MiB, or five seconds is an acceptable production interaction budget. The relative rules below decide competitiveness.

## D6 — Accounting contract

All fields from the cold event-graph boundary remain required, including logical queries, physical calls/bytes, byte categories, proof/index nodes, planner/resident/text visits, provider scans, full-history events/bytes, and elapsed time. #1315's scan/replay/tracker counters and #1316's target verification are additive.

Required phase-local counters are:

- provider fields from `cold-history.jsonl`:
  `requested_id_count`, `returned_record_count`, `physical_read_calls`, `physical_bytes`, `framing_bytes`, `metadata_bytes`, `proof_bytes`, `payload_bytes`, `index_nodes_read`, `scan_records_visited`, `full_history_events`, `full_history_bytes`;
- planner fields in the phase-total records of `cold-history.jsonl`:
  `planner_metadata_nodes_visited` (unique verified records inspected, including selected-base metadata and distinct target verification), `scan_events_visited`, `scan_dedups`, `scan_critical_base_found`, `scan_fallback_reason`, `replay_set_current_count`, `replay_set_shared_count`, `replay_set_incoming_count`, `tracker_events_replayed`, `tracker_events_output`;
- fallback fields in those phase totals:
  `fallback_stage` (`provider`, `verification`, `scan`, `payload`, `resource`, or `oracle`), general `fallback_reason`, and the narrower #1315 `scan_fallback_reason` only when the scan owns the decision. Provider/verification reasons include `unavailable`, `missing_in_authenticated_range`, `corrupt_meta`, and `rank_violation`; payload-stage reasons are `payload_missing` and `payload_corrupt`. They are not forced into the scan enumeration. Every cap hit uses `fallback_stage = resource` and `fallback_reason = resource_bound`; `scan_fallback_reason = resource_bound` is additionally set only when the refused metadata/proof/elapsed charge occurs while the L11 scan is active, otherwise the scan field is null;
- resident/text fields:
  `resident_records_visited`, `resident_text_code_units_visited`, `resident_text_scalars_visited`;
- capture/size fields in `candidate-captures.jsonl` and its `candidate-results.json` summaries:
  `full_overlay_rebuild_us`, `incremental_sidecar_maintenance_us`, `capture_us`, `snapshot_commit_bytes`, `resident_candidate_bytes`, `event_meta_index_bytes`, `cold_payload_store_bytes`, `accelerator_bytes`, `oracle_full_history_bytes`;
- timing fields in raw/sample arrays and summaries in `candidate-results.json`:
  `candidate_decode_us`, `receipt_validation_us`, `restore_to_text_observed_us`, `restore_to_editable_us`, `first_edit_us`, `restore_plus_first_edit_us`, `admission_us`, `concurrent_planning_us`, `concurrent_payload_replay_us`, `transformed_effect_application_us`, `bounded_admission_us`, `read_full_history_us`, `full_history_decode_admit_materialize_us`, `incoming_application_us`, `fallback_admission_us`, `fallback_to_editable_us`; `restore_to_text_observed_us` is a harness observation, not a public lifecycle state;
- memory fields in `candidate-results.json`:
  `peak_rss_bytes` for the canonical Linux native/JS child process, collected per arm by GNU `/usr/bin/time -v` under `LC_ALL=C` over the whole single-process consumer lifetime; consumer commands may not spawn descendants. Candidate and oracle use the same runtime command/input mode. Browser/process-tree heap observations are supplementary and never compared with this RSS lane.

`accelerator_bytes = snapshot_commit_bytes + event_meta_index_bytes`; it excludes canonical full history and cold payload bodies because R0 does not authorize duplicating or replacing the production archive. `resident_candidate_bytes` is exactly the bytes decoded before editability, not the on-disk accelerator total. Any implementation-defined allocation estimate is separate from serialized byte counts.

A cache hit keeps logical query/planner visit counts while physical calls/bytes may be zero. A metadata-dependent path never becomes a zero-query path merely because the provider cache was warm.

## D7 — Fixed artifact ownership

The canonical runner writes exactly the registered artifact filenames. This decision registers additive runner-v1 fields such as path selection and artifact hashes; #1318 must copy the exact field ownership rather than claiming the older prose was already complete. Runner output remains `schema_version: 1`; V2 names refer to the sidecar/snapshot generation and do not force a runner schema rename.

| Artifact | Authoritative content |
|---|---|
| `manifest.json` | source/submodule/tool/browser revisions; clean base; fixture seeds/hashes; `r0_resource_profile_v1`; sample/warm-up counts; target/runtime; shared-effect-boundary presence; measurement capabilities; baseline failures; selected SHA-256 boundary (`executable_crypto_dependency` for Gate R0; native/JS probe hashing plus independent Nushell verification) |
| `result.json` | gate `pass`/`fail`; fixed failure class/exit code; candidate/path outcomes; selected promotable paths or `none`; artifact hashes |
| `capability-ledger.json` | every matrix row → minimum authority tier, projection state, expected path, required reads, demonstrated result |
| `candidate-captures.jsonl` | owned bytes-only capture identity, content/publication IDs, component byte counts/hashes, capture/rebuild/maintenance timing, producer revision; no live handles |
| `candidate-results.json` | raw samples and p50/p95/max by candidate/path/fixture/phase; ratios; byte/memory summaries; `pass`/`negative`/`not_applicable`; selection result |
| `operation-matrix.jsonl` | one expanded row/sample with expected/actual classification, observation hashes, counters, and outcome |
| `oracle-differential.jsonl` | candidate/oracle observations at the owning seam, normalized fields, equality result, detected-before-mutation flag |
| `cold-history.jsonl` | one provider event plus phase totals; candidate and oracle streams separate; positive controls included |
| `negative-results.json` | fixed negative reason, first failed obligation, fallback evidence, missing capability, limits/observed values, reproducible command/case |
| `validation.log` | raw commands/output for preflight, hashes, Nushell check, EGW CI, `verify-publish-package.nu` one-archive/executable-exclusion proof, MoonBit checks/tests/fmt/info, `.mbti` diff review, browser run, submodule reachability/push order, independent reviews |

Raw timing samples live inside `candidate-results.json`; raw row observations live in the JSONL artifacts. Summaries without raw values are `evidence_missing`.

## D8 — Measurement procedure

### Correctness and determinism

- Every conformance row required for a positive A/C result runs on native and JS. The native producer remains the authority fixture source; the fresh JS consumer must independently execute the candidate codec, receipt validation, and every planner/tracker path claimed positive. A missing JS implementation is `negative: js_consumer_capability_absent`, not `not_applicable` and not a vacuous cross-target pass.
- Canonical bytes, digests, exact heads, ranks, planner decisions, and normalized observations must match across targets.
- Each capture is regenerated three times from the same seed; content IDs and canonical bytes must match. Publication sequence may differ and is compared separately.
- Every consumer is a fresh process with only the handoff bytes. Source producer state is destroyed before consumer launch.

### Native/JS phase measurements

- Build release artifacts before timing.
- Use 5 untimed warm-up pairs and 30 measured pairs per required 1k/10k fixture and candidate/path. Each pair yields one candidate and one matched oracle sample with a shared `pair_id` from 0 through 29.
- Even `pair_id` runs candidate then oracle; odd `pair_id` runs oracle then candidate, yielding exactly 15 pairs in each order. Each arm starts a fresh consumer and a freshly reset cold provider/cache; input bytes, fixture hash, resource profile, and runtime build are identical within the pair. No arm may reuse provider cache or candidate state from its mate.
- Phase clocks start after exact input bytes are available and end before evidence serialization. Process startup and evidence-write time are reported separately, not charged to the algorithm phase.
- Capture/rebuild and incremental-maintenance timings use 10 warm-ups and 50 measured iterations over preconstructed deterministic inputs; mutation/setup outside the named phase is excluded and separately reported.
- Percentiles use nearest-rank selection and raw values are retained. Every summary emits `n`, the one-based selected rank, and the selected sorted raw value (p95 rank 29 for n=30; rank 48 for n=50). p95 is descriptive; no confidence interval is claimed.

### Chromium product measurements

- Use release Warren/static output and a pinned Chromium revision.
- One navigation warms the build/cache. Then run 20 measured full-history oracle/control reloads per valid product fixture. Candidate AB/BA pairing is required only if a future separately reviewed opaque paper-branch seam exists; otherwise candidate rows are `not_applicable: product_restore_seam_absent`.
- For the existing façade, the end-to-end black-box clock ends when `MarkdownEditor::open` has produced the expected public text and a real local edit is observed. It does not claim distinct text-ready/editable milestones or a candidate frontier receipt.
- Record storage read, archive/open, expected-text observation, first edit, and fallback/error intervals where the existing surface owns them. Candidate decode/receipt/first-event clocks belong to the fresh JS test consumer. Missing a clock required for the applicable seam is `measurement_failure`.
- Browser long tasks and heap observations are supplementary; they do not replace the required clocks/read counters.

Canonical performance evidence requires the pinned Linux environment recorded in `manifest.json`. Other platforms may run conformance but mark performance `not_measured`; they cannot publish the final selection.

## D9 — Correctness, read, and candidate outcome rules

Evaluation occurs in this order:

1. **Harness/oracle validity.** Positive controls, independent oracle, bytes-only separation, revision hashes, and required artifacts must pass. Failure is a nonzero gate failure.
2. **Semantic equality.** Any escaped mismatch is a gate failure. A mismatch safely detected before mutation may become Candidate negative with explicit fallback.
3. **Path/read contract.** Zero-read rows require every metadata, payload, scan, and full-history field to be zero. Indexed rows permit only named metadata. Concurrent rows require exact replay payload equality. Hidden `export_all`, `get_all_ops`, `walk_and_collect`, `diff_and_collect`, `Branch::checkout`, or equivalent full walk is `unexpected_cold_read`.
4. **Resource bounds.** Absolute and fixture-relative bounds must pass. Otherwise fallback plus Candidate negative.
5. **Performance/size qualification.** Only a semantically correct, read-admissible result is compared for promotion.

Fixed Candidate negative reasons are:

- `capture_capability_absent`;
- `public_capture_seam_absent`;
- `js_consumer_capability_absent`;
- `product_restore_seam_absent`;
- `canonical_profile_unsupported`;
- `duplicate_declared_parent_unsupported`;
- `rank_exhausted`;
- `authenticated_index_absent`;
- `proof_unavailable`;
- `proof_corrupt`;
- `payload_missing_or_corrupt`;
- `replay_base_unprovable`;
- `placeholder_tracker_unavailable`;
- `legacy_control_unavailable`;
- `resource_bound`;
- `read_not_bounded`;
- `semantic_mismatch_detected`;
- `pre_capture_undo_receipt_absent`;
- `serialized_size_regression`;
- `insufficient_performance_margin`.

A negative record names the first failed obligation but retains all earlier observations. It may not omit candidate reads already performed before fallback.

`result.json.status == "pass"` when the harness/oracle and all required evidence pass and every candidate/path has `pass`, reproducible `negative`, or justified `not_applicable`. The fixed runner failure classes and exit codes from the current plan remain unchanged. `oracle_mismatch`, `causal_semantics_mismatch`, `unexpected_cold_read`, or missing evidence are never successful negatives.

## D10 — Relative performance and selection rules

No weighted aggregate may trade correctness, bytes, or one morphology against another. Report every fixture independently. Geometric means may appear as descriptive summaries only.

### Ordinary paper path (Candidate A)

Candidate A is **promotable evidence** only when:

- receipt validation, first local insert/delete, and hot strict-forward rows pass with literal zero provider/full-history reads;
- in the fresh JS feasibility consumer on `S-linear` 10k, `S-replacement` 10k, and `S-unicode` 10k, both `restore_to_editable` p95 and `restore_plus_first_edit` p95 are `<= 0.75 ×` matched full-history oracle p95;
- isolated first-edit p95 and strict-forward admission p95 are each `<= 1.10 ×` the same operation on an already restored full-history branch;
- incremental sidecar maintenance p95 is `<= 1.10 ×` matched admission without sidecar maintenance;
- for 1k+ histories, `resident_candidate_bytes <= 0.25 × oracle_full_history_bytes` and `accelerator_bytes <= oracle_full_history_bytes`.

A correct result outside the 75% material-win threshold but within the 110% non-regression envelope is `negative: insufficient_performance_margin`; it is not the next production investigation. A lane above 110% is the same negative with the regressed phase named. Size failure is `serialized_size_regression`. Even a positive internal result records `product_restore_seam_absent` separately and cannot authorize browser integration until #1318 assigns a later opaque-interface decision.

### Bounded concurrency/undelete path (Candidate C)

Candidate C is promotable evidence only when:

- all C/U conformance rows match the oracle or take their specified negative/fallback;
- at least `C-short` 10k, `A-long` 10% conflict, and U-01/U-02/U-03 execute bounded replay rather than full fallback;
- planner metadata equals the exact unique verified request set (selected base and distinct target verification included), payload identities equal the exact above-base replay set, and all absolute/cold-byte/relative-latency bounds pass;
- the Candidate C comparison lane is one end-to-end `bounded_admission_us = concurrent_planning_us + concurrent_payload_replay_us + transformed_effect_application_us`; its matched fallback lane is `fallback_admission_us = read_full_history_us + full_history_decode_admit_materialize_us + incoming_application_us`; both start with the same resident text/frontier and incoming bytes and end after the same text/frontier observation;
- bounded replay `bounded_admission_us` p95 is `<= 0.75 × fallback_admission_us` p95 on `C-short` 10k and `A-long` 10%; component phases are reported but are not cross-compared to unlike fallback phases;
- required indexed/ordinary lanes remain within their separately stated 110% matched-operation envelope; one-time capture/rebuild is never folded into admission;
- temporary tracker state is disposed and no post-phase alias/resident growth remains.

`A-long` 50%, multiroot, or any cap-exceeding row may be a bounded negative without invalidating a positive C result. If every genuine-concurrency row falls back, if any replay-required U-01–U-04 positive row cannot run the tracker, or if splitting placeholders are incomplete, Candidate C is negative. U-05–U-07 keep their specified semantic-reject, pending/fallback, or negative outcomes and are not required to run the tracker.

### Legacy control (Candidate B)

Candidate B receives correctness and measurement results but is `not_applicable` for canonical promotion. It may be cited as a bounded migration-control comparison only. It cannot win a tie or justify production persistence of `FugueTree`, `IndexedState`, `OpLog`, or destination-local IDs.

### Fastest correct selection

Selection is path-specific and deterministic:

1. discard non-correct, read-inadmissible, or non-promotable results;
2. for each ordinary implementation, compute its primary key as the maximum of its three `restore_plus_first_edit` p95/oracle-p95 ratios on `S-linear` 10k, `S-replacement` 10k, and `S-unicode` 10k;
3. for each concurrent implementation, compute its primary key as the maximum of its `bounded_admission_us` p95/`fallback_admission_us` p95 ratios on `C-short` 10k and `A-long` 10%;
4. find the minimum primary key per path. The tie band contains every implementation whose key is `<= minimum * 1.10`; this fixed set avoids pairwise/non-transitive ties;
5. within the tie band, sort lexicographically by total `resident_candidate_bytes` over the key fixtures, total cold-miss `physical_bytes`, total logical metadata queries, then stable ASCII candidate implementation ID. The first entry wins;
6. if no path qualifies, publish `no_viable_candidate` and the bounded negatives rather than weakening the threshold.

A selected A ordinary path and C concurrent extension form one paper-branch recommendation; they are not competing persisted branch formats.

## D11 — Known production and evidence boundaries

- The current v1 local archive is one complete synchronous blob. It can report whole-blob load/decode only; it cannot claim production partial storage reads. R0 provider reads are test-only segmented capability evidence.
- Current Loomark has no production-equivalent collaboration surface. Native/JS remote traces are admission evidence, not a user-visible remote benchmark.
- Browser localStorage quota failures remain storage-boundary observations and are excluded from latency percentiles.
- The full-history oracle remains available for every fixture and is never replaced by candidate hashes.
- Peak memory is required on the canonical Linux child-process run. Browser heap is supplementary because browser APIs and isolation can vary.
- The 16 ms line in the Eg-walker paper is context for next-frame operations, not an R0 restore acceptance threshold. R0 uses matched relative thresholds because browser/toolchain/fixture costs differ.
- Existing P3 evidence demonstrates that history JSON decode/admission can dominate while projection refresh remains small, but it does not establish R0 thresholds or prove replay-free editability.

## D12 — Functional core / imperative shell

### Functional core

- expand fixture/matrix descriptors into deterministic expected obligations;
- compare candidate/oracle normalized observations;
- validate phase-local accounting identities and zero/read-set rules;
- apply absolute and fixture-relative resource limits;
- compute percentile summaries, ratios, candidate outcomes, and path-specific selection from raw values;
- produce structured failure/negative decisions without I/O.

### Imperative shell

- build/run native, JS, Nushell, and Chromium processes;
- read clocks/RSS and pass elapsed values to the core;
- perform provider I/O and emit one observation per call;
- write fixed artifacts and validation logs;
- invoke full-history fallback only when the core requests it.

No mutable global counter or runner-side semantic reconstruction is permitted. Nushell validates and joins records; EGW owns causal/replay decisions and Markdown owns public behavior.

## Consequences for #1318/#1319

The plan and implementation tickets must be rewritten to reflect this decision:

- remove `ClosedTail` and the persistent position-to-identity/tombstone Candidate C artifact;
- treat A ordinary and C concurrent/undelete as complementary paper-branch paths;
- keep B as legacy control only;
- replace “closed-concurrent zero reads” with bounded authenticated concurrency accounting;
- include the fixed matrix, S/C/A morphologies, resource profile, artifacts, sampling, thresholds, and negative taxonomy here;
- preserve the EGW submodule push-before-parent-pointer rule and require publish preflight to prove the executable probe is excluded while the extracted module remains exactly one verified archive; if not, use package-local test stdout rather than widening exports;
- use and record `selected_hash_boundary = executable_crypto_dependency`: native/JS probe hashing through `moonbitlang/x/crypto` plus independent Nushell verification, while proving the probe dependency is excluded from the production archive;
- keep the current Markdown façade limitation explicit: no text import is causal candidate evidence, and browser candidate timing is not applicable without a later reviewed opaque seam;
- start implementation with the runner/independent oracle, then ordinary restore, bounded concurrency, undelete, legacy control, and final comparison as separate slices.

#1317 is resolved by this contract. #1318 owns coordinated plan/ticket edits; #1319 owns the final decision-complete handoff review.

## Sources inspected

### Primary algorithm and trace sources

- Eg-walker paper §3.5–3.7 and §4 (`/tmp/egwalker-paper.txt`; published as [arXiv:2409.14252](https://arxiv.org/abs/2409.14252)): critical versions, partial replay/placeholders, persistent event graph plus cached final text, S/C/A trace categories, and load/merge/file/memory measurement dimensions.
- EGW `GraphEntry.timestamp`, `CausalGraph`, `OpLog`, `AdmissionReceipt`, `Op`, `Branch`, `DeleteIndex`, and `Document` sources under `deps/event-graph-walker/internal/`: current oracle and evidence seams cited by the dependency decisions above.
- Loro L11 critical-version implementation and specification at commit `4d3d3f1de107aebcd0b824e53e05d6bb5c6a5974`, cited by the concurrency decision: single-head waterline scan and entry-point coverage precedent.

### Repository evidence and contracts

- `docs/evidence/2026-08-18-loomark-p3-archive-reopen.md`: ten-sample release-browser paired measurements and phase decomposition.
- `docs/performance/2026-08-10-loomark-startup-history-corpus.md`: synthetic/archive morphology limits, fresh-writer/materializer prototypes, and warning against deriving a replay threshold from one corpus.
- `docs/research/2026-08-17-egw-p3-text-admission-characterization.md`: structural admission counters and complete/duplicate/pending/partial distinctions.
- `apps/loomark/examples/vanilla/bench-startup.mjs`: current warm-up, raw sample, and nearest-rank browser harness behavior.
- `.github/workflows/ci.yml`: release benchmark, MoonBit, TypeScript, and Playwright validation surfaces.
- `docs/plans/2026-08-19-loomark-editable-branch-restore-feasibility.md`: existing runner/artifact/failure contract, portions of which #1318 must replace after this decision.
