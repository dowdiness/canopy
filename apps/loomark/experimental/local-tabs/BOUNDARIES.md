# Local tabs Worker trial — boundary and reuse record

Explicit `?local-tabs-worker=1` enters a Text-only experimental page from the
real Loomark app entry, before normal repository/account initialization. It
uses Loomark's MarkdownEditor/TextArea/TextChange and styles. Normal app,
Source/DocumentReplica schema, account enrollment and cloud sync are unchanged.

| Boundary | Required regression |
|---|---|
| First open / 100k restore | Atomic seed, fresh writer; readonly until ready; no EGW on main |
| Local edit / delayed remote offer | Preserve every optimistic input; reject offer on local revision or composition mismatch |
| Japanese composition | Freeze remote DOM; commit original displayed basis; terminal input clears fence |
| Save R while typing R+1 | Only exact packet transaction completion removes that packet; never clear newer dirty |
| Worker dies before edit response | Retain native intent; no save authorized before main retains immutable packet |
| Worker dies before/during/after save | Replay durable union and retained packets; same operation IDs, exactly once |
| A→B→A / late response | Worker epoch, request ID and document identity fence all responses |
| Close/reload | Only committed union advertised Saved; pending text stays exportable and unload guarded |
| Duplicate/reordered hints | Hints carry no operations; poll IDB, validate original whole packets |
| Undo/Redo | Record only local edits; known concurrent-delete revival unchanged; restart clears Undo explicitly |
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

The Worker keeps an editing replica matching the main display's accepted basis
and a merged replica admitting durable remote packets. Main accepts a remote
offer only without intervening input; then Worker advances the editing replica.
Optimistic edits always execute on their original basis. Both replicas stay in
the Worker after restore. Double restore/memory overhead is measured, not hidden.
On Worker recovery, main retains the last accepted Version, uncommitted packets
and unaccepted native intents. It does not recreate EGW on the main thread.
