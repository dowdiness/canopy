# Canopy and Loomark

Canopy provides incremental, causally ordered document editing; Loomark is the Markdown writing application built on it. This glossary distinguishes an Editing Document, its durable representations, and one running editing session.

## Language

**Editing Document（編集ドキュメント）**:
The Loomark-owned Markdown entity whose identity and causal history continue across writing instances. It contains Canopy Markdown causal state but is not identical to that state, its Markdown body file, Metadata, snapshot, or running session.
_Avoid_: Loomark document, logical document, file, buffer, session

**Detached Editing Document**:
An Editing Document with no active Writing instance lease. It retains causal state independently of an editor runtime and remains owned by the persistence shell until the appropriate durability condition permits release — File durability for File-backed persistence, or acknowledged archive Local durability for Archive-backed persistence — or until explicit recovery permits release.
_Avoid_: Closed file, snapshot, editor session

**Persistence Coordinator**:
The sole application shell for one Editing Document that owns an Aggregate Markdown runtime and coordinates Writing instance leases, EGW synchronization, File association, External change observation, Autosave, Metadata transactions, and recovery. Multiple windows never write the Markdown body file or Metadata independently.
_Avoid_: Authority, editor runtime, Writing instance, file lock

**Coordinator epoch**:
The process-local generation of one Persistence Coordinator lifetime. Replacement invalidates commands and leases from the prior epoch; surviving Writing instances may re-register under the new epoch, but the epoch and active leases are never Metadata.
_Avoid_: Causal version, Publication token, durable session

**Writing instance lease**:
The revocable, Coordinator-epoch-scoped lifecycle right for one Writing instance and replica identity to mutate an Editing Document through its mounted editor runtime. Its lifecycle is `Active`, `Draining`, then `Released`; a lease never transfers ownership of the Editing Document and is not persistence evidence.
_Avoid_: Document ownership, writer identity, file lock, session snapshot

**Mount**:
The attachment of a fresh Writing instance lease and mounted editor runtime to an Editing Document. Multiple leases may coexist under one Persistence Coordinator; mounting does not consume a detached value or transfer Authority.
_Avoid_: Open file, restore, ownership transfer

**Unmount**:
The idempotent request to release one Writing instance lease. A lease with unacknowledged Accepted causal handoff enters `Draining` and retains replay-safe evidence after its terminal runtime closes. It reaches `Released` after Aggregate acknowledgment, or after explicit Close with content recovery preserves portable text while acknowledging causal-history loss; only release of the last lease enters Detached Editing Document state, and no outcome implies save or persistence success.
_Avoid_: Save, close file, return document, destroy editor

**Draining lease**:
The non-editable Writing instance lease waiting to finish accepted-evidence delivery to the Aggregate Markdown runtime. Repeated Unmount reports the current draining state; Coordinator unavailability routes close through explicit recovery rather than silently releasing the lease.
_Avoid_: Active editor, Saving status, ghost lease

**Markdown body file**:
The human-readable `.md` file associated with an Editing Document for Git and external editors. In File-backed persistence it is the File Authority; only portable Markdown content belongs in it. An exported copy without a File association is not the Markdown body file.
_Avoid_: Save file, archive, document, exported copy

**Archive-backed persistence**:
A persistence capability in which no Markdown body file is associated with the Editing Document. One atomic application-owned archive replacement retains portable content and causal Metadata together; exported Markdown remains an unassociated copy.
_Avoid_: Browser mode, File-backed persistence, temporary session

**File-backed persistence**:
A persistence capability with a continuing File association to a Markdown body file. File Authority, File baseline, external-change admission, and Content conflict behavior apply only in this mode; writable operation additionally requires Safe file replacement.
_Avoid_: Desktop mode, Archive-backed persistence, downloaded file

**Safe file replacement**:
The adapter capability required for writable File-backed persistence. Replacement never exposes partial content, preserves the original on failure, safely targets resolved symbolic links, supports exact readback for Self-write acknowledgment, and retains required file permissions. It does not claim a portable compare-and-replace primitive against uncooperative external processes; the Observed external variant guarantee defines that limit. Without Safe file replacement, Loomark limits the association to read-only access and offers Archive-backed editing, Export Markdown, or Choose New Location.
_Avoid_: Writable handle, in-place truncation, best-effort save

**Export Markdown**:
The creation of an unassociated portable `.md` copy from an Editing Document. Export does not create File Authority, change identity, or alter persistence mode.
_Avoid_: Save As, Autosave, Markdown body file

**Import Markdown**:
The creation of a new Editing Document and causal history baseline from portable Markdown content without continuing another Editing Document's identity. Opening a cloned Markdown body file without synchronized Metadata follows this rule even when another device edits equivalent content.
_Avoid_: External admission, reopen, history restore

**Join Existing Editing Document**:
The explicit continuation of an Editing Document from its shared identity and causal history supplied by synchronized Metadata or another authorized participant. Path and content-hash similarity never imply a join.
_Avoid_: Import Markdown, hash match, file association

**File encoding profile**:
The byte-level encoding retained for a Markdown body file. The initial profile accepts UTF-8 only, keeps an optional BOM outside the Editing Document source, performs no Unicode normalization, and rejects invalid UTF-8 without rewriting it; exact line terminators remain part of the Editing Document source.
_Avoid_: Content format, Markdown syntax, automatic encoding detection

**Metadata**:
Durable application-managed information associated with an Editing Document but excluded from its Markdown body file, including logical identity and opaque causal history. It preserves the Causal Authority through Atomic Metadata transactions but is not itself an Authority, user-visible file, or Git artifact.
_Avoid_: Sidecar, sidecar file, attached archive, metadata file

**Authority**:
A scope-specific rule that settles one kind of disagreement. No single representation is the Authority for file content, causal history, identity, and derived views at once.
_Avoid_: 正本, source of truth, global authority

**File Authority**:
The Markdown body file's authority over portable content at file-backed open, save, and external-change admission. It does not determine causal history or Editing Document identity.
_Avoid_: Causal Authority, current editor state, Metadata

**Causal Authority**:
The accepted operation history's authority over causal order, Editing Document identity, and writer identity. Metadata preserves it durably; a Markdown body file cannot reconstruct it.
_Avoid_: File Authority, file history, Metadata

**File association**:
The relationship between an Editing Document and the current location and safely resolved physical target of its Markdown body file. A path change updates the association without changing the Editing Document's identity or causal history.
_Avoid_: Editing Document identity, physical file identity, document path

**Physical file identity**:
A file-adapter capability used to recognize that multiple paths, including a safely resolved symbolic link and its target, address the same writable file and therefore require one Persistence Coordinator. It is device-local and never determines Editing Document identity.
_Avoid_: Editing Document identity, File association, portable identity

**Aliased file handling**:
The capability-aware policy for file aliases. A safely resolved symbolic link preserves the link, associates its target, and shares one Coordinator with the target path; if safe resolution is unavailable, Loomark refuses file-backed editing and offers read-only open or Import Markdown. Hard-linked files are unsupported for initial file-backed editing because atomic replacement can split their shared physical identity.
_Avoid_: Path-based identity, symlink replacement, independent alias writers

**File baseline**:
The Markdown body file content last acknowledged by Loomark as the shared ancestor of its current content and a later external file change.
_Avoid_: Snapshot, saved version, latest file

**External file relocation**:
A rename or move of a Markdown body file by Git or an external tool. When recognized, it updates the File association without becoming a content change or a new Editing Document.
_Avoid_: External file change, import, Save As

**Ambiguous relocation**:
The condition in which more than one file could be the relocated Markdown body file. Loomark requires an explicit user choice and never guesses which candidate inherits the File association.
_Avoid_: Content conflict, duplicate, automatic relocation

**Save As**:
A new Editing Document and Markdown body file created from another Editing Document's current portable content. It receives a new identity, treats the copied content as its history baseline, and has an independent causal future; the original remains unchanged, and an existing target path is never replaced.
_Avoid_: Duplicate, External file relocation, rename, Export Copy

**Choose New Location**:
An explicit resolution of Missing file state or Committed pending file that writes the current accepted content to a new, unoccupied path and moves the File association there. The Editing Document identity and causal history continue unchanged.
_Avoid_: Save As, Duplicate, import

**External file change**:
A change to a Markdown body file made through Git, including branch checkout, or an external editor. Line-terminator conversion, final-newline changes, Unicode normalization, and visible whitespace changes are content changes; only a BOM-only change belongs to the File encoding profile. Loomark admits an external change automatically only when Loomark's accepted current content equals the File baseline and no External concurrency uncertainty is active.
_Avoid_: Content conflict, remote edit, archive replacement

**Observed external variant**:
The exact Markdown body file content successfully read by Loomark at an external-change or pre-publication check. Loomark preserves every observed variant; an intermediate write replaced before Loomark can observe it lies outside the guarantee of a portable plain-file workflow.
_Avoid_: Watcher event, inferred version, filesystem history

**External admission**:
The deterministic bounded multi-span conversion of an admitted external file's final text, relative to the File baseline, into inferred causal edits that preserve unchanged spans and produce the exact external source. UTF-16 validation, a resource budget, and exact replay verification are mandatory; exceeding the budget falls back to one contiguous replacement, which must also satisfy receiver admission limits before any mutation. If no inferred batch — including the contiguous-replacement fallback — fits within receiver admission limits, apply nothing, preserve the Observed external variant, and enter Content conflict. Admission preserves the Editing Document identity but never claims to recover the external editor's original operations or intent.
_Avoid_: Import, whole-source replacement, exact operation reconstruction

**Coordinator writer**:
The stable synthetic replica identity used by the Aggregate Markdown runtime to generate application-originated main-history operations, including External admission and Resolution application. Operation category and provenance live in application records. It persists across reopen and never represents a person, external editor, or tool.
_Avoid_: Writing instance, user identity, operation category, external editor identity

**External admission transaction**:
The atomic optimistic application of one inferred External admission batch. Before mutation, Loomark validates its expected causal version, File baseline, and Observed external variant fingerprint. A match applies every inferred edit exactly once under the Coordinator writer and records one application-level undo group; a mismatch applies none, preserves every Observed external variant, and enters Content conflict without re-diffing against the newer Loomark source.
_Avoid_: Automatic rebase, partial admission, structural commit

**External admission undo**:
The Persistence Coordinator-owned undo of the latest External admission as one group. Normal Undo may select it only while no later causal or file change has occurred and both the expected document version and file fingerprint still match; otherwise it makes no change and requires an explicit Revert External Change review.
_Avoid_: Writing instance undo, selective historical undo, automatic rollback

**Revert External Change**:
An explicit reviewed causal change that reverses an older External admission without deleting its history. It is required after later document or file changes make External admission undo ineligible.
_Avoid_: History deletion, normal Undo, file restore

**External concurrency uncertainty**:
The condition after a Loomark source change in an active Editing Document lifetime where a plain external file write cannot prove which prior content its writer observed. An external write enters Conflict state rather than silently replacing the Loomark variant; close and reopen resets the uncertainty against the newly acknowledged file.
_Avoid_: Content conflict, unsaved, external writer identity

**Missing file state**:
The read-only condition in which an Editing Document's associated Markdown body file no longer exists. Loomark preserves the Editing Document and Metadata without automatic expiration, withholds automatic recreation and ordinary editing, and requires explicit user resolution or deletion.
_Avoid_: Deleted document, Content conflict, recovery-blocked

**Remove from Loomark**:
The explicitly confirmed removal of Metadata and File association while leaving the Markdown body file unchanged. Reopening the file creates a new Editing Document and causal history baseline.
_Avoid_: Delete file, close, unlink

**Move Markdown File to Trash**:
The explicitly confirmed move of the Markdown body file to the operating system trash while preserving the Editing Document and Metadata in Missing file state.
_Avoid_: Remove from Loomark, permanent delete, close

**Delete Editing History Permanently**:
The single explicitly confirmed irreversible deletion, available only in Missing file state, of Metadata, Resolution drafts, Publication ledger entries, and Prepared resolution records. Loomark automatically makes every view read-only, revokes all Writing instances, closes their views, and deletes atomically; if safe revocation cannot complete, no deletion occurs and no force or recovery-file path is offered. Recovery Markdown files remain ordinary files and require separate deletion.
_Avoid_: Remove from Loomark, Move Markdown File to Trash, automatic expiration, force delete

**Deletion marker**:
A content-free, short-lived application record containing only an opaque document key and Deletion epoch. It rejects stale writes and resumes interrupted deletion without retaining Markdown content, causal history, conflict variants, title, or path; Loomark removes it after every relevant Writing instance is revoked.
_Avoid_: Metadata archive, recovery record, permanent tombstone

**Content conflict**:
The condition in which Loomark content and an Observed external variant both diverge from the same File baseline, External concurrency uncertainty prevents proving that the external writer observed the Loomark variant, or an otherwise eligible Observed external variant cannot be admitted atomically under UTF-16 validation, receiver admission limits, and exact replay. Every observed variant remains recoverable until deliberate resolution; none may be discarded by silent overwrite.
_Avoid_: External file change, CRDT conflict, last-write-wins

**Conflict state**:
The read-only editing condition for an unresolved Content conflict. The Markdown body file retains the external variant, durable Metadata retains the Loomark variant, and Loomark withholds ordinary editing and file writes until resolution.
_Avoid_: Error state, merge failure, recovery-blocked

**Conflict resolution**:
A deliberate exact choice of the external or Loomark variant, or the application of a reviewed Resolution draft, as the next Markdown body file content. `Use External` and `Use Loomark` produce exactly the named variant; resolution is recorded as a Resolution transaction in the same Editing Document.
_Avoid_: Retry, automatic merge, last-write-wins, archive restore

**Resolution transaction**:
The application-owned durable record that binds both pre-resolution variants and the chosen result to exact main-history before/after versions and authoritative mutation evidence. Its main mutation is a normal causal edit rather than embedded application metadata; the record makes an applied Conflict resolution undoable through normal history, including after reopen.
_Avoid_: EGW operation payload, Autosave, transient undo, conflict marker

**Prepared resolution record**:
The durable pre-publication record that preserves the Publication token, both conflict variants, sealed candidate, and expected file fingerprint before a destructive Conflict resolution can replace the Markdown body file. Preparation neither mutates main history nor establishes Saved status or an Applied workspace; it supplies evidence for crash recovery and finalization.
_Avoid_: Resolution transaction, Metadata durability, Applied, Autosave

**Prepared resolution recovery**:
The reopen classification that compares a Prepared resolution record, a Publication ledger entry bound to durable main history, and the current Markdown body file. Without ledger evidence, matching prepared or candidate content cannot prove whether main mutation was accepted; Loomark preserves the prepared state and requires reconciliation rather than reconstructing, retrying, or canceling the main mutation without durable idempotency evidence. With ledger evidence, main mutation is never retried; unexpected file content becomes an Observed external variant and requires revalidation or a new Content conflict.
_Avoid_: Blind retry, archive restore, file overwrite

**Resolution draft**:
A durable EGW-backed candidate created by `Keep Both` and collaboratively editable by multiple Writing instances. Its causal history is separate from the Editing Document, is preserved in Metadata, and resumes after reopen; it does not change the Editing Document or Markdown body file until explicit application, while the file retains the external variant and Metadata failure falls back to a Recovery Markdown file.
_Avoid_: Editing Document branch, Applied document, Autosave target, local-only draft

**Resolution workspace**:
The application-owned lifecycle envelope that links one Content conflict to its separate Resolution draft history and coordinates `Drafting`, `Deferred`, `Sealing`, `CommittedPendingFile`, `Applied`, and `Discarded` states. EGW owns draft convergence; Loomark owns workspace identity, persistence, participation, and Apply Resolution policy. `Discarded` requires explicit confirmation, deletes only the draft history, and returns to the unresolved Conflict state.
_Avoid_: Editing Document, EGW branch, collaboration room

**Deferred resolution**:
The resumable state entered by `Resolve Later`. The Resolution draft remains durable and the Markdown body file retains the external variant until a Writing instance chooses `Continue Resolution`.
_Avoid_: Shelved, Abandoned, Closed, Saved

**Committed pending file**:
The read-only recovery state in which a Resolution transaction and its Publication ledger entry are durable but the sealed candidate has not received exact Self-write acknowledgment from the Markdown body file. Main mutation is never retried; Loomark permits only completion of file persistence, review of newly observed content, Choose New Location, or close for later recovery.
_Avoid_: Rejected, Applied, Autosave pending, retryable commit

**Applied resolution**:
The finalized state in which the Resolution transaction and Publication ledger entry are durable, the Markdown body file has exact Self-write acknowledgment for the chosen content, and Metadata records completion. Normal Editing Document work may resume.
_Avoid_: Main commit only, Saved status, Committed pending file

**Resolution baseline**:
The external variant acknowledged when a Resolution draft is created or last revalidated. It identifies what external content the draft was reviewed against and remains distinct from the Editing Document's File baseline.
_Avoid_: File baseline, Causal seal, draft source

**Revalidation required**:
The orthogonal condition entered when the current Markdown body file diverges from the Resolution baseline. Loomark preserves the prior and latest external variants without changing the Resolution draft, and prohibits sealing until a Writing instance completes Review Latest External.
_Avoid_: Content conflict, automatic merge, Deferred resolution

**Review Latest External**:
The explicit comparison of the Resolution baseline, latest external variant, and current Resolution draft. Selected changes enter the draft as normal EGW operations; `Mark Reviewed` advances the Resolution baseline only when the current file still matches the reviewed fingerprint, including when no change was selected, and warns when applying the draft would replace latest external content.
_Avoid_: Automatic merge, External admission, Use Latest External

**Revalidation outdated**:
The result when `Mark Reviewed` finds that the Markdown body file changed after review began. The Resolution baseline does not advance, selected draft operations remain preserved, and Review Latest External restarts against the newest variant.
_Avoid_: Rejected edit, Content conflict, discarded review

**Recovery Markdown file**:
A human-readable content-only `.md` fallback containing the Loomark variant when normal content and Metadata durability cannot preserve it. It never claims to preserve Editing Document or draft identity, operation IDs, writer identities, causal frontier, collaborative undo, or Publication state. In File-backed persistence, Loomark creates it without replacement under a unique name beside the Markdown body file and falls back to a user-chosen location when that directory is unwritable. In Archive-backed persistence, which has no body-file directory, Loomark requires a user-chosen location and unique name. Loomark withholds close until recovery succeeds or the user explicitly discards the changes.
_Avoid_: Metadata, archive, causal recovery, backup, Autosave target

**Close with content recovery**:
The explicit last-resort release of a Draining lease after Coordinator replay fails and a Recovery Markdown file safely preserves the accepted portable text. It never establishes Saved status and warns that causal history and collaborative undo were not preserved.
_Avoid_: Unmount success, File durability, causal handoff

**Resume Resolution from Recovery**:
The explicit creation of a new Resolution draft identity and causal history baseline from Recovery Markdown file content when the original Editing Document and Content conflict Metadata remain readable. If that Metadata is unavailable, the file can only enter through Import Markdown as a new Editing Document.
_Avoid_: Reopen draft, history restore, Join Existing Editing Document

**Review Recovered Content**:
The explicit comparison of normal-editing Recovery Markdown content with a readable existing Editing Document. Applying reviewed differences creates a new causal edit under a fresh Writing instance while preserving Editing Document identity; it never claims to recover the lost operations, and the recovery file remains until the user deletes it. If Metadata is unavailable, only Import Markdown is possible.
_Avoid_: Causal recovery, External admission, automatic restore

**Document archive**:
An application-owned recovery value containing an Editing Document's identity, portable Markdown, and opaque causal history. In file-backed editing it is Metadata and does not override a divergent Markdown body file.
_Avoid_: Snapshot, session snapshot, save file

**Active document**:
The sole Editing Document selected for the current standalone application while document catalogs and document switching remain unavailable.
_Avoid_: Current file, active session, recent document

**Baseline archive**:
The first complete archive that establishes a new active Editing Document's identity before its first history-changing commit.
_Avoid_: Empty snapshot, default file

**Local archive repository**:
The application-managed Metadata repository that retains the latest complete document archive for the standalone application's active document. It is the content Authority only when no Markdown body file is present.
_Avoid_: Session store, backup, replica

**Local restore policy**:
The resource-admission policy used when reopening a device-owned document archive. It is distinct from policy for history received from another replica.
_Avoid_: Network limit, archive format limit

**Repository acknowledgment**:
Confirmation that one complete archive replacement finished successfully in the local archive repository. It describes one repository operation, not the current product durability state.
_Avoid_: Saved status, durable-local state

**File durability**:
The condition in which the accepted content is represented by a completed write to its Markdown body file.
_Avoid_: Metadata durability, repository acknowledgment, applied

**Metadata durability**:
The condition in which the Editing Document's accepted identity and causal history are represented in acknowledged Metadata.
_Avoid_: File durability, Saved status, backed up

**Atomic Metadata transaction**:
The storage capability that durably applies all Metadata belonging to one logical transition or leaves the prior state unchanged. Causal history, Publication ledger entry, Resolution receipt, and workspace state must never become independently visible; without this capability Loomark does not claim Metadata durability, permit destructive resolution, or provide Archive-backed persistence.
_Avoid_: Field write, best-effort persistence, Safe file replacement

**Metadata-unavailable state**:
The file-backed condition in which a valid Markdown body file exists but its associated Metadata is corrupt, unreadable, or from an unsupported newer version. Loomark preserves and distinguishes the failed Metadata, leaves the file unchanged, and requires explicit confirmation before opening the content under a new Editing Document identity.
_Avoid_: Recovery-blocked, silent import, Content conflict

**Applied locally**:
The status after one Mounted Markdown runtime accepts a commit and can show its result. It carries authoritative mutation evidence for that replica but implies neither Aggregate acknowledgment nor durability.
_Avoid_: Aggregated, Saved status, optimistic preview

**Aggregate acknowledgment**:
Confirmation that the Aggregate Markdown runtime causally applied the accepted window history. It permits the Persistence Coordinator to schedule persistence but implies neither File durability nor Metadata durability.
_Avoid_: Commit receipt, Repository acknowledgment, Saved status

**Saving status**:
The user-facing status after Aggregate acknowledgment while required persistence work remains incomplete — Autosave file writes and Metadata work for File-backed persistence, or one atomic archive replacement for Archive-backed persistence. Aggregate synchronization never waits for the Autosave debounce.
_Avoid_: Applied locally, Saved status, replicated

**Saved status**:
The user-facing confirmation that content is durable — through File durability for File-backed persistence, or acknowledged archive Local durability for Archive-backed persistence. In File-backed mode, this status remains active when Metadata durability fails and Loomark separately warns that editing history was not preserved. Archive-backed mode reaches this status only when one atomic archive replacement durably carries both content and causal Metadata.
_Avoid_: Metadata durability, repository acknowledgment, fully saved

**Autosave**:
The automatic persistence triggered by an accepted causal change. In File-backed persistence, a source-changing commit establishes File durability before Metadata durability; a source-equal history change updates Metadata without rewriting an unchanged Markdown body file. In Archive-backed persistence, one atomic archive replacement carries the accepted portable content and causal Metadata; acknowledgment establishes Local durability and Metadata durability together, without a Markdown body file or External change observation.
_Avoid_: Repository acknowledgment, periodic backup, history no-op

**Self-write acknowledgment**:
Recognition that an observed file change exactly matches one expected Autosave generation for the same File association and File encoding profile. It advances the File baseline; any mismatch is handled as an External file change rather than hidden by timing-based watcher suppression.
_Avoid_: External admission, watcher timeout, ignored file event

**External change observation**:
The reread and fingerprint comparison that establishes an Observed external variant. This applies only to File-backed persistence, which has a Markdown body file to observe; Archive-backed persistence has no body file and does not perform file observation. A watcher reduces detection latency but never supplies correctness; in File-backed mode, observation is mandatory on focus or resume, immediately before Autosave's physical replacement, and immediately before Causal seal or `Mark Reviewed`. A mismatch stops the pending write or seal.
_Avoid_: Watcher event, polling guarantee, cached stat

**History-changing commit**:
An accepted document commit that advances causal history, whether or not its resulting Markdown source differs from the prior source.
_Avoid_: Text change, source change

**History no-op**:
An accepted document commit that leaves causal history unchanged.
_Avoid_: Unchanged text

**Applied document**:
The current accepted in-memory document state, which may be newer than its Markdown body file or Metadata.
_Avoid_: Saved document, durable document

**Local durability**:
For the standalone application when no Markdown body file is present, the condition in which the current accepted document version is represented by an acknowledged archive in the local archive repository.
_Avoid_: Applied, replicated, backed up

**Recovery-blocked**:
The condition in which an existing archive cannot be safely reopened and remains preserved while editing and replacement are withheld.
_Avoid_: Empty document, recovered, reset

**Writing instance**:
One active host lifetime that writes operations under its own replica identity. Multiple writing instances may edit the same Editing Document concurrently; a surviving host retains its identity across Coordinator replacement, while full reopen starts a fresh writing instance and retains the Editing Document identity.
_Avoid_: Editing Document identity, user identity, browser identity, window

## Framework — Markdown causal editing

Framework vocabulary for the Canopy layer contained by a Loomark Editing Document. These terms describe causal Markdown runtime mechanics without application identity, file ownership, persistence policy, or product conflict state.

**Markdown causal state**:
The Canopy-owned opaque history, causal version, sentinel-free portable source, and reconstruction capability from which replica runtimes are mounted. It owns history admission and export but no Editing Document identity, File association, Metadata storage, Saved status, Resolution workspace, or Publication ledger.
_Avoid_: Editing Document, archive, parser state, file buffer

**Mounted Markdown runtime**:
The Canopy-owned live EGW and parser runtime for one Writing instance lease. It accepts Markdown commits and returns outcomes, receipts, snapshots, and history evidence without deciding application persistence or conflict policy.
_Avoid_: Editing Document, Persistence Coordinator, mounted file

**Markdown commit outcome**:
The Canopy result algebra for one commit: rejected without mutation, committed with authoritative receipt evidence, or committed with receipt evidence, a later issue, and an Accepted causal handoff. Both committed variants prohibit retry and remain distinct from persistence status; compatibility façades may translate committed-with-issue into their legacy error shape.
_Avoid_: Result error, Saved status, Publication outcome

**Accepted causal handoff**:
The opaque replay-safe ownership evidence returned with committed-with-issue so a caller can admit the exact accepted history to the Aggregate Markdown runtime, reconstruct accepted Markdown causal state, and discard the terminal mounted runtime without reading parser or projection internals. At-least-once delivery is safe because operation identity and causal versions make admission idempotent; it exposes neither a read snapshot nor mutable internal collections.
_Avoid_: Snapshot, commit retry token, parser recovery, mutable history

**Accepted handoff admission**:
The Aggregate outcome for an Accepted causal handoff: advanced, already present, pending dependencies, or rejected evidence. Only an advanced causal version schedules persistence; already-present evidence acknowledges replay without duplicating Autosave.
_Avoid_: Commit retry, duplicate save, parser reconstruction

**Aggregate Markdown runtime**:
The headless Canopy replica owned by a Persistence Coordinator while leases or persistence work remain. It receives every window and application operation, materializes the causally complete portable source used for Autosave, and is never a user Writing instance; after last unmount and completed persistence, its history returns to Markdown causal state and the runtime may be discarded.
_Avoid_: Leader window, Editing Document, Authority, permanent runtime

## Framework — staged publication

Framework vocabulary for the EGW-versioned companion that owns causal sealing and publication of a Resolution draft. Distinct from the Editing Document domain, Markdown causal editing, and projection editing: these describe how a sealed candidate moves from draft convergence to applied transaction, not how documents persist or how trees keep identity.

**Staged publication**:
The lifecycle that moves a Resolution draft from collaborative editing through Causal seal to application of one sealed candidate. It separates draft convergence, which may continue independently, from one Resolution transaction in the Editing Document's main history; it does not make persistence, network, and Metadata one atomic transaction.
_Avoid_: Save, commit, deploy, two-phase commit

**Causal seal**:
The operation that fixes a sealed frontier on a separate draft EGW history after required participant flush acknowledgments or an explicit `Apply Current Draft` choice. Checkout of the sealed version remains constant while later draft operations advance the live head into a Recovery head; they do not enter the sealed candidate. It is not a branch, merge, or snapshot.
_Avoid_: Branch point, checkpoint, tag, freeze

**Publication token**:
The stable application identity of one intent to publish one sealed candidate. It lets Loomark detect duplicate main-history application and correlate recovery across the Markdown body file and Metadata, but does not make those stores atomic; a committed outcome bound to the token never authorizes retry.
_Avoid_: Version tag, lock, session key, cross-store transaction

**Publication ledger**:
The application-owned Metadata index that binds a Publication token to durable main-history before/after versions, its Resolution receipt, and Publication outcome. A matching ledger entry is the durable evidence that main mutation committed; the ledger is not part of EGW operations or the Markdown body file.
_Avoid_: EGW history, File baseline, Prepared resolution record, transaction log

**Publication outcome**:
The result of applying a sealed candidate: rejected without main-history mutation, committed with authoritative mutation evidence, or committed with both mutation evidence and a later issue. Both committed forms prohibit retry.
_Avoid_: Error channel, save result, retry signal

**Recovery head**:
The live EGW draft version after it advances beyond a Causal seal. It identifies late operations that remain recoverable but are excluded from the sealed candidate and the applied Resolution transaction.
_Avoid_: Document head, autosave, recovery file, main history

## Framework — projection editing

Framework vocabulary for the projection engine that backs the application terms above. Distinct from the Editing Document domain: these describe how the editing session's tree keeps identity across reparses, not how documents persist.

**Projection execution**:
The derivation of replaceable Block, semantic, diagnostic, and presentation artifacts from immutable committed input. Every group uses Markdown source; the Block interactive group also uses selection/focus state captured at the same Projection stamp. Projection execution may complete after its requesting mutation and cannot mutate authority state.
_Avoid_: Authority commit, parser callback, render pass

**Projection generation**:
One contiguous lifetime of projection state initialized from a coherent committed source. Recovery, replacement, or a source-continuity gap starts a new generation, after which results from every earlier generation are obsolete.
_Avoid_: Writing instance, document version, browser generation

**Projection stamp**:
The provenance that binds projection work and its artifacts to one Projection generation, one adapter-lifetime ordered position, the exact source revision used for derivation, and the originating causal document version. The sequence does not reset when generation changes. Artifact display requires current source provenance; applying an edit intent additionally requires the exact causal version.
_Avoid_: Cache key, timestamp, render version

**Group work**:
One independently terminal derivation for one demanded consistency group. One projection request may issue Block, Preview, and diagnostics group work with different outcomes; a presentation may correlate several adopted group work items.
_Avoid_: Authority event, projection request, frame

**Artifact Bundle**:
The immutable atomic payload of one group work item, derived from one Projection stamp and adopted as one demand-defined consistency group. Unrelated groups do not share an adoption barrier, and an absent undemanded artifact is not an independently current representation.
_Avoid_: Application state, parser snapshot, all-lane snapshot, independent view cache

**Reconciliation**:
The identity-preserving match between the previous projection tree and the newly reparsed tree: it decides, for each node in the new tree, whether it is the same node as one in the old tree (carrying its NodeId) or a fresh node. It is not text diffing and not CRDT merge.
_Avoid_: Merge, diff, CRDT merge

**Identity evidence**:
What reconciliation may consult when deciding that a new node is the same as an old node: sibling position (positional), a structural-edit hint (hint-directed), or a payload fingerprint (exact-key). The three kinds are a closed public set — the surface offers no hints+exact-key combination — but each mode combines its own evidence with positional LCS internally, and fallback matching preserves sibling order rather than strict position.
_Avoid_: Matching mode, strategy, policy record

**Fresh identity**:
A newly allocated NodeId, given to a node that reconciliation cannot match to any previous node — including fresh nodes at unmatched positions and nodes whose old identity retired or was ambiguous (Replace / Move / unresolved wrap). The counterpart of preserved identity, where a node keeps its previous NodeId across an edit.
_Avoid_: Identity carry (as a noun), id retention

**Markdown edit application**:
The language-owned transition that turns one typed Markdown structural-edit intent into one accepted document change, preserves its identity evidence, and reports the exact source transforms. It does not decide Loomark receipt, history, or selection meaning, and it does not serialize an FFI response.
_Avoid_: Edit train, Loomark commit
