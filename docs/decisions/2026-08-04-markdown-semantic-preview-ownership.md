# Markdown semantic Preview ownership

**Date:** 2026-08-04

**Status:** Accepted for the private single-mount Loomark host.

**Related:**

- [Loomark application handoff](../plans/2026-08-01-loomark-application-handoff.md)
- [Loom Markdown semantic attachment boundary](../../deps/loom/docs/decisions/2026-08-04-markdown-semantic-attachment-boundary.md)
- [Issue #1145](https://github.com/dowdiness/canopy/issues/1145)

**Decision:** The Markdown editor offers an explicit construction path that
returns its existing editing facade together with one semantic attachment over
the exact parser created for that facade. The ordinary constructor remains
attachment-free. The private Loomark host retains the editor and attachment for
its existing page/process lifetime and installs owning semantic documents only
at accepted Preview transition points.

**Keep until:** A reusable Browser Session with explicit teardown supersedes
the private single-mount host.

## Context

Loomark's Raw and Block modes already share one canonical source, parser,
projection, edit-lowering path, identity model, and SourceMap. Its earlier
Preview read the editable Block snapshot, which intentionally cannot represent
the complete source-aware Markdown semantic model.

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

The existing Markdown editor constructor keeps its behavior and owns no
semantic attachment. A separate Markdown-specific constructor returns the same
facade plus one Loom semantic attachment created inside the companion boundary
where the live parser is already available. The two paths share one private
initialization implementation so source seeding and initial projection cannot
drift.

The companion handoff carries only the typed semantic attachment. It does not
expose the parser, runtime, Watch, Scope, cache, or a generic callback.

The generic editor privately roots each projection memo it already owns for the
editor's lifetime. This makes runtime-wide collection by a co-located semantic
attachment safe without adding a new public lifecycle API. Because the current
editor has no destructor, these roots deliberately follow the host's
page/process lifetime.

### Functional core and imperative shell

The private Loomark model holds an optional owning semantic document. Its
imperative update shell reads the attachment only when an accepted transaction:

- enters Preview;
- changes canonical source while Preview is active; or
- restores a snapshot whose resulting mode is Preview.

Rejected and unchanged transactions retain the prior accepted document.
Leaving Preview clears or ignores the read model. Rabbita view evaluation never
reads the attachment.

Rendering is a deterministic `source + MarkdownIR -> typed Rabbita Html`
transformation. Every public semantic view has an explicit decision. Raw HTML
nodes render as text, and rejected URL destinations remain visible without an
active `href` or `src`.

## Consequences

- Raw, Block, and Preview observe one parser and one accepted mutation path.
- Ordinary and headless Markdown editors pay no semantic attachment cost.
- Repeated Preview selection and edits create no additional attachments.
- Preview can represent lists, quotations, reference metadata, breaks,
  autolinks, HTML nodes, recovery, and diagnostics without converting back to
  the legacy editable Block model.
- The generic editor's existing projection memos remain rooted for the editor's
  lifetime. Short-lived editors on a shared runtime are not given a new teardown
  claim by this decision.
- A future reusable Session must introduce and test explicit teardown for the
  editor-owned roots and semantic attachment together. It may supersede the
  lifetime portion of this ADR without changing the semantic renderer or read
  model.

## Non-goals

- Public Browser Session, early unmount, remount, or host reuse.
- Generic parser or reactive accessors.
- A second parser, DOM owner, HTML-string injection, or semantic identity
  protocol.
- Replacement of the editable Block projection, structural editing, SourceMap,
  or reconciliation paths.
- Trusted raw-HTML passthrough or new Markdown syntax.
