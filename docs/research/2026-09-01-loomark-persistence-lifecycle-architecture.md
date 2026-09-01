# Loomark persistence lifecycle architecture survey

**Date:** 2026-09-01

**Status:** Research — not an implementation proposal

## Question

What is the deepest practical module for Loomark's multi-document persistence
lifecycle, and what is the minimum identity needed to reject stale timers and
storage acknowledgments without introducing a generic request framework?

This survey rechecks the design against:

- the working-tree accepted decision
  [Loomark document deletion](../decisions/2026-08-31-loomark-document-deletion.md);
- current and historical Loomark implementations;
- Rabbita's authoritative command and IndexedDB implementations;
- the IndexedDB transaction-scheduling specification;
- OpenSeek's immutable state and durable-store patterns; and
- established async state-machine alternatives.

## Fixed constraints

The working-tree deletion decision fixes the following behavior. This survey
does not reopen it.

1. A persisted Source contains Document identity, exact Saved text, and Change
   order.
2. Change order is assigned when Document text changes. Browser time is an
   input, but a per-tab monotonic floor seeded above the loaded maximum makes
   each assigned value fresh within the page lifetime. It is ordering data, not
   a trustworthy cross-tab clock.
3. An empty repository is valid. A New document is ephemeral, reserves an
   identity without writing Browser storage, and is promoted on its first text
   change.
4. The Application Model owns pure per-document persistence lanes. Operations
   for one Document ID are ordered; unrelated Document IDs are not blocked by
   application policy.
5. A confirmed Delete waits for an already-running Autosave for the same
   target, then becomes terminal for that lane.
6. Repository effects return acknowledged document changes, not replacement
   RepositorySnapshots. The reducer applies each acknowledgment to its latest
   immutable Snapshot.
7. Delete has an identity separate from editor Activation. Missing
   acknowledgment starts a bounded Browser storage probe; elapsed time alone
   proves neither success nor failure.
8. Activation identifies the current TextArea/Preview ownership. It must not
   suppress persistence completion for a document that is no longer selected.
9. Uncoordinated tabs remain last-completion-wins and may recreate a deleted
   record.
10. The Text input task updates Document text and in-memory Change order only.
    Serialization, list-content preparation, and IndexedDB stay outside it.

Sources:

- `apps/loomark/CONTEXT.md`
- `docs/decisions/2026-08-24-loomark-source-first-interactive-contract.md`
- `docs/decisions/2026-08-25-loomark-textarea-edit-boundary.md`
- `docs/decisions/2026-08-31-loomark-document-deletion.md`

## Relevant implementations

### Merged quiescent Delete is deliberately too small for the new contract

Commit `d75add0159b3e42a9a3547624e91ade9e50a465b` on `origin/main` implements
a deliberately quiescent Delete. It allows one repository operation, blocks
switching until the active document is Saved, returns a replacement Snapshot,
refuses deleting the final Source, and has no watchdog or probe. Its accepted
decision explicitly rejected per-document lanes for that smaller product.

The working-tree deletion decision supersedes those assumptions. The merged
implementation is useful as the deletion test's shallow baseline, not as the
new architecture.

### The unmerged coordinator demonstrates the locality failure

The local branch `feat/loomark-delete-document` at
`a5f48a3aab625165c7aa94215d232724d59e5eec` explored the larger contract. It
contains:

- a 449-line `PersistenceCoordinator`;
- a 921-line application `update`;
- generic lane generation and request IDs;
- separate `SaveState`, coordinator lane state, `DocumentDeletion`, and
  `delete_recovery_save`; and
- app code that interprets coordinator outcomes and constructs the next
  command.

The coordinator correctly proves single-flight saves, latest-value coalescing,
cross-document acknowledgment reordering, Delete-after-Save, and probe
recovery. But the interface exposes the protocol as separate methods:
enqueue/complete save, enqueue/complete Delete, begin/complete/expire probe.
The application must know their legal order and mirror their state for UI.
Follow-up commit `a5f48a3a` had to add `delete_recovery_save` to restore
application durability state when deletion failed. That is direct evidence of
poor locality: the persistence truth existed in two modules.

Deletion test: removing the coordinator would move lane ordering into the app;
removing the app's mirrored persistence states would move presentation and
recovery decisions into the coordinator. The right move is not either deletion
alone. The cluster should collapse behind one reducer interface.

### Historical queue proves latest-value coalescing

Commit `8b792bf495000549aa0f9664871a2c8a3da7dec9` used
`LocalArchivePersistenceQueue` with one in-flight write, one replaceable latest
pending write, request identity, queue epoch, document identity, and an opaque
document version. The evidence in
`docs/evidence/2026-08-24-loomark-persistence-intent-coalescing.md` verifies:

- A→B→A fencing;
- stale-completion rejection;
- latest-value promotion after either success or failure;
- retry;
- queue-lifetime fencing; and
- materialization only after an intent becomes selected.

The shape “one in flight plus latest pending” remains valuable. Its entire
identity set does not.

The old queue allowed different LocalText payloads to share one opaque document
version, replaced a selected-document queue across activations, and supported
heterogeneous FullHistory and LocalText payloads. Those facts justified a
request ID and queue epoch. The new contract assigns a fresh Change order to
every Document text change and retains one lane per Document across switches.
It has one Source record shape. Request ID and queue epoch no longer remove any
caller knowledge.

## Rabbita and IndexedDB findings

Rabbita's command model is TEA-shaped: a pure update returns managed Cmd values,
and asynchronous results return as later messages. Models hold values, not
commands, callbacks, or mutable browser handles.

Authoritative sources:

- `deps/rabbita/skills/rabbita.md`
- `deps/rabbita/doc/001_intro/readme.mbt.md`
- `deps/rabbita/doc/004_using_command/readme.mbt.md`
- `deps/rabbita/rabbita/indexed_db/README.mbt.md`
- `deps/rabbita/rabbita/indexed_db/provider.mbt`

The current checked-out Rabbita provider serializes commands per Config. That
implementation cannot support the working-tree watchdog design: if a committed
Delete's acknowledgment is withheld, the provider remains draining and queues
the probe behind it.

Rabbita commit `96445ed16092b3eb91c1fd8205012695245c866f` fixes that mismatch. It
admits queued transactions in invocation order without waiting for earlier
completion callbacks. IndexedDB then schedules overlapping transaction scopes.
A focused test commits a Delete while withholding its application callback,
admits a later readonly probe, and observes the record as missing before the
Delete callback is released.

Source:
[moonbit-community/rabbita-compatible fork commit 96445ed](https://github.com/dowdiness/rabbita/commit/96445ed16092b3eb91c1fd8205012695245c866f),
reachable from branch `prototype/indexeddb-concurrent-admission` and stable tag
`canopy-loomark-indexeddb-concurrent-admission-20260901`.

The provider still guarantees one callback per admitted operation through its
local `completed` guard, and reports Stored only from the transaction complete
event. It provides no replay and no external cancellation of an admitted
transaction. The design may therefore trust exactly-once completion delivery
within one mounted application. If that adapter contract changes or a second
adapter with duplicate delivery is introduced, save-attempt identity must be
reassessed.

The IndexedDB specification confirms that read/write transactions with
overlapping object-store scopes are scheduled in creation order. Transaction
admission independence therefore removes provider-created acknowledgment
head-of-line blocking; it does not promise simultaneous physical writes.

Source:
[IndexedDB §2.7.2 Transaction scheduling](https://w3c.github.io/IndexedDB/#transaction-scheduling).

## OpenSeek findings

OpenSeek is useful as design precedent, not as a persistence implementation to
copy.

At revision `ae9dedfcbc72cd9b3e6e8e35a2e660212c6e1a05`:

- `Session::append_event` returns a new immutable Session and its assigned,
  contiguous SessionEvent;
- `SessionStore::append` performs filesystem effects and rejects a stale
  immutable Session before writing;
- tool results correlate with a tool-call ID;
- subtask lifecycle records combine a nonce with explicit states; and
- independent sessions use per-session storage locks.

Sources:

- [agent_session/types.mbt](https://github.com/moonbitlang/openseek/blob/ae9dedfcbc72cd9b3e6e8e35a2e660212c6e1a05/agent_session/types.mbt)
- [agent_session/store/store.mbt](https://github.com/moonbitlang/openseek/blob/ae9dedfcbc72cd9b3e6e8e35a2e660212c6e1a05/agent_session/store/store.mbt)
- [subtask registry](https://github.com/moonbitlang/openseek/blob/ae9dedfcbc72cd9b3e6e8e35a2e660212c6e1a05/cmd/openseek/internal/subtask/registry.mbt)

The transferable principles are immutable next state, explicit lifecycle
variants, entity-scoped ordering, and domain-specific correlation. OpenSeek does
not use one universal attempt identity across session append, tool call, and
subtask lifecycle. Its filesystem fingerprints and locks solve cross-process
consistency that Loomark explicitly excludes; they should not be copied.

## Alternatives

| Architecture | Depth and locality | Verdict |
|---|---|---|
| Quiescent global reducer | Small, but blocks Document switch and cannot represent independent inactive saves or Unknown deletion outcome | Reject for the accepted contract |
| Separate coordinator plus mirrored app state | Proves lane ordering, but exposes protocol and duplicates durability/deletion state | Replace, do not layer |
| Generic AttemptId on every effect | Uniform-looking, but save still needs Change order, Delete still needs phase, and timers still need their own freshness | Reject |
| Per-document actors | Gives isolation, but introduces mutable lifecycle owners and another effect system beside Rabbita | Reject |
| Event-sourced persistence core | Adds replay, compaction, and unbounded history that ordinary local recovery explicitly excludes | Reject |
| Snapshot/CAS across tabs | Solves a conflict the product accepts; adds read-modify-write and conflict UI | Reject |
| Cancellation/takeLatest | Cannot cancel an admitted IndexedDB transaction and would discard the required Save-before-Delete barrier | Reject |
| Pure Documents aggregate with private lanes | One interface owns text authority, lane policy, acknowledged deltas, and recovery; shell remains thin | Recommend |

Redux Toolkit's official `createAsyncThunk` documentation demonstrates unique
request IDs and a `currentRequestId` guard for overlapping requests. XState
uses invoked-actor and delayed-event IDs tied to explicit lifecycle states.
These are useful when multiple same-shaped operations may overlap or be
cancelled. Loomark deliberately permits only one save per Document lane, and
its existing Change order already identifies the source candidate. A generic
request ID would be redundant rather than protective under the Rabbita adapter
contract.

Sources:

- [Redux Toolkit createAsyncThunk](https://redux-toolkit.js.org/api/createAsyncThunk)
- [XState invoke](https://stately.ai/docs/invoke)
- [XState delayed events](https://stately.ai/docs/delayed-transitions)

## Recommended deep module

### Module and seam

Create one package-private **Documents module**. Its external seam is one
reducer-shaped interface:

```text
Documents + DocumentsEvent -> (Documents, Array[DocumentsDecision])
```

The exact MoonBit interface is intentionally not designed in this research
note. The important constraint is one transition entry rather than separate
protocol methods. Query methods expose only read-only product views needed by
the app: selected identity/text, Recent documents data, save/delete status, and
whether an action is currently permitted.

The module's implementation owns:

- every current Document text;
- the per-tab Change order floor and current Change order per Document;
- the latest immutable RepositorySnapshot;
- one private persistence lane per Document;
- New document identity reservation and first-change promotion;
- one in-flight save and one replaceable latest candidate per lane;
- quiet/max Autosave policy;
- Save-before-Delete ordering;
- acknowledged-delta application;
- Delete watchdog, probe, Unknown outcome, and late resolution; and
- the product statuses from which UI is derived.

The module does not own TextArea/DOM behavior, Preview, IndexedDB, clocks,
random UUID generation, modal interaction, or command execution. Those remain
in the imperative shell. Clock and UUID results enter as values in events.

### Active/inactive representation

A naïve immutable `Map[DocumentId, Document]` copy on every keystroke would put
document-count work on the Text input path. Keep the active Document directly
in Documents and keep inactive Documents in a private collection keyed by
Document ID. Text input then replaces only the active value. A Document switch
performs the active/inactive exchange, where O(number of documents) work is
acceptable if the chosen MoonBit collection requires copying.

This zipper-like representation is an implementation detail, not a second text
authority and not part of the interface. Internal collections must not escape;
return ArrayView values or defensive copies as appropriate.

Before implementation, compare concrete MoonBit core candidates with `moon ide`
in the synced implementation worktree: Map for keyed inactive state, Set for
occupied identities, Array/ArrayView for stable read-only projections,
String/StringView for non-copying name inputs, and Option/Result for explicit
absence/failure. The current checkout's `moon ide outline` cannot resolve the
Loomark package while the working tree and base are out of sync, so no API
choice is claimed here.

### Shell decisions

Documents returns concrete decisions rather than an injected storage port:

- observe browser time or allocate a UUID;
- arm a quiet or maximum timer;
- store one validated Source;
- delete one known Source; and
- probe one Delete target.

The Rabbita shell converts those values to existing high-level `@cmd` and
`@indexed_db` commands. Command and timer outcomes return a typed
`DocumentsFeedback`; synchronous Text, composition, retry, and consent intents
cannot enter that feedback path. The parent wraps feedback once, reduces it in
both Editing and PreparingNew, and repairs the active Document invariant only
in Editing. There is one production adapter, so adding a trait would create a
hypothetical seam. Tests call the pure reducer directly and inspect its
decisions.

`source_repository` should remain the browser-storage adapter. It performs
encoding/decoding, schema validation, key validation, IndexedDB command
construction, scanning, and corruption isolation. Save/Delete completions carry
acknowledged deltas, never a precomputed replacement Snapshot. Whether the
adapter accepts an opaque known-Document token or independently rechecks a
Snapshot is an interface-design question for the next phase; unknown IDs must
still fail before IndexedDB work.

## Minimal identities

| Concern | Required identity | Why |
|---|---|---|
| Document lane and persisted record | Document ID | Stable product identity |
| Text change, quiet timer, save candidate, save acknowledgment | Change order | Fresh on every text change; distinguishes byte-identical A→B→A text |
| Continuous-input maximum timer | Checkpoint ID | Survives multiple Change orders in one dirty interval; rejects an old maximum timer after a later checkpoint |
| Delete result, acknowledgment watchdog, probe, probe timeout, late resolution | Delete request ID plus expected phase | Distinguishes retries and makes one lifecycle explicit |
| TextArea and Preview ownership | Activation | UI only; not a persistence fence |

No SaveAttemptId is required under the current adapter contract:

- the lane admits only one save;
- retry starts only after that operation's exactly-once failure callback has
  settled it;
- retrying unchanged text keeps the same Change order;
- a completion is accepted only when its exact Source matches the lane's
  in-flight candidate; and
- after settlement, a repeated message no longer matches an in-flight state.

The third point is important: **retry does not mint a Change order**. Change
order changes only with Document text. Correctness here relies on Rabbita's
exactly-once completion/no-replay contract. If duplicate delivery becomes a
real adapter behavior, add a save-attempt identity then; do not prepay for it.

No ProbeId is required if one Delete request may start at most one probe. The
Delete request ID plus `Deleting | Probing | Unknown | Confirmed | Failed`
phase rejects stale probe/watchdog events. If the product later permits repeated
probes for one Delete request, a probe identity becomes real at that point.

No lane generation or queue epoch is required. Lanes survive Document switch,
Document IDs are not reused within the page, and callbacks cannot survive a
full page reload.

## Failure matrix

| Scenario | Transition rule |
|---|---|
| A→B→A text | Each accepted text change gets a fresh Change order; an older Source acknowledgment cannot equal the in-flight candidate |
| Save active, newer text arrives | Replace only the lane's latest pending candidate; do not encode it yet |
| Active save succeeds or fails | Apply success delta if valid, then promote the latest pending candidate; failure never prevents promotion |
| Retry unchanged failed text | Reuse the Source/Change order; safe because the failed operation has delivered its sole callback before retry |
| Switch before quiet timer | Timer is scoped by Document ID and Change order, not Activation; inactive Document continues toward Autosave |
| Save completes after switch | Update that Document lane and latest Snapshot; do not inspect current Activation |
| Delete confirmed during save | Drop not-yet-started save candidates, wait for the issued save to settle, then issue Delete |
| Delete acknowledgment missing | Matching watchdog moves `Deleting` to `Probing` and admits a Browser storage probe |
| Probe missing | Apply SourceDeleted to the latest Snapshot and confirm Delete |
| Probe present/fails or probe timeout | Enter Unknown without inventing success/failure |
| Late Delete success in Unknown | Confirm and apply deletion once |
| Late Delete failure in Unknown | Restore target availability without changing selected Document |
| Reload | Full scan builds a new aggregate; no in-memory epoch is needed |
| Other tab recreates target | Accepted Uncoordinated-tabs behavior; later full scan reveals durable state |

## Testing strategy

The interface is the test surface.

Replace tests that inspect command debug strings or call coordinator protocol
methods with deterministic reducer tests covering the matrix above. Retain a
small shell suite for decision-to-Rabbita wiring and transaction-result mapping.
Retain production Playwright cases for actual IndexedDB commit, withheld
acknowledgment/probe behavior, switching, reload, and IME.

The historical unmerged coordinator tests are valuable scenario inventory, not
a test suite to layer underneath the new module. Port their observable
behaviors and delete tests that only pin request counters, lane generation, or
private map shape.

## Conclusion

A better design than the earlier generic AttemptId proposal exists.

Use one deep Documents module with a single reducer interface and private
per-document lanes. Keep one in-flight save plus the latest pending candidate.
Use operation-specific identity: Document ID + Change order for text/save,
Checkpoint ID for bounded Autosave, and Delete request ID + phase for the
Delete/probe lifecycle. Keep Activation out of persistence. Apply acknowledged
deltas to the latest immutable Snapshot. Use Rabbita commit `96445ed` so a
withheld acknowledgment cannot block the recovery probe.

This design has greater depth than both the merged quiescent Delete and the
unmerged multi-method coordinator: callers learn one transition interface,
while ordering, recovery, identity, and Snapshot merge rules gain locality in
one implementation.

## Remaining design questions

1. Should Documents be a new `internal/documents` package, or remain private in
   the app package? A package gives a language-enforced seam but requires a
   deliberately designed MoonBit interface.
2. Should the storage adapter independently revalidate known membership with a
   Snapshot, or accept an opaque validated operation produced only by
   Documents?
3. What exact Change-order exhaustion behavior should prevent further edits or
   saves when the JavaScript-safe integer ceiling is reached?
4. What accepted intervals should the Delete acknowledgment and probe
   watchdogs use?
5. Which read-only projection belongs in Documents versus a separate Recent
   documents presentation module?
