# EGW multi-document runtime reassessment

**Date:** 2026-08-24

**Status:** Directional roadmap — not an implementation plan or commitment

**Tracking:** [#1362](https://github.com/dowdiness/canopy/issues/1362)

## How to use this roadmap

This document points Canopy in a preferred direction. It does not approve immediate implementation. It does not promise that every checkpoint will happen. It also does not fix package names, public APIs, or delivery dates.

The source-first baseline described here applies to Loomark application documents. It does not replace Canopy's CRDT-first editor framework.

Use the safety rules when a real product need appears. Before any checkpoint or evidence work starts, create a separate, small issue with its own scope and stop conditions. Consider only the next checkpoint, gather evidence, and stop if the evidence does not support more work.

## The question

Should Canopy add something like Automerge Repo? Automerge Repo manages many documents and can load or sync them from storage and the network. If we add something similar, where do we draw the lines between causal authority (the part that decides which edits are allowed and in what order), source-first editing (where the exact source text is the normal saved form), workspace management, storage, and networking?

## Recommendation

**Do not build an always-on Automerge Repo clone.** Do not make every managed document depend on a live shared-editing history. That does not fit how Canopy works today.

If multi-document work becomes necessary, keep these five responsibilities separate:

1. **Source-first Document Catalog.** Every normal Loomark document lives here. A "source-first" document saves its exact source text as the normal record. A linked file may also be the file authority. The shared-editing history is optional. Most documents never create or store an EGW (event-graph-walker) history at all.

2. **Optional reference-only Workspace Index.** When the app needs to show a list of documents or link parent documents to child documents, add a thin index. This index only holds references (pointers) to other documents. It does not hold their content or their history. Think of it like a table of contents, not a folder that contains the files.

3. **Per-document Causal Authority Host — only when collaboration is required.** A "causal authority" is the part of the system that decides which edits are allowed right now and in what order. Most documents do not need one. A document gets its own authority host only when causal collaboration is explicitly required and the evidence gate passes.

4. **Private Authority Directory.** This is an internal bookkeeping table inside the application shell, which is the thin layer that performs I/O and owns live objects. It makes sure that for any given `DocumentId` (a permanent name for a document), only one authority host is the "real" one at a time. It also tracks warm documents (still in memory) versus cold documents (closed and saved), and matches old async results to the right generation so stale results do not cause bugs.

5. **Separate payload-opaque collaboration runtime.** The collaboration runtime handles networking, timers, and backpressure (slowing down when the network is busy). "Payload-opaque" means it passes document messages along without opening or interpreting them. The causal logic stays in EGW and peer-sync, not in this layer.

Evidence may later support a convenient `Repo` façade on top. Before that decision, validate the source-first catalog boundary and the point where a normal document can become a collaboration document.

## Why the workspace coordinator stays separate

The existing `workspace/coordinator` already has several jobs. It owns shared reactive cells, editor registration, dependency tracking, and garbage-collection roots ([`types.mbt:133-155`](../../modules/canopy/workspace/coordinator/types.mbt), [`methods.mbt:24-156`](../../modules/canopy/workspace/coordinator/methods.mbt)). Adding history, storage, networking, document IDs, and authority would give it too many different jobs. The application shell should connect the coordinator to the workspace index and authority directory while keeping them separate.

## Why the IDs are different

Two kinds of ID serve different jobs:

- **`DocumentId`** is a permanent application-level name for a document. It survives restarts, renames, and moves.
- **`ReplicaId`** identifies one writing instance — one copy of the document being edited on one device.

These must be different. A projection `NodeId` (an internal position marker) cannot be used as a cross-replica document reference because after divergent reconciliation (when two devices merge different edits), the same logical node may point to different positions on different replicas ([`2026-05-23-workspace-identity-decision.md:12-45`](2026-05-23-workspace-identity-decision.md), gate #4 in that document).

## Why changes across documents are not atomic

"Atomic" means a group of changes either all happen together or none happen. Changes across independent EGW documents are not atomic. A manifest update (changing the list of child documents) and a child document update can be seen in different orders by different replicas ([`2026-05-22-spec-aware-workspace.md:533-537`](2026-05-22-spec-aware-workspace.md)). If we ever need grouped changes, we must design a staged application protocol, idempotent operations (operations that give the same result no matter how many times they run), and orphan recovery (fixing a child whose parent reference arrived before the child itself).

## Current Canopy constraints

### Normal editing is source-first

Production Loomark separates four layers: browser draft, canonical source, source record, and optional causal archive. A CRDT is a data structure that merges edits from separate copies. CRDT changes, archive preparation, and IndexedDB browser-storage work must not go into the 10 ms raw input task. The causal archive only gets created when there is an explicit need and evidence gate — for example, when collaboration is required ([`2026-08-24-loomark-source-first-interactive-contract.md`](../decisions/2026-08-24-loomark-source-first-interactive-contract.md#decision)).

Because of this, the Automerge Repo assumption that "every open document is always an EGW document" does not hold in Canopy.

### Causal authority is one per document

When a document reconnects while still warm (still in memory), it reuses the existing authority. When it reopens cold (from disk), it must verify that the portable text, exact frontier (the last known sync point), and canonical history all agree before allowing local edits. Being able to read the text does not mean you are allowed to edit it causally ([`2026-08-12-causal-authority-residency.md:38-86`](../decisions/2026-08-12-causal-authority-residency.md)).

The restore lifecycle has seven states. It covers loading, two readable recovery states, waiting for the editor to appear on screen, editable, terminal readable failure, and unavailable. Async results are matched by mount generation ([`2026-08-20-loomark-private-restore-coordinator.md:33-79`](../archive/decisions/2026-08-20-loomark-private-restore-coordinator.md)). The `AuthorityDirectory` must not skip this ordering.

### Collaboration is already split into five layers

The five layers are: EGW core, EGW-versioned peer-sync companion, payload-opaque collaboration runtime, infrastructure providers, and application policy. This split is settled ([`2026-07-21-egw-collaboration-responsibility-boundary.md:60-164`](../decisions/2026-07-21-egw-collaboration-responsibility-boundary.md)). The current `modules/canopy/sync_session` still exposes `@text.Version` and `@text.SyncMessage` on its public surface, so it is not yet the payload-opaque runtime of Layer C ([`sync_session.mbt:18-53`](../../modules/canopy/sync_session/sync_session.mbt)).

## Lessons from other projects

### Automerge Repo

Automerge Repo is more than a set of adapters. `DocumentQuery` combines results from multiple sources (storage, network) with `pending/ready/unavailable` states and uses source priority to avoid saying a document is unavailable too early ([`DocumentSource.ts:4-40`](https://github.com/automerge/automerge-repo/blob/5815ac8226c2357b20ba98f827b362bfadc11aec/packages/automerge-repo/src/DocumentSource.ts#L4-L40), [`DocumentQuery.ts:8-108`](https://github.com/automerge/automerge-repo/blob/5815ac8226c2357b20ba98f827b362bfadc11aec/packages/automerge-repo/src/DocumentQuery.ts#L8-L108)). Each document gets its own `DocSynchronizer` that tracks peer state. `CollectionSynchronizer` is a thin routing layer ([`DocSynchronizer.ts:90-111`](https://github.com/automerge/automerge-repo/blob/5815ac8226c2357b20ba98f827b362bfadc11aec/packages/automerge-repo/src/synchronizer/DocSynchronizer.ts#L90-L111), [`CollectionSynchronizer.ts:82-177`](https://github.com/automerge/automerge-repo/blob/5815ac8226c2357b20ba98f827b362bfadc11aec/packages/automerge-repo/src/synchronizer/CollectionSynchronizer.ts#L82-L177)).

**What to reuse:** per-document decision owner, thin collection router, multi-source progress tracking, bounded flush.

**What not to copy:** always-live CRDT handles, using source priority alone to stand in for authority, and a combined storage/network façade. Canopy needs a richer lifecycle than just "ready" because file authority, source readability, and causal editability are different things.

### Yjs

Yjs does not require a central repo. You can attach persistence and network providers directly to the same `Y.Doc` ([`README.md:463-505`](https://github.com/yjs/yjs/blob/567af9b41fe5e1290e0cfe7fcc025a9f98c514a0/README.md#L463-L505)). Subdocuments have their own `guid`, `shouldLoad`, and `load()`. A parent document can refer to a child without forcing the child to load right away ([`Doc.js:17-24`](https://github.com/yjs/yjs/blob/567af9b41fe5e1290e0cfe7fcc025a9f98c514a0/src/utils/Doc.js#L17-L24), [`Doc.js:142-164`](https://github.com/yjs/yjs/blob/567af9b41fe5e1290e0cfe7fcc025a9f98c514a0/src/utils/Doc.js#L142-L164)). `y-indexeddb` appends document updates and compacts them after a threshold ([`y-indexeddb.js:9-44`](https://github.com/yjs/y-indexeddb/blob/ff468b5e9cb329165d7db7a9a9c4cf948aee5f5f/src/y-indexeddb.js#L9-L44)).

**What to reuse:** workspace parent holds independent child references, children load lazily, providers compose per document.

**What to watch out for:** providers must implement subdoc load semantics, and Canopy cannot assume every normal document is always a CRDT document.

### iroh-docs

`DocsApi` offers collection-level create/list/open/import. Each `Doc` handle manages one document's close/share/start_sync/subscribe ([`api.rs:195-265`](https://github.com/n0-computer/iroh-docs/blob/8cfeacb087b4b195b1930683aa4448e990da0659/src/api.rs#L195-L265), [`api.rs:268-299`](https://github.com/n0-computer/iroh-docs/blob/8cfeacb087b4b195b1930683aa4448e990da0659/src/api.rs#L268-L299), [`api.rs:422-470`](https://github.com/n0-computer/iroh-docs/blob/8cfeacb087b4b195b1930683aa4448e990da0659/src/api.rs#L422-L470)). Read/write capability is tied to document namespace identity ([`sync.rs:175-263`](https://github.com/n0-computer/iroh-docs/blob/8cfeacb087b4b195b1930683aa4448e990da0659/src/sync.rs#L175-L263)).

**What to reuse:** thin collection façade, per-document state, subscriptions, and capability.

**What not to copy:** making identity and write secrets the same thing. In Canopy, document identity, application authorization, and EGW `ReplicaId` are separate concerns.

## Alternatives

| Option | Verdict | Main reason |
|---|---|---|
| Always-on full Automerge Repo | Rejected | Breaks the source-first baseline and the 10 ms input gate. Causal archive target is not ready. |
| Yjs-style per-doc providers only | Partially adopted | Good independence and lazy loading, but nothing ties together availability, authority, and promotion. |
| Whole workspace in one EGW container | Limited use only | Puts all files in one history, but loses partial loading, independent sharing, and failure isolation. |
| Global authority actor | Rejected | Goes against per-document authority residency and failure isolation. |
| **Hybrid (recommended)** | **Recommended** | Keeps source-first editing. Only the children that need causal capability get upgraded. |

EGW does have a multi-block `container::Document` type, so the single-container option is technically possible. But current sync targets the whole document, and the Canopy `SyncEditor` uses a flat text façade. A whole-workspace container only makes sense when you can accept always-loading everything, whole-history sync, moderate history size, workspace-wide undo, and no failure isolation.

## Responsibility diagram

```text
Application Workspace
├─ DocumentCatalog             source records / DocumentId / file association
├─ WorkspaceIndex?             reference-only; does not hold child content or history
├─ existing Coordinator        reactive editor cells / GC / dependency lifecycle
└─ private AuthorityDirectory  canonical host uniqueness / generation / warm-cold
      └─ CausalAuthorityHost per promoted document
           ├─ EGW text OR container typed authority
           ├─ per-peer peer_sync::State
           ├─ causal readiness/admission reducer
           └─ persistence decisions

Payload-opaque Collaboration Runtime
└─ Network providers / timers / backpressure

Storage and File providers
└─ source record / causal archive / cold history capabilities built separately
```

The `AuthorityDirectory` is an internal index inside the application shell, not a public repository. Private lifecycle routers or separate typed registries hold the text and container hosts. Both hosts use EGW. There is no second CRDT engine to justify a public common interface yet.

## Safety rules

1. Normal input tasks must not run EGW, archive, network, or storage I/O.
2. `DocumentId` is durable application identity. `ReplicaId` is writing instance identity. They are different.
3. At most one canonical host exists for each `DocumentId`. `AuthorityGeneration` is only used to reject stale work and finish a safe handoff.
4. Readable does not mean editable. Every mutation re-checks readiness and generation.
5. Cold activation becomes editable only after history/frontier/source consistency checks pass.
6. Stale async completions are no-ops if the generation does not match.
7. Restart-time durability of pending causal operations must be handled explicitly when the sender cannot guarantee re-delivery.
8. For file-backed documents, do not confuse File Authority with Causal Authority ([`2026-08-09-markdown-file-backed-authority-and-external-admission.md:45-93`](../decisions/2026-08-09-markdown-file-backed-authority-and-external-admission.md)).
9. Manifest and child operations are not atomic. Treat orphans, missing children, and torn references as normal states that need recovery.
10. The collaboration runtime does not interpret document content causally. Causal recovery stays in EGW/peer-sync.

## Possible future checkpoints

These checkpoints are decision points, not assigned tasks or promised features. Start one only when a real product need justifies it. Each checkpoint may end with a decision to stop.

1. **Source catalog evidence** — test multi-document create/open/switch/delete, atomic source records, and the 10 ms input goal. Do not add EGW at this point.
2. **Reference index evidence** — explore independent child references, lazy open, and missing/orphan recovery. Verify locally first. Do not lock down a sync manifest.
3. **One-document promotion evidence** — explore pinning a source revision, preparing a causal candidate without stopping input, and switching modes only after validation. Stay source-first on failure.
4. **Authority residency evidence** — check warm reconnect, cold read-only access, canonical fallback, stale generations, and restore after eviction.
5. **Collaboration runtime evidence** — explore a payload-opaque reducer separate from the current text-coupled `sync_session`. Use text and container drivers to test the boundary.
6. **Cross-document protocol evidence, only if needed** — study grouped changes, staged publication, and orphan recovery. Do not choose a single container only to avoid this question.

## When to reconsider this decision

Re-evaluate if any of these become true:

- All product documents are formally required to be collaboration-capable at all times, and the source-first baseline is removed.
- Measured data shows that promotion/cold admission costs are unacceptable, and always-resident authority wins on total cost.
- Independent sharing, lazy loading, and failure isolation are not needed, and cross-document atomicity is the top priority. Only then does the single container become the strong option.
- A real second CRDT engine (not EGW) needs to be supported. Only then should a public engine adapter seam be considered.
- Most cross-document operations must be atomic to be correct, and an application-level staged protocol cannot meet the requirement.

None of these conditions have evidence today. So the safest choice — and the one most aligned with Canopy's existing decisions and external implementation findings — is **source-first catalog + reference-only workspace index + optional per-document causal authority**.
