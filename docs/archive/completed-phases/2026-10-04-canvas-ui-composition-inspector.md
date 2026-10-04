# Canvas UI composition and Inspector ownership

**Status:** Complete

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/1454>.
Implementation and local verification completed on 2026-10-04 on
`docs/canvas-ui-inspector-design`; push/PR publication remains pending.
The issue owns publication status. The design below is historical.

Decision record:
[Canvas UI composition and Inspector ownership](../../decisions/2026-10-04-canvas-ui-composition.md).

Initial implementation evidence: 104 MoonBit tests, 57 Chromium E2E tests,
TypeScript checking, and release/production builds passed. Three native-edit
regressions covered draft/caret/cancel behavior, dirty Source rejection, and
same-task focus/Enter. The last failed before synchronous focus-ID allocation
and passed afterward.
Chromium smoke also covered IME, refocus, empty/unchanged edits, library filtering
and unique insertion, and a real terminal-latch fixture. The terminal probe and its
export were removed and the production app rebuilt. Existing visual styling
was preserved. The adopted decision above is the current contract.

Precommit review found that a cancelled Inspector field could retain an old
value after a later canonical Source edit. The fix unpins cancelled sessions
and explicitly synchronizes changed native input properties for inactive
fields, preserving Editing and Submitted drafts. A fourth browser regression
covers cancellation, an incremental Source parameter edit, and another
Inspector edit; the same sequence passed in a manual Chromium smoke.
The 104 MoonBit tests passed after the production fix. Review also removed
five unused JavaScript mutation exports while retaining app-private MoonBit
declarations used by existing domain tests.

Final focused verification passed TypeScript checking, the production build,
and nine Chromium scenarios twice each (18 passes, one worker, no retries).
These cover Inspector behavior plus the existing edge-gesture and overflowed
edge-geometry scenarios. Earlier full-suite runs had an edge-gesture timeout
and a Source-startup timeout; both scenarios passed the final focused run.
The cancellation regression now edits only the numeric Source token so it
preserves node identity rather than replacing the whole document. A clean
58-test full-suite run was not established after review.

## Why

Canvas's TypeScript shell owns Inspector DOM construction, field sessions,
rename/parameter commands, notification forwarding, and the order in which
MoonBit UI roots mount. The graph and Source state already live in MoonBit.
Removing result JSON conversions alone leaves that ownership split intact.

Decision: move application UI composition, the entire `#inspector-node`
subtree, library/search, and keyboard deletion into MoonBit. Keep independent
Rabbita models connected through small, typed receivers owned by the receiving
host. Do not build an event bus, merge all UI state, or rewrite render publication.

Clean-cutover constraint: backward compatibility is not a requirement. The
earlier proposal to retain a TS Source-notice registration callback is withdrawn.
It existed only because library/delete were left in TS, not because the desired
application needs an external notification interface. Move those callers rather
than preserve, rename, or wrap that interface.

## Scope

In:

- One app-private `mount_canvas_ui` entrypoint in `apps/canvas/main`.
- Inspector summary, source-backed binding/numeric parameter fields, field
  sessions, and operation requests.
- Library list/filter behavior and keyboard Delete/Backspace handling, including
  synchronous event admission and source-backed operation requests.
- Typed internal routing among Inspector, library, keyboard input, Source, and
  context menu.
- A shared decode of the existing published render snapshot.
- Removal of replaced TS functions, mount exports, types with no remaining
  consumers, and corresponding interface/caller updates.

Out:

- Validation list, action-stat rendering, action-log inspection shortcut, and
  the RAF loop; these remain TS-owned in this slice.
- Canvas geometry, graph lowering, projection identity, parser recovery,
  GraphOperation serialization, and graph/action-log ownership.
- A render-publisher protocol rewrite, new incr graph, generic command facade,
  application-wide health registry, multi-canvas support, or a new disposal API.
- Visual redesign and performance claims. Code ownership is the objective.

## Current State

Inspected baseline: Canopy `303e52bc46b37fd4e6315e913c809a3595e21060`
(PR #1436 merged). References below describe that revision.

- [TS shell](../../../apps/canvas/web/src/main.ts): `renderInspector`,
  `renderSourceNodeEditor`, `bindCommitOnChange`, `commitSourceRename`,
  `commitSourceParam`, and the individual mount calls in `init`.
- [GraphAdapter](../../../apps/canvas/web/src/graph-adapter.ts): `renameNode`,
  `setNodeParam`, `applyOperation`, `publishRenderState`, action-log delivery.
- [Render layer](../../../apps/canvas/main/canvas_render_layer.mbt): one JSON
  custom-event subscriber, `CanvasRenderLayerSnapshot`, and
  `publish_render_state`. The private snapshot omits Inspector metadata.
- [Runtime](../../../apps/canvas/main/canvas_runtime.mbt): memoized Inspector
  watch with selection-before-hover precedence.
- [Host policy](../../../apps/canvas/main/canvas_host_policy.mbt): source-backed
  render state has no Inspector value. TS currently synthesizes selected-node
  details from the already-published nodes. Source hover remains unsupported.
- [Source owner](../../../apps/canvas/main/source_demo.mbt): notice subscription,
  dirty-text guards, `source_demo_result_step`, terminal `parser_failed` latch.
- [Graph DSL adapter](../../../apps/canvas/main/graph_dsl_adapter.mbt): typed
  `SourceBackedGraph::apply_operation`, numeric value/unit metadata, rename
  selection transfer, and sticky `parser_failure`.
- [Context menu](../../../apps/canvas/main/context_menu.mbt): typed outcomes
  currently stringified and passed to TS solely to reach Source.
- [FFI adapter](../../../adapters/editor/moonbit-result.ts): an exception escaping
  an adapted export invalidates/attempts to destroy an owned handle.
- [Rabbita mount](../../../deps/rabbita/rabbita/top.mbt) creates a BrowserHost per
  root; [subscriptions](../../../deps/rabbita/rabbita/sub/sub.mbt) provide
  `unload` and `update_tagger`. A raw `Emit`/`Cmd` is host-scoped.

## Desired State

### Ownership and external interface

| Owner | Responsibility |
|---|---|
| TS bootstrap | Load CodeMirror/modules; create GraphAdapter/backing; call one UI mount |
| MoonBit composition | Wire roots and private typed receivers; expose no notice registration |
| Inspector model/view | Select presentation; own field sessions and the complete Inspector subtree |
| Library / keyboard input | Own search/list actions and synchronous delete-event admission |
| Source update owner | Execute source-backed Inspector/library/delete requests; own Source status, dirty protection, editor synchronization, terminal failure |
| Graph backing | Validate/lower/apply typed operations; preserve identity; append operations |
| Existing TS shell | RAF publication, validation/action-stat, action-log inspection |

Proposed app-private entrypoint, in descriptive signature notation:

```text
mount_canvas_ui(handle, on_change) -> Unit
```

Resolve runtime/source mode once from the existing backing registry rather than
adding another authoritative mode flag. TS retains its mode choice for backing
creation. `on_change` requests the still-TS-owned render/publication work; it
does not carry an operation result or notification. There is no TS notice
reporter, registration function, or returned command facade.

After cutover, individual `mount_*` implementations become internal helpers.
Remove displaced executable exports, module requirements, and TS adapter methods
after migrating their real callers; do not leave aliases, forwarding wrappers,
deprecated signatures, or dual old/new decoding paths. Keep an export only for
a current consumer, not hypothetical compatibility. Render publication remains
necessary for TS validation/action-stat; context dismissal is internal once its
TS delete caller is removed, unless the reference inventory finds another owner.

Document the executable interface's app-private ownership under issue
[#1341](https://github.com/dowdiness/canopy/issues/1341). That documentation is
not a prerequisite for deleting obsolete app wiring and does not justify a shim.

### DOM ownership

MoonBit exclusively owns the children of `#inspector-node`. TS never clears,
patches, or attaches field listeners inside that subtree after cutover.
`#validation-list`, `#action-stat`, and existing panel chrome stay outside it.
Keep current CSS, IDs used by browser consumers, labels, value/unit separation,
and keyboard accessibility. Runtime Inspector remains read-only; only selected
source-backed nodes expose the editor.

MoonBit also owns `#node-library` children and the `#node-search` input listener.
The search field and panel chrome may remain static HTML; moving their DOM
parents is not required to transfer behavior. Catalog data stays typed in
MoonBit instead of being serialized and decoded in TS. Remove the TS delete
listener branch; the unrelated action-log inspection shortcut may remain.

### Composition, receivers, and lifetime

Keep existing roots; no portal or common parent DOM rewrite is needed.
Composition creates local receiver slots and mounts roots in this order:

1. Inspector: registers its snapshot/completion/terminal receiver.
2. Source toggle and, in source mode, Source panel: registers its private typed
   request/result ingress. CodeMirror readiness is not a prerequisite for
   receiving graph-operation notices.
3. Render layer: receives the Inspector snapshot callback.
4. Library/search, keyboard input, context menu, and pointer session: receive
   existing change callbacks and private Source receivers where applicable.
5. Return to TS; TS performs the existing first `render()`.

Each typed receiver is created by a `custom_sub` loader. It captures that
**receiving host's** scheduler and current tagger, returning `Unit` after queuing
the message there. Never pass a foreign `Emit` or execute another host's `Cmd`
in the caller's host. Keep receivers out of Eq-comparable models.

`update_tagger` rebinds locally. `unload` revokes the receiver, removes its
listeners, and prevents captured callbacks from dispatching to a dead host.
Already-deferred source-sync callbacks must check revocation before dispatch.
Reuse the scheduler-bound subscription mechanism, not the old string/JSON notice
registration protocol. Delete that protocol's decoder, registration payload,
and no-op-unload implementation; private replacement receivers are revocable.
No module-global notice map.

Receiver invocation is an effect, not work performed inside a pure reducer.
Completion is allowed to arrive later or while other messages are queued.
Source settle notifications retain their existing deferred/coalesced delivery:
they fire before the source wrapper finishes updating and cannot be read inline.

This is one composition entrypoint, not one BrowserHost or a new unmount API.
The app still has a page lifetime and fixed roots. Repeated whole-app mounts and
SPA teardown are not promised by this slice. Missing required receiver
registration at startup is a mount error, never a permanent no-op fallback.

### Read path: one decode, two consumers

Keep `publish_render_state`, its returned JSON, custom-event name, and TS
`GraphAdapter.publishRenderState` behavior. The render-layer event loader parses
once and delivers the parsed value to its own model and a typed projection to
Inspector. Change its message from a JSON string to the parsed snapshot; do not
add a second Inspector event listener/parser or read the graph again.

Extend that snapshot with the existing `selected` and `inspector` fields.
Reuse `NodeJson`, `NodeParamJson`, and `InspectorNodeJson`; add decoding support
where needed rather than inventing another transport schema. Decode the current
publisher's actual shape. Do not retain historical optional-value shapes,
fallback decoders, or compatibility tests solely to preserve an old interface.

Inspector projection rules:

1. Use the published runtime Inspector, preserving selection-before-hover.
2. In source mode only, when absent, resolve
   `selected ?? selected_nodes[0]` in the decoded nodes and synthesize the
   current selected-node summary. Parameters come from that `NodeJson`.
3. Otherwise show the current empty-state presentation.

The small Eq projection excludes viewport, positions, edges, and action count.
Unrelated snapshots therefore do not reset field sessions or input DOM. Source
fallback may scan the decoded nodes for the selected ID; it must not rebuild a
graph or allocate a second index just for this lookup. Invalid transport must
not become an empty graph/Inspector or a source-operation success.

### Library and keyboard operation ownership

Library filtering retains trim/case-insensitive label/description matching.
Runtime insertion keeps the existing placement calculation and current-geometry
validation. Source insertion uses the existing typed unique-binding operation,
not a TS-produced AddNode DTO. Preserve edge-selection clearing, status updates,
and once-only operation logging. No second catalog or source-lowering logic.

Keyboard admission runs synchronously in MoonBit's DOM event handler:

- Match Delete/Backspace and current modifier rules.
- Ignore inputs, textarea, select, and editable ancestors, including CodeMirror.
- Read current backing selection, not the last RAF snapshot. Capture the
  selected edge or node IDs in the accepted intent, preserving edge precedence.
- With no target, do not prevent default or create a graph operation.
- With a target, prevent default before returning from the DOM callback and
  dispatch the captured intent. Never wait for an asynchronous completion to
  cancel a browser default, and never retarget to a later selection.

Runtime requests use the current typed runtime operations. Source library/delete
requests run under the Source update owner's failure/dirty-state policy, just
like Inspector requests. Source semantic rejection still counts as a handled
key: the browser must not perform a different default action after rejection.
Preserve context-menu dismissal for handled deletion. Keyboard/library do not
need Inspector session IDs or reply channels; no caller waits for a result.

Terminal Source state disables source-backed mutation admission. Already queued
requests stop at the Source latch. No replacement TS callback is needed for
success, rejection, or terminal state.

### Edit session and event contract

Use a field key `(node_id, Binding | Parameter(name))` and a monotonically
increasing Inspector-local session ID. A session holds its captured canonical
value and phase: `Editing`, `Submitted`, or `Cancelled`. Keep the current
projection separate. The native input owns the in-progress text; read its value
when requesting commit. Do not write its value or remount it on each keystroke.

Use keyed field DOM. Canonical initialization stays fixed during an active
session. A field reset generation may change after commit/cancel/target change,
but never merely because a viewport/action snapshot arrives. Numeric inputs
contain the number only; the unit remains a separate span. Read-only values
remain read-only. Preserve existing accessible labels and non-colliding field
identity independently of the CSS/test-facing sanitized input ID.

| Event | Decision / effect |
|---|---|
| Focus | Start a fresh session with field identity and canonical baseline |
| Enter outside IME | Prevent default synchronously; accept one commit for this session |
| Enter during IME | Do not prevent composition or submit |
| Native change | Request the same commit, carrying field/session and current value |
| Escape | Prevent default; mark session cancelled, restore baseline, blur; no graph operation |
| Blur | End editing; never re-arm a submitted/cancelled session |
| New focus after Escape | Start a new session; previous cancellation must not suppress it |
| Selection/target disappears | Invalidate old session; late events cannot target the new selection |
| Unrelated snapshot | Preserve input node, text, focus, selection range, and session |
| Matching completion | Reset to the latest canonical field; close submitted session |
| Stale completion | Ignore for Inspector state; never undo an already-completed graph operation |
| Terminal Source state | Cancel pending session; disable Inspector mutations |

Commit trims the supplied value. Empty or unchanged text produces no operation,
notice, or action-log entry. A real commit sets `Submitted` before running any
effect. For Enter/Escape, programmatic blur occurs in the command phase **after**
that state transition; otherwise blur's synchronous `change` can beat the cancel
message. Do not restore/blur first and only then enqueue cancellation.

A blur caused by a legitimate focus transition may commit the old field if its
commit was admitted before selection changed. A late event after invalidation
is ignored. Every request contains the captured node/parameter identity; it
must never resolve its target by looking up whichever node is selected later.

### Typed write path and completion

```text
Inspector input
  -> Inspector reducer: session admission
  -> command: typed Source edit receiver
  -> Source update: GraphOperation + SourceBackedGraph.apply_operation
  -> Source status/editor synchronization + narrow Inspector completion
  -> on_change -> existing TS RAF -> shared snapshot publication
```

Inspector request variants are binding rename and numeric parameter update;
the private Source ingress also accepts library insertion and captured deletion.
Reuse existing typed operations, constructors, and lowering. Do not call a
JSON export or pass an operation result through TS to get it back into MoonBit.

The Source update receives the session ID and a scheduler-bound reply receiver.
Its operation result stays in Source. Inspector needs only a narrow typed
completion (`Applied`, `Rejected`, or `ParserStopped`) with that session ID,
not a copy of source, diagnostics, action count, or a new public result DTO.
Every admitted request completes, including rejection with an unchanged
snapshot and requests arriving after a terminal latch.

Reuse `source_demo_external_status` and the existing result-folding policy:

- Success with clean Source synchronizes canonical text through the existing
  echo-suppressed CodeMirror command.
- Success while Source is dirty updates status without replacing editor text
  or clearing dirty state; use the #1436 external-success guard.
- Rejection preserves Source text and dirty state, and reports the diagnostic.
  Inspector itself resets to the canonical field, as it currently does after
  rendering a rejected operation.
- Clear selected edge after an attempted non-noop operation on success or
  semantic rejection, matching the current Inspector handlers.
- Graph backing alone appends the operation. Use `on_change` and existing
  `emitOperationsThrough` during publication to deliver it once to TS consumers;
  neither completion nor CodeMirror echo appends another operation.

Context-menu Source outcomes also call the Source receiver with their existing
typed result. Delete the stringify -> TS callback -> decode detour in full.
Inspector, library, keyboard, and context-menu notifications remain private to
MoonBit; none register a reporter in TS.

### Terminal failure is not a semantic rejection

Execute Inspector/library/delete requests under `source_demo_update`'s existing
`Failure` catch and the backing's sticky `parser_failure`. The catch sets terminal
Source status, retains editor text/last-good display, and notifies mutation-owning
UI models even when failure originated in the Source editor rather than Inspector.
Post-latch requests receive `ParserStopped` without touching the attachment.
Do not send a normal success/rejection notification or attempt another mutation.

This intentionally differs from the old TS Inspector failure route:
`adaptMoonBitModule` eagerly invalidates/attempts to destroy an owned handle
when an export throws. Internal source-backed UI requests instead follow the
already existing MoonBit Source-panel failure policy. They do not acquire an
implicit JS failure wrapper by virtue of being mounted from JS. Backing
terminality, not an assumption that the wrapper still runs, prevents reuse.

Do not redesign `adaptMoonBitModule`; any retained external exports still use
its failure boundary. The former TS library/delete paths no longer exist.
Full handle-lifetime characterization remains issue
[#1340](https://github.com/dowdiness/canopy/issues/1340). Recovering/replacing a
failed parser is outside scope.

## Steps

1. Characterize the behavioral gaps in the current Inspector through its UI:
   cancel/refocus, Enter/change dedup, focus preservation, and stale-target
   events. Preserve current graph lowering and Source dirty-state tests.
2. Add private composition/Inspector/library/keyboard code in `apps/canvas/main`,
   reusing Source result/error handling and scheduler-bound subscriptions. Add
   minimal snapshot fields and share the one decode. Keep reducers separate;
   no new package/framework is required.
3. Cut over `init` to `mount_canvas_ui(handle, on_change)`. Transfer Inspector,
   library/search, and delete-input ownership together; wire context results
   directly to Source. Never land the former notice registration as a
   transitional public interface.
4. Delete TS `renderInspector`, `renderSourceNodeEditor`, `bindCommitOnChange`,
   `safeParamInputId`, `commitSourceRename`, `commitSourceParam`, `renderLibrary`,
   `addNodeAt`, the search listener, and the Delete/Backspace listener branch.
   Delete `reportSourceOperation`, `sourceNoticeReporter`, their types, and the
   MoonBit string-operation/result decoder and registration protocol.
   Remove displaced `GraphAdapter` mutation helpers and result DTOs after
   migrating all actual callers. Keep shared node/render/action-log types only
   where a surviving consumer requires them.
5. Migrate exported mount callsites, module declarations, `moon.pkg`, generated
   interfaces, and browser consumers; remove old public mount aliases. Use
   language navigation to inventory exported references before this edit.
6. Run the focused validation below, then preserve adopted interface/ownership
   requirements in current docs and archive/delete this plan under the normal
   documentation lifecycle. Do not mark the migration complete after merely
   introducing the composition wrapper.

## Acceptance Criteria

- [x] TS bootstraps `mount_canvas_ui(handle, on_change)`; MoonBit owns Inspector,
      library/search, and delete-input behavior. No notice registration remains.
- [x] Runtime selected/hover details and source selected-node fallback remain
      correct; source hover and nonnumeric parameter edits are not invented.
- [x] Enter + change + blur produces one operation. Escape produces none;
      refocus after Escape can commit. IME Enter does not submit.
- [x] Viewport/hover/action updates do not erase draft text, move the caret, or
      replace the focused field. Late old-field events/completions cannot
      mutate or reset another node's editor.
- [x] Rename selection/edge behavior and numeric unit preservation remain
      correct. Empty/unchanged input does not mutate or log an operation.
- [x] Rejection with an unchanged snapshot completes the session; another edit
      remains possible. Source diagnostics and dirty-text preservation survive.
- [x] Internal success is logged once and reaches existing TS operation
      consumers through publication, without a duplicate CodeMirror echo.
- [x] All UI-origin Source notifications remain in MoonBit. No TS reporter,
      result forwarding, or legacy operation decoder remains. Render publication
      stays only for its surviving display/action-log consumers.
- [x] Library filtering and insertion work in runtime and source mode without
      changing placement or unique-binding rules.
- [x] Delete/Backspace preserves editable-target guards, edge/node precedence,
      no-selection behavior, synchronous default cancellation, rejection notices,
      and once-only action logging; queued intent never deletes a later selection.
- [x] Parser Failure retains Source text, latches terminal state, disables
      source-backed UI mutations, and completes pending Inspector requests
      without another attachment access. It is not a semantic rejection.
- [x] All affected callsites/declarations/interfaces are migrated; no duplicate
      DOM owner, unused compatibility export, global notice registry, or
      permanent throwaway probe remains.

## Validation

Implementation-time checks, from the affected module roots:

```bash
# apps/canvas
moon check --target js --deny-warn main
moon test --target js --release main
moon fmt --check main
moon info --target js
moon build --target js --release main

# apps/canvas/web
npm run build
npm run test:e2e -- e2e/source-backed.spec.ts e2e/canvas-handles.spec.ts
```

Inspect generated interface changes. Extend existing pure tests only for
consumer-visible state transitions, not callback wiring, wording, JSON copy
counts, or source-text assertions. Source terminal-state tests must use a
controlled failure seam/fixture; invalid graph syntax is **not** a substitute
for Loom `Failure`.

Exercise the real browser in both runtime and source mode: selection/hover,
rename, numeric parameter, cancel/refocus, an unrelated snapshot during editing,
library filtering/insertion, node/edge deletion, no-selection and editable-target
key handling, rejection, and dirty Source preservation. Check Source text, graph state,
selection/focus, notices, and action-log effects together. A compile or reducer
test alone does not prove this DOM cutover. Run normal affected pre-PR gates at
publication; do not assume this design session has validated the future code.

### Design-time evidence already obtained

On 2026-10-04, against the inspected baseline:

- Real Chromium Source UI, frequency `440 -> 880`, Enter: observed `keydown`,
  `change`, `blur`; source became `880Hz`, actions `1 -> 2`.
- Next `990`, Escape: `change` carried restored `880`, then blur; source/actions
  stayed unchanged. Next focus, `660`, Tab: DOM showed `660`, but source remained
  `880Hz` and actions remained `2`. This confirms the per-element commit latch
  suppresses later edits after cancellation; do not preserve that bug.
- A throwaway session reducer exercised duplicate commit, cancel/change,
  refocus after cancellation, and stale old-session events successfully.
- A compiled MoonBit prototype mounted two independent Rabbita roots. A command
  sent typed integer `41` to the Source host's scheduler-bound receiver; its
  command replied `42` through the Inspector host's receiver. Both states were
  observed in the browser. No shared model or JSON transport was needed.
- Temporary source, HTML, and export were removed; the original release JS app
  was rebuilt. No production behavior change is part of this design.

These probes establish event order and receiver feasibility. They do not prove
future Inspector DOM reconciliation, IME behavior, terminal-failure UI, or the
new library/keyboard migration. Those remain implementation acceptance checks.

## Risks and decisions

- Independent hosts are not a transaction: use receiver-owned schedulers,
  command-phase sends, explicit completion, and session identity.
- Stable DOM requires replacing the old per-element commit latch, not merely
  translating it. Input resets are deliberate transitions, not render effects.
- The existing source-backed render path rebuilds its published representation;
  this plan adds no second graph read and makes no speedup claim.
- Backward compatibility is not a requirement. Remove obsolete executable
  interfaces and migrate their callers in one cutover; do not retain an old
  design merely to reduce the number of changed files.
- The implementation adopts the ownership decision recorded in the linked ADR;
  this archived specification is no longer the current contract.
