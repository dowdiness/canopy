# Local-first document ownership

Direction for making a Loomark document something the user owns on their own
device, rather than something an editing session holds while it happens to be
running.

Treat this as direction, not implemented behavior. It names invariants and
requirements; it does not describe the current state of any package, and it
should not be read as a report on what exists today.

## The distinction this design exists to hold

An editor that keeps a document in memory and can serialize its text is not the
same thing as an editor that owns a document. The difference is not durability
of the characters. It is durability of *identity*.

A document has:

- **text** — what it currently says
- **history** — the operations that produced that text, and their causal order
- **identity** — which document this is, and which writer produced each part

Text alone round-trips through any file. History and identity do not. An editor
that persists only text can reopen the same characters, but the reopened
document is a new object: it shares no causal past with the one that was
closed, and therefore shares no future with any other replica of it.

That loss is invisible on a single device. It becomes visible the first time a
second device, a second person, or an undo across a restart is involved, and at
that point it is not repairable — the information was never recorded.

So the rule this design turns on:

> **Persist the operation history. Text is a view of it.**

## Four authorities, kept distinct

Confusing these is the failure this design prevents.

| Authority | What it settles |
| --- | --- |
| Causal | what happened, and in what order |
| Current state | what the document says now |
| Portable artifact | what survives this software's disappearance |
| Derived caches | syntax tree, semantic IR, projection, view patches |

The Causal Authority is the operation graph. Current state is materialized
from it. Derived caches are reconstructible and never authoritative — losing
them costs time, never information.

Portable content has two persistence modes, neither a single universal
authority:

| Mode | What survives | What settles portable content |
| --- | --- | --- |
| Archive-backed | Opaque history payload, portable text, application Metadata | Exported `.md` is an unassociated portable artifact; no File Authority exists |
| File-backed | Continuing File association to a Markdown body file | The Markdown body file is File Authority for portable content; accepted operation history remains Causal Authority for causal order and identity |

There is no global authority. File Authority and Causal Authority each settle
their own scope.

In Archive-backed persistence, the portable artifact is deliberately redundant.
It is the guarantee that remains when the history cannot be read at all, and it
is why an archive is never reduced to "just the operations". Opening an
unassociated `.md` — including a copy of an exported file — follows Import
Markdown: a new Editing Document and a new causal history baseline, unless
synchronized Metadata supports Join Existing Editing Document.

In File-backed persistence, a continuing File association makes the Markdown
body file the File Authority for portable content. External admission preserves
Editing Document identity when associated content changes. A rename or move
preserves identity by updating the association. Import Markdown remains the
path for an unassociated `.md`, whether copied, exported, or never associated.

## Session state is not an archive

An editor keeps state that describes *this session* — which view mode is open,
where focus sits, what the text currently is. That is worth saving and
restoring, and it is not a document archive.

Restoring session state reproduces an appearance. Restoring an archive resumes
an object. Naming both "snapshot" invites a future change that quietly routes
document recovery through the session path, at which point every reopened
document silently becomes a fresh one. The two must stay separately named and
separately versioned, and the session form must say in its own documentation
that it is not a recovery format.

## The archive is an envelope the application owns

An archive is application-owned metadata wrapping an opaque history payload,
plus the portable text.

The history payload's own serialization is a closed contract belonging to the
CRDT: it admits exactly the fields that protocol defines, and it neither
carries nor tolerates application metadata. Document identity, archive
versioning, and anything reserved for later therefore live in an **outer
envelope**, with the payload embedded whole and uninterpreted.

This is not a workaround. It is the boundary working correctly: the application
persists bytes it cannot read, and the CRDT never learns what a document is
called or where it is stored.

Two consequences that must not be discovered later:

**Document identity belongs in the envelope from the first version.** The
history payload carries writer identity but no document identity. Adding it to
the payload afterwards is a protocol break; adding it to an envelope that
already exists is a field.

**The archive versions itself, separately from the wire.** Wire compatibility
and archive compatibility have different lifetimes: a protocol may break
between releases that must still open each other's files. One number cannot
represent both.

The envelope must also carry enough to answer "why can't this be read" without
consulting the payload. A reader that has only the payload's own verdict cannot
promise to distinguish a damaged file from one written by a newer release —
that distinction is not something a wire decoder owes anyone, and an archive
that depends on it has borrowed a guarantee from a layer that never offered it.
The difference matters to the user, because "this document is from a newer
version of Loomark" and "this document is corrupt" call for opposite actions.

## What replay does and does not restore

Replaying a history reproduces an **equivalent** document, not an identical
in-memory structure. Operation identity, causal order, materialized text, and
the version frontier survive. Process-local bookkeeping is reconstructed rather
than transported.

This bounds how correctness can be checked. In particular, a version frontier
is a per-writer high-water mark, not a summary of content: two histories can
agree on both the text and the frontier while containing different operations.
Anything that asserts "the document was restored correctly" by comparing text
and version is therefore asserting something weaker than it appears to. The
honest checks are a canonical comparison of the history itself, and a merge
performed after restore.

The same reasoning applies to a transient state a replica may hold: operations
received but not yet applicable, because the operations they depend on have not
arrived. Such state is not part of the history and is not carried by a history
export. Discarding it on restart is acceptable only while every sender can be
asked again. Once that is not guaranteed, the archive must retain it, which is
why the envelope reserves room for it before it is needed.

## Durability is a state, not a moment

Saving is not one event. At minimum:

- **applied** — the operation is in the document and on screen
- **durable locally** — it is in this device's archive
- **replicated** — some other replica has it
- **backed up** — a designated remote holds it

Later states never substitute for earlier ones. In particular, "sent" is not
"saved": a product that reports network success as durability lies precisely
when the network is the thing that failed. Offline, "saved locally, not yet
synced" is a normal state and must be presented as one, not as a warning.

Only the first two are meaningful before replication exists, and a design that
ships only those is complete for a single device — provided it does not borrow
the vocabulary of the others.

An archive replacement is atomic. A partially written archive is not a degraded
archive: text may survive while the history does not, which is exactly the loss
this design exists to prevent. Local durability is reported only after a
replacement completes.

## Requirements on the editing path

These bind whatever submits edits, and they are cheap to satisfy while that
path is being built and expensive to retrofit once archives exist.

**One writer identity per writing instance.** The identity attached to
operations distinguishes concurrent writers. Two windows editing the same
document at the same time are two writers, whatever else they share. Reusing
one identity across them produces a history that cannot be distinguished from a
legitimate one, and no later repair can separate them. This must hold before
any archive is written, because an archive records the identity it was given.

**Edits arrive as edits.** Submitting a whole document and letting the editor
infer what changed makes the recorded granularity an artifact of the inference
algorithm rather than a record of what the user did. Whatever that algorithm
yields is what the history keeps: a coarse inference rewrites spans the user
never touched, and text is no signal that it happened, because the rewritten
span is identical. What is lost is operation identity across that span, and
with it undo granularity and any concurrent edit inside it.

The requirement is not "use a better diff". It is that the editing path knows
what the user did and says so, rather than handing over two documents and
asking the editor to guess.

Persistence sharpens this second requirement rather than adding to it. A live
session with a coarse input path is merely degraded. An archive with a coarse
input path has durably recorded a history of whole-document replacements in
place of what the user actually did, and no later feature can recover a
granularity that was never captured.

Snapshot inference is a narrowly scoped external-boundary exception for
File-backed persistence only. External admission deterministically infers
bounded multi-span edits from an admitted file's final text relative to the
File baseline, validates sentinel-free UTF-16 boundaries, uses a resource
budget with one-contiguous-replacement fallback, and requires exact replay.
The selected inferred batch — including the contiguous-replacement fallback —
is preflighted against receiver admission limits before any mutation. If no
inferred batch fits, apply nothing, preserve the Observed external variant,
and enter Content conflict. It uses the stable synthetic Coordinator writer
for application-originated operations; application records distinguish
admission provenance, and it never claims to recover the source editor's
original operations or intent. This exception does not relax the requirement
for any Loomark-originated input path: user actions within Loomark always
arrive as edits.

**Persistence triggers on history, not on text.** An operation that leaves the
text unchanged still advanced the document. Anything that decides whether to
save by comparing text will eventually skip a save that mattered.

## Scale limits are a choice restore must make deliberately

Admitting a history is subject to resource limits, and those limits are
receiver policy — a decision about how much a given consumer is willing to
take in, not a property of the format.

Restore is a consumer, and a different one from the network. It is reading
bytes this device itself wrote, under no time pressure and from no untrusted
party. If restore is built by routing an archive through the same admission
path used for remote traffic, it silently inherits a policy written for a
different threat, and a document grows until one day it cannot be reopened —
with a failure that names a limit rather than anything the user can act on.

The design position is that restore states its own limit, deliberately. A
document has a maximum size only because someone chose one; that choice must be
measured against real documents and surfaced to the user before it is reached,
rather than discovered in the field. Splitting a history into a base plus
increments is the eventual answer to whatever ceiling is chosen — and not a
reason to build the split before a ceiling has been measured.

## What this design does not settle

Convergence of text is not convergence of meaning. Two people editing the same
structure concurrently can converge to a document neither intended, while every
replica agrees byte for byte. Recording what the user meant, rather than only
what changed, makes that detectable and explainable — it does not make it
mergeable. Semantic merge rules are separate work.

Interim behavior should be honest rather than clever: after merging, re-derive
the structure and, when an expected structural outcome does not hold, surface
it for review instead of silently repairing it.

Parser coverage belongs to a different axis than any of this. The parser and
projection never silently reformat or rewrite text on Loomark-originated
paths; constructs the parser does not understand are held losslessly and simply
cannot be structurally edited. File-backed persistence may write accepted
content to a Markdown body file, and the application may deliberately persist
changes, but these are application writes of accepted content — not parser or
projection writeback. Coverage limits what can be manipulated, not what can be
kept — and the product contract should say so plainly: everything is preserved,
structure editing applies to what was recognized, unrecognized regions are
never rewritten without an explicit user action, and the parser and projection
never silently reformat.

## Verification

This document states invariants and requirements, and deliberately carries no
source-line citations, so that code movement does not make it wrong.

Three of the assumptions it reasons from do not depend on anything being built
first, so they are not left to prose. They are pinned as executing checks in
`workspace/probe/document_ownership_assumptions_wbtest.mbt`: that a checkpoint
round-trips into a fresh editor with equal history, that equal text and equal
version do not imply equal history, and that a text-preserving edit still
advances the document. If the substrate moves under this design, those fail
first — and a failure there means this document needs revisiting, not that the
tests need fixing.

Standalone Loomark now pins two of these requirements in executable behavior:
each reopened writing instance receives a fresh identity, and local archive
replacement follows causal history advancement rather than source comparison.
The repository and application tests cover source-preserving history changes,
true history no-ops, failed replacement, and continued editing after reopen.

Requirements should stop living only in this document as they become
expressible. **This document holding a constraint is a stage, not an
achievement** — prose is the weakest place to keep a rule, and the sections
above should shrink as the rules move into code.

Observations behind the claims — which were read, which were executed, which
remain unverified — are recorded separately, dated and pinned to the commits
they were taken at:

- [`docs/evidence/2026-08-03-local-first-document-ownership-claims.json`](../evidence/2026-08-03-local-first-document-ownership-claims.json)

A mismatch between that record and current code is drift to re-check, not a
defect in this document: a requirement can be violated by a change without
being invalidated by it.

## Related

- [Grand Design](GRAND_DESIGN.md) — vision, principles, implementation order
- [Stable Document Entity Graph](stable-document-entity-graph.md) — stable
  editing-entity identity above projection
- [Design Concerns](design-concerns.md) — open problems
- [Markdown file-backed authority and external
  admission](../decisions/2026-08-09-markdown-file-backed-authority-and-external-admission.md)
  — File Authority, External admission, and the persistence-mode split
