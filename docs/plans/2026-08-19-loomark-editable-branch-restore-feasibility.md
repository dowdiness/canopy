# Gate R0: Editable Branch Restore Feasibility

> **Status: rewrite pending.** The accepted R0 research contracts through
> [the evidence/performance decision](../research/2026-08-21-r0-evidence-performance-decision-contract.md)
> supersede this plan's `ClosedTail`, persistent position/identity Candidate C,
> closed-concurrent zero-read wording, and globally competing A/B/C roles. A is
> now the ordinary paper path, C its concurrency/undelete extension, and B a
> legacy control only. Issue
> [#1318](https://github.com/dowdiness/canopy/issues/1318) owns the coordinated
> rewrite. Do not implement this plan as-is.

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/1288>

The issue owns active status and backlog membership. This plan owns the test-only execution contract and links back to the issue above.

Related issue: [#1281 — avoid full text snapshots during remote admission reconciliation](https://github.com/dowdiness/canopy/issues/1281).

The relationship is coordination, not a dependency: #1281 covers resident-authority remote admission; this gate covers cold archive restore and editable-branch hydration. Both must reuse any accepted authority-owned effect/receipt boundary rather than inventing parallel Markdown-side authority logic.

## Why

Loomark archive reopen is dominated by history decode and causal admission, but the current production `Document` has not proved that plain text plus an exact frontier can restore an editable branch. Before choosing a checkpoint, persistent branch, active-store schema, or public Markdown API, the project needs an evidence gate that identifies the minimum authority capability and projection state required for real edits and causal admission.

## Scope

In:
- `deps/event-graph-walker/internal/document/` and `deps/event-graph-walker/internal/oplog/` for package-local authority and admission probes;
- `deps/event-graph-walker/internal/branch/` for the concrete test-only position-based Candidate C boundary;
- `deps/event-graph-walker/internal/restore_feasibility_probe/` for a test-only EGW executable package with repo-proven `pkgtype(kind: "executable")` and native stdout capture; its exclusion from production package exports is a preflight acceptance condition;
- `modules/canopy/editor/markdown/` for package-owned façade contract/oracle adapters;
- `apps/loomark/archive/` and `apps/loomark/examples/vanilla/` for the true public-façade black-box restore harness;
- `scripts/test-loomark-editable-branch-restore-feasibility.nu` as the canonical Nushell gate runner;
- `scripts/README.md` and `.github/workflows/ci.yml` for the fixed runner contract and Nushell validation routing;
- fixed gate artifacts: `manifest.json`, `result.json`, `capability-ledger.json`, `candidate-captures.jsonl`, `candidate-results.json`, `operation-matrix.jsonl`, `oracle-differential.jsonl`, `cold-history.jsonl`, `negative-results.json`, and `validation.log`.

Out:
- production checkpoint/materialized-state persistence;
- portable archive, wire, public API, IndexedDB, or OPFS changes;
- history trimming, remote transport, collaboration UX, and restart undo;
- production `Verified BaseBranch` or `ClosedTail` types.

## Current State

- The accepted Causal Authority residency architecture separates durable history, current text, and temporary merge state, but explicitly records implementation as incomplete.
- The current local archive is a complete v1 envelope whose history is decoded and admitted on reopen.
- The Markdown facade does not expose EGW pending identities, partial admission details, or cold-history segment reads.
- EGW package-local prototypes already provide evidence seams for causal cuts, fresh writers, and editable text materialization. Paper-aligned text-event lowering is Gate A branch evidence rather than a guaranteed source file in this checkout, and none of these prototypes is a replay-free production restore API.
- The varied-history measurement shows history decode/admission dominates the measured local reopen path.

## Desired State

A test-only gate compares a full-history Markdown/EGW restore oracle with serialized candidates through two explicit seams: Markdown black-box behavior and EGW white-box authority evidence. The result identifies whether Candidate A, B, or C can restore an editable branch without hot-loading full history, or records a bounded negative result and the exact missing capability. It also records whether any later additive opaque Markdown API is justified.

## Steps

1. Add the EGW package-local capability, ClosedTail, pending, partial-admission, and canonical-history read probes without exposing production symbols.
2. Add the EGW-local `is-main` producer and bytes-only JSONL handoff; add the Markdown/browser consumer that reads only the handoff bytes.
3. Add the concrete Candidate A/B/C capture and bytes-only restore fixtures; do not extend the v1 archive envelope.
4. Add the Markdown black-box oracle and first-edit/recovery parity cases.
5. Re-check #1281's accepted effect/receipt boundary. If it has not landed, record `shared_effect_boundary: absent` and proceed without inventing a Markdown-side substitute.
6. Run the complete operation matrix, differential comparison, cold-read accounting, and measurement suite.
7. Write the capability ledger, candidate comparison, negative-result ledger, raw traces, API-boundary decision, and validation evidence.
8. Review generated interfaces and validate the EGW submodule independently before any parent pointer change.

## Acceptance Criteria

- [ ] Candidate state crosses a bytes-only Worker/process boundary; no source object or mutable authority alias is retained.
- [ ] Full-history restore remains the oracle and candidate behavior matches for text, frontier, fresh-writer distinctness, normalized next-operation behavior, target visibility, pending/duplicate/conflict outcomes, and recovery classification.
- [ ] EGW white-box tests cover partial admission, pending membership, missing parent/origin/target, implicit same-agent predecessor closure, ClosedTail validation, and cold-history provider reads.
- [ ] Candidate C tests treat its position-to-identity index as UTF-16 source spans mapped to canonical identities; non-BMP cases verify conversion only at the Markdown façade seam and never reuse destination-local LV or item-space integers.
- [ ] Markdown black-box tests cover text readiness, editability, recovery, first local edit, and public error behavior without depending on EGW internals.
- [ ] Strict-forward and closed-concurrent cases record zero cold-history provider reads; in-memory scans are measured separately.
- [ ] Candidate C is either concretely restored without a full graph walk or recorded as a bounded negative result.
- [ ] The capability ledger maps every operation-matrix row to its minimum authority and projection level.
- [ ] A later Markdown API recommendation, if any, is opaque and additive; no raw EGW state becomes public.
- [ ] The canonical runner writes the fixed artifact set and exits non-zero for missing evidence, unexplained reads, oracle mismatch, harness failure, or generated-interface drift. A valid candidate-negative result exits zero and is recorded as evidence.
- [ ] EGW changes follow independent submodule review/push order, the EGW package archive remains one verified publish artifact with the probe's visibility classified, and all affected `.mbti` files are reviewed.

## Validation

```bash
nu --ide-check scripts/test-loomark-editable-branch-restore-feasibility.nu
nu scripts/test-loomark-editable-branch-restore-feasibility.nu --output-dir artifacts/loomark-editable-branch-restore-feasibility
cd deps/event-graph-walker && just ci
cd ../.. && NEW_MOON_MOD=0 moon check modules/canopy/editor/markdown
NEW_MOON_MOD=0 moon test -p dowdiness/canopy/editor/markdown
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
```

Inspect every generated `.mbti` change. The gate is evidence-only and must not introduce a production public API or archive schema change.

## Risks

- The Markdown facade and EGW internals cannot satisfy the entire gate through one seam; the split evidence contract must remain explicit.
- Candidate B may serialize legacy layout that is too large or unstable; it is a bridge only, never canonical history.
- Candidate C may be non-executable until a retained position-based branch exists; a negative result is valid evidence.
- The existing workspace may have unrelated dependency/toolchain failures; gate evidence must distinguish those from candidate failures.

## Notes

- The issue is intentionally separate from the completed local archive repository issue, the P3 measurement issue, and the EGW Gate A reference-model issue.
- Any EGW white-box change must be committed and pushed in the EGW repository before a Canopy submodule pointer is updated.

---

## Problem Statement

When Loomark reopens a local archive, the current path decodes the outer archive, decodes the embedded canonical history, admits the history into the production Markdown/EGW stack, and only then makes the document editable. The varied-history measurements show that history decoding and causal admission dominate this path. Projection refresh is not the dominant cost.

The existing archive contains portable Markdown and opaque causal history. A tempting optimization is to persist the current text together with an exact frontier and skip full history replay during normal reopen. The current production `Document`, however, still owns a `FugueTree`, `OpLog`, and `IndexedState` together. Local insert, delete, and undelete use legacy position/identity and origin machinery. The current implementation has not proved that portable text plus frontier can recreate an editable production branch.

The project therefore needs an evidence gate before choosing a checkpoint format, persistent branch shape, active browser storage schema, public restore API, or history-compaction policy. The gate must distinguish a text snapshot that is safe to display from a branch that is safe to edit and admit causal work from.

## Solution

Build a test-only **Editable Branch Restore Feasibility Gate** with two coordinated seams rather than pretending that one package boundary can observe everything. The Markdown/Loomark seam remains the highest product seam: it exercises archive restore, text readiness, editability, recovery classification, and public behavior. An EGW package-local white-box seam exercises authority hydration, pending membership, origin/target lookup, partial admission, and cold-history access. An evidence-assembly step compares the two results. The existing full-history restore remains the behavioral oracle.

The gate will maintain an explicit capability ledger rather than assuming that a field set is the answer. It will classify the minimum authority capability required by each operation and compare it with the editable projection required to exercise that operation. It will also produce an API-boundary decision: capabilities needed only for evidence remain internal, while a capability needed by a stable Markdown product workflow may receive a later additive opaque façade contract. R0 itself does not implement that public contract.

The candidate space is two-dimensional:

- **Authority capability:** from an exact frontier through identity membership, payload/target lookup, causal ancestry and pending state, up to the resident operation log.
- **Editable projection:** from plain text, through a position/identity index and a disposable legacy materializer, to a canonical position-based editable branch.

The gate will evaluate three representative combinations:

- **Candidate A:** a minimal authority summary with the smallest plain-text or indexed projection that can satisfy the operation matrix;
- **Candidate B:** the same authority summary with a disposable, versioned legacy Fugue/IndexedState projection;
- **Candidate C:** a concrete test-only canonical position-based editable branch containing the state required for local identity/position operations without reconstructing the branch through a full history walk. The existing text-event adapter is evidence for a migration direction, not Candidate C by itself. If no such retained branch can be constructed, C records a bounded negative result rather than being treated as a passing candidate.

Candidate C has one explicit capture/restore artifact shape. The capture is an owned, versioned value with no live references:

```text
CandidateCArtifact {
  schema_version
  base {
    exact_frontier  // canonical RawVersion set, never destination-local LV
    portable_text  // UTF-8 source; mappings below carry explicit UTF-16 units
    position_to_identity_index  // ordered UTF-16 spans -> canonical RawVersion
    identity_payload_visibility_table  // identity, payload, tombstone/winner state
    historical_writer_sequence_floors  // provenance only; never active writer state
    committed_membership_and_duplicate_evidence
  }
  closed_tail {
    operation_identity  // canonical RawVersion identity
    declared_parents
    canonical_position_or_delete_target  // UTF-16 insertion offset or RawVersion target
    payload
    operation_kind
  }[]
  integrity { base_digest, tail_digest }
}
```

Restore decodes and validates the artifact, allocates a fresh writing-instance identity, materializes an editable position-based branch, applies `closed_tail` in causal order, and verifies text, frontier, fresh-writer distinctness, normalized next-operation behavior, target visibility, and duplicate/conflict behavior against the oracle. `exact_frontier` and every operation identity use canonical RawVersion identities; position mappings use explicitly tagged UTF-16 source offsets, never destination-local LV or item-space integers. For every tail operation, closure also derives the implicit same-agent predecessor `(agent, sequence - 1)` when applicable and verifies its ancestry. The artifact must not contain a raw `FugueTree`, `IndexedState`, full `OpLog`, `Ref`, or `CausalSnapshot`. A missing field or unresolved lookup produces a recorded Candidate C negative result; invoking a full graph walk is a Candidate C failure, not a successful restore. The base tables are canonical logical records, not serialized legacy indexes: if restoration requires rehydrating a destination-local `FugueTree`/`IndexedState` table, the outcome is Candidate B or a Candidate C negative result.

The gate uses the following operation matrix as one artifact rather than scattering the cases across user stories:

| Trace | Minimum behavior to compare | Expected fast-path classification |
|---|---|---|
| Local insert/delete/undelete | fresh writer allocation, normalized next-operation identity/parents, position/target semantics, text, frontier | strict-forward |
| Duplicate/conflicting identity | membership, payload validation, classification | strict-forward or explicit rejection |
| Partial admission prefix | committed prefix, pending remainder, authority/frontier transition | explicit partial result |
| Source-equal causal advance | advanced frontier/version, zero visible-text effect, unchanged cursor/parser/projection state | strict-forward |
| Zero-commit recovered admission | recovered classification, no visible-text effect, coherent snapshot requirement | explicit recovery result |
| Parent-before-child and pending drain | pending membership, wake/drain result, implicit predecessor closure, frontier | closed-concurrent |
| Tail-contained parallel branch | parents, origins, targets, payloads all resolvable | closed-concurrent |
| Missing parent/origin/target | exact missing dependency and fallback reason | non-closed fallback |
| Concurrent work whose ancestor precedes the base | merge result and cold-history boundary | non-closed fallback |

Where a retained base and increment are evaluated, the increment will be treated as a **ClosedTail**, not merely a causally-forward tail. Every parent, origin, delete/undelete target, identity, and payload needed to interpret a tail operation must be resolvable from the retained base authority or from another tail operation. A tail that is not causally closed must take an explicit cold-history fallback rather than silently behaving as a fast-path tail.

The gate succeeds only when a candidate can be restored without hot-loading full history, remains editable, produces the same observable causal behavior as the full-history oracle, and reports cold-history reads explicitly. It produces a capability ledger, candidate comparison, negative-result ledger, and reproducible evidence. It does not select or implement a production persistence architecture.

## User Stories

1. As a Loomark author, I want a reopened document to become editable without waiting for the entire historical archive to replay, so that reopening a large document is responsive.
2. As a Loomark author, I want the reopened text to match the authoritative document, so that faster startup does not show stale or fabricated content.
3. As a Loomark author, I want my first local insert after reopen to have the same causal meaning as an insert after a full-history restore, so that the optimization does not corrupt future edits.
4. As a Loomark author, I want local deletion after a fast restore to remove the same logical target as a full restore, so that visible position and identity semantics remain stable.
5. As a Loomark author, I want local undelete after a fast restore to resolve the same tombstone as a full restore, so that recovery of deleted content remains correct.
6. As a Loomark author, I want non-BMP and Unicode text to retain the same identity and position behavior after restore, so that the fast path does not depend on ASCII-only assumptions.
7. As a Loomark author, I want a locally replayed causally-forward remote trace to apply after fast restore without loading all cold history, so that normal causal admission does not pay the cold-recovery cost.
8. As a Loomark author, I want a locally replayed duplicate remote trace to remain a duplicate after fast restore, so that retransmission does not create a second edit.
9. As a Loomark author, I want a remote change with a missing parent to remain pending rather than being guessed or dropped, so that causal delivery remains reliable.
10. As a Loomark author, I want a pending remote change to drain identically when its parent arrives, so that fast restoration does not change convergence behavior.
11. As a Loomark author, I want a conflicting identity/payload to be rejected or classified exactly as it is after full restore, so that the fast path does not weaken admission validation.
12. As a Loomark author, I want concurrent remote work that cannot be interpreted from the retained base and tail to trigger an explicit recovery path, so that the application never silently misapplies a concurrent change.
13. As a Loomark author, I want a damaged or unsupported retained state to fall back to canonical history without changing the document's authority, so that an optimization failure is recoverable.
14. As a Loomark author, I want a retained state that passes byte-integrity checks but fails semantic comparison to be rejected, so that checksums are not mistaken for proof of correctness.
15. As a Loomark author, I want a crash or restart between retained-state writes not to create an apparently editable but incomplete branch, so that future persistence work has a clear recovery contract.
16. As a maintainer, I want the full-history restore to remain a deterministic oracle, so that every candidate can be checked against existing behavior.
17. As a maintainer, I want candidate state to be serialized and restored in a fresh process-equivalent instance, so that tests cannot pass by retaining aliases to the original operation log or materializer.
18. As a maintainer, I want to know the smallest authority capability needed for local insertion, so that the eventual persisted state does not include unnecessary causal metadata.
19. As a maintainer, I want to know the smallest authority capability needed for deletion and undelete, so that tombstone and target semantics are not accidentally omitted.
20. As a maintainer, I want to know the smallest authority capability needed for duplicate and conflict handling, so that the candidate does not pass only visible-text tests.
21. As a maintainer, I want to know the smallest authority capability needed for pending registration and drain, so that missing-parent behavior is part of the restore contract.
22. As a maintainer, I want to distinguish a missing position-to-identity index from missing causal membership, so that a failed candidate produces an actionable migration result.
23. As a maintainer, I want to distinguish a missing legacy Fugue cache from a missing canonical branch capability, so that a temporary compatibility cache is not promoted to canonical storage by accident.
24. As a maintainer, I want closed-tail validation to check parents, origins, targets, identities, and payloads, so that a tail is not called bounded merely because it is small.
25. As a maintainer, I want tail-contained parallel branches to be tested, so that the fast path does not incorrectly require a linear operation order.
26. As a maintainer, I want a tail with an unresolved dependency to identify the exact cold-history boundary it requires, so that fallback behavior is observable and measurable.
27. As a maintainer, I want strict-forward, closed-concurrent, and non-closed cases classified separately, so that the runtime can later choose direct apply, bounded materialization, or fallback intentionally.
28. As a maintainer, I want cold-history reads counted at the storage boundary, so that a candidate cannot claim replay-free restore while hiding a full read behind an adapter.
29. As a maintainer, I want cold-history bytes and event counts recorded for fallback cases, so that later critical-version or suffix-replay work has evidence.
30. As a maintainer, I want restore time, serialized state size, first-edit latency, and remote-admission latency measured separately, so that a faster restore does not conceal a slower first edit.
31. As a maintainer, I want the candidate comparison to record negative results, so that failed approaches are not rediscovered as future checkpoint proposals.
32. As a maintainer, I want the gate to avoid changing public APIs or generated interfaces, so that the experiment cannot silently become an unsupported production commitment.
33. As a maintainer, I want the gate to avoid changing the wire or portable archive contract, so that the experiment remains independent of future product-format decisions.
34. As a maintainer, I want the gate to use the existing Markdown archive/open and EGW admission behavior wherever possible, so that the evidence tests the real production semantics rather than a parallel miniature implementation.
35. As a maintainer, I want the gate to distinguish the paper's target state separation from today's production capabilities, so that paper claims are not treated as proof of current implementation feasibility.
36. As a maintainer, I want the gate outcome to identify whether a small authority summary, a disposable legacy cache, or a canonical editable branch is the next justified step, so that production work begins from evidence.
37. As a maintainer, I want active browser storage choices deferred until the retained-state shape is known, so that IndexedDB or OPFS does not freeze an unproven data model.
38. As a maintainer, I want full canonical history retained during the experiment, so that undo, audit, historical replay, concurrent merge, and cache repair remain available for comparison.
39. As a maintainer, I want the gate to leave the current local archive behavior unchanged, so that existing durable documents remain recoverable while the feasibility work proceeds.
40. As a coding agent, I want one canonical validation command and an observable completion checklist for the gate, so that the result can be reviewed without interpreting an implementation diary.

## Implementation Decisions

- This is a test-only feasibility slice. It does not implement `Verified BaseBranch`, `ClosedTail`, checkpointing, materialized-state persistence, history compaction, or a new production restore path.
- The Markdown/Loomark seam is the black-box product oracle. The true black-box consumer lives in the archive/standalone harness and imports only the public Markdown façade; package-local Markdown tests may supply typed contract adapters but are not claimed as black-box. It verifies archive/open behavior, text readiness, editability, recovery classification, first edit behavior, and public façade parity.
- The EGW seam is package-local and white-box. It verifies authority hydration, identity membership, pending registration/drain, origin/target lookup, partial admission, ClosedTail validation, and candidate-specific history access. It must not be shared through a production public API.
- The EGW producer is a separate test-only executable package at `internal/restore_feasibility_probe/` with repo-proven `pkgtype(kind: "executable")` and native support. It calls only intentionally `pub` internal module APIs or owns its probe implementation; package-private `*_wbtest` helpers are never imported across package boundaries. Before implementation is accepted, the EGW publish check must prove that the producer is excluded from production package exports and that the extracted package still passes its frozen check; if exclusion cannot be proved, the producer must be replaced by a package-local test stdout path rather than widening the published module.
- The two seam results are joined by serialized evidence, not by importing EGW internal types into Canopy or by exposing a storage handle through Markdown. The EGW-local `is-main` producer emits one versioned JSONL envelope per case to stdout; Nushell captures it into `candidate-captures.jsonl`/`cold-history.jsonl`. The Markdown/browser consumer reads only those bytes and emits its own versioned JSONL observations; Nushell joins records by `run_id` and `case_id`.
- The JSONL handoff envelope is `{ schema_version, run_id, case_id, producer, status, payload }`; producer values are `egw_authority`, `markdown_oracle`, or `runner`. Package-local tests never import this DTO; only the is-main producer and Nushell process exchange it.
- `manifest.json` records `shared_effect_boundary` as `present` with the consumed contract and source revision, or `absent` when #1281 has not landed/been accepted. This field is required even when R0 proceeds independently.
- Candidate state must cross a bytes-only serialization boundary. The final acceptance suite must run a producer and consumer as separate processes, or use a Worker with a bytes-only `postMessage` boundary and no object transfer. The consumer receives no source object, mutable collection, `Ref`, `CausalSnapshot`, operation log, or materializer alias. An in-process decode may supplement this test but cannot replace it.
- Candidate serialization is a test fixture/sidecar. The current v1 portable archive remains the full-history oracle and is not extended with unknown candidate fields.
- The authority-capability ledger uses ordered levels from exact frontier, through committed identity membership, payload/target lookup, writer allocation policy, historical sequence provenance, duplicate evidence, causal ancestry/pending lookup, to the complete resident operation log. The projection ledger uses plain text, text plus position/identity index, disposable legacy materializer, and canonical editable branch.
- The ledger must map every row of the operation matrix to its minimum authority level and projection level. Duplicate membership and writer sequence are explicit ledger entries, not assumptions hidden inside a generic summary.
- Candidate A evaluates a minimal authority summary with the smallest projection that can satisfy the operation matrix. Candidate B adds a versioned, disposable legacy Fugue/IndexedState cache only as a compatibility candidate. Candidate C is the concrete retained position-based branch described in the Solution; the existing text-event prototype is supporting evidence only.
- A candidate is not accepted because its visible text matches. Acceptance requires behavioral equivalence for text, frontier, emitted operation identity and payload, writer sequencing behavior, duplicate/conflict outcomes, pending membership, target visibility, and recovery classification.
- Internal representation equality is not required. The observable contract is the next operation and admission behavior, not equality of FugueTree layout or cache allocation.
- Writer allocation is restore-time behavior, not captured active state. Every restored instance receives a fresh writer identity; two fresh restores must never emit colliding identities. After normalizing the fresh writer identity, the candidate must match the full-history oracle's next-operation sequence, parents, kind, payload, and causal behavior. Historical sequence floors in Candidate C are provenance/evidence only and are never reused as the active writer.
- `ClosedTail` is initially a test invariant and validator, not a production type. For every tail operation, every required declared parent, implicit same-agent predecessor `(agent, sequence - 1)` when applicable, origin/position, delete/undelete target, identity, and payload must be resolved from the retained base authority or the tail itself. The implicit predecessor's ancestry must also be closed; declared parents alone are insufficient.
- The gate classifies three paths: strict-forward direct application; a closed but concurrent tail that can be boundedly materialized; and a non-closed case that must use cold-history fallback.
- A tail is not considered closed merely because it contains a parent chain. Origin metadata, delete/undelete targets, duplicate identity evidence, payload validation, and pending dependencies are part of closure.
- A cold-history fallback must be explicit. It must report the reason for fallback, the boundary or ancestry it required, events read, bytes read, and whether the candidate was discarded or repaired.
- A `cold-history read` means a call into the test-only canonical-history/segment provider. It is distinct from scanning an already-loaded in-memory candidate. The probe records provider reads, while runtime scans are measured separately. The current monolithic v1 archive may report whole-blob load/decode; it cannot claim partial segment-read evidence.
- The full canonical history remains available and authoritative throughout the gate. A candidate state is an accelerator and may never promote unverified text or mutate causal authority.
- Integrity checks may use checksums, generations, or equivalent test metadata, but semantic integrity requires differential comparison with the full-history oracle. A checksum alone cannot make a candidate editable.
- The gate covers a local archive restore into an editable Markdown document and the causal operations needed immediately after restore. It does not introduce a new active-store schema.
- The gate does not choose between IndexedDB and OPFS. Storage-provider work begins only after the required retained-state capabilities and size/update boundaries are known.
- No public archive version, wire version, generated interface, public checkpoint/restore API, or production document lifecycle is changed by this slice.
- R0 must still decide whether a later additive Markdown API is justified. Candidate public concepts may include an explicit text-ready/editable/recovery status or an opaque causal handoff/admission receipt, but raw EGW state, pending identity arrays, history readers, and materializer handles are never public API. Any selected API is a follow-up specification, not an R0 implementation.
- The gate records the current production/legacy dependency honestly. If text plus frontier cannot restore an editable branch, the result is a capability gap, not permission to serialize the entire legacy materializer as canonical state.
- The gate is independent of the paper-aligned target architecture. The paper provides the target rationale; the current production implementation remains the oracle under test.
- The gate remains separate from remote/sync product implementation. Remote cases are included only as restore-behavior probes for causal correctness, not as a collaboration feature delivery.

## Testing Decisions

- Tests verify externally observable behavior and capability boundaries, not private field layout. A candidate that happens to serialize the same internal array is not considered more correct than one with a different representation if behavior is equivalent.
- The full-history restore path is the reference-model oracle. Every candidate is compared after a fresh restoration and after the same deterministic operation trace.
- The EGW white-box probe observes cold-history access at the canonical-history provider seam. The Markdown black-box suite observes only product-level archive/open and recovery behavior. Counting only high-level decode calls is insufficient for the EGW candidate, while the v1 whole-blob path is reported honestly as a coarse load rather than a partial read.
- Before any zero-read assertion is accepted, a known-positive control performs one canonical-history provider read and proves that provider read count, operation count, and byte count all record it.
- Partial admission, pending identity membership, exact missing dependency, origin/target resolution, and ClosedTail validation are asserted in EGW package-local tests. The Markdown suite asserts the corresponding public text/frontier/editability/error behavior; it must not pretend that the façade exposes internal pending identities.
- The core correctness suite covers initial materialization, local insert at start/middle/end, sequential insert, visible delete, stale delete, undelete, non-BMP scalar handling, duplicate delivery, same-identity payload conflict, causally-forward admission traces, source-equal causal advance, zero-commit recovered admission, missing parent, pending drain, and partial admission at the EGW seam.
- Source-equal cases assert an advanced frontier/version with no visible-text effect and unchanged cursor/parser/projection state. Zero-commit recovered cases assert the recovery classification and coherent snapshot requirement without fabricating a text effect.
- The core correctness suite also covers tail-contained parallel branches, concurrent work whose common ancestor is before the retained base, unresolved origins, unresolved targets, and a tail with a missing parent. These cases must classify strict-forward, closed-concurrent, or non-closed fallback rather than merely assert a final string.
- The persistence round-trip suite serializes candidate state, destroys the source instance, restores it through the bytes-only Worker/process-equivalent boundary, and verifies no live alias to the original operation log, `Ref`, causal snapshot, or materializer is required.
- The oracle comparison records visible text, exact frontier, fresh-writer allocation and normalized next-operation behavior, target visibility, and recovery classification at the Markdown seam. Canonical operation identity/payload, committed membership, pending membership, duplicate/conflict classification, origin/target resolution, and partial outcomes belong exclusively to the EGW white-box seam; they are not decoded through the Markdown facade.
- A cold-history probe records provider read count, operation count, byte count, requested ancestry/boundary, and fallback reason. Strict-forward and closed-concurrent fast-path cases require zero provider reads; any in-memory scan of the retained candidate is recorded separately and does not qualify as a provider read.
- Failure tests cover checksum mismatch, generation mismatch, unsupported candidate version, incomplete base, incomplete tail, unresolved dependency, semantic mismatch with a seemingly valid checksum, and candidate hydration failure. Each failure must reject or discard the accelerator without changing canonical authority.
- The first-edit suite measures and compares local insert, local delete, and local undelete immediately after restore. A candidate that restores quickly but performs a hidden full replay on the first edit fails the fast-path contract.
- The causal trace suite runs one, ten, and one hundred locally simulated causally-forward operations, duplicate delivery, pending dependency arrival, and a concurrent fallback. It records latency and cold-history reads but does not implement or claim a remote transport or production collaboration feature.
- The measurement suite records serialized candidate bytes, restore time, first-edit latency, tail replay time, causal trace latency, peak memory where available, cold-history events, and cold-history bytes. It reports p50/p95/max where sample counts support those summaries.
- One canonical Nushell runner, `nu scripts/test-loomark-editable-branch-restore-feasibility.nu --output-dir <dir>`, owns the gate exit status and must write exactly the fixed artifact set: `manifest.json`, `result.json`, `capability-ledger.json`, `candidate-captures.jsonl`, `candidate-results.json`, `operation-matrix.jsonl`, `oracle-differential.jsonl`, `cold-history.jsonl`, `negative-results.json`, and `validation.log`. `result.json` contains `schema_version: 1`, `status` (`pass` or `fail`), `failure_class` (null or one of the fixed classes below), candidate outcomes, and artifact paths.
- Fixed failure classes are `preflight_invalid`, `toolchain_failure`, `submodule_failure`, `harness_failure`, `oracle_mismatch`, `causal_semantics_mismatch`, `unexpected_cold_read`, `evidence_missing`, `interface_drift`, `measurement_failure`, and `runner_failure`. A Candidate A/B/C inability to satisfy the contract is not a runner failure: it is `candidate_outcome: negative` in `candidate-results.json`, with the missing capability and evidence in `negative-results.json`, and the overall gate may still pass.
- The runner returns exit code `0` only when all required suites and artifacts complete, even if one or more candidates are negative. It returns `10` for preflight, `20` for toolchain, `21` for submodule, `30` for harness, `31` for oracle mismatch, `32` for causal semantics mismatch, `33` for unexpected cold read, `34` for missing evidence, `35` for interface drift, `40` for measurement, and `50` for runner-internal failure.
- Runner preflight requires a clean worktree and records the baseline hashes of affected `.mbti` files. `interface_drift` means an unexpected uncommitted regeneration during the run; intended committed internal-package interface changes are reviewed evidence, not a self-failure. Unrelated pre-existing generated-interface changes are a separate `preflight_invalid` result.
- CI syntax-checks the Nushell runner with `nu --ide-check` and runs its fixture tests; the gate runner is included in the same tooling path filter as the affected Markdown/EGW packages.
- The fixed runner exit-code contract is documented in the Nushell runner header and the scripts tooling documentation so that the numeric codes are not an unregistered local convention.
- Tests retain the full-history oracle and candidate traces as raw evidence so that a failed candidate can be analyzed without rerunning the entire browser harness.
- Prior art includes the existing Markdown archive/open contract, `open_with_semantic_attachment`, explicit archive restore limits, existing archive/repository lifecycle tests, EGW admission contract tests, the Causal Cut prototype, the fresh-writer authority prototype, and the editable text-session materializer prototype. The paper-aligned text-event adapter is Gate A branch evidence, not a required source file in every clean checkout.
- No test requires a public test-only API. EGW instrumentation remains package-local `*_wbtest` evidence; Markdown integration remains black-box. If a cross-package helper is unavoidable, it must be explicitly classified as a test-helper package and its generated-interface change reviewed; it may not appear accidentally in a production façade.
- The acceptance checklist is satisfied only when `result.json.status == "pass"`, every candidate has `pass`, `negative`, or explicit `not_applicable` outcome evidence, and the submodule/interface/review criteria are recorded in `manifest.json` and `validation.log`. A passing subset of local text tests is not sufficient.

## Out of Scope

- Implementing a production `Verified BaseBranch` or `ClosedTail` type.
- Choosing or implementing a checkpoint cadence, snapshot compaction policy, or history-trimming policy.
- Replacing canonical history with a snapshot or discarding cold history.
- Changing the portable archive envelope, archive version, wire version, or sync protocol.
- Changing the production `Document`, `TextState`, `MarkdownEditor`, `FugueTree`, `OpLog`, or `IndexedState` ownership model.
- Implementing any public restore, checkpoint, branch, history-reader, or cold-history API. R0 may recommend a later additive opaque Markdown API, but that API requires a separate reviewed specification and implementation task.
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
- The accepted Causal Authority residency architecture already supports the direction of cold text/frontier presentation with durable history and explicit fallback. This gate supplies the missing proof for the current production EGW implementation; it does not replace that architecture.
- The accepted architecture requires local event generation to remain disabled until a text/frontier candidate has been validated against authority. The gate must preserve that rule in its failure cases.
- The completed local archive repository owns a complete local archive and explicit recovery classification today. This gate must not silently change that durable contract while testing a future active-store separation.
- The existing EGW Gate A reference-model issue and the P3 characterization remain related evidence, not substitutes for this gate. This gate tests whether current production behavior can hydrate an editable branch without full history hot loading. The paper-aligned text-event adapter is referenced as Gate A branch evidence, not assumed to exist in every clean checkout.
- Before publishing the API-boundary decision, re-check #1281. If its authority-owned effect/receipt boundary has landed and passed review, record the exact consumed contract; otherwise record that the shared boundary is absent and keep the R0 result independent.
- The expected outcomes are intentionally asymmetric: A is the preferred result; B is an acceptable temporary migration bridge only if it is bounded, discardable, versioned, and reconstructible; C is the migration direction if legacy materialization cannot be reduced to a bounded disposable cache. C is not considered evaluated until a concrete retained branch can be serialized and restored without `Branch::checkout`-style full walking.
- This is also an API-boundary investigation. If the gate shows that a stable product workflow needs a capability beyond the current Markdown façade, the result must describe the smallest opaque additive API and keep EGW authority types private. If the capability is needed only to observe tests, no public API change is justified.
- Any EGW white-box change follows submodule ownership rules: commit and validate it in the EGW repository, push it through its own review, and update the Canopy pointer only after the referenced commit is reachable. The gate evidence must identify both repository revisions.
- The gate should be labeled `ready-for-agent` only after its test-only scope, oracle, operation matrix, and observable exit conditions are accepted. The unresolved choice of A, B, or C is the purpose of the gate, not an implementation ambiguity within it.
- The spec should be published as a separate task from the completed archive persistence issue and from the remote-sync measurement issue. Its result should link back to the measurement evidence and forward to the production implementation issue selected by the gate.
