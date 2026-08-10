# EGW staged publication responsibility boundary

**Date:** 2026-08-09

**Status:** Accepted target architecture; implementation not started

**Related:**

- [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)
- [Markdown file-backed authority and external admission](2026-08-09-markdown-file-backed-authority-and-external-admission.md)
- [Library API boundary](2026-06-11-library-api-boundary.md)

**Reader:** Maintainers designing or reviewing causal sealing, publication outcomes, or Resolution draft application across EGW, Loomark, and the collaboration runtime.

**Decision:** Introduce an EGW-versioned staged-publication companion that owns causal sealing, a sealed frontier/version, classification of head advancement after seal, and committed/rejected/committed-with-issue publication outcomes with no-retry-after-commit semantics. The companion owns no peers/windows, transports, timeouts, persistence, file I/O, or product resolution policy.

**Keep until:** Permanently. ADRs are durable and are superseded rather than deleted.

**Disposition:** Supersede this record if implementation evidence from both text and container drivers shows that the staged-publication boundary cannot remain independent of the adjacent layers.

## Context

The existing EGW collaboration responsibility boundary separates collaboration into five layers: EGW core, an EGW-versioned peer-sync companion, a reusable payload-opaque collaboration runtime, infrastructure providers, and application policy. That boundary owns transport, session management, and CRDT synchronization.

This ADR specializes that boundary for Resolution draft publication. A Resolution draft is a separate EGW-backed candidate with its own causal history, collaboratively editable by multiple Writing instances. When a draft reaches a convergence point, it must be sealed and applied to the main Editing Document without merging draft history directly into main history, and without allowing retry after a committed outcome.

Implementation evidence:

- EGW text and sync façades support fixed-version read-only materialization while the live head advances, and sync reports that classify pending operations. See [`deps/event-graph-walker/text/pkg.generated.mbti`](../../deps/event-graph-walker/text/pkg.generated.mbti) and [`deps/event-graph-walker/sync/pkg.generated.mbti`](../../deps/event-graph-walker/sync/pkg.generated.mbti) for current source-verified interfaces, not promised new package API.
- [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)
- [Local-first document ownership](../design/local-first-document-ownership.md)

These sources demonstrate that EGW can produce a fixed-version read-only view while the live head continues to advance, and that sync reports can classify pending operations. They do not prove that a staged-publication companion can remain independent of the peer-sync or runtime layers.

## Responsibility split

| Reason to change | Owning layer |
|---|---|
| CRDT operations, causal rules, façade versions, sync-message formats, or document-local pending replay change | EGW core (unchanged) |
| Causal sealing, sealed frontier/version, head-advancement classification after seal, or publication outcome semantics change | EGW staged-publication companion |
| Participant sets, freeze/flush acknowledgments, timeouts, coordinator succession, or transport change | Payload-opaque collaboration runtime |
| Network, hosting, room routing, access control, reconnect backoff, or storage-provider implementation changes | Infrastructure provider |
| Conflict variants, Resolution workspace lifecycle, seed/UI, Metadata, Publication ledger, File Authority, Use External/Use Loomark/Keep Both behavior, application of one Resolution transaction to main Editing Document, file-first Autosave, recovery, or undo change | Loomark |

EGW core remains unchanged: no writable branch/fork and no tentative Resolution draft operations in the main Editing Document history. A separate EGW-backed Resolution draft has its own causal history and can be collaboratively edited by multiple Writing instances.

## State and outcome invariants

**Seal uses a separate draft EGW history.** The current text and sync façades support fixed-version read-only materialization while the live head advances, and sync reports that classify pending operations. Sealed checkout remains fixed while later draft operations advance the live head; those operations remain recoverable outside the applied candidate.

**Seal coordination does not wait forever or discard late work.** The collaboration runtime freezes connected participants and gathers flush acknowledgments. When a participant does not respond, Loomark offers `Wait`, `Apply Current Draft`, and `Cancel`; choosing `Apply Current Draft` seals the known frontier, and operations arriving later advance a Recovery head without changing the sealed checkout.

**Draft history is never merged directly into main Editing Document history.** Application materializes the sealed candidate and commits one Resolution transaction. The main Editing Document's causal history does not absorb draft operations.

**EGW cannot alone guarantee exactly-once across main mutation, Markdown body file, and Metadata.** Loomark assigns a stable Publication token to one sealed candidate and supplies it opaquely to the companion. Application-owned Metadata carries a Publication ledger that binds the token to durable main-history before/after versions, its Resolution receipt, and outcome; EGW operations and the Markdown body file do not carry the token. The ledger lets Loomark detect duplicate main-history application and correlate partial recovery, but does not make the stores atomic; a committed or committed-with-issue outcome never authorizes retry.

**Destructive resolution is prepared before file replacement.** Normal Autosave remains file-first. Before a Conflict resolution can replace the external variant in the Markdown body file, Loomark durably records the Publication token, both variants, sealed candidate, and expected file fingerprint. Preparation does not mutate main history or establish Saved status. After main mutation commits, Loomark persists the resulting history and Publication ledger entry as `CommittedPendingFile`, atomically replaces the file, then finalizes the workspace as `Applied`. This resolution-specific sequence preserves enough evidence to classify and resume a partial publication after crash without changing ordinary Autosave ordering.

**Crash recovery classifies durable evidence rather than guessing execution.** On reopen, Loomark compares the prepared token with durable main history and compares the current file with the prepared external and candidate variants. Because neither EGW operations nor the file carry the Publication token, an absent ledger entry cannot by itself classify main mutation as rejected:

| Publication ledger entry bound to durable main history | Current file | Recovery |
|---|---|---|
| Absent | Prepared external variant | Preserve the prepared state and report indeterminate publication; reconcile durable and replicated main-history evidence without retrying or canceling the main mutation |
| Absent | Sealed candidate | Preserve the prepared state and candidate, report indeterminate publication, and require durable idempotency evidence before any main-history action |
| Absent | Other observed content | Preserve every variant, keep publication indeterminate, and require revalidation without retrying main mutation |
| Present | Sealed candidate | Finalize Metadata and mark the workspace applied |
| Present | Prepared external variant | Report a committed persistence issue; do not retry main mutation |
| Present | Other observed content | Enter a new Content conflict; do not retry main mutation |

File-content equality alone never authorizes reconstruction or retry of main mutation. Without durable idempotency evidence, the prepared state remains read-only and Loomark offers only reconciliation, later recovery, or content-only recovery.

`CommittedPendingFile` is read-only. Loomark may complete file persistence, review newly observed content, choose a new location, or close for later recovery, but it may not accept ordinary edits or retry the Resolution transaction. The workspace becomes `Applied` only after exact self-write acknowledgment and Metadata finalization.

**Plain-file conflict preservation is scoped to observed variants.** Immediately before replacement, Loomark rereads the file and compares it with the expected fingerprint; a mismatch stops publication and requires revalidation. Exact self-write acknowledgment classifies the result after replacement. A portable plain-file workflow cannot guarantee preservation of an intermediate external write that another uncooperative process replaces before Loomark can observe it, and the product must not imply otherwise.

**Incubate with Loomark/text evidence.** Do not claim stable generic support until a second real adapter/consumer validates the seam. Current container façade must not be claimed to have text-equivalent historical materialization.

## Relationship to existing ADR

This ADR specializes the EGW collaboration responsibility boundary. It does not supersede any existing ADR. The peer-sync companion, collaboration runtime, infrastructure providers, and application policy layers retain their ownership as defined in the 2026-07-21 ADR. This ADR adds a sibling EGW-versioned companion responsibility beside peer-sync, rather than a new universal layer, and clarifies that Resolution draft publication is application policy (Loomark) that consults the companion for seal and outcome semantics.

## Rejected alternatives

### Writable branch or fork in EGW core

Rejected because it would couple EGW core to Resolution draft semantics and require EGW to understand main Editing Document history. The separate draft history keeps EGW core unchanged and allows the companion to own seal semantics independently.

### Tentative Resolution draft operations in main Editing Document history

Rejected because it would make main history aware of draft convergence and require rollback or conditional commit. The separate draft history and one-shot application keep main history deterministic.

### EGW-owned exactly-once guarantee across main mutation, file, and Metadata

Rejected because EGW owns CRDT synchronization, not file I/O, Metadata persistence, or application-level transaction semantics. An application-assigned Publication token carried opaquely by the companion supports duplicate detection and recovery correlation without coupling EGW to persistence.

### Merge draft history into main history at application

Rejected because it would require main history to understand draft causal structure and would make undo/recovery ambiguous. Materializing the sealed candidate as one Resolution transaction keeps main history linear and undoable.

### Claim stable generic support before second adapter validates

Rejected because the container façade has no text-equivalent historical materialization evidence. Incubating with Loomark/text evidence prevents premature API commitment.

## Consequences

- EGW core remains free of Resolution draft semantics and main-history awareness.
- The staged-publication companion is a deterministic core that accepts seal events and returns outcome and next-state commands. It does not own peers, transports, timeouts, persistence, or product policy.
- Loomark owns application of one Resolution transaction to main Editing Document, including file-first Autosave, recovery, and undo.
- The collaboration runtime remains payload-opaque; it does not interpret seal or publication semantics.
- An application-owned Publication ledger binds the Publication token and outcome/receipt to durable main history for duplicate detection and partial-recovery correlation; it does not make main mutation, file, and Metadata atomic.
- Sealed checkout remains fixed while later draft operations advance the live head; those operations remain recoverable outside the applied candidate.
- Current container façade must not be claimed to have text-equivalent historical materialization until a second adapter validates the seam.
- Current text and sync façade capabilities are source-verified implementation evidence for fixed-version read-only materialization while live head advances and pending-operation classification; they are not promised new package API. See [`deps/event-graph-walker/text/pkg.generated.mbti`](../../deps/event-graph-walker/text/pkg.generated.mbti) and [`deps/event-graph-walker/sync/pkg.generated.mbti`](../../deps/event-graph-walker/sync/pkg.generated.mbti) for the current interfaces.

## Non-goals

- Implementing or moving code in this documentation change.
- Changing EGW core to own Resolution draft semantics or main-history awareness.
- Defining the peer-sync companion's protocol or the collaboration runtime's envelope format.
- Specifying Loomark's Resolution workspace lifecycle, conflict resolution UX, or Autosave policy.
- Claiming generic support for container or non-text façades before a second adapter validates the seam.
