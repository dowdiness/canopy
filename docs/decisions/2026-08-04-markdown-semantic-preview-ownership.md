# Markdown semantic Preview ownership

**Date:** 2026-08-04

**Status:** Accepted current implementation; superseded when #1244 completes.

**Related:**

- [Loomark application handoff](../archive/plans/2026-08-01-loomark-application-handoff.md)
- [Loom Markdown semantic attachment boundary](../../deps/loom/docs/decisions/2026-08-04-markdown-semantic-attachment-boundary.md)
- [Issue #1145](https://github.com/dowdiness/canopy/issues/1145)
- [Lifecycle follow-up #1159](https://github.com/dowdiness/canopy/issues/1159)
- [Concurrent projection execution target](../archive/decisions/2026-08-12-loomark-concurrent-projection-execution.md)

**Decision:** The Markdown editor offers an explicit, opt-in construction path
that returns its existing editing facade together with one semantic observer
over the same parser. Ordinary construction remains observer-free. The private
Loomark host retains both resources for its existing page/process lifetime and
installs owning semantic documents only at accepted Preview transition points.

**Keep until:** The concurrent projection execution target completes #1244 and
removes the main-thread editor/semantic-observer co-location described here.

## Context

Loomark's editing modes already share one canonical source, parser, projection,
edit-lowering path, identity model, and source mapping. Its earlier Preview read
the editable projection, which intentionally cannot represent the complete
source-aware Markdown semantic model.

Constructing a second parser for Preview would allow the three modes to observe
different commits and would duplicate incremental work. Exposing a generic
parser or reactive accessor would weaken the editor facade. Attaching semantic
observation to every ordinary Markdown editor would retain work for consumers
that never request Preview.

The current private host rejects a second mount and has no early-unmount or
reuse contract. Its editor resources therefore already have page/process
lifetime.

## Decision

### Construction and ownership

The existing Markdown editor construction path keeps its behavior and owns no
semantic observer. A separate opt-in path returns the same facade plus one
observer created inside the companion seam where the live parser is already
available. The two paths share one private initialization implementation so
source seeding and initial projection cannot drift.

The companion handoff carries only the typed semantic observer. It does not
expose parser or runtime internals, reactive ownership handles, caches, or a
generic callback.

The generic editor privately roots the projection state it already owns for the
editor's lifetime. This makes runtime-wide collection by a co-located observer
safe without adding a new public lifecycle interface. Because the current
editor has no teardown contract, these roots deliberately follow the host's
page/process lifetime.

### Functional core and imperative shell

The private Loomark model holds an optional owning semantic document. Its
imperative update shell reads the observer only when an accepted transaction:

- enters Preview;
- changes canonical source while Preview is active; or
- restores a snapshot whose resulting mode is Preview.

Rejected and unchanged transactions retain the prior accepted document.
Leaving Preview clears or ignores the read model. View evaluation never performs
effectful semantic reads.

Rendering is a deterministic transformation from canonical source and an owning
semantic document to an inert typed view tree. Every public semantic form has
an explicit rendering decision. Raw HTML renders as text, and rejected URL
destinations remain visible without becoming active links or media sources.

## Consequences

- Raw, Block, and Preview observe one parser and one accepted mutation path.
- Ordinary and headless Markdown editors pay no semantic-observer cost.
- Repeated Preview selection and edits create no additional observers.
- Preview can represent lists, quotations, reference metadata, breaks,
  autolinks, HTML nodes, recovery, and diagnostics without converting back to
  the legacy editable projection.
- The generic editor's existing projection state remains rooted for the editor's
  lifetime. Short-lived editors on a shared runtime are not given a new teardown
  claim by this decision.
- A future reusable Session must introduce and test explicit teardown for the
  editor-owned roots and semantic observer together. It may supersede the
  lifetime portion of this ADR without changing the semantic renderer or read
  model.

## Non-goals

- Public Browser Session, early unmount, remount, or host reuse.
- Generic parser or reactive accessors.
- A second parser, DOM owner, HTML-string injection, or semantic identity
  protocol.
- Replacement of the editable projection, structural editing, source mapping,
  or reconciliation paths.
- Trusted raw-HTML passthrough or new Markdown syntax.
