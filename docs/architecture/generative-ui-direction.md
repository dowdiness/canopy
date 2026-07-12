# Generative UI direction

## Thesis

Canopy should treat Generative UI as incremental editing of a stateful UI
program, not as repeated generation of disposable HTML or JSX.

The important property is that an AI-generated view remains editable,
state-preserving, incrementally updateable, and safe to reconcile with human
edits. JSX is one projection surface for this idea, not the definition of the
whole system.

The existing architecture is a good fit:

```text
source / semantic UI program
  → incremental parse and projection
  → stable view identity
  → patch adapter
  → UI surface
```

## Why this matters

Whole-view regeneration causes lost input, remounted components, broken focus,
unnecessary work, and conflicts between AI and human edits. Incremental
projection makes the generated result behave more like a shared, editable
artifact.

The differentiator is therefore not that a model can write JSX. It is that a
model can safely edit a structured UI while preserving user state and making
the change inspectable, reversible, and eventually mergeable.

For V1, "mergeable" is limited to sequential or single-writer edits. Canopy
does not yet define how concurrent semantic UI edits map to projection identity,
conflict resolution, or user-visible state. The CRDT source-edit path and the
future semantic-edit path must not be treated as having the same guarantees.

## Direction

### Structured edits instead of whole-view generation

Natural-language requests should eventually lower to semantic UI edits such
as adding a field, changing a layout, or showing a detail panel. The system
should validate, preview, reject, undo, and merge these edits at a structural
boundary.

### Human and AI co-editing

AI changes must preserve user-entered values, focus, selection, and local
customizations wherever the structure permits. Human edits and AI edits should
eventually be represented in the same incremental and collaborative model. The
V1 implementation should first establish these preservation rules for
sequential edits before claiming concurrent co-editing semantics.

### Streaming and interruption

The UI should be useful while generation is incomplete. This requires
well-defined partial states, placeholders, transaction boundaries, cancellation,
and resumption rather than treating incomplete output as a fatal parse error.

### Semantic UI with multiple projections

The long-term abstraction should be a semantic UI model that can project to
JSX/DOM, native UI, canvas, accessibility-oriented views, voice interfaces,
and other surfaces. Renderer adapters must share one patch and identity
contract while remaining free to implement platform-specific behavior.

### Capability-bounded generation

Generated UI must not imply unrestricted authority. Components, actions, data
access, expressions, and side effects should be constrained by explicit
capabilities and schemas. Structural edits should be auditable and, where
needed, require approval before effects occur.

## High-value applications

- Adaptive data-exploration workspaces that add filters, charts, and detail
  views without losing the current query state.
- Forms that reveal and validate fields based on the user's answers.
- Educational surfaces that generate exercises, hints, visualizations, and
  explanations around the learner's current state.
- Collaborative workspaces where people and AI edit the same structured view.
- Temporary debugging interfaces assembled from live program state.

## Risks to measure

- Non-deterministic or surprising model edits.
- State loss during identity changes or reconciliation.
- Accessibility and responsive-layout regressions.
- Unsafe actions hidden behind generated controls.
- Versioning and migration of generated UI structures.
- Latency, token cost, and bundle/runtime overhead.

## Recommended sequence

1. Finish V1 correctness gates: CI, browser validation, and property-based
   coverage for patch ordering, sibling indexes, nested updates, disposal,
   isolation, and failed-apply recovery. See issue #888.
2. Demonstrate one read-only or sandboxed end-to-end use case: an AI-assisted
   data-exploration or adaptive-form surface that preserves user state. Place a
   minimal component, action, and data capability boundary before exposing any
   side effect.
3. Extract the patch, identity, state-preservation, and capability invariants
   from that use case, then define the renderer-neutral conformance suite.
4. Add semantic edits, preview/undo, and auditability. Define concurrent
   semantic-edit and conflict behavior before describing co-editing as a
   supported guarantee.
5. Validate the shared contract with a second materially different adapter,
   then generalize from JSX to multiple projections.

## Non-goals

This direction does not require making JSX a universal UI language, allowing
arbitrary model-generated code, or replacing conventional hand-authored UI.
The initial goal is a safe incremental bridge between structured generation,
human editing, and multiple UI projections.

Related: [JSX Incremental Parser for Generative UI](../plans/2026-07-09-jsx-incremental-parser-generative-ui.md),
[property-based correctness coverage issue #888](https://github.com/dowdiness/canopy/issues/888).
