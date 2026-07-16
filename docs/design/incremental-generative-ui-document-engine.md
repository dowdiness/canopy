# Incremental Generative UI document engine

**Status:** Design direction; not implemented.

**Related:** [Generative UI direction](../architecture/generative-ui-direction.md) · [Stable Document Entity Graph](stable-document-entity-graph.md) · [JSX DOM patch contract](../decisions/2026-07-13-jsx-dom-patch-contract.md) · [Input vertical slice](../plans/2026-07-12-generative-ui-input-vertical-slice.md) · [Responsibility Map](../architecture/responsibility-map.md) · [Human-centered product principles](../architecture/human-centered-product-principles.md)

## Load-bearing question

A Generative UI document receives text, projection, and agent inputs that may
be incomplete, conflicting, duplicated, stale, or unapproved. The load-bearing
question is not which syntax carries a proposal. It is which transition counts
as committed document meaning.

The answer is a validated, atomic semantic transaction. Text, projection, and
agent adapters may propose transactions, but none of them is document
authority.

## Scope and non-goals

This is a narrowly scoped operation/semantic-authoritative model for a new
`GenerativeUiDocument`. Current Canopy remains text/CRDT authoritative for
existing language editors; this document does not replace that responsibility
map ([Responsibility Map](../architecture/responsibility-map.md)).

Not included:

- An implementation plan, task checklist, or file-by-file breakdown.
- A global replacement of the text-first Canopy pipeline.
- A public renderer-neutral API. The first implementation remains internal
  until a real vertical slice and a materially different renderer validate the
  shared invariants.
- A change to the current product sequence. A private semantic core is bounded
  falsification research, not permission to add generated behavior before the
  fixed personal-knowledge baseline is accepted or to bypass the existing V1
  adapter gates.
- A claim that the operation history provides CRDT or causal-merge semantics.

## First principles

The design follows five rules:

1. **Current meaning has one authority.** A valid committed UI graph at an
   explicit revision is the current document meaning.
2. **Proposals are not authority.** Draft text, projection gestures, agent
   output, JavaScript callbacks, and renderer state cannot directly mutate the
   committed graph.
3. **Commit is atomic; effects are not commit.** Persistence of the next graph
   and its applied transaction is one atomic decision. Source rewriting and
   rendering are post-commit effects with explicit recovery state.
4. **Identity names its stability scope.** Source handles, projection handles,
   semantic node IDs, renderer IDs, and document IDs are distinct.
5. **Generated input is data.** It crosses a bounded, schema-validated request
   boundary and never carries executable callbacks or host objects.

## State and authority model

A Generative UI document has five first-class state classes:

1. **Draft source state** — lossless source and CST at a `DraftRevision`,
   possibly incomplete or unresolved.
2. **Committed semantic state** — a valid UI graph identified by `DocumentId`,
   `GraphRevision`, and `SchemaRevision`, plus the canonical digest of the
   immutable schema descriptor named by that revision.
3. **Commit history and request ledger** — applied batches plus request IDs,
   actor, provenance, approval evidence, terminal outcomes, and schema
   revisions. Applied history explains how meaning changed; the request ledger
   provides retry safety and auditability.
4. **Runtime state** — host-owned binding values, interaction and tool state,
   and renderer/session-local working state.
5. **Sync state** — the explicit relation among draft, committed graph, source
   rewrite cursor, and each renderer baseline, including drafting,
   rewrite-conflict, schema-unavailable, and dirty-renderer conditions.

The committed graph is authoritative for current document meaning. Applied
history is authoritative for accepted semantic changes. The request ledger is
not document meaning, and runtime values never become document meaning merely
because a renderer displays them.

Draft source may intentionally differ from committed semantics. Parse or
lowering failures update diagnostics and sync state while the last valid
committed graph remains current. No path may silently promote draft, runtime,
or renderer state into committed meaning.

## The semantic commit boundary

The semantic commit protocol is the only path that can advance committed
meaning. Regular edits enter through `UiOperationRequested`, which carries a
non-empty forward `OperationBatch`; the batch, not each primitive, is the
transaction unit. A future schema migration uses the same atomic commit
protocol through a separate host-only gate rather than a generated operation
request.

```text
UiOperationRequested
  → request-ID lookup and limit validation
  → host policy / authority gate
  → approval evidence check (if required)
  → base graph + schema revision check
  → pure ordered batch application on a private working graph
  → final graph invariant + component schema validation
  → classify terminal outcome
     Applied          → atomically persist graph, revision,
                        AppliedUiOperation, RequestRecord, and effect outbox
     NoSemanticChange → persist RequestRecord only
     Rejected         → persist RequestRecord only
  → respond; run source-rewrite and renderer effects only after Applied
```

`AppliedUiOperation` names the committed envelope for the whole batch. Primitive
operations are not independently committed. One committed batch advances
`GraphRevision` exactly once.

Every terminal outcome of a host-constructed request — `Applied`,
`NoSemanticChange`, or `Rejected` — produces a conceptual `RequestRecord`
containing the request ID, canonical request content (or an equality-preserving
canonical representation), canonical digest, terminal outcome, and any resolved
handle-to-ID mapping. The host persists this record before responding to the
caller. Proposal decoding or limit failures that occur before the host
constructs a canonical request are boundary diagnostics rather than
request-ledger outcomes.

An `Applied` outcome is atomic with the graph, applied history, and outbox
entries. `NoSemanticChange` and `Rejected` records do not advance graph
revision and do not append to applied history. A rejected batch leaves the
graph, graph revision, applied history, source, and renderer baselines
unchanged. If the final semantic state equals the initial semantic state, the
result is `NoSemanticChange`: no semantic revision advances and no
`AppliedUiOperation` is appended.

The host owns the component registry and schema revision. Generated input may
name only host-issued components and capabilities; it cannot register a
component, choose another schema revision, or supply approval evidence on the
host's behalf.

## Semantic commit versus renderer apply

Actual DOM or renderer mutation is not part of the semantic transaction. Only
renderer-independent document schema and capability policy may reject a graph
before semantic commit. An adapter may run a pure preflight before applying a
committed graph, but its result changes that renderer's sync state rather than
the semantic transaction. Semantic commit never depends on an actual DOM
mutation succeeding.

A committed transaction emits durable source-rewrite and render work through
an outbox. Renderer success advances that renderer's baseline. Renderer failure
leaves the committed graph unchanged, marks only that renderer dirty, and
schedules repair from the committed graph.

The existing JSX session keeps its accepted V1 rule that a candidate is not
reported as committed until DOM application succeeds
([JSX DOM patch contract](../decisions/2026-07-13-jsx-dom-patch-contract.md)).
That is an adapter/session commit for the current candidate pipeline. It must
not define the new document engine's semantic commit, because one renderer's
availability cannot determine meaning for every renderer.

## Request envelope and idempotency

A request contains, conceptually:

| Field | Rule |
| --- | --- |
| `RequestId` | Host-issued and unique within one document; reused IDs must carry the same canonical request content; the digest is an index and check, not an equality proxy. |
| Actor and provenance | Host-attested origin such as text, projection, agent, or undo. |
| Base graph revision | Must equal the current `GraphRevision`. |
| Base schema revision | Must equal the committed `SchemaRevision`. |
| Origin revision | Required for text-derived requests; identifies the exact `DraftRevision` that was lowered. |
| Approval evidence | Host-issued evidence when required by the current user-authorized, revocable policy; generated input cannot mint it. |
| `OperationBatch` | Non-empty ordered list of bounded primitive operations. |

The canonical digest is computed from the validated typed request, not from
raw transport bytes. It includes a version or domain tag, document and actor
identity, provenance, base revisions, approval evidence identity, and the
ordered canonical batch. It excludes `RequestId`, transport timestamps,
whitespace, and object-key order. Boundary validation rejects duplicate object
keys and non-finite numbers; canonical encoding orders map keys and gives
`BindingRef` one stable representation before digest computation. Digest
equality never establishes request equality.

Two committed semantic states are equal only when they share the same schema
revision, root identity, semantic node IDs, components, canonical properties,
and ordered children. `GraphRevision`, history, draft complement, runtime,
renderer, and diagnostics are excluded from semantic equality. Changing
`SchemaRevision` is a semantic change even when the node graph is otherwise
identical.

A repeated `RequestId` with equal canonical request content returns the
recorded terminal outcome only after the stored digest matches the canonical
content. A mismatch fails closed as an integrity error. Neither path alters the
existing record, committed graph, applied history, or effect outbox.

A repeated `RequestId` with different canonical request content is always
rejected without mutation. If the digest is equal despite differing content,
classify it as a collision; if the digest differs, classify it as request-ID
reuse. Neither case may alter the existing `RequestRecord`, committed graph,
applied history, or effect outbox.

The initial slice does not compact request records. A later retention design
may remove canonical content only after it defines and tests an equality-
preserving tombstone or a monotonic actor request sequence that still rejects
ID reuse and digest collisions. A digest or unspecified actor watermark alone
is insufficient.

A text-derived request is rejected and re-lowered if its origin revision is no
longer the current draft revision. Projection- and agent-derived requests use
the committed graph revision for semantic conflict detection; source rewrite
uses a separate compare-and-swap rule described below.

## Forward operation algebra

### Primitive vocabulary

| Primitive | Meaning |
| --- | --- |
| `InsertNode` | Declare one request-local new-node handle with component, initial properties, parent, and placement. |
| `MoveNode` | Move an addressed non-root node to a parent and placement. |
| `SetProperty` | Add or replace one declarative property value. |
| `RemoveProperty` | Remove one declarative property. This is distinct from assigning `null`. |
| `RemoveNode` | Atomically remove the addressed node and its complete subtree. |

Requests address committed nodes with `Existing(UiNodeId)` and nodes introduced
in the same batch with `New(NewNodeHandle)`. A new-node handle is unique only
inside its request and must be declared exactly once by `InsertNode`. Each
`NewNodeHandle` is resolved to its declaration-order insertion ordinal before
pure apply. The logical `UiNodeId` is an opaque deterministic derivation from
`(DocumentId, RequestId, insertion ordinal)`. The resolution is pure, retries
produce the same mapping, different request-ordinal pairs produce different
IDs, and generated input cannot select durable IDs. Once ID resolution occurs,
the terminal `RequestRecord` stores the handle-to-ID mapping, and an applied
envelope stores the same resolved mapping; generated callers have no path to
mint durable IDs.

`InsertNode` inserts one node rather than an arbitrary subtree. A caller builds
a subtree with an ordered batch whose parent insertions precede their children.
Initial properties must satisfy node-local required-property rules at insertion;
full child-cardinality and graph invariants are checked on the completed private
working graph.

`RemoveProperty` is a forward operation, not merely an undo detail. The
separation from `SetProperty` preserves schemas where `null` is a valid value
and makes deletion explicit in audit and approval policy.

Primitive preconditions are strict. `InsertNode` requires an undeclared local
handle, an allowed component, and an already resolvable parent. `MoveNode` and
`RemoveNode` require an existing non-root target; a move beneath the target's
own subtree is rejected before mutation. `RemoveProperty` requires the property
to be present. `SetProperty` may assign the current value, and `MoveNode` may
resolve to the current placement; the final no-semantic-change rule decides
whether the batch commits.

Changing a node's component kind is not an initial primitive. An adapter lowers
that change to subtree removal and insertion with fresh semantic identity unless
a later domain use case proves that cross-kind identity must survive.

### Placement

Tree insertion and movement use identity-relative placement rather than raw
numeric indexes:

- `AtStart`
- `AtEnd`
- `Before(sibling_ref)`
- `After(sibling_ref)`

A sibling reference may be an existing semantic ID or an earlier request-local
new-node handle. The anchor must be a child of the target parent in the private
working graph at that point in batch evaluation. For a move within one parent,
the moved node is detached before placement is resolved. Missing, removed,
self, forward, or wrong-parent anchors reject the whole batch.

### Batch laws

A forward `OperationBatch` obeys these laws:

1. It is non-empty and evaluated in source order against one private working
   graph.
2. Structural preconditions are checked as each primitive is evaluated; final
   tree and schema invariants are checked on the completed working graph.
3. Later primitives may address nodes inserted or moved earlier in the same
   batch.
4. Any failure rejects the entire batch. No prefix becomes visible in the
   graph, history, source, or renderer.
5. A successful batch creates one applied-history record and advances graph
   revision once, regardless of primitive count.
6. A batch whose final graph equals its base graph is `NoSemanticChange` and
   does not advance semantic revision.
7. Limits apply to primitive count, inserted nodes, resulting graph growth,
   property depth, string/collection size, and total decoded request size.

These laws make a multi-node text edit, projection gesture, agent proposal, or
undo one transaction without exposing partially valid meaning.

### Graph invariants

Pure apply and final validation preserve at least these invariants:

- Semantic node IDs are host-derived, unique within the document, and never
  reused.
- The host-owned generated-surface root exists and cannot be inserted, moved,
  or removed by a request.
- Every non-root node has exactly one parent; the tree is connected and
  acyclic.
- Every placement resolves to one deterministic sibling order.
- Every component and property is allowed by the pinned component schema.
- Required properties, child kinds, child cardinality, and graph-size limits
  hold in the final graph.
- Runtime binding values, callbacks, JavaScript objects, DOM handles, and host
  chrome identities are absent from the graph.
- The first operation slice has no property-level references to arbitrary
  `UiNodeId` values. A future reference algebra must define dangling-reference
  and removal policy before such references are admitted.

## Value and schema boundary

Committed property values are immutable, bounded data. The initial value
algebra is JSON-shaped literals plus host-issued symbolic `BindingRef` values
when a component schema explicitly permits them. A `BindingRef` identifies a
host capability; the resolved binding value stays in runtime state and is not
serialized into the graph. An unavailable or revoked `BindingRef` produces a
runtime `BindingUnavailable` diagnostic and yields no value; it does not
mutate or invalidate the committed graph.

The initial algebra excludes expressions, functions, action callbacks, raw
HTML, URLs with ambient authority, provider objects, DOM nodes, and JavaScript
host objects. Commands and side effects require a separate commands-as-data and
approval design.

Each `SchemaRevision` names one immutable canonical schema descriptor. Every
committed graph and applied transaction pins both that revision and the
canonical descriptor digest. Regular generated requests can only target that
revision. On restore, the host must supply a descriptor whose identity and
digest both match. A missing descriptor, a reused revision with different
content, or a digest mismatch preserves the committed bytes and history but
enters `SchemaUnavailable`: no reinterpretation, semantic commit, or rendering
occurs under a different schema.

A schema migration is a separate host-only command boundary, not a normal
generated `OperationBatch`. It validates the complete migrated graph under the
target schema, records both schema revisions and migration provenance
atomically, and never runs merely because a new registry version is installed.
The initial operation slice implements only fail-closed `SchemaUnavailable`;
migration authoring remains deferred.

## Inverse algebra and undo

Pure batch application captures the before-images required to derive an
internal inverse batch:

| Forward primitive | Internal inverse |
| --- | --- |
| `InsertNode` | `RemoveNode` |
| `MoveNode` | `MoveNode` to the previous parent and placement |
| `SetProperty` on an existing property | `SetProperty` with the previous value |
| `SetProperty` on an absent property | `RemoveProperty` |
| `RemoveProperty` | `SetProperty` with the removed value |
| `RemoveNode` | `RestoreSubtree` with the complete validated before-image |

The inverse of a batch applies primitive inverses in reverse order.
`RestoreSubtree` is internal because it carries trusted before-images and may
resurrect semantic IDs that generated callers must never mint or reuse.

Undo never rewinds graph revision or edits applied history. It submits the
inverse as a new request at the current base revision, passes current policy
and schema validation, and may be rejected if intervening changes invalidate
its preconditions. The private core need not expose undo, but any product
adapter that permits generated commits must provide a user-visible reversal
path. The exact history retention and interaction design remain later choices.

## Draft, rewrite, and renderer transitions

State changes follow a reducer-shaped boundary:

```text
DocumentState + DocumentEvent → DocumentState + Decision
```

The functional core decides transitions and emits commands. The shell performs
persistence, parsing, source rewriting, rendering, clocks, and provider I/O,
then reports their results as new events.

The required transition behavior is:

1. **Draft edited:** preserve the exact source, advance `DraftRevision`, and
   request parse/lowering. Committed meaning does not change.
2. **Parse or lowering failed:** retain diagnostics and enter drafting state.
   The last committed graph remains current.
3. **Text lowering found no semantic delta:** retain the new lossless syntax
   complement and mark it semantically synchronized without creating a request
   or advancing graph revision.
4. **Text lowering produced semantics:** resolve source-local handles to
   existing semantic IDs or request-local new-node handles, then produce one
   batch tied to the exact draft and graph revisions. If either base is stale
   at commit time, reject and re-lower.
5. **Semantic batch committed:** atomically advance the graph and enqueue
   source-rewrite and render effects.
6. **Text-origin commit:** if the committed batch describes the still-current
   draft, mark the draft synchronized without rewriting it.
7. **Projection- or agent-origin commit:** rewrite source only when the draft
   revision, rewrite-eligible status, and source semantic baseline all match
   the effect preconditions. Otherwise the draft is preserved byte-for-byte
   and enters `RewriteConflict`; the committed graph is not rolled back.
8. **Renderer applied:** advance only that renderer's baseline.
9. **Renderer failed:** retain committed meaning, mark that renderer dirty, and
   repair from the committed graph.

A host policy may defer projection or agent commits while a draft is dirty, but
the engine's safety rule is stronger: even when such a commit is allowed, it
must never overwrite a diverged draft. Temporary disagreement is explicit
state, not silent loss and not corruption.

## Identity scopes

The following identities must not be confused:

| Scope | Owner | Stability |
| --- | --- | --- |
| Source-local handle | draft source / CST | One source instance; renameable and rewriteable. |
| Request-local new-node handle | one `UiOperationRequested` | Exists only while validating one batch. |
| Current Canopy projection `NodeId` | session projection ([ProjNode](../../core/proj_node.mbt), [ProjectionMemo](../../core/projection_memo.mbt)) | Session-local projection continuity. |
| `UiNodeId` | Generative UI document | Stable within one logical document and its full-state restore. |
| Renderer node ID | one renderer/session registry | Adapter-local. |
| `DocumentId` | persistence/host boundary | Distinguishes restore from import, clone, or fork. |

A semantic identity is the pair `(DocumentId, UiNodeId)`. The deterministic
derivation of `UiNodeId` from `(DocumentId, RequestId, insertion ordinal)`
means retries produce the same allocation without exposing the derivation to
generated input. Derived IDs are recorded even if later operations in the same
committed batch remove the new node, and IDs are never reused within one
document history. A no-op request namespace remains reserved by its
`RequestId`. The serialized and hash representation is private and
collision-checked.

Full-state restore preserves `DocumentId` and `UiNodeId`. Plain-text import
creates a new `DocumentId` and fresh semantic IDs; it does not claim identity
continuity. Clone or fork creates a new `DocumentId`, even if an implementation
preserves local node labels for diagnostics.

`UiNodeId` is internal to `GenerativeUiDocument`. It is not a new public stable
entity ID for existing Canopy languages and must not be backed by projection
`NodeId`. Its representation remains private so a future collaborative version
can compose with `event-graph-walker` tree identity rather than maintain a
second causal identity system.

The existing `data-node-id` reservation
([JSX DOM patch contract](../decisions/2026-07-13-jsx-dom-patch-contract.md))
is separate evidence that renderer identity is adapter-owned; it does not
establish semantic identity.

## Persistence and recovery invariants

A semantic commit durably groups:

- the next graph or checkpoint/delta reference;
- next graph revision, pinned schema revision, and canonical schema descriptor
  digest;
- the complete validated `AppliedUiOperation` batch, resolved new-node ID
  allocations, and provenance;
- the request ID, canonical request content (or an equality-preserving canonical
  representation), canonical digest, and terminal outcome; replay compares
  canonical content, not digest equality;
- the source-rewrite and renderer outbox entries.

After a crash, recovery loads the latest valid checkpoint and replays a
contiguous applied-history suffix. Every replay step must match its base graph
and schema revisions and produce the recorded next revision. The reconstructed
graph must equal the stored checkpoint at the same revision. The restored
schema descriptor must match the pinned revision and digest. A gap, canonical-
content or digest mismatch, unavailable or changed schema, or replay mismatch fails closed
into diagnostic read-only state; recovery must not guess a graph.

Each outbox entry carries conceptual effect metadata: an `EffectId`, target,
base graph revision, target graph revision, a graph hash or snapshot
reference, and an optional expected draft revision or status. Delivery is
at-least-once, so source and renderer adapters must be idempotent against
their recorded effect IDs and baselines. Redelivery cannot create another
semantic commit.

Renderer rule: dirty state takes precedence over stale acknowledgment and
rebuilds from the latest committed snapshot. When the renderer is clean, a
target revision at or below its baseline is stale and treated as an
acknowledgment; a base equal to the baseline may apply; a gap rebuilds from
the latest committed snapshot and never applies an older delta. Source rewrite rule: a source effect requires a
matching draft revision, valid and rewrite-eligible draft state, and a
matching source semantic baseline; otherwise the source is preserved and the
effect enters `RewriteConflict`. Gaps are coalesced to the latest committed
snapshot and its canonical source rather than replaying stale intermediate
patches. Observed state remains monotonic.

Checkpoint cadence, compaction format, and storage backend remain
implementation decisions. Their representations may vary; the atomicity,
replay, and fail-closed rules may not.

The initial applied history is a single-writer transaction/audit log. It must
not acquire ad hoc causal merge semantics. If collaborative semantic editing is
introduced, `event-graph-walker` owns causal history, tree CRDT semantics,
sync, and undo; this layer must adapt to those APIs rather than compete with
them ([Stable Document Entity Graph](stable-document-entity-graph.md)).

## Concurrency policy

The initial document engine serializes semantic requests. A request with a
stale graph or schema revision is rejected; it is not automatically rebased.
Text edits may continue in draft state, but only an exact draft revision can
produce a text-derived commit.

This is a strict optimistic-concurrency policy, not a semantic CRDT merge
claim. Identity-relative placement reduces accidental index coupling but does
not itself provide concurrent ordering semantics.

## Existing implementation to reuse

| Concern | Source |
| --- | --- |
| Request lifecycle and generation rules | [GenerativeUiLifecycle](../../lib/cognition/generative_ui.mbt) |
| Fail-closed candidate and capability validation | [GenerativeUiCandidate](../../lib/cognition/generative_ui_candidate.mbt) |
| JSX adapter preflight, DOM apply, dirty recovery | [JSX DOM patch contract](../decisions/2026-07-13-jsx-dom-patch-contract.md); [render_baseline](../../ffi/jsx/render_baseline.mbt) |
| Lossless parser and CST | [Loom](../../loom/) |
| Projection, ViewNode, ViewPatch adapters | [Responsibility Map](../architecture/responsibility-map.md); [ProjNode](../../core/proj_node.mbt) |
| Future CRDT semantics | `event-graph-walker` (submodule) |

## Existing implementation not to freeze into the core

Current adapter behavior remains local to its adapter and must not become
permanent core semantics:

- Whole-candidate synthetic JSX lowering
  ([generative_ui_adapter](../../ffi/jsx/generative_ui_adapter.mbt)).
- Candidate-always-remount behavior
  ([render_baseline](../../ffi/jsx/render_baseline.mbt)).
- Session-local and synthetic node IDs.
- `DomPatch` as renderer-neutral semantics. It is a JSX session boundary, not
  a universal patch contract.
- Normalized JSX `Renderable::unparse` output as a lossless or byte-faithful
  writer ([JSX proj_traits](../../loom/examples/jsx/proj_traits.mbt)).
- Table, filter, and summary candidate variants as generic core. They are
  first-slice adapter content.

## Execution and trust boundary

The `js_engine` supports persistent interpreter state, JSON calls, explicit
queues, and advanced host objects. Its stable embedding documentation states that it is
not a security sandbox (js_engine `docs/EMBEDDING.md`,
`docs/design/embedded-runtime-vision.md`).

An agent adapter may submit only a decoded proposal body. Boundary decoding
makes a bounded immutable copy; no callback, source handle, semantic graph
reference, renderer registry, DOM object, or host object crosses with it. The
host constructs `UiOperationRequested` and attaches its request ID, actor,
schema, generation, authority, and approval facts rather than trusting
agent-supplied claims.

Arbitrary agent-generated orchestration code remains gated on deterministic
execution budgets, interruption, re-entry rules, disposal/generation tokens,
async-host completion lifetime, and a killable Wasm or process boundary if
hostile code is claimed safe. The operation slice proves the structured request
boundary without executing arbitrary agent-generated JavaScript.

Trusted host chrome and approval UI use a separate root, component registry,
and authority domain from the generated surface. The current JSX contract
reserves `data-node-id` and keeps expression spans inert. Those controls
constrain adapter injection, but they do not establish the full structural
separation required by the document engine.

## Text adapter

A temporary text adapter is permitted: newline-committed, flat declarations
with explicit parent and placement, plus a lossless per-record complement. It
is not the final language. JSX remains an adapter and import surface; JSON
Lines remains only a possible wire format.

For snapshot-style text, a syntactically complete newline-terminated declaration
prefix must retain the same lowered meaning when an incomplete suffix is
appended. This snapshot-prefix rule does not apply to append-only operation
streams whose later records intentionally move, update, or remove earlier
nodes.

## Staged direction

1. Preserve the existing structured-candidate lifecycle and JSX session as the
   validated V1 adapter baseline.
2. Introduce the renderer-independent semantic graph, forward batch algebra,
   reducer transitions, persistence boundary, and structured request envelope.
3. Add the temporary text adapter and projection/agent request adapters; prove
   rewrite-conflict behavior without arbitrary JavaScript execution.
4. Add a materially different renderer and validate shared graph, identity,
   state-preservation, and capability invariants.
5. Only then consider a public renderer-neutral contract or collaborative
   semantic editing.

The private core may test step 2 as a discardable falsification experiment. It
must not add product or adapter behavior before the personal-knowledge fixed
baseline and existing V1 gates pass, and it cannot freeze a renderer-neutral
contract before the use-case and second-adapter evidence above.

## Proof obligations

Deterministic unit, property, replay, and boundary tests must establish each
obligation before the corresponding behavior is claimed safe:

- Only the semantic transaction boundary advances committed meaning.
- A failed primitive rejects the whole batch; no prefix is observable.
- One successful batch advances graph revision once; a semantic no-op does not.
- `RemoveProperty` is distinguishable from assigning `null`.
- Duplicate request delivery with equal canonical content and a matching stored
  digest cannot apply a batch twice; canonical-content/digest mismatch fails
  closed.
- Request-local handles resolve once to the recorded semantic IDs and cannot
  mint or reuse durable IDs.
- Derived inverse batches restore the prior graph when their preconditions
  still hold.
- Syntax-only edits preserve committed meaning and graph revision.
- Invalid or concurrently changed draft text is never overwritten by a source
  rewrite.
- Renderer failure cannot roll back or advance semantic meaning.
- Checkpoint replay reconstructs exactly the committed graph and fails closed
  on gaps, mismatches, or an unavailable or changed schema descriptor.
- Persisted `NoSemanticChange` and `Rejected` records survive restart and retry
  without creating graph revisions, applied history, or outbox entries.
- Projection and renderer IDs cannot be observed as durable semantic identity.
- Stale graph, schema, and text-derived draft revisions are rejected.
- Generated input cannot obtain host chrome, callbacks, runtime binding values,
  DOM handles, or component-registration authority.
- The host trust boundary is structural rather than policy-only.
- Every host-constructed request persists its terminal `RequestRecord` before
  the response is sent.
- Canonical-equivalent transport inputs produce identical digests regardless of
  key order, whitespace, or transport encoding.
- An equal-digest, different-content collision is rejected without mutation and
  does not alter the existing `RequestRecord`, committed graph, applied history,
  or effect outbox.
- A `SchemaRevision` change is semantic even when the node graph is otherwise
  identical.
- Arbitrary duplicated or out-of-order effect delivery converges monotonically;
  dirty repair takes precedence over stale acknowledgment, and stale
  intermediate patches are never applied.
- Stale source rewrite effects never overwrite a diverged draft.
- Deterministic node identity produces the same mapping on retry and different
  mappings for distinct request-ordinal pairs.

### Falsifiable validation gate

Before production source, renderer, persistence, or JavaScript integration, a
private semantic core must pass one deterministic transcript:

1. Preserve an invalid human draft while keeping the last committed graph.
2. Apply one duplicated host-constructed agent request exactly once.
3. Reject its stale source rewrite as `RewriteConflict` without changing draft
   bytes.
4. Converge a failed renderer after duplicate, stale, and out-of-order effects
   without regressing its baseline.
5. Restart from checkpoint, history, request records, and outbox with the same
   graph, schema revision, semantic IDs, draft bytes, and terminal outcome.

The [Semantic-core validation plan](../plans/2026-07-16-incremental-generative-ui-semantic-core-validation.md)
defines the reference model, observation oracle, fault injection, generated
traces, and evidence mapping. The gate covers only obligations observable in the
private core and fake shell. It does not establish adapter isolation, host trust,
hostile-JavaScript safety, collaboration, agency, accessibility, or product
value. It cannot authorize PKE semantic candidates before that direction's
fixed deterministic baseline is accepted. Product claims remain subject to the [Human-centered product principles](../architecture/human-centered-product-principles.md)
gates for agency and contestability, inclusion and cognitive steady state, and
net value against fixed alternatives; the other boundaries require their own
validation.

Collection, tree, replay, and state-machine laws require unit and property
tests. `moon prove` is optional and limited to small scalar decision functions
that compile under the documented prover constraints. Failure of the fixed
transcript requires revising or rejecting this document-engine direction before
adapter work begins.

## Deferred decisions

- Storage backend, checkpoint cadence, compaction, and retention sizing.
- The approval and preview interaction layered over the required
  user-authorized, revocable policy.
- The host migration authoring API beyond the fail-closed schema rules above.
- The user-visible reversal interaction and which historical transactions
  remain undoable.
- When or whether the text adapter becomes a first-class language.
- When or whether to promote the operation vocabulary to a public API.
- The exact mapping to `event-graph-walker` if collaborative semantic editing
  is introduced.
- The second-renderer conformance contract.
