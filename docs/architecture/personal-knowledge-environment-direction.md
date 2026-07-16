# Personal knowledge environment direction

**Status:** near-term primary product direction. This document states the
strategic reorientation and governing principles; it does not describe
implemented behavior.

## Strategic reorientation

Canopy's long-term vision — write, negotiate structure, surface context — is
unchanged. The current implementation remains a projectional editor with CRDT
collaboration. Near-term primary development effort shifts to a
**human-centered personal knowledge environment** whose initial wedge is
resumable technical project memory for developers and researchers.

The projectional editor is preserved in maintenance and proving-ground mode.
Its incremental, collaborative, and multi-representation capabilities remain
available. The editor's role will be reconsidered once the knowledge
environment has produced measurable product evidence.

## Initial wedge: resumable technical project memory

Technical work loses continuity every time a person stops and restarts.
Resumption is manual: the person rereads, reorients, and reconstructs the
state that was obvious last time. The initial wedge captures enough semantic
activity during a work session that the same person can resume from a
checkpoint rather than cold memory.

Deliberately narrow:

- **Project-scoped.** Capture is limited to one explicit work context at a time.
- **Integrated with tools already in use.** Capture happens through an existing
  agent runtime; no new always-on background process.
- **Resume-first.** The first useful output is "where did I leave off," not a
  full knowledge graph.

## Core loop: Capture → checkpoint → Resume

```
Capture semantic activity
    → checkpoint curated memory
    → Resume from checkpoint in next session
    → ...
```

**Capture** observes semantic activity — what the person was doing at the
level of intent and outcome, not raw keystrokes. Project-scoped, opt-in.
Observes tool invocations, proposals, file-level changes, and session
transitions with stable identity and provenance.

**Checkpoint** records goals, decisions, open questions, and next actions the
person wants to encounter again. Anchors are human-authored or explicitly
accepted; the system does not infer decisions from an agent transcript. A
deterministic reducer organizes accepted anchors so the same inputs produce
the same state.

**Resume** reconstructs orientation from the latest checkpoint plus new
activity since. A derived view over the checkpoint, supplemented by
subsequent activity, leaving the checkpoint unchanged.

## Semantic activity, not surveillance

The boundary is what capture is allowed to observe:

| Captured | Not captured in first slice |
|---|---|
| Tool invocations with declared identity | Raw keyboard or screen input |
| Proposals with base revision and outcome | System prompts, context-file contents |
| File-level changes attributed to a session | Hidden reasoning traces |
| Session lifecycle (start, fork, compaction, end) | Credentials or API keys |
| Declared model/agent identity | Arbitrary full tool output |
| | Anything not opted in |

Capture candidates are not authoritative. A candidate becomes curated memory
only after the person, or a deterministic policy the person chose, accepts it.
Replay with the same stable identity must not create a duplicate entry.

## Authority and provenance

Three distinct authorities with enforced boundaries:

1. **Agent runtime** owns the conversation session — prompt history, model
   responses, tool invocations, persistence. Authoritative for what the model
   saw and said.
2. **Knowledge environment** owns imported activity and curated memory, once
   imported with stable identity, idempotent replay, and provenance.
3. **Person** owns decisions about what to capture, keep, and delete. Capture
   is opt-in; curated memory is inspectable and correctable; deletion is
   explicit.

Provenance travels with every record: source session, source event, actor,
ancestry, and relevant document revision. Records lacking required provenance
are rejected.

## Local ownership and privacy

Canopy-owned activity data, curated memory, and checkpoints live on the
person's devices. No required external service; capture must not transmit
another copy of agent-session data. Any later synchronization must preserve
local ownership and pass its own collaboration and deletion review.

The first slice makes no provider call. The agent runtime may already use an
external model under its own policy, but capture adds no provider disclosure.
A later provider-assisted feature requires a separate data-egress and
product-value gate.

These rules are specific applications of the
[human-centered product principles](human-centered-product-principles.md).

## Deterministic baseline before semantic or generated behavior

- The activity reducer is deterministic. Same inputs → same checkpoint, no
  provider call.
- The Resume view is deterministic over a fixed checkpoint plus fixed event
  log. No generated summarization in the first slice.
- A fixed, inspectable transcript is the first acceptance artifact. The Resume
  view renders it faithfully before any semantic capture, provider call, or
  generated summary.

Semantic candidates and generated summaries remain out of scope until this
baseline is proven correct, inspected, and accepted.

## Generated UI: disposable projection, never authority

Generative or adaptive UI is a disposable projection over curated memory. It
cannot mutate authoritative records directly, and rejected output changes no
committed state. Authoritative changes require the proposal and commit boundary;
the fixed deterministic view remains available.

## Review gates

### First-slice gate

- A fixed transcript of representative activity events exists and is
  inspectable.
- A Resume view renders it as a chronological activity list plus checkpoint
  summary.
- Rendering is deterministic: same transcript → same view, no provider call.
- A person unfamiliar with the transcript can read the view and correctly
  answer "what was this session doing, and where did it leave off" within a
  predeclared bound, tracing each answer to source activity.

### Product-evidence gate

- At least one external developer or researcher uses the Resume view during
  actual work across multiple sessions.
- Resumption time, measured from opening the tool to orientation, is shorter
  than the person's unaided baseline.
- The person can name at least one specific decision or claim surfaced by the
  tool they would otherwise have reconstructed manually.

If the product-evidence gate does not pass, the direction is reconsidered.
Evidence decides rather than this document predetermining the outcome.

## Related documentation

The [product vision](product-vision.md) remains the long-term destination, and
[human-centered product principles](human-centered-product-principles.md) govern
this direction. The first slice treats the external agent runtime as a
read-only source; Canopy neither owns its loop nor grants it mutation authority.
Implementation starts with the
[Pi session activity → Resume view prototype](../plans/2026-07-16-pi-activity-capture-resume-prototype.md).
