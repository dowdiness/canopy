# Personal knowledge environment direction

**Status:** near-term primary product direction. This document states the
strategic reorientation and the principles that govern it. It does not describe
implemented behavior.

## Strategic reorientation

Canopy's long-term vision — write, negotiate structure, surface context — is
unchanged. The current implementation remains a projectional editor with CRDT
collaboration. The near-term product direction, however, shifts primary
development effort toward a **human-centered personal knowledge environment**
whose initial wedge is resumable technical project memory for developers and
researchers.

The projectional editor is preserved in maintenance and proving-ground mode. It
is not abandoned: its incremental, collaborative, and multi-representation
capabilities remain available when the product needs them. The
product-development priority, however, is the knowledge environment. The
editor's role will be reconsidered once the knowledge environment has produced
measurable product evidence.

## Initial wedge: resumable technical project memory

Technical work — a codebase, a research thread, a multi-session analysis —
loses continuity every time a person stops and restarts. Today, resumption is
manual: the person rereads, reorients, and reconstructs the state that was
obvious last time. The initial wedge is a tool that captures enough semantic
activity during a work session that the same person can resume from a
checkpoint rather than from cold memory; shared authority and collaborative
resumption remain separate product questions.

The wedge is deliberately narrow:

- **Project-scoped.** One work context at a time (one repository, one research
  thread, one analysis), not system-wide surveillance of everything a person
  does.
- **Integrated with tools already in use.** Capture happens through an existing
  agent runtime during technical work and requires no new always-on background
  process.
- **Resume-first.** The first useful output is "where did I leave off, and
  what was I doing," not a full knowledge graph.

## Core loop: Capture → checkpoint → Resume

```
Capture semantic activity
    → checkpoint curated memory
    → Resume from checkpoint in next session
    → ...
```

Three stages, each with a distinct authority boundary.

**Capture** observes semantic activity during a work session. Semantic means
"what the person was doing at the level of intent and outcome," not raw
keystrokes or screen pixels. Capture is project-scoped, opt-in, and under the
person's control. It observes tool invocations, proposals, file-level changes,
and session transitions — the activity that has project meaning — and records
them with stable identity and provenance.

**Checkpoint** records the goals, decisions, open questions, and next actions
the person wants to encounter again. In the first slice, those anchors are
human-authored or explicitly accepted; the system does not infer decisions
from an agent transcript. A deterministic reducer selects and organizes the
accepted anchors, so the same activity and checkpoint records produce the same
state. Later slices may add semantic or generated candidates, subject to
review gates.

**Resume** reconstructs orientation from the latest checkpoint plus any new
activity since the checkpoint. It is a derived view that renders what the
checkpoint says, supplemented by what has happened since, while leaving the
checkpoint unchanged.

## Semantic activity, not surveillance

Capture is explicitly semantic and project-scoped. The boundary between
semantic activity and surveillance is drawn by what the capture system is
allowed to observe:

- **Captured:** tool invocations with their declared identity, proposals with
  their base revision and outcome, file-level changes attributed to a session,
  session lifecycle transitions (start, fork, compaction, end), and the
  declared identity of the model or agent involved.
- **Not captured in the first slice:** raw keyboard or screen input, system
  prompts, context-file contents, hidden reasoning traces, credentials or API
  keys, arbitrary full tool output, and anything the person has not opted in
  to.

Capture candidates — proposed additions to curated memory — are not themselves
authoritative. A candidate becomes curated memory only after the person, or a
deterministic policy the person chose, accepts it. The no-duplicate-entry
principle applies at ingestion: replaying an activity event with the same
stable identity must not create another ledger entry or another accepted
memory.

## Authority and provenance

Three distinct authorities coexist, and the boundaries between them are
enforced, not advisory.

1. **The agent runtime owns the conversation session.** Prompt history, model
   responses, tool invocations, and session persistence live in the agent
   runtime's session store. The agent runtime is authoritative for what the
   model saw and said.
2. **The knowledge environment owns imported activity and curated memory.**
   Once activity is imported — with stable identity, idempotent replay, and
   provenance — it belongs to the knowledge environment's store. Curated
   memory derived from that activity also belongs here.
3. **The person owns decisions about what to capture, what to keep, and what
   to delete.** Capture is opt-in. Curated memory is inspectable and
   correctable. Deletion is explicit and honored.

Provenance travels with every record: its source session, source event, actor,
ancestry, and relevant document revision when one exists. Records that lack
the provenance required for their event kind are rejected at the boundary.

## Local ownership and privacy

Canopy-owned activity data, curated memory, and checkpoints live on the
person's devices. There is no required external service and the capture path
must not transmit another copy of agent-session data. Any later synchronization
must preserve local ownership and pass its own collaboration and deletion
review.

The first slice makes no provider call. The agent runtime may already use an
external model under its own policy, but capture adds no provider disclosure of
its own. A later provider-assisted feature requires a separate data-egress and
product-value gate.

## Deterministic fixed baseline before semantic or generated behavior

Every semantic or generated behavior must pass through a deterministic fixed
baseline before it can be trusted as product.

- The activity reducer is deterministic. The same input events produce the
  same checkpoint, every time, with no provider call.
- The Resume view is deterministic over a fixed checkpoint plus a fixed event
  log. No generated summarization in the first slice.
- A fixed, inspectable transcript representing a work session is the first
  acceptance artifact. The Resume View renders that transcript faithfully
  before any semantic capture, provider call, or generated summary is
  introduced.

Semantic capture candidates and generated summaries are introduced only after
the fixed baseline is proven correct, inspected, and accepted.

## Generated UI: disposable projection, never authority

Generative or adaptive UI — including generated Resume views — is a
disposable projection over curated memory. It is never itself knowledge
authority. The rules carried forward from the existing generative UI
direction:

- Generated output cannot mutate curated memory or activity records directly.
- Any mutation of authoritative state flows through the proposal and
  commit boundary.
- A failed or rejected generated view must not advance committed state.
- The person can always revert to the fixed deterministic view.

## Review gates and go-no-go conditions

The shift to PKE as near-term primary direction is conditional. The following
gates must pass before further product investment is justified.

### First-slice gate (exit of the first plan)

- A fixed transcript of representative activity events exists and is
  inspectable.
- A Resume View renders the fixed transcript as a chronological activity list
  plus a checkpoint summary.
- The rendering is deterministic: the same transcript produces the same view
  every time, with no provider call.
- A person unfamiliar with the transcript can read the Resume View and
  correctly answer "what was this session doing, and where did it leave off"
  within a predeclared bound, and can trace each answer to source activity.

### Product-evidence gate (before expanding beyond the first slice)

- At least one external developer or researcher uses the Resume View as part
  of their actual work across multiple sessions.
- Resumption time — measured from "opened the tool" to "oriented on current
  state" — is measurably shorter than the person's unaided baseline.
- The person can name at least one specific decision or claim surfaced by the
  tool that they would otherwise have had to reconstruct manually.

If the product-evidence gate does not pass, the direction is reconsidered.
Projectional-editor development may return to primary priority, or a narrower
knowledge-environment hypothesis may be tested; the evidence decides rather
than this document predetermining the outcome.

## Relationship to existing direction documents

The PKE direction does not replace the product vision. It changes the current
priority and applies existing principles to a narrower wedge:

- The [product vision](product-vision.md) remains the long-term destination.
- The first slice treats an external agent runtime as a read-only capture
  source. It does not require Canopy to own an agent loop or grant an agent
  mutation authority.
- The [human-centered product principles](human-centered-product-principles.md)
  continue to govern all product behavior. The PKE direction is a specific
  application of those principles to a new initial wedge.

## Related documentation

- [Product Vision](product-vision.md) — the long-term destination.
- [Human-centered product principles](human-centered-product-principles.md) —
  canonical behavior invariants.
- [Pi session activity → Resume view prototype](../plans/2026-07-16-pi-activity-capture-resume-prototype.md)
  — first concrete slice.
