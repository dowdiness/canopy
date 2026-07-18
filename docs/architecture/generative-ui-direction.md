# Generative UI direction

## Research purpose

Canopy's top-level Generative UI question is not tied to one data format, user
job, output representation, or provider:

> For which people, intents, contexts, and lifecycles does a generated
> interface create useful capability, and what generation authority is
> necessary to create that value?

The research program must discover those conditions before choosing a preferred
representation. A successful experiment in one job does not establish a global
architecture, and a failed experiment does not reject Generative UI outside
that experiment's frozen scope.

## Current architecture hypothesis

Canopy's current hypothesis is that treating generated UI as incremental editing
of a stateful UI program can make the result editable, state-preserving,
incrementally updateable, and safe to reconcile with human edits. This is one
candidate answer to the research question, not the definition of Generative UI
or a conclusion that disposable documents and executable generated interfaces
are unhelpful.

JSX is one projection surface for this hypothesis, not the definition of the
whole system. The existing architecture is a good fit:

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

## Candidate spectrum

Opportunity discovery evaluates these modes as parallel candidates:

| Mode | Generated result | Native strength |
| --- | --- | --- |
| Static | Content, parameters, or tool choices inside a host-authored UI | Predictability, speed, and host control |
| Declarative | A component tree, bindings, and allowlisted actions | Flexible composition with structural validation |
| Open-Ended | A document such as HTML and CSS | Visual freedom and portable presentation |
| Dynamic | Executable UI code | Novel stateful behavior, computation, and integration |
| Projectional | A semantic UI artifact and structured edits | Direct editing, identity, replay, and collaboration |
| Hybrid | Explicitly bounded combinations of the other modes | Authority matched to each part of the interface |

These modes are not a maturity ladder and do not form a single strength axis.
Declarative generation is not preferred because its first implementation
already exists, Dynamic generation is not a last resort, and Projectional
generation is not the winner merely because it matches Canopy's architecture.
Open-Ended presentation, Dynamic execution, and Projectional identity are
incomparable capabilities. A job may require one mode, several incomparable
minimum modes, or a Hybrid.

Lifecycle is a separate axis. Static, Declarative, Open-Ended, Dynamic,
Projectional, and Hybrid results may each be ephemeral, session-scoped,
personally persistent, shared, or productized. Persistence increases identity,
migration, provenance, replay, ownership, and maintenance obligations; it is
not intrinsic to Projectional representation.

Expressiveness, execution authority, persistence, and inspectability are also
separate axes. Dynamic generation remains eligible where custom behavior,
local state, computation, or integration produces value unavailable to a fixed
component vocabulary. Its sandbox, dependency, interruption, lifecycle,
latency, and maintenance costs are evidence to measure against that value, not
reasons to exclude it before discovery.

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

Generated UI must not imply unrestricted authority. Every mode needs a boundary
appropriate to what it can execute: schemas and allowlists for declarative
programs; document isolation for open-ended output; and sandboxing, budgets,
interruption, dependency policy, re-entry control, and disposal for Dynamic
code. Projectional artifacts additionally need explicit edit, identity, and
commit authority.

The first engineering prototype uses an allowlisted declarative component model
with no model-controlled network access, raw HTML, navigation, or arbitrary
code/expression execution. That is a contract for one validated slice, not a
research conclusion or a permanent ceiling on later experiments.

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

## Opportunity hypotheses

Potential value is broader than one data-exploration task. Discovery should
sample materially different jobs rather than treat any item below as an
established consumer:

- Adaptive data-exploration workspaces that add filters, charts, and detail
  views without losing the current query state.
- Forms and workflows that reveal, validate, and act on information according
  to the person's changing intent.
- Educational surfaces that generate exercises, hints, simulations,
  visualizations, and explanations around the learner's current state.
- Monitoring and debugging interfaces assembled from live system state.
- Personal or domain-specific applications whose useful interaction was not
  known when the host was authored.
- Creative authoring surfaces in which the generated interface is itself
  inspected, edited, and reused.
- Collaborative workspaces where people and AI evolve a shared artifact.

The value source may be information selection, composition, visual adaptation,
novel behavior, computation, integration, editability, persistence, reuse, or
collaboration. An experiment must name which source it tests instead of using
"Generative UI" as an undifferentiated treatment.

## Risks to measure

- Non-deterministic or surprising model edits.
- State loss during identity changes or reconciliation.
- Accessibility and responsive-layout regressions.
- Unsafe actions hidden behind generated controls.
- Versioning and migration of generated UI structures.
- Latency, token cost, and bundle/runtime overhead.

## Current bounded implementation sequence

The following sequence validates Canopy's incremental, capability-bounded
architecture hypothesis. It is not the ordering for opportunity discovery and
does not make its JSON/CSV job, Declarative representation, or projectional
direction the default for later product experiments.

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

This direction does not require making JSX a universal UI language, replacing
conventional hand-authored UI, or treating unrestricted execution as a
prerequisite for every experiment. It also does not exclude open-ended
documents, Dynamic generated code, or hybrids from opportunity discovery.

The current engineering goal is narrower: establish a safe incremental bridge
between structured generation, human editing, and multiple UI projections.
Other modes must earn their own value and safety claims through evidence suited
to what they generate and execute.

## Human outcome gate

Generated UI changes are meaningful only when they meet the product-level
gates defined in [Human-centered product principles](human-centered-product-principles.md).
This document's generative-UI-specific interpretation:

- **Candidate rationale/provenance tied to the exact candidate/revision.**
  Every generated change carries a reason the person can read, linked to the
  specific candidate and base revision that produced it.
- **Preview/rejection cannot mutate committed state.** Internal dry-run must
  validate a candidate before it reaches the session commit boundary; rejected
  candidates change no committed state.
- **Apply/recovery preserves focus, selection, and orientation.** Generated
  changes preserve user-entered values, focus, selection, and local
  customizations whenever the structure permits.
- **Generated outcomes are compared with the strongest realistic alternative.**
  The comparator may be a fixed UI, rules-based system, hand-authored
  application, manual coding, conversational answer, or the workflow without
  an interface. The generated outcome must create measurably better value on a
  named task; novelty alone is not justification.

These gates are product requirements, not technical implementation details.
They sit above the commit and candidate contracts defined in this document.
A private semantic-core experiment may falsify proposed invariants, but it does
not replace this sequence, authorize product integration, or freeze a public
renderer-neutral contract.

Related: [JSX Incremental Parser for Generative UI](../plans/2026-07-09-jsx-incremental-parser-generative-ui.md),
[property-based correctness coverage issue #888](https://github.com/dowdiness/canopy/issues/888),
and the [Incremental Generative UI document engine](../design/incremental-generative-ui-document-engine.md).
