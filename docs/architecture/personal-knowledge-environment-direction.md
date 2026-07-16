# Personal knowledge environment direction

**Status:** near-term primary product direction. This document states strategy
and product invariants; it does not describe implemented behavior.

## Decision

Canopy's long-term vision — write, negotiate structure, surface context — is
unchanged. The current implementation remains a projectional editor with CRDT
collaboration. Near-term development shifts to a **human-centered personal
knowledge environment**, beginning with resumable technical project memory for
developers and researchers.

The projectional editor remains in maintenance and proving-ground mode. Its
incremental, collaborative, and multi-representation capabilities stay
available when product evidence calls for them.

## Initial wedge

Technical work loses continuity across interruptions. The first product should
help a person resume one explicit project without rereading an entire history.
It is deliberately:

- **Project-scoped:** one selected work context, never system-wide surveillance.
- **Integrated:** it captures semantic events from tools already in use.
- **Resume-first:** it restores orientation before attempting a knowledge graph.

## Capture → checkpoint → Resume

```text
Capture semantic activity
    → checkpoint accepted anchors
    → Resume in the next session
```

| Stage | Role | Authority |
|---|---|---|
| Capture | Record intent, outcomes, file changes, and session transitions with stable identity and provenance. | Imported activity remains evidence, not curated knowledge. |
| Checkpoint | Preserve goals, decisions, open questions, and next actions. | Anchors are human-authored or explicitly accepted; agent prose cannot promote itself. |
| Resume | Combine the latest checkpoint with subsequent activity. | The view is derived and cannot rewrite its sources. |

Replay of the same stable activity identity is a no-op.

## Capture boundary

| Included | Excluded from the first slice |
|---|---|
| Tool invocations and outcomes | Raw keyboard, screen, clipboard, or microphone capture |
| Revision-bound proposals | System prompts and context-file contents |
| File changes attributed to the session | Hidden reasoning and credentials |
| Session lifecycle and declared agent identity | Arbitrary full tool output or anything not opted in |

A capture candidate becomes curated memory only after the person, or a
revocable deterministic policy they chose, accepts it. The canonical
[human-centered product principles](human-centered-product-principles.md)
supply the governing rules for consent, pacing, accessibility, and reversal.

## Authority and provenance

| Owner | Owns |
|---|---|
| Agent runtime | Conversation history, model responses, tool invocations, and session persistence |
| Knowledge environment | Bounded imported activity and accepted curated memory |
| Person | What to capture, accept, correct, retain, and delete |

Provenance accompanies every activity and memory record so Resume claims can
be traced to their source.

## Local ownership

Canopy-owned activity, checkpoints, and curated memory stay on the person's
devices. The capture path adds no provider call or second transmission of agent
session data. Any later provider use or synchronization requires a separate
data-egress, collaboration, deletion, and product-value review.

## Fixed baseline before generation

The first acceptance artifact is a fixed, inspectable transcript rendered as
chronology and a deterministic Resume view. The same inputs must produce the
same checkpoint and view without a provider call.

Semantic candidates and generated summaries remain out of scope until this
baseline is correct, inspected, and accepted. Generative or adaptive views are
disposable projections: they cannot mutate authoritative records, rejected
output changes no committed state, and the fixed view remains available.

## Gates

| Gate | Pass condition |
|---|---|
| First slice | An unfamiliar evaluator identifies the session goal, verified outcome, unresolved question or next step, and source evidence within a predeclared bound. Rendering is deterministic. |
| Product evidence | An external developer or researcher uses Resume during actual work across multiple sessions; time from opening the tool to orientation improves over their unaided baseline; at least one useful surfaced claim remains traceable to its source. |

If the product-evidence gate fails, the direction is reconsidered. Evidence may
justify a narrower hypothesis or renewed projectional-editor investment.

## Related documentation

The [product vision](product-vision.md) remains the long-term destination, and
[human-centered product principles](human-centered-product-principles.md) govern
this direction. The first implementation is the
[Pi session activity → Resume view prototype](../plans/2026-07-16-pi-activity-capture-resume-prototype.md).
