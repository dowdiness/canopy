# Personal knowledge environment direction

**Status:** near-term primary product direction. This document states strategy
and product invariants; it does not describe implemented behavior.

## Decision

Canopy's long-term vision — write, negotiate structure, surface context — is
unchanged. The current implementation remains a projectional editor with CRDT
collaboration. Near-term development shifts to a **human-centered personal
knowledge environment** in which a person's past activity participates in
present thinking.

The projectional editor remains in maintenance and proving-ground mode. Its
incremental, collaborative, and multi-representation capabilities stay
available when product evidence calls for them.

## The experience

A person's past work — conversations, tool actions, corrections, decisions,
failures, and outcomes — should be available for reflection, daily work
improvement, and thinking, without requiring duplicate manual capture. The
person moves continuously across three scales:

| Scale | What it is |
|---|---|
| **Trace** | The exact conversation, tool invocation, file edit, or source artifact. |
| **Shape** | Flows, turning points, repetition, open threads, and connections across activity. |
| **Meaning** | What the person accepts, corrects, connects, or carries forward into current thought. |

The person discovers structure at Shape, moves to exact source at Trace, and
reconnects it to current thinking at Meaning. What this experience must not
become is defined once, in [Anti-goals](#anti-goals).

## Source strategy: agent history first

Agent coding histories are the first source because they contain a high volume
of intent, alternatives considered, corrections, concrete actions, tool
evidence, failures, and outcomes — all already produced in the course of
everyday work. The person should not be asked to capture what the tool already
recorded.

Later sources (notes, documents, bookmarks) may join when the end-to-end loop
is proven, but the first vertical slice uses agent history only.

## Role of the WorkBench

The synchronized Timeline / Conversation / Evidence WorkBench remains useful
for source inspection. Source-bounded chat—the workbench as the primary
interaction form—failed in direct use. The workbench is not the product.

## Independent chat prototype

An independent DeepSeek chat prototype is the current hypothesis. Ordinary
chat defaults to no history. Selected history and the current recorded path
attach only as explicit per-turn choices with an exact outbound preview and
per-turn context snapshots. Provider and model are fixed to DeepSeek
`deepseek-v4-flash` through a same-origin local relay. Authority is limited
to explicitly sent text and explicitly attached normalized history; import
and read authority remain separate from model-egress authority. Warnings do
not censor explicit source text. No automatic workflow is included; any future
automatic workflow must obey `automaticOutputAllowed` and sensitive gates. No
persistence, retrieval,
suggested prompts, automatic scanning, or multi-session authorization is
provided.

## Authority and provenance

Every source-bearing or interpretive item carries source references and
explicit epistemic metadata. The system keeps origin, derivation, and review as
independent dimensions; every item carries a value on each dimension, and the
classes below are named by their distinctive value:

| Class | Dimension | What it means |
|---|---|---|
| Recorded human content | Origin | What the person explicitly wrote or sent. |
| Human-accepted source commitment | Origin | A goal, decision, or checkpoint whose acceptance is itself recorded in the source history; distinct from later review in Canopy. |
| Observed tool output | Origin | Output recorded from a named tool action. The observation does not establish that the output is deterministic or true. |
| Assistant claim | Origin | Text an assistant model produced inside the recorded history. Recording alone does not verify its content. |
| Person-authored content | Origin | Content the person authors inside Canopy — corrections, connections, carried-forward notes — distinct from content recorded in the source history. |
| Canopy system output | Origin | An item Canopy derives rather than imports or receives through direct person authorship; always paired with an explicit derivation. |
| Directly recorded | Derivation | Content preserved from source history or authored directly in Canopy without a system-generated interpretation; origin distinguishes those cases. |
| Deterministic derivation | Derivation | An item or relation produced by a named, versioned rule over source data. |
| Model-inferred suggestion | Derivation | A hypothesis Canopy generates over the history; its model derivation remains visible even after review. |

Review state is a separate dimension: unreviewed, accepted, corrected, or
dismissed. Corroborating or contradicting evidence may later be linked to a
claim, but it never changes the claim's origin. Acceptance never erases origin
or derivation metadata. Every derived or suggested item retains its sources and
derivation.

## Local ownership

The default path keeps authoritative activity data on the person's devices and
adds no provider call or second transmission of agent session data. Any later
provider use, synchronization, persistence beyond the current session, or
automatic scanning requires a separate data-egress, collaboration, deletion,
and product-value review. The person retains a local authoritative copy even
when a separately authorized action transmits the minimum data it needs.

## Anti-goals

The following patterns are rejected regardless of technical merit:

- **Duplicate capture** — asking the person to record what the tool already
  produced.
- **Static report delivery** — generating a finished briefing without access to
  exact sources or direct manipulation.
- **Automatic advice** — treating a generated recommendation as the product
  instead of letting the person inspect its basis and decide what it means.
- **Source-less claims** — presenting any derived or inferred statement without
  immediate access to its provenance.
- **Questionnaire-driven product discovery** — treating evaluation forms or
  rating prompts as a substitute for a coherent experience and direct use.
- **Surveillance posture** — scanning, persisting, or transmitting activity
  without explicit consent or a revocable policy and data minimization.
- **Passive activity furniture** — a log viewer, productivity dashboard, task
  manager, or generic AI summary that displays activity without supporting
  movement across Trace, Shape, and Meaning.

## Retained constraints from prior evidence

These constraints came out of earlier prototypes and reviews and remain binding
on this direction:

- **Agent-history ingestion exclusions.** Automatic or passive ingestion omits
  raw keyboard, screen, clipboard, and microphone data; system prompts and
  context-file contents; hidden reasoning; and credential material. Explicit
  person-initiated posts or file selections are separate actions governed by
  consent and data minimization.
- **Semantic-generation scope.** The prior semantic study grants no general
  authorization for generation over history. Any later approach requires a
  separate plan, explicit authorization, and reliability evidence from
  representative history.
- **Provider-authorization scope.** Permission is limited to the named study or
  action for which it was granted. Study-specific authorization establishes no
  general provider permission.

## Fixed baseline before generation

The first baseline is a deterministic, source-backed view over selected history.
The same inputs must produce the same view without a provider call. Generative
or adaptive views remain disposable projections: they cannot mutate
authoritative records, rejected output changes no committed state, and the
fixed view stays available.

## High-level direction

The near-term path is one end-to-end vertical slice. Selected agent history
surfaces structure, and the person can move from that structure to exact source
and back without losing context. The person can then correct, dismiss, connect,
or carry something forward into current thought or work.

The final product form remains open until the slice is exercised. If direct
use of the slice fails to show that past activity improves present thinking,
the direction itself is reconsidered; the evidence may justify a narrower
hypothesis or renewed projectional-editor investment.

The canonical
[human-centered product principles](human-centered-product-principles.md)
supply the governing rules for consent, pacing, accessibility, and reversal.

## Related documentation

The [product vision](product-vision.md) remains the long-term destination, and
[human-centered product principles](human-centered-product-principles.md) govern
this direction. The current execution plan is
[Agent history as thinking environment](../plans/2026-07-18-agent-history-thinking-environment.md).
The earlier Resume prototype retains its technical and source-inspection
evidence:
[Pi session activity → Resume view prototype](../plans/2026-07-16-pi-activity-capture-resume-prototype.md).
The direct long-context semantic briefing study failed because cardinality
and content complexity defeated byte-only chunking; no Cloudflare or study
runtime remains in this PR.
