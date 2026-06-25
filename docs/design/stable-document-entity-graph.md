# Stable document entity graph

**Status:** Design direction rather than implemented behavior.

This note names the direction for Canopy's next identity layer. It should guide
experiments and plans, but code and generated interfaces remain authoritative.
The first implementation work should be a narrow spike, not a new framework.

## Thesis

Canopy needs a stable editing-entity layer, but it should grow out of the
existing projection identity pipeline rather than start as a parallel identity
system.

The target model is:

```text
Text / CRDT document     durable source of truth
Lossless CST            parsed source facts
Stable entity layer     stable index over editing targets
Incremental views       derived UI, diagnostics, outline, AI context
```

The stable entity layer is not an AST, and it is not a copy of the CST. It is a
thin, evidence-bearing index that says which editing targets exist now, where
they are anchored in the current source/projection, and how confidently they
correspond to targets from a previous state.

## Current stance

Do not introduce a new public entity ID system first.

Canopy already has projection identity, source mapping, edit lowering, and
incremental projection machinery. Treat that as **Phase 0 of the stable entity
layer**. The first task is to measure and extend it, not replace it.

The initial stable entity layer should be a side-table model over existing
projection identity:

- projection identity provides session-local entity identity;
- source maps provide current source anchors;
- projection children provide the primary tree relation;
- side tables add semantic status, evidence, diagnostics, and optional semantic
  anchors;
- derived views remain scheduled through the incremental runtime.

Only split out a distinct entity ID when a concrete spike shows that projection
identity cannot satisfy the required stability scope.

## Source of truth

The stable entity layer must never become the document's source of truth.

Structural edits follow this path:

```text
user intent
  -> language-owned edit calculation
  -> source/text patch
  -> CRDT/editor mutation
  -> parse
  -> projection reconciliation
  -> stable entity side tables
  -> derived views
```

Updating entity metadata alone must not count as editing the document. This
keeps text, collaboration, undo, parser recovery, and projection state on the
same path.

## Identity is a hypothesis

Stable identity is not a fact that is always knowable. It is a hypothesis with
evidence.

The system should record why identity was preserved or refreshed: range
continuity, same syntactic role, stable semantic key, edit provenance, retained
projection identity, language hints, or fallback matching. It should also record
when identity is ambiguous or low confidence.

This evidence is valuable even before it drives behavior. The first spike should
surface it in tests and debug views so identity failures become explainable.

> **Review note (positional ≠ semantic).** A surviving projection `NodeId`
> proves projection-*handle* continuity rather than semantic continuity.
>
> Pure sibling reorder keeps the old `NodeId`s but re-attaches them by position,
> so same-node evidence is positional and meaning-stability is *not* guaranteed
> across reorder without explicit move provenance.
>
> Consumers must not treat a live entity's meaning as stable across such edits.
> Explicit move provenance (`MarkdownEditOp::MoveBlock`) supplies the corrective
> `IdentityTransform::Move` for root-sibling (#723) and same-list item (#731)
> reorders.
>
> Cross-container moves stay rejected because the sibling-level reconciler cannot
> follow a node across a container boundary without ancestor-aware reconciliation.
> Whole-list-container moves also stay rejected because containers match by kind
> alone, so a moved list cannot be uniquely identified.
>
> See [SDEG Invariant & Semantics Review](sdeg-invariant-review.md) (I5/Sem3, G1,
> and *Decision: Markdown move-provenance scope*).

## Stability scopes

The design must name the stability scope before exposing any ID beyond an
internal experiment.

Important scopes are:

- stable across a single reparse;
- stable across malformed intermediate input;
- stable across an editor session;
- stable across reload;
- stable across collaborating peers.

The Phase 0 assumption is intentionally modest: stable entities are
**session-local** and derived from the current projection identity pipeline.
Reload-stable and peer-stable identities require either durable anchors,
deterministic keys, or a persistent side store, and should not be promised by
the initial API.

## Anchors and units

Anchors must carry explicit coordinate semantics. Canopy has multiple integer
coordinate spaces, including source-code-unit offsets, parser spans, CRDT item
positions, and frontend tree positions. Stable entity APIs must not expose raw
position integers without naming the unit.

The first spike should anchor entities with the existing source snapshot and
source-map ranges. CRDT operation anchors can be added later through an adapter
once the required durability behavior is proven.

## Relationship to event-graph-walker

`event-graph-walker` remains the durable collaboration substrate. It owns causal
history, text/tree CRDT semantics, sync, and undo.

The stable entity layer should compose with it, not duplicate it.

Not every semantic entity should become a durable CRDT object. Use durable CRDT
identity for document objects whose structure is itself collaboratively edited,
such as blocks or user-created structural nodes.

Treat syntax-derived entities, such as headings or declarations, as extracted and
reconciled unless a product case proves they need durable identity.

## Relationship to the incremental runtime

The stable entity layer stores facts and evidence. It should not own ad-hoc
cache invalidation. Labels, outlines, diagnostics, projections, semantic
summaries, and AI context are derived values and should flow through the
incremental runtime.

The first usable slice should avoid a mutable entity store that later has to be
wrapped reactively. Prefer immutable snapshots and explicit change summaries
until the dependency shape is known.

## Language boundary

The core model is language-agnostic, but entity extraction and edit lowering are
language-owned.

A language adapter should answer:

- which projection nodes count as stable editing entities;
- which source/token anchors define those entities;
- which language-owned keys help preserve identity;
- how a structural intent lowers to source edits;
- how to report identity evidence and ambiguity.

The reference spike should use Markdown headings before MoonBit declarations,
because Markdown has the more mature projection and edit stack in Canopy today.

## Lifecycle model

The stable entity layer needs lifecycle states, but the first implementation
should keep them diagnostic until behavior is proven.

The states describe an entity's relationship to the *current document*:

- live: currently anchored and usable;
- missing: temporarily absent, often due to malformed input;
- ambiguous: multiple plausible matches exist;
- tombstoned: retained for recovery or diagnostics;
- retired: no longer eligible for matching.

`garbage-collectable` is **not** a sixth state. It is a *predicate over retired
entities* — a property of an entity's relationship to its referrers and storage.
That is a different axis from the document-observation states above.

Keeping it a predicate rather than a state keeps garbage collection a policy
layered on the lifecycle rather than a transition baked into the state machine.

### Reference policy for non-live entities

Whether a non-live entity (missing, ambiguous, tombstoned, or retired) may be
referenced is decided by the *kind* of reference, not by the consumer:

- A **resolving reference** asks "what does this entity resolve to in the current
  snapshot?" It is read-time, transient, and non-owning: it is re-evaluated on
  every update and never keeps an entity alive. Resolving references may name any
  non-live entity. A live entity resolves to its current node; a missing or
  tombstoned entity resolves to nothing, with its last live observation available
  for display; an ambiguous entity resolves to its candidate set, which the
  consumer must handle as a set rather than a single node; a retired entity
  resolves to nothing.
- A **pinning reference** asserts "this relation must keep pointing at this entity
  even while it is non-live." It is durable, owning, and extends retention. A
  pinning reference is the only kind that can keep a non-live entity from being
  collected.

By consumer class:

- **Selection, diagnostics, and debug tooling** hold only resolving references.
  They may observe non-live entities — debug tooling may inspect every state,
  including retired — but never pin them, so they never extend retention or block
  garbage collection.
- **Undo** is owned by the event-graph-walker and operates on CRDT history, not on
  stable entities; it is never a reference class for this layer. When undo restores
  deleted content, the entity recovers through the ordinary matching path. A future
  *semantic* undo that named an entity directly would be a pinning reference, and
  would fall under the relation rule below.
- **Edges and relations** do not exist yet (they are gated behind a decision gate).
  When they arrive they are the only pinning class, and an edge to a non-live
  entity is what extends that entity's retention.

### Garbage collection

A retired entity is garbage-collectable when no pinning reference targets it.
Because no pinning references exist today, every retired entity is collectable.
The predicate's form reserves the future case where an edge keeps a retired
entity alive.

The transition *into* retired depends on a retention threshold that is left to a
later decision. This section fixes only the safety precondition for discarding —
the precondition that garbage collection, undo correctness, and bounded retention
all depend on.

> **Markdown heading slice resolved.** A committed delete and a transient
> malformed parse both produce an absent heading, but the production Markdown
> heading side-table now separates them before lifecycle advancement.
>
> PR #767 derives snapshot validity from parser diagnostics plus projection
> `Error` nodes in the source-map memo path: valid deletes advance absence
> counters, while malformed snapshots hold the prior row state.
>
> The [SDEG Invariant & Semantics Review](sdeg-invariant-review.md) holds the
> authoritative, code-grounded transition table, the per-state resolution rules,
> and the gap inventory for future non-Markdown or public-SDEG generalization.

## Phase 0 spike

The next step is a design spike, not a broad package split.

Scope:

1. Choose Markdown headings as the first entity kind.
2. Treat existing projection identity as the entity reference.
3. Use current source-map ranges as anchors.
4. Add diagnostic side tables for status and matching evidence.
5. Test rename, reorder, duplicate headings, delete/restore, malformed input,
   and large paste/format-like edits.
6. Verify that edits still flow through the existing language edit path.

Success means the existing pipeline preserves identity well enough for common
heading edits and produces explainable failures for the cases it cannot handle.

Failure does not immediately justify a new entity core. First try adding better
language hints, identity evidence, and projection-identity realignment. Only
separate entity identity from projection identity after those routes are shown to
be insufficient.

## Decision gates

Create a distinct stable entity core only if the spike demonstrates at least one
of these needs:

- projection identity cannot model the needed lifecycle;
- identity must survive reload or peer synchronization;
- semantic entities need graph relations beyond the projection tree;
- language-independent evidence and diagnostics cannot be expressed as side
  tables;
- durable CRDT anchors must participate directly in matching.

Until then, keep the design internal and side-table based.

## Non-goals for the first slice

- No new general-purpose ECS.
- No parallel rendered view tree.
- No public stable entity API.
- No persistent semantic entity storage in the CRDT layer.
- No full graph store before a single entity kind proves the need.
- No raw byte-range anchors at package boundaries.

## Related guidance

- [Responsibility Map](../architecture/responsibility-map.md)
- [Range/span unit boundaries](../decisions/2026-06-13-range-span-unit-boundaries.md)
- [Identity and reuse mechanisms](../decisions/2026-06-01-identity-and-reuse-mechanisms.md)
- [SDEG NodeId Side Table Sketch](sdeg-nodeid-side-table.md)
- [SDEG Invariant & Semantics Review](sdeg-invariant-review.md)
- [Analysis Query Layer](analysis-query-layer.md)
- [Design Concerns](design-concerns.md)
