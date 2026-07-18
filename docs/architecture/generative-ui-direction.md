# Generative UI direction

## Purpose and authority

Canopy's top-level Generative UI question is not tied to one user job, output
representation, or generation system:

> For which people, intents, contexts, and lifecycles does a generated
> interface create useful capability, and what generation authority is
> necessary to create that value?

This document is the source of truth for durable Generative UI principles,
taxonomy, and architectural claim boundaries.

Research and implementation plans own concrete jobs, representations, execution
mechanisms, staged sequences, and acceptance criteria. Evidence from one bounded
plan may revise this direction, but it must not silently become a general
architectural conclusion.

## Candidate spectrum

Opportunity discovery evaluates six representation modes as parallel candidates:

| Mode | Architectural definition | Native strength |
| --- | --- | --- |
| Static | Generated content or choices within a host-owned interaction | Predictability and host control |
| Declarative | Generated structure composed within declared capabilities | Inspectability and structural validation |
| Open-Ended | Generated presentation outside a fixed structural catalog | Expressive presentation |
| Dynamic | Generated executable behavior | Novel state, computation, and integration |
| Projectional | Generated semantic operations over an identity-bearing artifact | Editing, replay, provenance, and collaboration |
| Hybrid | Explicitly bounded combinations of other modes | Authority matched to each part of an interface |

These modes are not a maturity ladder and do not form a single strength axis.
Open-Ended presentation, Dynamic execution, and Projectional identity are
incomparable capabilities. A job may require one mode, several incomparable
minimum modes, or a Hybrid.

Lifecycle is a separate axis. Every representation mode may be ephemeral,
session-scoped, personally persistent, shared, or productized. Persistence
increases identity, migration, provenance, replay, ownership, and maintenance
obligations; it is not intrinsic to Projectional representation.

Expressiveness, execution authority, persistence, and inspectability are also
separate axes. Each experiment must identify the minimum sufficient capability
and authority bundle instead of assuming that a more expressive mode is better.

## Durable principles

### Discover value before choosing architecture

A Generative UI proposal must name the person, job, context, value source,
strongest realistic alternative, expected lifecycle, and required authority.
Generation is justified only by a useful outcome that the strongest alternative
cannot provide as effectively. Novelty and technical feasibility are not product
value.

### Keep generated output subordinate to human authority

People must be able to understand what the system proposes, what it may affect,
and which decisions remain theirs. Consequential changes require explicit
acceptance or a narrow, revocable policy chosen by the person. Generated output
must not acquire authority merely because it was successfully produced.

### Preserve continuity when continuity creates value

When a job depends on ongoing interaction or editing, generated changes should
preserve the person's values, focus, selection, orientation, and local
customizations wherever the structure permits. Whole replacement remains a
valid mode where continuity is unnecessary; it is not the default for an
identity-bearing artifact.

### Separate proposals from committed state

Generation produces untrusted proposals, not authoritative state. A proposal
must cross explicit validation and commitment boundaries before it can change a
canonical artifact. Rejection or failed application must not be reported as a
successful commit.

Generation, validation, state ownership, and commitment policy remain distinct
responsibilities. No generation mechanism owns artifact identity or decides by
itself that an output is accepted, useful, or committed.

### Make change inspectable and reversible

Generated changes should retain enough identity, rationale, and provenance for a
person to inspect what changed and why. Reversal must preserve prior work rather
than reconstructing an approximation of it. Persistence and collaboration raise
these obligations but do not define the representation mode.

### Treat incompleteness and interruption as normal states

Generation may be partial, cancelled, superseded, or resumed. Those states need
explicit semantics so incomplete work does not corrupt the last accepted
artifact or overwrite newer intent.

### Scope identity and collaboration claims precisely

Sequential editing, concurrent editing, cross-session identity, and shared
collaboration are different guarantees. Evidence for one does not establish the
others. Canopy must not claim semantic co-editing until conflict, identity, and
recovery behavior are defined for that scope.

### Separate technical correctness from product evidence

Deterministic validation can establish lifecycle, state, and projection
invariants. It cannot establish that a generated interface is useful.

Product claims require comparison with the strongest realistic alternative on a
named job. Architecture claims require evidence across materially different
contexts.

## Current architecture hypothesis

Canopy's current hypothesis is that incremental editing of an identity-bearing
semantic artifact can create value when people need generated changes to remain
editable, state-preserving, inspectable, and reversible. This hypothesis aligns
with Canopy's projectional architecture, but it is neither the definition of
Generative UI nor the preferred answer before opportunity discovery.

Where semantic editing is justified, natural-language intent should lower to
structured operations over a canonical model rather than bypassing that model.
Multiple projections may share semantic intent and identity without requiring a
single universal representation or premature renderer-neutral contract.

The hypothesis remains bounded. A successful Projectional experiment does not
exclude Static, Declarative, Open-Ended, Dynamic, or Hybrid approaches. A failed
experiment rejects only its frozen person, job, representation, comparator, and
evidence contract.

## Human outcome gate

Generated UI changes are meaningful only when they meet the product-level gates
defined in [Human-centered product principles](human-centered-product-principles.md):

- **Legibility and governance:** people can understand generated changes and
  retain authority over consequential effects.
- **Orientation:** changes preserve the person's place and attention.
- **Accessible equivalence:** generated capability has an equivalent accessible
  path.
- **Rationale and reversal:** changes carry understandable provenance and can be
  undone without losing prior work.
- **Net value:** the outcome improves a named job over its strongest realistic
  alternative.

These gates govern every representation mode. No architecture, model, or
implementation path is exempt.

## Non-goals

This direction does not prescribe one universal UI language, require generated
execution, replace conventional hand-authored interfaces, or rank representation
modes before evidence exists. It also does not authorize production integration,
participant recruitment, or a public contract.

## Detailed work

Concrete research and execution details live in their bounded documents:

- [Generative UI opportunity discovery](../plans/2026-07-17-generative-ui-opportunity-discovery-design.md)
  defines sampling, evidence, comparison, and stop rules.
- [Generative UI input vertical slice](../plans/2026-07-12-generative-ui-input-vertical-slice.md)
  records the completed bounded implementation sequence and its technical
  acceptance criteria.
- [Structured-data bounded-provider experiment](../plans/2026-07-15-generative-ui-live-provider-experiment-design.md)
  preserves one deferred confirmatory protocol without generalizing its job or
  representation.
- [Incremental Generative UI semantic-core validation](../plans/2026-07-16-incremental-generative-ui-semantic-core-validation.md)
  defines the evidence required for the current semantic architecture
  hypothesis.
