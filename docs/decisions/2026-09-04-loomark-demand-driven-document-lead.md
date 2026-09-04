# Loomark derives Document leads through a feature-owned incremental graph

**Date:** 2026-09-04

**Status:** Accepted

**Related:** [Source-first interactive contract](2026-08-24-loomark-source-first-interactive-contract.md), [Source repository](2026-08-29-loomark-source-repository.md), [Document deletion](2026-08-31-loomark-document-deletion.md)

## Context

Recent documents, Delete confirmation, and Export need the same compact way to
recognize a Loomark document from its contents. The projection must not make the
UI interpret repository snapshots or Markdown, must not become another Document
text authority, and should not parse every document while Recent documents is
hidden.

The existing app view derives and renders Recent documents directly from
`RepositorySnapshot` and Catalog entries. Merely adding a renderer package would
leave feature assembly, keyed caching, lifecycle, and intent wiring scattered in
`app`. It would also fail to enforce the required dependency rule: a sibling of
`internal/source_repository` can still import that package.

The existing Sidebar owns collapse and mobile-open state inside a render
callback. That shape cannot expose visibility as an ordinary Rabbita dependency
without mirroring state, reading the DOM, or constructing graph nodes during
rendering. Passing the existing `SidebarScope` through `Val` is also invalid
because it combines comparable state with `Cmd` and `Emit` capabilities that
have no meaningful value equality.

## Decision

A **Document lead** is a total, deterministic projection of Document text. The
internal `document_lead` package owns Markdown parsing, normalization, safe
source-line fallback, and the existing content-derived-name analysis currently
inside `source_repository`. It exposes small equality-bearing product values and
narrow name operations rather than MarkdownIR, source origins, parser state, or
repository types. Task recognition enables the Markdown task-list extension.

Move the Source repository to `app/internal/source_repository`. MoonBit permits
that package to be imported from `app` and its descendants, but rejects imports
from the sibling `internal/recent_documents` feature. This placement makes the
repository-access prohibition a compiler rule instead of a convention.
`source_repository` consumes the narrow name-analysis API from `document_lead`;
it no longer owns Markdown traversal or exports `derive_name` to the app.

Documents retains the latest source selected for lead preparation, not a
computed Document lead. Existing and imported documents seed that source; a New
document seeds it when it first enters Recent documents. Later text changes
replace it through a lead-specific transition driven by the existing Autosave
`QuietElapsed` message. That transition checks the current change order
independently of the save lane, because maximum-delay or visibility-flush saving
may already have consumed the Autosave checkpoint.

When quiet elapses during IME composition, Documents records the matching quiet
fact but preserves the previous lead source. Composition end accepts it if the
change order is still current; a later text change invalidates it. Maximum-delay,
visibility-flush, and save feedback never replace a lead source themselves: they
establish durability facts, not that the user has paused. Lead preparation
shares the existing timer message but never waits for, or depends on, a Browser
storage result.

The `recent_documents` package owns the complete feature projection: its
capability-resolved input types, pure per-document lead graph, visibility branch,
keyed rendered rows, Delete confirmation presentation, and intent emission. A
small opaque feature handle may expose separate navigation and dialog `Val`s for
app layout composition. `app` supplies a `Val` of resolved feature inputs and
maps intents back to `Msg`; it does not construct the feature's `assoc_by` or
`switch_by` topology.

Inside the feature, an outer `assoc_by`, keyed by Document ID, first projects the
lead-source identity away from orthogonal selection, saving, and deletion state.
It derives the Document lead from that smaller value and then combines the
result with presentation state. A separate visibility branch consumes those
values only while Recent documents is shown. Inside that branch, another keyed
projection owns rendered rows and their commands.

Hiding Recent documents disposes the rendered branch while leaving pure cached
values. Hidden text changes mark the relevant pure graph dirty without running
extraction. Reopening
reconciles current keys before rendering and recomputes only changed leads.

Sidebar state remains component-local behind one opaque provider created during
app graph construction. The provider exposes a narrow incremental visibility
selector and command-producing operations, never a `Val` containing commands.
Loomark has one page-lifetime Recent-documents visibility state: it initially
shows on wide screens and hides on narrow screens, then continues unchanged
across breakpoint transitions. Each breakpoint selects presentation and effects
while preserving that visibility value.

## Validation

A throwaway browser probe on branch
`prototype/loomark-document-lead-cache` exercised the topology against the
actual Rabbita runtime. The
[demand and lifecycle probe](https://github.com/dowdiness/canopy/commit/67000cd7054309fd3261d46c9bab89e39c8f7252)
established demand suppression, keyed reuse, visible-scope disposal, and
demand-time removal reconciliation. The
[orthogonal-input probe](https://github.com/dowdiness/canopy/commit/d1b68ca5b34a0e255df835ae79bfcf84093ae06e)
then changed only A's save status: row renders increased from two to three while
extraction remained at two runs.

Hidden startup performed no keyed work. First demand built and evaluated two
pure branches and two rendered rows. Hiding disposed both rendered rows and the
visible branch while retaining both pure branches. Reopening rebuilt rows
without another extraction. After changing only A's content while hidden, the
next demand extracted only A. Deleting B while hidden retained B's pure branch
until the next demand, which disposed B before rendering only A.

The probe validates callback behavior and lifecycle, not elapsed-time
performance. Probe-only subscriptions observed cleanup; production pure nodes
remain free of subscriptions. It ran with MoonBit `0.1.20260819`, Rabbita commit
`6472dd339bc1cf93b04fcd3bae1fa8f9e775e9ed`, the JS debug target, and Chrome
`148.0.7778.215`. The prototype stays off the main branch.

A release-mode JS benchmark of the existing Markdown name analysis measured
about 167 ms to accept a changed-title 1 MiB Source and about 59 ms to derive
names for a 1000-Source large-document mix. These are not Document-lead
benchmarks and do not prove a product speedup. They do establish that repeated
browser-target Markdown parsing can be material, so unconditional parse-on-open
is not the simpler safe default.

A separate compiler probe confirmed MoonBit's package rule: a package below
`a/internal/` imports from `a/...`, while a sibling package is rejected during
build planning. The repository relocation therefore enforces the intended
negative dependency.

## Rejected alternatives

- Passing MarkdownIR to Recent documents leaks parser details, weakens equality
  with unrendered origins and metadata, and moves lead-selection policy into the
  UI.
- Keeping `source_repository` at the current sibling path and documenting a
  forbidden import does not satisfy compiler-enforced isolation.
- Making `recent_documents` a renderer leaf leaves its graph topology, cache,
  lifecycle, and Delete presentation in `app`, weakening feature locality.
- Moving the Documents reducer to an `internal/documents` package publishes a
  broad private protocol and splits atomic application transitions.
- Storing Document leads or a manual cache in the root Model duplicates
  Rabbita's cache and requires explicit invalidation.
- Parsing all leads on every visible render is simple for small data, but repeats
  potentially material Markdown work and loses reuse across hide and reopen.
- A second `incr` runtime, a new keyed-visible memo, or an always-active observer
  duplicates lifecycle machinery already provided by Rabbita.
- DOM visibility checks happen after graph construction and cannot prevent the
  work needed to construct that render.
- Mirroring Sidebar state through change callbacks creates two values that can
  disagree.
- Moving Sidebar presentation state into the root reducer expands the root
  protocol even though graph composition can share the provider's reactive
  visibility directly.
- Making Sidebar own Recent-document policy turns a reusable layout primitive
  into a Loomark-specific feature module.
- Keeping rendered rows across hiding retains stale HTML, commands, and local UI
  state; disposing the entire pure graph on hide reparses unchanged documents on
  every reopen.

## Consequences

A deleted document's pure cached lead may remain unobserved until the next
Recent-documents demand or feature disposal. On reopening, key reconciliation
removes deleted entries before rendering. Prompt hidden eviction would require
an eager observer or explicit cache and is intentionally not added without a
separate requirement.

The Source repository package path changes, and Markdown name-analysis tests and
benchmarks move with their semantic owner. This is a mechanical import migration
plus a deliberate dependency inversion; repository persistence behavior must
remain unchanged.

Implementation must project lead-source identity before combining orthogonal row
state. The pure keyed layer contains no HTML, commands, DOM handles, timers,
subscriptions, or parser instances. Tests distinguish first demand, quiet
replacement, status-only updates, hidden invalidation, reopen reuse, key removal,
and disposal of the visible row branch.
