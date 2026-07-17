# Incremental Generative UI document engine

**Status:** Design direction; not implemented.

**Related:**

- [Generative UI direction](../architecture/generative-ui-direction.md)
- [Stable Document Entity Graph](stable-document-entity-graph.md)
- [JSX DOM patch contract](../decisions/2026-07-13-jsx-dom-patch-contract.md)
- [Input vertical slice](../plans/2026-07-12-generative-ui-input-vertical-slice.md)
- [Responsibility Map](../architecture/responsibility-map.md)
- [Human-centered product principles](../architecture/human-centered-product-principles.md)

## Load-bearing question

Text, projections, and agents can produce incomplete, stale, duplicated, or
unapproved proposals. Which transition becomes document meaning?

For a new `GenerativeUiDocument`, the answer is one validated, atomic change to
a committed `UiGraph`. Proposal sources never mutate that graph directly.
Existing Canopy editors remain text/CRDT authoritative.

This design is bounded research. It does not authorize generated behavior
before the personal-knowledge fixed baseline or existing Generative UI V1 gates
pass. It also does not define a public renderer-neutral API, final source
syntax, or CRDT/causal-merge semantics.

## Authority and state

The document keeps five state classes separate:

| State | Authority |
| --- | --- |
| Draft | Lossless source and CST at a `DraftRevision`; may be invalid or incomplete. |
| Committed semantic | Valid `UiGraph`, document/graph/schema IDs, and immutable schema digest. |
| History and request ledger | Applied batches plus terminal records for retry and audit. |
| Runtime | Host bindings, interaction state, and renderer-local state; never document meaning. |
| Sync | Draft/graph relation, rewrite cursor, renderer baselines, conflicts, and dirty state. |

The committed graph is current meaning. Invalid draft updates diagnostics and
sync state while the last valid graph remains current. No path silently
promotes draft, runtime, or renderer state.

## Semantic commit

`UiOperationRequested` carries a non-empty ordered `OperationBatch`. The batch,
not each primitive, is the transaction unit.

```text
request lookup and bounds
→ host authority and approval policy
→ graph and schema revision checks
→ pure batch apply on a private graph
→ final graph and schema validation
→ terminal outcome
   Applied          → atomically persist graph, revision, applied batch,
                      request record, and outbox
   NoSemanticChange → persist request record only
   Rejected         → persist request record only
→ respond; release post-commit effects only for Applied
```

Before responding, the host persists a durable `RequestRecord` with the request
ID, canonical content, digest, outcome, and resolved handle-to-ID mapping.
Decode or bounds failures before canonical request construction remain boundary
diagnostics.

Only `Applied` advances `GraphRevision`. `NoSemanticChange` and `Rejected` are
ledger-only outcomes: they add no applied history or outbox work. Rejection
also exposes no partial batch and changes no graph, source, or renderer
baseline.

The host owns the component registry, schema, authority facts, and approval
evidence. Generated input can name only capabilities allowed by the pinned
schema. A product adapter must enforce a person-authorized, revocable policy
and require approval where that policy says; generated input cannot mint
approval evidence.

## Renderer separation

Semantic commit does not depend on DOM or renderer success. A committed change
emits durable source and renderer work through an outbox. Renderer failure
leaves meaning unchanged, marks only that renderer dirty, and schedules repair
from the committed graph.

The existing JSX session still follows its V1 rule that a candidate is not
reported committed until DOM apply succeeds. That adapter/session contract does
not define semantic authority for the new document engine.

## Requests and idempotency

| Field | Rule |
| --- | --- |
| `RequestId` | Host-issued and unique within one document. |
| Actor/provenance | Host-attested text, projection, agent, or undo origin. |
| Base graph/schema | Must match the committed revisions. |
| Origin revision | Required for text-derived requests; names the exact lowered draft. |
| Approval evidence | Host-issued when the current policy requires it. |
| Batch | Non-empty, ordered, and bounded. |

Canonical content comes from the validated typed request, not transport bytes.
It includes a version/domain tag, document and actor identity, provenance, base
revisions, approval identity, and ordered batch. It excludes `RequestId`,
timestamps, whitespace, and object-key order. Boundary decoding rejects
duplicate keys and non-finite numbers; canonical encoding orders keys and gives
`BindingRef` one stable representation.

The digest is only an index and integrity check. Canonical request content is
the equality authority.

- Same request ID and same canonical content returns the recorded outcome after
  verifying the stored digest. It performs no new mutation.
- Same ID with different content is request-ID reuse, or a digest collision when
  the digest also matches. Both fail closed without changing the existing
  record, graph, history, or outbox.
- Stored content/digest disagreement is an integrity error and also fails
  closed.

The initial slice does not compact request records. A future retention design
must first define and test an equality-preserving tombstone or monotonic actor
sequence. A digest or unspecified watermark is insufficient.

Semantic graph equality includes schema revision, root and node identities,
components, canonical properties, and ordered children. It excludes graph
revision, history, draft, runtime, renderer, and diagnostics.

Text requests are rejected and re-lowered when their origin draft is stale.
Projection and agent requests use the committed graph revision. The core does
not automatically rebase semantic operations.

## Forward operation algebra

| Primitive | Meaning |
| --- | --- |
| `InsertNode(handle, component, properties, parent, placement)` | Insert a new node. |
| `MoveNode(node, parent, placement)` | Reparent or reorder an existing node. |
| `SetProperty(node, key, value)` | Assign a schema-valid declarative value. |
| `RemoveProperty(node, key)` | Remove a property; distinct from assigning `null`. |
| `RemoveNode(node)` | Remove a non-root subtree. |

Requests address committed nodes with `Existing(UiNodeId)` and same-batch nodes
with `New(NewNodeHandle)`. A handle is request-local and declared exactly once
by `InsertNode`. Before apply, declaration order assigns each handle an
insertion ordinal. The host deterministically derives the opaque `UiNodeId`
from `(DocumentId, RequestId, insertion ordinal)` and records the mapping in the
terminal request record. Generated input never chooses durable IDs.

Placement is identity-relative:

```text
AtStart | AtEnd | Before(sibling) | After(sibling)
```

The parent and optional sibling must already resolve in the private working
graph; the sibling must belong to that parent. Same-parent moves detach the
moved node before resolving placement, and self anchors are invalid. Insert
requires a fresh local handle and allowed component. Move and remove require an
existing non-root node; a move cannot target its own subtree. `RemoveProperty`
requires a present property. Assigning the current value or moving to the
current position is allowed and handled by final no-op classification. Index
placement and fallback clamping are excluded.

Changing component kind is not a primitive. Adapters lower it to remove and
insert with fresh identity unless later evidence requires cross-kind identity.

Batch laws:

1. The batch is non-empty and applied sequentially to a private graph.
2. Each primitive reads the result of previous primitives.
3. Any failed precondition rejects the whole batch.
4. Final graph and schema validation occur before commit.
5. A final graph semantically equal to the base is `NoSemanticChange`.
6. Only `Applied` advances the graph revision.

Every valid graph has one host-owned root that requests cannot insert, move, or
remove. Node IDs are unique, each non-root node has one parent, and the tree is
connected, acyclic, and deterministically ordered. Component schemas enforce
required properties, child kinds/cardinality, and bounded values. Boundary and
graph limits cover decoded bytes, nodes, depth, children, properties, recursive
value depth and collection size, strings, value bytes, batch length, and
cumulative inserted subtree size.

## Values and schemas

Committed values are immutable bounded JSON-shaped literals plus host-issued
`BindingRef` values where the component schema permits them. A binding names a
host capability; its runtime value is never serialized. Missing or revoked
bindings produce `BindingUnavailable` without changing the graph.

The first slice excludes expressions, functions, action callbacks, raw HTML,
ambient-authority URLs, provider objects, DOM nodes, and JavaScript host
objects. Commands require a separate commands-as-data and approval design.

Each `SchemaRevision` names one immutable canonical schema descriptor. Commits
and checkpoints persist its revision and digest. Restore requires both to
match; missing or changed schema enters `SchemaUnavailable` while preserving
bytes and history. No reinterpretation, commit, or rendering occurs under a
different schema.

Schema migration is a separate host-only command. It validates the full graph
under the target schema and atomically records both revisions, the new digest,
and migration provenance. Installing a new registry version never triggers
migration automatically.

## Inverse batches and reversal

Pure apply captures before-images and derives an inverse in reverse order:

| Forward | Inverse |
| --- | --- |
| Insert | Remove the inserted node. |
| Move | Move to the previous parent and placement. |
| Set existing property | Restore the previous value. |
| Set absent property | Remove the property. |
| Remove property | Restore the removed value. |
| Remove subtree | Internal `RestoreSubtree` with the validated before-image. |

`RestoreSubtree` is host-internal because it can resurrect semantic IDs. Undo
never rewinds revision or history; it submits the inverse as a new request at
the current base and may fail current policy, schema, or conflict checks. Any
product adapter that permits generated commits must expose a user-visible
reversal path.

## Draft, source, and renderer transitions

The functional core follows:

```text
DocumentState + DocumentEvent → DocumentState + Decision
```

The shell performs persistence, parsing, rewriting, rendering, clocks, and
provider I/O, then reports results as events.

| Event | Required transition |
| --- | --- |
| Draft edit | Preserve exact bytes and advance `DraftRevision`; keep the graph unchanged until lowering succeeds. |
| Text-derived semantic change | Commit only when origin draft, graph, and schema revisions match. |
| No-delta text change | Preserve complement; sync without request, revision, history, or outbox. |
| Matching text-origin commit | Mark the current draft synchronized without rewriting its bytes. |
| Projection/agent commit | Rewrite only on matching draft and semantic baselines; otherwise enter `RewriteConflict`. |
| Renderer success | Advance only that renderer's baseline. |
| Renderer failure | Keep meaning, mark that renderer dirty, and repair from committed state. |

A host may defer agent/projection commits while draft is dirty. Even when it
allows them, source rewrite never overwrites a diverged draft.

## Identity scopes

| Identity | Scope |
| --- | --- |
| Source/CST handle | One parse or draft revision. |
| `NewNodeHandle` | One request. |
| Projection `NodeId` | Existing projection reconciliation. |
| `UiNodeId` | Durable semantic identity within one document history. |
| Renderer ID | One adapter instance. |
| `DocumentId` | Document/storage namespace. |

The stable semantic identity is `(DocumentId, UiNodeId)`. Derived IDs remain
reserved even when a same-batch operation removes the new node, and they are
never reused. A no-op request also reserves its request namespace. ID encoding
is private and collision-checked.

## Persistence and recovery

An applied commit atomically groups:

- next graph or checkpoint/delta reference;
- graph revision, schema revision, and schema descriptor digest;
- validated batch, ID allocations, and provenance;
- canonical request content, digest, and terminal outcome;
- source and renderer outbox entries.

Recovery loads the latest valid checkpoint and replays a contiguous history
suffix. Every step must match base graph/schema revisions and the next recorded
revision. Reconstructed graph, schema identity/digest, and checkpoint must
agree. Gaps, request-content/digest mismatches, unavailable or changed schemas,
and replay mismatches enter diagnostic read-only state.

Outbox effects carry `EffectId`, target, base/target graph revisions, graph hash
or snapshot reference, and optional expected draft state. Delivery is
at-least-once and adapters are idempotent against effect IDs and baselines.
Redelivery cannot create another semantic commit.

Renderer ordering is explicit:

1. Dirty state takes precedence and rebuilds the latest committed snapshot.
2. When clean, a target at or below the baseline is a stale acknowledgment.
3. An effect whose base equals the baseline may apply.
4. A gap rebuilds the latest snapshot; older deltas never apply.

A text-origin source effect matching the current draft marks it synchronized
without rewriting bytes. Projection/agent source effects require matching draft
revision, valid/rewrite-eligible status, and source semantic baseline; otherwise
they preserve source and enter `RewriteConflict`. Gaps coalesce to the latest graph and canonical source.
Observed state never regresses.

## Concurrency

The first engine serializes semantic requests. Stale graph or schema revisions
are rejected. Draft editing may continue independently, but only an exact draft
revision can produce a text-derived commit. No automatic rebase or semantic
CRDT merge is claimed. Future collaboration must integrate with
`event-graph-walker` rather than create a second causal identity system.

## Existing precedents

The design reuses principles, not dependencies:

| Precedent | Reused principle |
| --- | --- |
| `GenerativeUiLifecycle` | Generation IDs, cancellation, stale rejection, terminal states. |
| Candidate validation | Bounded capability checks before commit. |
| Replay source | Deterministic fixed-event replay. |
| JSX session | Draft preservation, base revision, dry-run, failed-apply recovery. |
| Render baseline | Dirty recovery and monotonic renderer state. |
| Stable entity work | Durable semantic identity distinct from projection IDs. |

The generic core does not freeze synthetic JSX, normalized unparse output,
candidate-always-remount behavior, session-local IDs, JSX `DomPatch`, or
current table/filter/summary candidate types.

## Trust boundary

An agent adapter submits only a bounded decoded proposal body. The host adds
request ID, actor, schema, generation, authority, and approval facts. No
callback, source handle, graph reference, registry, DOM object, or host object
crosses the boundary.

`js_engine` supports persistent interpreter state and advanced host objects but
is not a security sandbox. Arbitrary generated JavaScript remains gated on
budgets, interruption, re-entry, disposal/generation tokens, async lifetime,
and a killable Wasm or process boundary. The first slice executes no generated
JavaScript.

Trusted chrome and approval UI require a separate root, registry, and authority
domain from generated content. Existing inert expression spans and reserved
`data-node-id` constrain JSX injection but do not prove that separation.

## Text adapter

A temporary adapter may use newline-committed flat declarations with explicit
parent/placement and lossless per-record complement. JSX remains an adapter and
import surface; JSON Lines is only a possible wire format.

For snapshot text, appending an incomplete suffix must not change the lowered
meaning of a complete newline-terminated prefix. This rule does not apply to
append-only operation streams whose later records intentionally modify earlier
nodes.

## Sequence and validation gate

1. Preserve the existing structured-candidate and JSX V1 baseline.
2. Test the private semantic graph, batch, reducer, persistence, and request
   model as a discardable experiment.
3. Add text and projection/agent adapters only after the core gate passes.
4. Validate shared invariants with a materially different renderer.
5. Only then consider a public contract or collaborative semantic editing.

Step 2 does not bypass the PKE fixed baseline, V1 gates, real use-case evidence,
or second-adapter requirement.

Before adapter work, the private core must pass one deterministic transcript:

1. Preserve an invalid draft while retaining the last committed graph.
2. Commit one duplicated request exactly once after response loss.
3. Reject stale source rewrite without changing draft bytes.
4. Recover a dirty renderer under duplicate, stale, and gap delivery without
   regressing its baseline.
5. Restart with the same graph, schema identity, semantic IDs, request outcomes,
   draft, and pending effects.

The [semantic-core validation plan](../plans/2026-07-16-incremental-generative-ui-semantic-core-validation.md)
maps each invariant to focused, property, replay, or deferred evidence. It also
requires restart coverage for `NoSemanticChange` and `Rejected`, forced digest
collision tests, schema-descriptor corruption, inverse properties, and
fail-closed replay.

Collection, tree, and state-machine laws remain executable tests. `moon prove`
is optional and limited to small scalar decisions. Failure of the fixed
transcript rejects or revises this direction before adapter work.

Passing the core gate proves none of adapter isolation, host trust, hostile
JavaScript safety, collaboration, accessibility, agency, or product value.
Those claims remain subject to the
[human-centered product principles](../architecture/human-centered-product-principles.md)
and their own evidence.

## Deferred decisions

- Storage backend, checkpoint cadence, retention, and request-ledger bounds.
- Approval/preview interaction over the required revocable policy.
- User-visible reversal interaction and undo retention.
- Schema migration authoring API.
- Final text language and public operation API.
- Collaboration mapping to `event-graph-walker`.
