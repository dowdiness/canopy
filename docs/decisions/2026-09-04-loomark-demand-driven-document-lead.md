# Loomark derives Document leads through a demand-driven incremental graph

**Date:** 2026-09-04

**Status:** Accepted

**Related:** [Source-first interactive contract](2026-08-24-loomark-source-first-interactive-contract.md), [Source repository](2026-08-29-loomark-source-repository.md), [Document deletion](2026-08-31-loomark-document-deletion.md)

## Context

Recent documents, Delete confirmation, and Export need the same compact way to
recognize a Loomark document from its contents. The projection must not make the
UI interpret repository snapshots or Markdown, must not become another Document
text authority, and should not parse every document while Recent documents is
hidden.

The existing Sidebar owns its collapse and mobile-open state inside a render
callback. That shape cannot expose visibility as an ordinary Rabbita dependency
without mirroring state, reading the DOM, or constructing graph nodes during
rendering. Passing the existing `SidebarScope` through `Val` is also invalid
because it combines comparable state with `Cmd` and `Emit` capabilities that
have no meaningful value equality.

## Decision

A **Document lead** is a total, deterministic projection of Document text. A
new internal `document_lead` package owns Markdown parsing, normalization, and
safe source-line fallback. It exposes a small equality-bearing value rather
than MarkdownIR, source origins, parser state, or repository types. The internal
`recent_documents` package receives prepared Document leads and resolved
selection, saving, and deletion capabilities; it owns rendering and emits user
intents but does not make those decisions.

Documents retains the latest source selected for lead preparation, not a
computed Document lead. Existing and imported documents seed that source; a New
document seeds it when it first enters Recent documents. Later text changes
replace it only when the existing Autosave quiet checkpoint accepts the same
change order. Lead preparation therefore shares the established quiet fact but
never waits for, or depends on, a Browser storage result.

Rabbita owns the computed cache. An app-scoped `assoc_by`, keyed by Document ID,
derives pure Recent-document input values and caches each Document lead. A
separate visibility branch consumes those values only while Recent documents is
shown. Inside that branch, another keyed projection owns rendered rows and their
commands. Hiding Recent documents disposes the rendered branch while leaving
only pure cached values; hidden text changes mark the pure graph dirty without
running extraction. Reopening reconciles current keys before rendering and
recomputes only changed leads.

Sidebar state remains component-local behind one opaque provider created during
app graph construction. The provider exposes a narrow incremental visibility
selector and command-producing operations, never a `Val` containing commands.
Loomark has one page-lifetime Recent-documents visibility state: it initially
shows on wide screens and hides on narrow screens, then continues unchanged
across breakpoint transitions. Each breakpoint selects its presentation and
effects while preserving that visibility value.

## Validation

A throwaway browser probe on branch
`prototype/loomark-document-lead-cache` at `a38e40d8` exercised the proposed
topology against the actual Rabbita runtime. Its counters tracked pure keyed
branch construction, extraction, rendered-row branch construction, rendering,
and scope disposal.

Hidden startup performed no keyed work. First demand built and evaluated two
pure branches and two rendered rows. Hiding disposed both rendered rows and the
visible branch while retaining both pure branches. Reopening rebuilt the rows
without another extraction. After changing only A while hidden, the next demand
extracted only A. Deleting B while hidden retained B's pure branch until the
next demand, which disposed B before rendering only A.

The probe validates demand suppression, keyed reuse, visible-scope disposal, and
demand-time removal reconciliation. It does not measure elapsed time or establish
a performance improvement. Probe-only subscriptions observed cleanup; the
production pure layer remains free of subscriptions. The prototype stays off the
main branch.

## Rejected alternatives

- Passing MarkdownIR to Recent documents leaks parser details, weakens equality
  with unrendered origins and metadata, and moves lead-selection policy into the
  UI.
- Storing Document leads or a manual cache in the root Model duplicates
  Rabbita's cache and requires explicit invalidation.
- A second `incr` runtime, a new keyed-visible memo, or an always-active observer
  duplicates lifecycle machinery already provided by Rabbita.
- DOM visibility checks happen after graph construction and cannot prevent the
  work needed to construct that render.
- Mirroring Sidebar state through change callbacks creates two values that can
  disagree.
- Moving Sidebar presentation state into the root reducer expands the root
  protocol even though app-level graph composition can share the provider's
  reactive visibility directly.
- Keeping rendered rows across hiding retains stale HTML, commands, and local UI
  state; disposing the entire pure graph on hide reparses unchanged documents on
  every reopen.

## Consequences

A deleted document's pure cached lead may remain unobserved until the next
Recent-documents demand or provider disposal. On reopening, key reconciliation
removes deleted entries before rendering. Prompt hidden eviction would require
an eager observer or explicit cache and is intentionally not added without a
separate requirement.

Implementation must keep the app-scoped keyed layer free of HTML, commands,
DOM handles, timers, subscriptions, and parser instances. Tests must distinguish
first demand, quiet replacement, hidden invalidation, reopen reuse, key removal,
and disposal of the visible row branch.
