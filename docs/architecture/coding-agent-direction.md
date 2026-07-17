# Coding Agent Direction

**Status:** deferred target architecture. This document defines a safe
integration boundary; it is not a near-term implementation commitment. Canopy's
current priority remains the [Personal Knowledge Environment](personal-knowledge-environment-direction.md).

The source-backed investigation behind this direction is recorded in
[OpenSeek–Canopy integration research](../research/2026-07-16-openseek-canopy-integration.md).

## Decision

Canopy should reuse an external coding-agent engine rather than implement its
own agent loop. The engine may own model interaction, conversation state, tool
orchestration, and retries. Canopy must retain authority over projections,
validation, user approval, live document state, and collaborative commit.

The integration is worthwhile only when it serves a demonstrated product need.
Until then, this document preserves the boundary future work must respect.

## Boundary

```text
external agent engine
  → structured requests and proposals
  → replaceable adapter
  → Canopy semantic and projection APIs
  → validation and speculative preview
  → host-issued approval where authority changes
  → revision-checked collaborative commit
```

The adapter translates transport and protocol data. It must not become a second
owner of document semantics or workspace state.

## Responsibility split

### External agent engine

The engine owns:

- model and provider interaction;
- prompt and conversation state;
- generic tool-call orchestration;
- retry and model-call recovery policy;
- its session persistence;
- transport and credentials.

The engine does not own Canopy document revisions, projection identity,
semantic validation, approval, or collaborative-operation provenance.

### Canopy

Canopy owns:

- authoritative live documents and their revisions;
- incremental parsing, projections, and semantic context;
- proposal validation and speculative preview;
- user-facing approval decisions;
- CRDT commit and peer convergence;
- capability policy for effects that reach Canopy state;
- proposal, approval, and commit provenance.

Canopy does not own the coding-agent engine's model loop, concrete provider
client, conversation manager, or coding-tool retry system. Canopy's existing
provider-neutral request and result boundaries remain available to its own
cognition features.

### Adapter

The adapter owns:

- translation between an agent protocol and Canopy domain operations;
- correlation between external requests and Canopy revisions;
- process, stream, cancellation, and lifecycle handling;
- conversion of agent tool requests into context queries or proposals.

The adapter is replaceable. Canopy domain APIs must not depend on one engine's
wire format.

## Authority invariants

### No direct live writes

An agent cannot write directly to a Canopy-authoritative document, committed
workspace state, or DOM. Document changes enter as proposals and are applied
only by Canopy's commit boundary.

An isolated workspace may allow shell, build, test, or file effects under an
explicit host policy. Authority in an isolated workspace does not grant
permission to mutate a live Canopy document.

### Host-owned capabilities

The host chooses which tools and effects are available before a prompt is sent.
The agent cannot add to its own authority. If the host cannot verify the active
tool set, the integration fails closed.

Extra or third-party tools remain part of the host's policy; disabling
OpenSeek's built-ins alone cannot establish a general sandbox guarantee.

### Revision-bound proposals

A proposal identifies the exact document revision it was prepared from.
Validation and preview do not mutate the live document. Commit checks the
revision again so a concurrent edit cannot silently change the meaning of an
approved proposal.

### Host-issued approval

Approval belongs to the host and binds one exact proposal, base revision, and
preview. The agent cannot mint approval. Changing proposal content or its base
revision creates a new proposal and repeats validation and preview.

Read-only context requests and effect-free generated views do not require a
user approval step merely because an agent produced them. They still pass their
existing validation and capability boundaries.

### Idempotent effects

Any path that supports cancellation, retry, reconnect, or replay must identify
effect-bearing work strongly enough to prevent duplicate commit. Late or
cancelled results cannot acquire authority after their request has closed.

A narrow, ordered, single-process read-only bridge need not introduce a general
distributed-event protocol before it has an effect to deduplicate. Broader
correlation requirements should be justified by the transport and effects an
implementation actually supports.

## Functional core and imperative shell

Proposal validation, revision checks, capability decisions, and lifecycle
transitions belong in a deterministic functional core. The core receives
explicit inputs and returns decisions without transport or document mutation.

The imperative shell owns process I/O, scheduling, cancellation, provider and
protocol adapters, scratch editors, and the final live commit. Tests should pin
the functional core with deterministic inputs and keep shell tests focused on
effect wiring.

## Projection-aware proposals

Agents should request language-owned operations, not reproduce Canopy's
projection internals. For example, an agent may ask to rename a selected
binding. Canopy resolves scope, computes the text changes, previews the
projected result, and decides whether the proposal is valid.

The conceptual mutation flow is:

1. capture the authoritative base revision;
2. validate the structured proposal against Canopy semantics;
3. compute and preview the result without mutating the live document;
4. present the exact proposal and preview for host approval;
5. recheck the base revision and proposal identity;
6. commit through the CRDT editor and record provenance.

Rendering patches are outputs of the projection pipeline, never agent-authored
mutation inputs.

## Generative UI

The existing capability validation, dry-run, and session commit path remains
available to effect-free candidates; see the
[Generative UI direction](generative-ui-direction.md). A generated action that
changes a document or performs another host effect requires the same host-owned
authority boundary as other agent proposals.

Generated output cannot add event handlers, network access, persistence, or
direct DOM authority merely by requesting it.

## Session and audit separation

The external engine owns conversation history, model responses, tool calls, and
its own compaction or replay. Canopy owns the record of proposal identity, base
revision, approval, commit, and collaborative provenance.

The records answer different questions:

- the agent session explains what was requested and generated;
- the Canopy record explains what was authorized and changed authoritative
  state.

They may be correlated without sharing ownership. Loss or compaction of the
agent session cannot erase Canopy's commit provenance.

## Activation gates

Implementation should begin only when all of the following hold:

1. A named product experiment shows why an external coding agent is better than
   a simpler fixed workflow.
2. The selected engine can run without built-in paths that write around
   Canopy's document boundary.
3. The host can inspect the tools available to the model before sending a
   prompt.
4. An executable plan defines proposal identity, revision checks, approval,
   cancellation, idempotency, and CRDT convergence for one narrow slice.
5. The first slice uses one active editor and one language-owned operation; it
   does not introduce multi-document identity prematurely.

These gates protect the current Personal Knowledge Environment priority from an
unbounded agent-framework project while preserving a route to a later
integration.

## Deferred work

- stable multi-document identity and a document registry;
- cross-session proposal identity;
- concurrent semantic merge of agent proposals;
- effectful Generative UI actions;
- cryptographic approval evidence;
- general reconnect and replay semantics beyond a concrete transport need;
- a second provider abstraction for the external coding-agent engine.

## Non-goals

- reimplementing an agent loop in Canopy;
- making Canopy a general-purpose agent framework;
- allowing agents to bypass validation, approval, or collaborative commit;
- treating model output as authoritative state;
- coupling Canopy's domain API to OpenSeek or another agent protocol;
- changing the near-term product priority through this document alone.

## Related documentation

- [Personal Knowledge Environment Direction](personal-knowledge-environment-direction.md)
- [Human-centered product principles](human-centered-product-principles.md)
- [Generative UI Direction](generative-ui-direction.md)
- [Cognition Runtime](cognition-runtime.md)
- [OpenSeek–Canopy integration research](../research/2026-07-16-openseek-canopy-integration.md)
- [Codex App-Server Lowering](../research/2026-06-13-canopy-codex-app-server-lowering.md)
- [Responsibility Map](responsibility-map.md)
