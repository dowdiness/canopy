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
  → session-scoped identity preservation
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
the change inspectable and reversible. Semantic merging is a later capability,
not a V1 guarantee.

For V1, supported edits are limited to sequential or single-writer edits.
Canopy does not yet define how concurrent semantic UI edits map to projection
identity, conflict resolution, or user-visible state. The CRDT source-edit path
and the future semantic-edit path must not be treated as having the same
guarantees.

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

Expressiveness and authority are separate axes. Capability boundaries should
constrain ambient authority and effects without treating the first prototype's
component allowlist as the permanent ceiling on composition.

Generated UI must not imply unrestricted authority. Components, actions, data
access, expressions, and side effects should be constrained by explicit
capabilities and schemas. The first prototype should use an allowlisted,
declarative component model with no model-controlled network access, raw HTML,
navigation, or arbitrary code/expression execution. Structural edits should be
auditable and, where needed, require approval before effects occur.

### LLM input boundary

An LLM is an untrusted, asynchronous candidate generator, not the source of
truth for UI state. Its output must never mutate the committed UI directly.
The input path is:

```text
LLM/provider
  → untrusted candidate
  → syntax and schema validation
  → capability validation
  → base-revision check
  → candidate projection and internal dry-run
  → committed UI update
```

The provider transport, request lifecycle, UI-program validation, and renderer
must remain separate responsibilities. Provider-specific code may fetch and
decode model responses, but it must not own UI identity, DOM state, or commit
policy. The request lifecycle owns request identity, observed revision,
cancellation, chunk sequencing and assembly, finalization, stale-completion
rejection, terminal-state idempotency, and typed failure classification.
The UI input adapter owns the constrained UI-program schema and candidate
validation. The renderer only applies validated candidates through the session
commit boundary.

The first implementation should use a replayable fixed-chunk source before
connecting a live model. This makes incomplete output, duplicate chunks,
revision conflicts, cancellation, late responses, and deterministic replay
testable without depending on model behavior.

Deterministic replay establishes lifecycle and projection correctness; it does
not establish product value. Product experiments must compare generated outcomes
with an appropriate hand-authored baseline.

The output representation should evolve in stages:

1. constrained JSX-like source;
2. semantic edits such as adding a table or filter;
3. a renderer-neutral semantic UI program, only after a real use case and a
   second adapter establish the shared invariants.

Every candidate is evaluated against an explicit base revision. Cancelled or
stale candidates are rejected, and only a validated candidate can advance the
committed revision. A candidate is not committed until DOM application succeeds
and the session state, registry, mounted IDs, and revision remain consistent.
If application fails partway through, the existing session recovery and
dirty-state contract determines whether the previous state is restored or the
affected UI is rebuilt; the candidate must not be reported as committed. This
boundary is more important than any particular model provider or transport API.

The input path has two distinct kinds of preview. An internal dry-run or fake
DOM application is required before committing a candidate. A user-visible
approval preview is a separate product feature and is deferred beyond the
first vertical slice.

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
2. Demonstrate one read-only end-to-end use case: an AI-assisted JSON/CSV data
   exploration surface that incrementally produces a table, filters, and a
   detail/summary panel while preserving user state. Keep generated actions
   side-effect-free and place the minimal component, action, and data
   capability boundary before expanding the scope.
3. Extract provisional patch, identity, state-preservation, capability, and
   candidate-commit invariants from that use case. Require internal dry-run
   validation; defer user-visible approval preview.
4. Validate those provisional invariants with a second materially different
   adapter, then freeze the renderer-neutral conformance suite and contract.
5. Add semantic edits, preview/undo, and auditability. Define concurrent
   semantic-edit and conflict behavior before describing co-editing as a
   supported guarantee, then generalize from JSX to multiple projections.

## First vertical-slice acceptance criteria

The first Generative UI prototype is successful only if it demonstrates all of
the following:

- Existing input, filter, and selection state survives incremental generation
  whenever the structure permits.
- Incomplete or invalid generated input does not destroy the last valid UI.
- Reapplying the same update produces the same modeled UI result.
- A failed patch application leaves the candidate uncommitted and follows the
  session recovery/dirty-state contract without falsely advancing revision.
- The generated surface uses only allowlisted declarative components: no
  model-controlled network access, persistence, navigation, raw HTML, or
  arbitrary code/expression execution is reachable through generated controls.
- Cancelling generation invalidates its generation revision; late chunks from
  that revision are rejected and cannot overwrite newer committed UI.
- Resumption starts only from an explicitly selected committed revision.
- Chunk sequencing, duplicate handling, finalization, and terminal-state
  idempotency are deterministic and owned by the request lifecycle.
- Internal dry-run validation succeeds before any candidate commit; a
  user-visible approval preview is not required for this first slice.
- The prototype records enough patch/revision information to inspect what the
  model changed and to measure update latency.

The prototype should be treated as a sequential or single-writer experiment.
It does not claim concurrent semantic merging, cross-session identity, or a
renderer-neutral contract.

## Explicitly deferred

- Concurrent semantic-edit conflict resolution.
- Persistent or cross-session view identity.
- General-purpose renderer-neutral APIs.
- Additional language projections beyond the first validated use case.
- Typed pure-expression and local state-transition models, pending a concrete
  use case and validation by a materially different adapter.
- Commands-as-data, effect approval, and undo/audit semantics for generated
  actions.
- Formal proof of the JavaScript/DOM boundary; prove pure reconciliation
  invariants only after they are isolated from the adapter.

## Non-goals

This direction does not require making JSX a universal UI language, allowing
arbitrary model-generated code, or replacing conventional hand-authored UI.
The initial goal is a safe incremental bridge between structured generation,
human editing, and multiple UI projections.

## Human outcome gate

Generated UI changes are meaningful only when they meet the product-level
gates defined in [Human-centered product principles](human-centered-product-principles.md):

- **Legible and governable.** Every generated change can be read and
  understood. Consequential changes require explicit acceptance or a narrow,
  revocable policy the person chose.
- **Orientation-preserving.** Generated changes do not steal attention,
  fragment the user's place in the document, or create cognitively unstable
  transitions.
- **Accessible equivalence.** Every generated control has a keyboard and
  screen-reader equivalent path. Accessibility is not a fallback.
- **Rationale and reversal.** Each generated change carries a reason the
  person can read, and can be undone without losing prior state.
- **Net value over fixed alternatives.** The generated outcome must produce
  a measurably better result on a named task than a fixed, rules-based
  alternative. Novelty alone is not justification.

These gates are product requirements, not technical implementation details.
They sit above the commit and candidate contracts defined in this document.

Related: [JSX Incremental Parser for Generative UI](../plans/2026-07-09-jsx-incremental-parser-generative-ui.md)
and [property-based correctness coverage issue #888](https://github.com/dowdiness/canopy/issues/888).
