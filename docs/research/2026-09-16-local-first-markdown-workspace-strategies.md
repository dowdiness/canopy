# Local-first Markdown workspace strategies

**Date:** 2026-09-16

**Status:** Research — not an implementation proposal

**Access date for external sources:** 2026-09-16

## Question

How do representative Markdown and adjacent writing workspaces store, expose,
synchronize, and recover user data, and what bounded choices remain for Loomark?
This note compares strategies rather than treating a product name as a
strategy. Repository documents are treated as Loomark requirements and
inferences, not as external evidence.

## Reading boundary and Loomark constraints

**Observed repository facts.** Loomark currently uses browser IndexedDB records
whose durable Source is exact text plus document identity; its Catalog is
rebuildable, and Import creates a fresh identity. The README describes this
implemented behavior ([Loomark README](../../apps/loomark/README.md#autosave-and-recovery),
[repository decision](../decisions/2026-08-29-loomark-source-repository.md)).
The accepted direction separates Causal Authority (operation history and
identity), Current State, Portable Artifact, and derived caches
([ownership design](../design/local-first-document-ownership.md#four-authorities-kept-distinct)).
The accepted file-backed ADR makes an associated Markdown body file File
Authority for portable content while operation history remains Causal
Authority; unassociated Markdown remains Import, and bounded External admission
must preserve observed variants on mismatch ([ADR](../decisions/2026-08-09-markdown-file-backed-authority-and-external-admission.md)).

**Design inference.** A file can be user-owned and still fail to preserve
causal identity. Copying bytes with Dropbox, rsync, or Git is transport of file
states; it does not turn those states into causally related replicas. Loomark
must therefore name which authority is being synchronized and what happens when
body and metadata disagree.

## Comparison dimensions

For every strategy, the relevant questions are: what is authoritative; what is
written on disk; what works offline; how external edits are admitted; what
synchronization topology exists; how conflicts are represented; whether
identity and history survive; how backup/recovery works; how much user control
and longevity it offers; and which platforms or permissions constrain it.

## Strategy A — ordinary Markdown files as authority

### Evidence-backed examples

**Obsidian.** Obsidian's maintained help source states that a vault is a
local-filesystem folder, notes are Markdown-formatted plain-text files, external
editors may change them, and `.obsidian` contains vault-specific configuration
([How Obsidian stores data](https://github.com/obsidianmd/obsidian-help/blob/master/en/Files%20and%20folders/How%20Obsidian%20stores%20data.md)).
This is a file-authority model: the body and configuration files are the
portable substrate, not a hidden server database. Obsidian's official Sync
conflict page documents conflict resolution rather than claiming that arbitrary
concurrent file edits are causally merged
([Conflict resolution](https://obsidian.md/help/Obsidian+Sync/Conflict+resolution)).

**Logseq.** The maintained first-party repository describes Logseq as an
open-source, privacy-first knowledge-management and collaboration platform with
Markdown support ([Logseq README](https://github.com/logseq/logseq)).
Its current documentation distinguishes DB graphs from file graphs, states that
file graphs moved to a separate first-party project, and documents `db.sqlite`
as the DB graph's data authority
([DB-version changes](https://github.com/logseq/docs/blob/master/db-version-changes.md)).
The repository labels DB graphs beta and RTC sync alpha, warns that data loss is
possible, and recommends automated or regular SQLite backups
([DB version section](https://github.com/logseq/logseq#-database-version)).
That gives two concrete strategies in one product lineage; the evidence does
not justify treating the DB graph as ordinary Markdown authority.

### Operational shape

- **Authority/on-disk shape (fact):** Obsidian uses one Markdown file per note,
  with application configuration and attachments in the vault. Logseq's
  current DB graph instead stores graph data in `db.sqlite`; its file graph is
  now a separately maintained mode. **Inference:** in file-authority products,
  identity is usually path/name plus application conventions, not a portable
  operation identity.
- **Offline (inference bounded by shape):** any local editor can read and write
  the files without a network. This is availability of local bytes, not proof
  of merge safety.
- **External edits (fact/inference):** a file watcher can observe changed bytes,
  but a plain file has no writer ID or causal parent. Obsidian's conflict
  documentation's existence of conflict handling is evidence that concurrent
  file states need explicit treatment; it is not evidence of CRDT convergence.
- **Sync topology:** Dropbox/rsync-style copying is replica-to-replica file
  transport. Git adds a repository and remotes, but neither supplies causal
  operation identity for an editor's keystrokes.
- **Conflicts:** preserve competing files or ask the user to choose/merge;
  automatic line merging is necessarily a policy over snapshots. A dangerous
  failure is last-writer replacement that deletes a variant.
- **Identity/history:** file paths and Git commits can identify versions, but
  reopening copied text cannot prove it is the same Loomark document or recover
  editor operations. This follows directly from Loomark's ownership invariant
  that text alone does not preserve identity ([ownership design](../design/local-first-document-ownership.md#the-distinction-this-design-exists-to-hold)).
- **Backups/recovery:** ordinary filesystem backups and Git history are highly
  inspectable; recovery can restore a prior file. Recovery does not restore a
  causal CRDT history unless that history was separately stored.
- **Longevity/control/platform:** plain UTF-8 Markdown is maximally portable and
  user-inspectable. Browser Loomark cannot assume arbitrary directory access:
  the WHATWG File System Standard makes access permission-sensitive and notes
  that external changes and their reflection are implementation-defined
  ([File System Standard](https://fs.spec.whatwg.org/#files-and-directories)).

**Loomark implication (inference):** the accepted ADR's File Authority mode is
more precise than declaring `.md` globally authoritative: association preserves
identity only for the associated document, while an unassociated copy is
Import. External admission must be bounded, exact-replay checked, optimistic,
and variant-preserving rather than pretending to reconstruct external intent.

## Strategy B — application-owned database/archive with Markdown portability

**Joplin.** Joplin's official synchronization documentation says most sync logic
is abstracted behind drivers exposing filesystem-like read/write/delete/list
operations, and lists Joplin Cloud, Nextcloud, S3, WebDAV, Dropbox, OneDrive,
and local filesystem targets
([Synchronisation](https://joplinapp.org/help/apps/sync/)).
Its developer specification identifies local database models, syncable items,
per-item `sync_items` state, and the synchronizer that exchanges those items
with a selected target
([sync specification](https://joplinapp.org/help/dev/spec/sync/)).
The repository's own Logseq DB warning provides an adjacent caution:
database-backed graphs need explicit backups while an alpha sync path is
changing
([Logseq DB warning](https://github.com/logseq/logseq#-database-version)).

- **Authority/on-disk shape (fact):** the application database/records are the
  working authority; Markdown export is a portability seam. Joplin's driver
  contract is item-oriented rather than “sync a shared text file.”
- **Offline:** local database edits are available without a network; Joplin's
  docs state background synchronization occurs when the local application is
  running, implying local-first editing with later transport.
- **External edits:** editing an exported Markdown file is not automatically a
  continuation of the database's internal history. Re-import needs an explicit
  mapping or creates a new object; this is the same distinction Loomark's Import
  and Join Existing rules make.
- **Topology/conflicts:** a driver can point to a centralized service, WebDAV,
  object store, or local filesystem. A filesystem-like endpoint is a transport
  interface, not proof that two records share causal ancestry. Conflicts must be
  resolved by the application's record protocol or surfaced as variants.
- **Identity/history:** record IDs and application metadata can preserve
  identity and revisions, but exported Markdown alone cannot carry all of it.
  An archive envelope can retain opaque operation history alongside portable
  text, exactly as Loomark's ownership design requires.
- **Backups/recovery:** database snapshots and exported Markdown provide
  different recovery guarantees: the former can resume history, the latter can
  recover readable content. They must not be mislabeled as equivalent backups.
- **Longevity/control/platform:** app-owned formats enable richer history and
  indexing but increase format-decoder and migration dependence. Joplin's
  stated goal of avoiding dependence on one company and its multiple sync
  drivers is positive evidence for user choice, not a guarantee of perpetual
  decoder availability.

**Loomark inference:** an archive-backed mode is the cleanest way to preserve
causal history and atomic replacement without making Markdown carry fields it
cannot represent. Its cost is a proprietary envelope and an explicit export /
import boundary.

## Strategy C — file-sync and Git transport

**Git-backed Markdown app: Foam.** Foam's official documentation describes it
as a VS Code and GitHub-based personal knowledge system, says notes are standard
Markdown files, and labels the workflow Git-based ([Foam overview](https://docs.foam.md/)).
Its sync guide recommends committing changes through VS Code's Git integration,
GitDoc, or the CLI ([Foam source-control sync](https://docs.foam.md/getting-started/sync-notes/)).
This is maintained first-party evidence for a Git-backed Markdown workspace,
not an endorsement of every extension.

**Git mechanics.** Git's official book describes a content-addressable object
database, blobs for file contents, trees for names/directories, and commits that
point to trees and parents ([Git objects](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects)).
Git therefore retains snapshots and commit ancestry, but its normal merge unit
is repository content, not a causal stream of editor operations.

- **Authority/on-disk shape:** working-tree Markdown is the portable current
  artifact; `.git/objects`, refs, index, and commits retain repository history.
  Foam's app semantics are layered on this file tree.
- **Offline:** commits, branches, diffs, and local recovery work offline; push,
  fetch, and remote collaboration wait for connectivity ([Git distributed
  workflows](https://git-scm.com/book/en/v2/Distributed-Git-Distributed-Workflows)).
- **External edits:** Git notices modified working-tree files. An editor or
  script changing a file does not emit Loomark operations or identify the writer.
- **Topology:** peer repositories exchange commits through remotes; a central
  host is optional. A synced folder around `.git` is not equivalent to Git's
  object/refs protocol and can corrupt or race if treated as a live shared DB.
- **Conflicts:** Git can perform three-way textual merges and can leave conflict
  markers for human resolution; the official merge documentation describes this
  as a separate resolution step ([Git advanced merging](https://git-scm.com/book/en/v2/Git-Tools-Advanced-Merging)).
  A binary archive or non-text metadata sidecar does not gain those semantics.
- **Identity/history:** commit authors, parent commits, and content hashes give
  excellent snapshot provenance. They do not identify every editor operation,
  and rebases/force-updates alter ref presentation even when objects remain.
- **Backups/recovery:** commit DAGs, branches, tags, reflogs, and bundles can
  recover prior snapshots; users can inspect and copy the repository. Recovery
  of a Loomark causal document still requires the application archive or an
  explicit import baseline.
- **Longevity/control/platform:** Git and Markdown are broadly portable and
  self-hostable. Browser Loomark would need a Git implementation or native
  bridge, credential handling, repository storage, and UX for merge states;
  browser filesystem permissions remain a hard platform boundary ([File System Standard](https://fs.spec.whatwg.org/)).

**Inference:** Git is an excellent optional backup/history transport for files,
not a substitute for causal replica synchronization. It can complement
Loomark's File Authority, but must not be advertised as preserving document
identity across unassociated Markdown clones.

## Strategy D — operation/CRDT-first replicas

**Automerge.** Automerge's official docs say each device can keep a local copy,
update offline, save locally, and later synchronize; concurrent changes merge
without a central server. They also describe immutable snapshots, change
history, branches, versions, and network-agnostic transport ([Automerge docs](https://automerge.org/docs/)).

**Yjs.** Yjs's official documentation describes shared types that merge
concurrent changes without merge conflicts, says update order does not matter,
and separates the CRDT from network providers and persistence providers
([Yjs README](https://docs.yjs.dev/readme.md)). These are infrastructure facts,
not product evidence that a Markdown workspace has chosen Yjs.

- **Authority/on-disk shape:** the operation/change graph or encoded update log
  is causal authority; Markdown is a materialized export. Storage may be one
  binary document, update log, or database plus snapshots (library policy).
- **Offline:** local operations apply immediately and queue for later exchange;
  Automerge explicitly documents this offline model.
- **External edits:** a plain `.md` has no operation IDs. Admission must be an
  explicit snapshot-to-operations conversion with stated limits, or an import;
  it cannot recover an external editor's original intent.
- **Topology:** central server, peer-to-peer, relay, local network, removable
  media, and custom transports are possible because Automerge and Yjs separate
  data model from provider. Topology still determines availability, discovery,
  authentication, and backup.
- **Conflicts:** CRDT merge guarantees convergence under its data-type rules,
  not semantic correctness of Markdown structure. Concurrent edits can converge
  to text no author intended; product-level review remains necessary.
- **Identity/history:** writer IDs, operation IDs, causal parents, versions, and
  branches survive if persisted. Replaying yields equivalent state, while
  process-local session state (cursor/undo) need not survive.
- **Backups/recovery:** durable update logs and snapshots can restore the causal
  object; exported Markdown is a last-resort portable artifact. Compaction,
  decoder compatibility, and incomplete dependency sets are recovery risks.
- **Longevity/control/platform:** open formats/libraries and local storage help
  user control, but a future reader still needs the protocol implementation.
  Browser support is feasible in modern browsers (Automerge documents browser
  and Node/Rust/WASM targets), while durable local storage and file access have
  browser quota/permission/lifecycle constraints ([IndexedDB](https://w3c.github.io/IndexedDB/#introduction),
  [File System Standard](https://fs.spec.whatwg.org/)).

**Loomark inference:** this is the only compared strategy that directly meets
“persist operation history; text is a view.” It should be introduced only behind
measured restore limits, atomic archive replacement, and explicit portable
Markdown export. CRDT adoption does not remove the need to specify File
Authority, external admission, or semantic conflict UX.

## Strategy E — browser sandbox storage

**Platform evidence.** IndexedDB is a transactional key/value database API
intended for large offline data sets; the W3C specification describes object
stores, indexes, deterministic cursor traversal, and transaction commit/abort
behavior ([IndexedDB](https://w3c.github.io/IndexedDB/#introduction)). It also
allows multiple pages/workers to use one database while transactions coordinate
access, and requires version upgrades to wait for existing connections to close
([versionchange](https://w3c.github.io/IndexedDB/#handling-versionchange)). The
WHATWG File System Standard defines an origin-private file system entry point
and permission-sensitive handles, but leaves mappings and external-change
reflection implementation-defined ([File System Standard](https://fs.spec.whatwg.org/#introduction)).

- **Authority/on-disk shape:** browser-managed IndexedDB records or origin
  private files are authoritative to the web origin, not naturally visible as a
  user's Markdown folder. Loomark's current Source records are text authority;
  the accepted ownership direction would add an archive envelope for causal
  history.
- **Offline:** strong while the origin's data remains available and the app is
  loaded/installed; no network is needed for local reads and writes.
- **External edits:** IndexedDB has no ordinary external editor. File System
  handles can point at user files, but permissions, revocation, and
  implementation-defined reflection require explicit admission and recovery.
- **Topology/conflicts:** multiple tabs can overlap, but browser transactions
  are not a causal collaboration protocol. Without coordination, stale writes
  can overwrite or recreate records, as Loomark's context explicitly warns
  ([CONTEXT](../../apps/loomark/CONTEXT.md#uncoordinated-tabs)).
- **Identity/history:** application records can retain stable IDs and history;
  browser origin identity is not a document identity portable to another app or
  device.
- **Backups/recovery:** browser storage persistence requests are not user-visible
  Markdown backups. Export, explicit archive download, and file-backed copies
  are required for user-controlled recovery; hidden-page writes remain subject
  to lifecycle interruption ([Loomark README](../../apps/loomark/README.md#autosave-and-recovery)).
- **Longevity/control/platform:** sandbox storage gives a low-friction,
  cross-platform web implementation but is vulnerable to origin/profile loss,
  quota, browser lifecycle, and unavailable filesystem APIs. User-visible files
  maximize recovery and interoperability; IndexedDB maximizes atomic app-local
  records.

**Inference:** browser storage is a good local durability substrate, not by
itself a sync strategy. It can host either snapshot Sources or operation-first
archives, but the archive format and export/recovery contract decide whether
users actually own their data.

## Cross-cutting failure cases

### File copy is not causal replication

Dropbox, rsync, and Git can transport successive file states or commit DAGs.
They cannot infer which writer observed which prior state from a plain Markdown
file. Therefore they cannot, alone, guarantee causal ordering, operation
identity, or convergent concurrent editing. A copied associated body must either
carry synchronized Loomark Metadata or be treated as Import, per the accepted
ADR.

### Metadata/body crash consistency

An archive that stores history, identity, and portable text in separate ordinary
writes can expose a new body with old history (or vice versa). The ownership
design therefore requires an outer envelope and atomic replacement, reporting
local durability only after replacement completes ([atomic durability](../design/local-first-document-ownership.md#durability-is-a-state-not-a-moment)).
A derived index/name/catalog may be rebuilt and should not be allowed to make a
valid Source undiscoverable ([source repository decision](../decisions/2026-08-29-loomark-source-repository.md#consequences)).

### Conflicting external variants

Suppose Loomark acknowledges body `A`, an external tool writes `B`, then Loomark
writes `C` before admitting `B`. The external observation cannot prove whether
its writer saw `A` or `C`. Automatically diffing `B` against `C` risks silently
choosing a history. The accepted ADR requires optimistic preflight against
causal version, file baseline, and observed fingerprint; on mismatch, apply
nothing, retain every observed variant, and enter Content conflict
([external concurrency uncertainty](../decisions/2026-08-09-markdown-file-backed-authority-and-external-admission.md#external-concurrency-uncertainty)).

## Viable Loomark alternatives

1. **Archive-first, Markdown export/import.** Persist an atomic envelope with
   opaque operation history, identity, metadata, and portable text in browser
   storage; export Markdown as an explicitly unassociated artifact. Add a
   separate backup/import flow. This best protects causal identity, with the
   cost of a non-Markdown archive and browser recovery UX.
2. **Archive-first plus bounded associated File Authority.** Keep alternative 1
   and implement the accepted File-backed ADR: associated body files are
   portable-content authority; external admission is bounded inference with
   exact replay, conflict preservation, and no operation-reconstruction claim.
   This gives user-visible files without making arbitrary files causal truth.
3. **Markdown-first with synchronized sidecar Metadata.** Make a Markdown body
   and a colocated Loomark envelope/sidecar travel together. Associated pairs
   preserve identity/history; missing or mismatched sidecars become Import or
   conflict. This maximizes filesystem interoperability but makes pairwise crash
   consistency, rename, copy, and partial-sync recovery harder.
4. **CRDT archive with optional Markdown projection and causal sync.** Store
   operation-first replicas locally and exchange updates through a provider;
   keep Markdown as export or associated projection. This enables multi-device
   causal convergence but has the largest protocol, compaction, semantic-merge,
   and browser resource surface.

## Decision matrix

| Alternative | Causal identity | User-visible Markdown | Offline/local recovery | Causal multi-device sync | External-edit safety | Browser/platform cost |
|---|---:|---:|---:|---:|---:|---:|
| Archive-first export/import | High | Export only | High if envelope backup works | Later; explicit protocol needed | High; import is unambiguous | Low–medium |
| Archive + bounded File Authority | High | Yes, associated | High if archive remains authority | Later; file copy is not sync | Medium–high; bounded conflict path | Medium–high |
| Markdown + sidecar | Medium–high when paired | Yes | Medium; pair can split | Possible only with sidecar-aware protocol | Medium; missing/mismatched sidecar is common | Medium |
| CRDT archive + projection | High | Projection/export | Medium–high, subject to format limits | High | Medium; external text still needs admission | High |

Scores are Loomark design judgments, not measurements. The matrix deliberately
separates “Markdown visible” from “causal sync”; no row treats file ownership as
replication.

## Recommended bounded next experiment

Implement no product commitment. Build a throwaway, format-level probe that
runs outside the app and measures two candidate envelopes: (a) whole-history
plus portable text and (b) base-plus-increment history plus portable text. Use a
small corpus of real Markdown sizes and these scenarios:

1. crash simulation before, during, and after archive replacement;
2. restore followed by a new local edit and merge with a pre-crash replica;
3. equal text with different histories;
4. body `A` → external `B` while Loomark advances to `C`, including conflicting
   external variants;
5. bounded external multi-span inference and exact replay;
6. copied Markdown with absent, stale, or mismatched Metadata; and
7. archive growth, restore latency, and browser storage size at stated scales.

**Pass criteria (falsifiable):** every acknowledged archive either restores a
canonical equal history or is reported unavailable without presenting text as
fully recovered; torn writes never produce a mixed history/body; all conflicting
external variants remain recoverable; no external inference exceeds its stated
budget; and a copied unassociated `.md` never silently joins an existing causal
identity. Record measured size/latency and failure cases before choosing an
archive shape.

**Stop/falsification conditions:** stop the archive-first direction if atomic
replacement cannot be made observable before the durability watermark; stop
bounded External admission if exact replay or conflict preservation fails under
budget; stop CRDT-first expansion if restore cannot distinguish equal text from
unequal history, or if realistic documents exceed the chosen restore budget;
stop sidecar pairing if crash or partial-sync trials routinely lose the mapping
between body and Metadata.

## Unresolved product decisions

- Is the primary user promise “never lose readable Markdown” or “resume the
  same causal document,” and what status vocabulary exposes the difference?
- Which archive bytes are user-backup-visible, versioned, and supported across
  Loomark releases?
- Should a user be able to adopt an old identity after losing its history, given
  that replicas may still hold the old history?
- What semantic conflicts in Markdown structure require review even after a CRDT
  converges text?
- Which desktop/native bridge, browser File System API subset, or server relay
  is in scope, and how are permission loss, quota loss, and origin loss recovered?
- Is Git an optional export/backup integration, or a supported transport with a
  defined conflict UX? It must not be presented as causal replication without a
  Metadata-aware protocol.

## Source inventory

All external sources below are first-party documentation, specifications, or
maintained project repositories; all were accessed 2026-09-16.

- Obsidian Help source: [How Obsidian stores data](https://github.com/obsidianmd/obsidian-help/blob/master/en/Files%20and%20folders/How%20Obsidian%20stores%20data.md), [Conflict resolution](https://obsidian.md/help/Obsidian+Sync/Conflict+resolution).
- Joplin: [Synchronisation](https://joplinapp.org/help/apps/sync/), [developer sync specification](https://joplinapp.org/help/dev/spec/sync/).
- Logseq: [maintained source README](https://github.com/logseq/logseq), [DB-version changes](https://github.com/logseq/docs/blob/master/db-version-changes.md).
- Foam: [official overview](https://docs.foam.md/), [source-control sync](https://docs.foam.md/getting-started/sync-notes/).
- Git: [official Git book, objects](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects), [distributed workflows](https://git-scm.com/book/en/v2/Distributed-Git-Distributed-Workflows), [advanced merging](https://git-scm.com/book/en/v2/Git-Tools-Advanced-Merging).
- Automerge: [official documentation](https://automerge.org/docs/).
- Yjs: [official README](https://docs.yjs.dev/readme.md).
- Web platform: [W3C IndexedDB](https://w3c.github.io/IndexedDB/), [WHATWG File System Standard](https://fs.spec.whatwg.org/).
- Loomark repository sources read for constraints: [CONTEXT](../../apps/loomark/CONTEXT.md), [README](../../apps/loomark/README.md), [ownership design](../design/local-first-document-ownership.md), [surface design](../design/local-first-document-surface.md), [file-backed ADR](../decisions/2026-08-09-markdown-file-backed-authority-and-external-admission.md), and [source repository decision](../decisions/2026-08-29-loomark-source-repository.md).
