# Local tabs Worker trial — boundary and reuse record

Explicit `?local-tabs-worker=1` enters a Text-only experimental page from the
real Loomark app entry, before normal repository/account initialization. It
uses Loomark's MarkdownEditor/TextArea/TextChange and styles. Normal app,
Source/DocumentReplica schema, account enrollment and cloud sync are unchanged.

| Boundary | Required regression |
|---|---|
| First open / 100k restore | Atomic seed, fresh writer; readonly until ready; no EGW on main |
| Local edit / delayed remote offer | Preserve every optimistic input; reject offer on local revision or composition mismatch |
| Japanese composition | Freeze remote DOM; retain terminal input and original displayed basis through Worker recovery or blocked save; Retry persists it |
| Save R while typing R+1 | Only exact packet transaction completion removes that packet; never clear newer dirty |
| Worker dies before edit response | Retain native intent; no save authorized before main retains immutable packet |
| Worker dies before/during/after save | Replay durable union and retained packets; same operation IDs, exactly once |
| Long replay / silent Worker exit | Whole-packet progress renews only the matched watchdog; 120k catch-up completes without false restart; real silence recovers the identical packet |
| A→B→A / late response | Worker epoch, request ID and document identity fence all responses |
| Close/reload | Only committed union advertised Saved; pending text stays exportable and unload guarded |
| Duplicate/reordered hints | Hints carry no operations; poll IDB, validate original whole packets |
| Undo/Redo | One group per native intent, including separated ReplaceAll hunks; only local edits recorded; known concurrent-delete revival unchanged; restart clears Undo explicitly |
| Resource failure | Keep native draft and packets, show not saved, never slice admission or evict history |
| Disposal | Actual Rabbita local subscription terminates Worker/listeners, rejects callbacks |

Reference: Canopy #1421 at af1859e004a05df5cabb78be5a0ca43b252e3592,
worker_transport.mbt (epoch/request fences, errors, timeout, disposal),
worker_client.mbt (generation/sequence admission), worker regression/lifecycle
tests. No whole-branch merge. Preview's latest-only work dropping is NOT reused:
every local intent and accepted operation packet remains queued until ack.

Reuse: existing public EGW TextState/SyncSession/apply_transition/UndoManager,
existing local-tabs proof-of-concept immutable IDB journal and pure UTF16/
selection helpers; real MarkdownEditor input_view/admit; Rabbita after_render
command and Local subscription cleanup. Worker owns mutable EGW and IDB effects;
pure protocol admission and selection transformations are separately tested.

The MoonBit Worker calls `UndoManager::stop_capturing()` once before applying
a native intent's prepared replacements. EGW's existing timestamp-based capture
groups that intent's hunks; no public EGW API or submodule change is needed.
Binding-admitted input is retained independently of the Worker's execution
gate; read-only UI prevents new edits without discarding an in-flight commit.

The Worker keeps an editing replica matching the main display's accepted basis
and a merged replica admitting durable remote packets. Main accepts a remote
offer only without intervening input; then Worker advances the editing replica.
Optimistic edits always execute on their original basis. Both replicas stay in
the Worker after restore. Double restore/memory overhead is measured, not hidden.
On Worker recovery, main retains the last accepted Version, uncommitted packets
and unaccepted native intents. It does not recreate EGW on the main thread.

The compiled `engine/main` now owns FIFO dispatch and typed request/session,
packet, offer and duplicate-result data. EGW `Version` values stay typed when
exporting a local delta; only the actual journal/thread contract encodes them.
`SyncMessage` values are reused across the editing and merged replicas rather
than crossing an internal JSON facade for each EGW call.

The native adapter reuses Rabbita `js.Promise`, checked `js.Error_` conversion,
`js.Object` and `js.JsArray` for browser/storage boundaries. Wire objects are
constructed explicitly, including the approximate-selection array attribute;
MoonBit record layouts are not sent to JavaScript consumers. Core `String.iter`
counts Unicode scalars without a temporary character array, and the established
`core.mjs` alignment/scalar helpers and `store.mjs` journal policy remain shared.
Mutation is confined to Worker-owned replicas, FIFO/session state and I/O.

Rabbita's generic Worker request envelope is not used in this step: retaining
the existing wire lets the Worker migrate without creating a second main-thread
controller beside `client.mjs`. Main-controller ownership is a separate change.
