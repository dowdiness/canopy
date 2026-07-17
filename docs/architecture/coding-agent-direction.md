# Coding Agent Direction

**Status:** deferred target architecture that defines a safety boundary while
Canopy's near-term priority remains the
[Personal Knowledge Environment](personal-knowledge-environment-direction.md).

See [OpenSeek–Canopy integration research](../research/2026-07-16-openseek-canopy-integration.md)
for the source-backed investigation.

## The boundary to preserve

A coding-agent engine already knows how to call models, run tools, keep a
conversation, and recover from model failures. Rebuilding those capabilities in
Canopy would create a second agent framework without improving the part Canopy
is designed to own.

Reusing an engine looks simple until the first edit. Its normal shell and file
tools can change the same source that Canopy parses, projects, and shares with
peers. If those tools write directly, Canopy may display a change it never
validated, approved, or recorded as a collaborative operation.

The safe boundary is therefore narrower: the engine may decide what to request,
but Canopy decides what a request means and whether it changes authoritative
state. This direction should be implemented only when a product experiment
shows that an agent works better than a simpler fixed workflow.

## Ownership

| Layer | Owns | Does not own |
| --- | --- | --- |
| External engine | Models, prompts, conversation state, generic tool orchestration, retries, credentials, and its session | Canopy revisions, semantics, approval, or commit provenance |
| Canopy | Live documents, revisions, projections, semantic context, validation, approval, CRDT commit, and proposal provenance | The coding-agent loop, concrete provider client, conversation manager, or generic tool retries |
| Adapter | Protocol translation, request correlation, process I/O, cancellation, and conversion to Canopy queries or proposals | Document semantics or authoritative state |

The adapter is replaceable. Canopy's domain APIs must not depend on one engine's
wire format. Existing provider-neutral request and result boundaries remain
available to Canopy's own cognition features.

## Authority rules

### The agent cannot write live state

An agent cannot write directly to a Canopy document, committed workspace state,
or DOM. Document changes enter as proposals and are applied only by Canopy's
commit boundary.

A separate workspace may allow shell, build, test, or file effects under an
explicit host policy. Access there does not grant access to a live Canopy
document.

### The host chooses capabilities

Removing direct editor writes is not enough if another enabled tool can reach
the same files. The host therefore chooses which tools are available before
sending a prompt, and the agent cannot expand that set. If the host cannot
verify the active tools, the integration stops.

Third-party tools remain the host's responsibility. Disabling an engine's
built-ins is not a general sandbox guarantee.

### Preview does not authorize a later document

A proposal identifies the document revision it was prepared from. Validation
and preview do not mutate the live document. Even after approval, commit checks
the revision again; otherwise a concurrent edit could change the meaning of the
proposal between preview and application.

Approval is issued by the host and binds one proposal, base revision, and
preview. Any content or revision change creates a new proposal and repeats
validation.

Read-only queries and effect-free generated views do not need user approval,
but they still pass their existing validation and capability checks.

### One authorized effect happens once

A correct commit can still become incorrect when cancellation, retry, reconnect,
or replay delivers the same result twice. Any effect-bearing path must prevent a
duplicate commit. Late and cancelled results cannot gain authority after their
request closes.

A single-process read-only bridge has no effect to deduplicate and does not need
a general replay protocol. Correlation requirements should grow with the
transport and effects actually supported.

## Integration boundary

```text
external engine
  → replaceable adapter
  → Canopy semantic query or proposal
  → validation and preview
  → host approval when authority changes
  → revision-checked CRDT commit
```

Agents should request language-owned operations instead of reproducing Canopy's
projection internals. For a rename, the agent can name the desired operation
while Canopy resolves scope, computes the text changes, and previews the
resulting projection.

The mutation flow is:

1. capture the base revision;
2. validate and compute the proposal without live mutation;
3. show the exact preview for host approval;
4. recheck revision and identity;
5. commit through the CRDT editor and record provenance.

Rendering patches are projection outputs, never agent-authored mutation inputs.

## Functional core and imperative shell

A deterministic core owns proposal validation, revision checks, capability
decisions, and lifecycle transitions. It receives explicit inputs and returns
decisions without I/O or document mutation.

A thin shell owns process I/O, scheduling, cancellation, scratch editors, and
the final live commit. This keeps proposal decisions testable without turning a
transport mock into the source of truth.

## Generated UI and audit

Not every agent result carries the same authority.

Effect-free candidates may keep using the validation, dry-run, and commit path
in the [Generative UI direction](generative-ui-direction.md). A generated
action that changes a document or performs a host effect crosses the proposal
boundary above.

The external engine owns conversation history and tool-call records. Canopy
owns proposal identity, base revision, approval, commit, and collaborative
provenance. The records may be correlated, but losing or compacting the agent
session cannot erase Canopy's commit record.

## Activation gates

Implementation requires all of the following:

1. A read-only agent condition beats the fixed workflow on a named user task.
2. Any use of PKE or session data passes the fixed-baseline and data-egress
   gates.
3. The engine can run without built-in write paths around Canopy.
4. The host can inspect available tools before sending a prompt.
5. An executable plan covers identity, revision checks, approval, cancellation,
   idempotency, and peer convergence.
6. The first slice uses one active editor and one language-owned operation.

## Deferred

- multi-document identity and registry;
- cross-session proposal identity;
- concurrent semantic merge;
- effectful Generative UI actions;
- cryptographic approval evidence;
- general reconnect and replay semantics;
- a second provider abstraction for the external engine.

## Non-goals

- implementing an agent loop in Canopy;
- making Canopy a general agent framework;
- bypassing validation, approval, or collaborative commit;
- treating model output as authoritative state;
- coupling Canopy's domain API to OpenSeek;
- changing the near-term product priority through this document.

## Related documentation

- [Personal Knowledge Environment Direction](personal-knowledge-environment-direction.md)
- [Human-centered product principles](human-centered-product-principles.md)
- [Generative UI Direction](generative-ui-direction.md)
- [Cognition Runtime](cognition-runtime.md)
- [OpenSeek–Canopy integration research](../research/2026-07-16-openseek-canopy-integration.md)
- [Codex App-Server Lowering](../research/2026-06-13-canopy-codex-app-server-lowering.md)
