# The surface a locally-owned document presents

What the application programs against, once a document is something the user
owns rather than something an editing session holds.

[Local-first document ownership](local-first-document-ownership.md) settles what
must be preserved and why. This document settles what shape presents it. Treat
it as direction: it names invariants and boundaries, carries no source
citations, and does not describe what any package does today.

## The noun is the document, not the editor

An editor is a session. It has a cursor, a view mode, an undo stack, a person
in front of it. A document has none of those and outlives all of them.

Making the editor the top-level object forces every document-level concern to
enter through a session that may not exist. Persisting an increment, admitting
a peer's operations, answering how large the history has grown, reporting what
is durable — none of these need a cursor, and a surface that demands one has
made the session a prerequisite for owning a document.

The inversion also hides the case the design exists for. Two windows on one
document are two writing instances, and if the editor is the document, then two
windows are two documents that must be reconciled with each other. The
reconciliation is real, but calling both sides separate documents is what makes
a shared identity look like a reasonable thing to hand them.

So: **a document is the object; a writing session is a capability opened on
it.** Sessions are created and discarded against a document that persists
across all of them.

## What belongs to which

| | Document | Session |
| --- | --- | --- |
| Operation history | ✓ | |
| Current text, as a view of the history | ✓ | |
| Version frontier | ✓ | |
| Durability watermarks | ✓ | |
| Writer identity | | ✓ |
| Cursor, selection, focus | | ✓ |
| Undo and redo stacks | | ✓ |
| View mode, projection focus | | ✓ |

The line is not "what is mutable" or "what is expensive". It is: **would this
still be true if everyone closed their window?** Everything in the right column
is an appearance to reproduce; everything in the left column is an object to
resume. The ownership document says these must stay separately named and
separately versioned. Making them separate types is how that stops depending on
anyone remembering it.

Derived caches — syntax tree, semantic IR, projection, view patches — belong to
neither. They are rebuilt from the text and are never authoritative, so they are
not state to place but state to discard.

## Admission is one operation

Operations enter a document from exactly three places: a session's edits, a
peer's history, and an archive being opened. The last two are the same
operation. Opening an archive is admitting a history into a document that holds
nothing yet; merging is admitting one into a document that holds something.
Nothing distinguishes them but the receiver.

A surface that exposes only the empty-receiver case cannot express the general
one, and loses more than a feature: **the only honest way to check that a
restored document was restored is to merge with it.** Equal history bytes show
that two documents have the same past. Only an exchange of subsequent
operations shows they share a future, and sharing a future is the thing that is
lost when a document is reopened as a new object.

So the document admits a history, and opening is composed from admission rather
than standing beside it.

## Openings are named for what they cost

Two ways a document comes into existence:

- **Opening** an archive continues a document that already exists. Identity,
  history, and causal past all carry.
- **Importing** text creates a new document. It has no past, and no future in
  common with whatever produced the text.

These are the same code until the envelope exists, and they must still be named
apart from the beginning, because the moment identity lives in an envelope one
of them reads an identity and the other mints one. Splitting a name later is a
breaking change; reserving the distinction now costs nothing.

Naming also sets the default. Importing is the lossy path — the ownership
document is explicit that a `.md` touched by an outside tool re-enters as an
import and never as a merge between two truths. A surface where constructing
from text is the obvious call and continuing a document is the exceptional one
has its defaults inverted, and every caller that reaches for the obvious call
silently creates a new document.

## Identity is minted, never supplied

The invariant is one writer identity per writing instance. A caller-supplied
identity cannot enforce it: nothing stops two instances receiving the same
value, and the resulting history is indistinguishable from a legitimate one, so
no later repair can separate them.

An identity supplied as an argument is therefore not a parameter but a defect
waiting for a second window. **Opening a session mints the identity; the caller
never names it.** Determinism for tests is a seam on the session, not a
parameter on the public path.

This matters more than it appears, because the identity is not only the CRDT
replica. It is simultaneously the undo owner, the ephemeral presence identity,
and the peer identity. One supplied string decides four things at once, and the
places it is wrong are not the same places it is noticed.

## Export is a cut, not a dump

Persistence triggers on the history advancing. If the only export is the whole
history, then every save rewrites everything the document has ever been, and
the cost of saving grows with the age of the document rather than the size of
the change.

The primitive is therefore **the history since a version**, with the whole
history as the degenerate case of cutting at nothing. This is also the base and
increments the ownership document names as the eventual answer to scale, which
means the shape that answers scale is the same shape that answers routine
saving — it does not need to be built later or separately.

A version is what makes the cut. That it can also be compared to detect that
the document advanced is a consequence of being a frontier, not its purpose. A
surface that offers comparison and withholds the cut has kept the smaller half.

## Durability is a set of watermarks

Applied, durable locally, replicated, backed up. Each is the same kind of
statement about a different destination: *everything up to here has arrived*.
So each is a version, and the ladder is a set of watermarks over one type,
ordered and monotone.

Stating it this way makes the design's rule structural rather than remembered.
"Sent is not saved" is not a discipline to follow but two different watermarks
that cannot be substituted for one another. Adding replication later adds a
watermark, not a redesign.

One caveat the frontier itself imposes: a version summarizes what a writer has
seen, not what a document contains, so a watermark is a claim about one
document's own progress and never a comparison between two documents.

A watermark advances only when a replacement completes. A partially written
archive is not partial durability — it is a document whose text may have
survived while its history did not, which is the loss the whole direction
exists to prevent.

## Admission states its policy at the call

Resource limits are a consumer's policy. Two consumers admit histories for
opposite reasons: the network defends against a sender it does not trust, and
opening an archive defends against exhausting this device on data it wrote
itself. The first is a question about an adversary; the second is a question
about capacity. One number cannot be both, and a shared number means whichever
was written first silently governs the other.

Policy therefore belongs to the admission, not to the document. A document does
not have a maximum size; a caller admits under a stated policy, and different
callers state different ones.

A ceiling nobody can see is a ceiling discovered in the field. The document must
be able to answer how much room remains under a given policy, so that a limit
can be surfaced before it is reached rather than reported as a failure at the
moment a document stops opening.

## Withheld operations are a state, not a failure

Operations can arrive whose causal prerequisites have not. This is ordinary in
any system where more than two replicas exchange history, and the ownership
document already treats such operations as real state an archive must
eventually retain.

An admission that can only succeed or raise cannot report that it took some
operations and is holding others. The state the design reserves room for then
has no way to reach the application, and a caller cannot distinguish a document
that is waiting from one that is broken.

Admission therefore reports what it took and what it is holding. Whether
withheld operations are acceptable is the caller's judgment: for a peer
exchange they are expected, and for an archive that claims to be complete they
are evidence that it is not. **This is where restore states its own policy** —
not by owning a separate mechanism, but by making a different judgment about the
same report.

## Three layers, not two

- **Document** — knows operations, versions, and views. Knows nothing about
  files, formats, or destinations.
- **Archive** — the envelope: application-owned metadata wrapping a payload it
  does not interpret, plus the portable text. Owns document identity, its own
  format version, and room reserved for what is not carried yet.
- **Store** — atomic replacement, locations, and the reporting of durability.

The middle layer is the one most easily skipped, and skipping it is how document
identity ends up somewhere that cannot hold it: the payload's serialization is a
closed contract belonging to the CRDT, admitting exactly its own fields. There
is no seam in it for what a document is called.

## What this design does not settle

**Undo across a restart conflicts with per-instance identity.** The ownership
document counts undo across a restart among the losses it exists to prevent, and
undo state is a session's, discarded with the window. Recovering it after a
restart requires either promoting undo into the archive, or letting a new
session claim a previous instance's operations as its own — and the second
contradicts one identity per writing instance. This design does not choose. It
records that the choice exists, and that the envelope is where the first option
would land.

**Whether importing text should be able to adopt an existing identity.** A
document reconstructed from its portable artifact after its history is lost is
a new document by this design. Whether it should be allowed to claim the old
identity — and what that would mean for replicas that still hold the history —
is not settled here.

**Semantic merge.** Convergence of text is not convergence of meaning. Nothing
in this surface makes a structurally incoherent merge detectable; that is
separate work.

## Verification

Two assumptions this design rests on are measurable without building it, and
were measured rather than argued: that admitting a history into a populated
document and into an empty one is the same operation, and that a history whose
prerequisites are absent is reported today as an error rather than as a
withheld count. Observations are recorded in
[`docs/evidence/2026-08-03-markdown-facade-history-transport.json`](../evidence/2026-08-03-markdown-facade-history-transport.json).

The rest is not yet expressible and should stop living in this document as it
becomes so: the document and session split when they are separate types, the
minted identity when opening a session generates it, the watermarks when
durability is reported as versions, and the admission policy when it is an
argument rather than a property fixed at construction.

A prediction that would falsify the document and session split: some piece of
state that must survive a restart but belongs to no document — if one exists,
the line drawn here is in the wrong place. Undo is the candidate, and the
unsettled question above is where it would show.

## Related

- [Local-first document ownership](local-first-document-ownership.md) — what
  must be preserved, and why
- [Grand Design](GRAND_DESIGN.md) — vision, principles, implementation order
- [Stable Document Entity Graph](stable-document-entity-graph.md) — stable
  editing-entity identity above projection
