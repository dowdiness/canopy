# Loomark local-first document persistence — design

Status: design only, independently reviewed, then reduced. No implementation
plan, no ticket, no code.

Extends `docs/plans/2026-08-01-loomark-application-handoff.md`, which assigns no
owner to persistence.

## Why

Loomark can edit a Markdown document. It cannot own one.

`loomark/core/pkg.generated.mbti` defines `ApplicationStateSnapshot` as
`{version : Int, source : String, mode : ApplicationMode}`. Restoring from it
reproduces the characters on screen and nothing else: no causal history, no
version frontier, no continuity with any replica that already holds operations
from this document.

Closing the tab therefore does not pause the document. It abandons it and
starts a new one that happens to contain the same text. This is invisible until
a second device or a second person exists, and unrecoverable once they do.

One sentence states the whole design: **persist the operation history, not the
text.**

## Scope

In:

- persist and restore a single document's CRDT history across process restart
- the identity needed for that to be well-defined
- three methods on the Canopy `editor/markdown` façade
- a storage seam thin enough to fake in a test

Out, and enforced rather than merely listed:

- network sync, remote apply, peers
- workspace/document catalog
- durable intent log, semantic conflict review
- browser storage implementation
- extraction into a reusable library

The last item is a deliberate deferral: the repository lives in `loomark/` as
application code, and extraction is considered only when a second consumer
exists and the same contract holds for it.

## Current state

Read on `origin/main` at `127d603f`.

Everything needed already exists one layer below the façade:

    event-graph-walker/text/pkg.generated.mbti
      SyncMessage::to_json_string / from_json_string
      Version::to_json_string / from_json_string
    editor/pkg.generated.mbti:154,170
      SyncEditor::export_all / get_version

The façade hides all of it. `MarkdownEditor` wraps `SyncEditor` privately
(`editor/markdown/editor.mbt:76-78`) and publishes only `MarkdownEditor`,
`commit`, and `snapshot`. No version, no export.

So this design invents no algorithm and no format. It surfaces three methods
and writes two files.

## Design

### The archive is two files

    document.archive.json       -- Loomark envelope, carrying the checkpoint opaquely
    document.md                 -- the plain source text

The envelope is Loomark's, not the CRDT's. The checkpoint cannot carry archive
metadata itself: its decoder rejects any object that is not exactly
`schema`, `format`, `operations`, `heads`
(`event-graph-walker/text/sync.mbt:982-985`, `exact_object_fields`). Adding a
`document_id` or an archive version to it would make the file undecodable.

    {
      "loomark_archive": 1,        -- this envelope's version
      "document_id": "...",
      "crdt_codec_version": 1,
      "checkpoint": "<to_json_string output, opaque to Loomark>",
      "pending_operations": null,  -- reserved
      "undo": null,                -- reserved
      "actors": null               -- reserved
    }

`document_id` must exist here from the start. The checkpoint wire format has no
document identity at all, so without an outer envelope a later network phase
could bind valid history to the wrong document — and it could not be added to
the checkpoint later without a schema break.

There is no manifest, because two files need no index. There are no change
segments and no compaction, because there is no measured problem for them to
solve; `CLAUDE.md` forbids designing an optimization before a microbenchmark
reproduces its bottleneck.

The envelope is replaced atomically. A torn write is not a degraded archive: a
truncated checkpoint fails decoding outright, and `document.md` cannot
reconstruct a `Version`, so a half-written envelope loses the document's causal
identity even though its text survives. `DurableLocal` is reported only after
an atomic replacement completes.

`document.md` is redundant — it is derivable from the checkpoint. It is kept
anyway, as the single guarantee that survives Loomark's disappearance and a
corrupt checkpoint. It is a materialized view and is never merged back: an
externally edited `.md` is diffed against the last export and enters as an
explicit import operation, not as a second authority.

`crdt_codec_version` sits in the envelope for the same reason the envelope
exists. The CRDT's serialization does have a schema field
(`event-graph-walker/text/sync.mbt:718-723`), but its decoder accepts only
schema 1 and collapses every failure into one generic `MalformedMessage`
(`event-graph-walker/text/sync.mbt:840-845`). A reader cannot ask it whether a
file is damaged or merely newer. The envelope answers that before the bytes
reach the decoder.

### The façade gains three methods

    version()           -> MarkdownVersion
    export_checkpoint() -> MarkdownCheckpoint
    open_checkpoint()   -> MarkdownEditor

`commit` already exists. `MarkdownVersion` and `MarkdownCheckpoint` wrap
`@text.Version` and `@text.SyncMessage` opaquely, so no `@text` type appears in
the generated interface and Loomark persists bytes it cannot interpret.

Loomark writes both files after a commit that changed the version, and reads
them at startup. That is the entire repository.

### Identity

`DocumentId` identifies the document across sessions. `ReplicaInstanceId`
identifies one writing instance and is fresh per mount.

`DocumentId` lives in the archive envelope, never in the checkpoint.

At the time of writing, every Loomark mount passed the same hardcoded id
(`loomark/internal/rabbita/application.mbt:1067`, `"loomark-dev-host"`), which
becomes the `TextState` replica, the undo owner, the ephemeral hub id, and the
peer identity at once (`editor/sync_editor.mbt:62-91`) — two browser tabs were
one replica. A fix is in flight separately from this design. It breaks nothing
that this design depends on, because nothing persists or recovers that id
today; this design simply requires that the fix land before any archive is
written, or every archive records a replica identity that is not unique.

### What V1 deliberately does not need

Each of these was in the first draft of this design and was removed because it
only becomes necessary once remote operations exist, which Scope excludes.

| Removed | Needed only when |
| --- | --- |
| journal-before-apply ordering | remote operations are applied |
| "apply extent is unknown" doctrine | `apply_sync` is called |
| persisting causally pending operations | a causal gap can occur |
| `Replicated` / `BackedUp` states | a peer exists |
| durable replica-to-actor mapping | attribution across people matters |

Local editing generates its own operations, so apply-first is inherent and
ordering has nothing to choose between. Applying an **intact** checkpoint to a fresh editor
cannot leave pending operations, because `export_all` emits the complete oplog
(`event-graph-walker/text/sync.mbt:1053-1059`), which contains every parent,
origin, and replica predecessor; an empty oplog likewise yields zero pending.
So the `apply_sync` raise pathology recorded in the review below cannot arise
on the restore path for a checkpoint we wrote.

This holds for intact input only, and the boundary matters. A syntactically
valid but truncated checkpoint that retains dependent operations *can* produce
pending operations and therefore `VersionNotFound`. Restore must treat that
raise as "this archive is unusable", never as "retry" — which is why atomic
replacement above is load-bearing rather than hygiene.

Durability has two states, not four: `Applied` and `DurableLocal`. While
offline the user is shown "saved locally", which is a normal state and not a
warning.

### Reserved extension points

Reserved means a field exists and is empty in the Loomark envelope, not that a
feature is postponed and will require a breaking change later. They cannot live
in the checkpoint, whose decoder rejects unknown fields.

- a `pending_operations` section, because `TextState` holds them outside the
  oplog (`event-graph-walker/text/text_doc.mbt:36-39`) and `export_all` does
  not read them
- an `undo` section, because `UndoManager` owns separate mutable stacks that no
  checkpoint captures
- an `actor` section, because wire operations carry replica identity only

## Derived state and incr

The derived layer is already incremental, and persistence should stay out of it.

`SyncEditor` exposes its entire derived pipeline as `@cells.Derived` hanging off
one runtime — `parser_source`, `parser_ast`, `parser_syntax_tree`,
`parser_diagnostics`, `cached_proj_node`, `registry_memo`, `source_map_memo`
(`editor/pkg.generated.mbti:141,188-207`). Source text, CST, projection, and
source map are already incr cells. There is no derived-state problem left for
this design to solve; `editor/markdown` deliberately collapses that surface into
one plain `snapshot()`.

Persistence must not join that graph, for three reasons.

Writing is an effect, and a `Derived` that writes puts I/O in the functional
core, which the Functional Core / Imperative Shell rule in `CLAUDE.md` forbids.

`Derived` recomputes lazily when something asks, and a long-lived reader needs
a watch to stay alive. That alone would not settle it, because `@cells` also
offers `Effect`, which runs eagerly and is an implicit GC root — the obvious
counter-proposal. `Effect` still does not work here: it accepts a synchronous
`() -> Unit` only, so it cannot express completion-ordered durability, which is
the entire content of `DurableLocal`. An eager cell that cannot report when the
write finished is worse than no cell, because it looks like it did.

The trigger is already discrete and cheap. A checkpoint is written when a commit
changed the version, and comparing two `Version` values answers that directly.
A dependency graph would be machinery for a question that is already answered,
and a long-lived cell would additionally need a `Watch`/`Observer` GC anchor
kept alive for nothing.

What is worth reusing is the read side: the repository takes the source it
writes from the existing snapshot rather than materializing text a second way.

There is one honest use for incr here, and it is on the display side rather
than the storage side. The "saved locally / saving" indicator is a pure
projection of `document_version == last_durable_version`, and belongs as a
derived cell alongside the projection cells the editor already publishes. The
write remains in the shell; only the answer to "is it current?" is derived.

`loomark/core` currently imports only `moonbitlang/core/immut/vector`. Keeping
incr out of it is not an omission — the handoff plan requires that core import
no runtime, and a zero-dependency pure reducer is the asset that makes the
acceptance test below trivial to write.

## Acceptance shape

The first test is writable before any storage exists, in-process:

    create a document offline, edit it, discard the editor,
    rebuild it from the two persisted strings,
    assert the source and the version match, then edit further

The oracle is **not** source plus `Version`. That pair is too weak to prove
continuation: `Version::from_ops` records only the maximum sequence per replica
(`event-graph-walker/text/types.mbt:99-117`) and ignores operation content,
parents, and origins. Two histories can agree on both — insert different
characters under the same replica identity, then delete them, and source and
`Version` match while the stored item content differs. A later undelete or a
merge then diverges.

The oracle is therefore the canonical logical checkpoint — `SyncMessage`
already provides `to_canonical_bytes` — plus one assertion that a merge after
restore produces the expected result. A structural dump of `TextState` is still
wrong to assert: replay is equivalent, not byte-identical, because wire
operations omit the process-local `lv` and reconstruct it on apply.

The test belongs to the Loomark repository API, not to `SyncEditor` — per the
test-ownership rule, each package tests its own logic.

## Design review outcome

Reviewed twice on 2026-08-03 by Codex (GPT-5), read-only, at `127d603f`, with
every finding re-verified against the source before being folded in.

The second review targeted over-reduction and found four defects, all now
addressed above: the checkpoint cannot carry archive metadata because its
decoder rejects unknown fields; `document_id` must be reserved now or a later
network phase forces a schema break; source-plus-`Version` is too weak an
acceptance oracle; and atomic replacement plus the 100,000-operation restore
ceiling were reduced away when they are load-bearing for the declared scope. It
also corrected the incr argument: `Effect` is eager and self-anchoring, so
laziness and GC cost alone did not justify the conclusion — the missing
completion signal does.

It confirmed that the removed network machinery is genuinely not load-bearing
for V1.

From the first review, three findings apply only to the excluded remote path
and are recorded here so that a later design does not rediscover them:

- `SyncEditor::apply_sync` reconciles derived state even on failure, by design
  (`editor/sync_editor.mbt:470-471`), and raises `VersionNotFound` even when
  the apply fully succeeded but left pending operations
  (`editor/sync_editor.mbt:482-483`), discarding the `SyncReport` first. A raise
  does not mean "not applied".
- pending operations and undo stacks sit outside the checkpoint.
- `ActorId` has no durable representation.

## Known cruft this design routes around

Named so it is not rediscovered, and explicitly out of scope here.

`SyncEditor::apply_sync` returns `Unit raise` and discards a `SyncReport` that
is already `pub(all)` and already carries applied/duplicate/pending counts
(`event-graph-walker/text/pkg.generated.mbti:52-57`). The code labels this the
"legacy Unit-raising SyncHost seam" (`editor/sync_editor.mbt:476-477`); the
constraint is one closure type (`sync_session/sync_session.mbt:37`). Returning
the report would delete a class of caller-side guesswork, but `apply_sync` has
over a hundred call sites, mostly tests, so it is a separate tracked change and
must not be smuggled into this work.

## Risks

- The archive format is the hardest thing to change once users have data.
  Mitigation: version it, keep `document.md` as an unconditional escape hatch,
  and reserve the three sections above.
- Writing a full checkpoint per commit is O(oplog) per keystroke-group. This is
  accepted for V1 and is the one place a microbenchmark is owed before the
  design is called finished — not to optimize preemptively, but to know the
  document size at which it stops being acceptable.
- There is a hard ceiling independent of performance. Decoding enforces default
  limits of 16 MiB encoded and 100,000 operations
  (`event-graph-walker/sync/types.mbt:61-66`), so a document that exceeds them
  cannot be restored at all, and fails with `LimitExceeded` rather than
  anything a user could act on. V1 must decide whether to raise the limit at
  the restore call site or to surface the ceiling honestly; it may not discover
  it in production. This is the strongest argument that change segments will
  eventually be needed — but it is a ceiling to measure against, not a licence
  to build them now.

## Notes

- Evidence read on `origin/main` at `127d603f`.
- The next artifact is a reviewed implementation plan, not code.
