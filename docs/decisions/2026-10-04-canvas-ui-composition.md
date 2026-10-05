# ADR: Canvas UI composition and Inspector ownership

**Date:** 2026-10-04
**Status:** Accepted
**Issue:** [#1454](https://github.com/dowdiness/canopy/issues/1454)
**Implementation plan:** [Completed design and evidence](../archive/completed-phases/2026-10-04-canvas-ui-composition-inspector.md)

## Context

Canvas kept Inspector editing, library/search, keyboard deletion, and mount
ordering in TypeScript while the graph and Source state lived in MoonBit.
Source results crossed into TypeScript only to be serialized and routed back
to the Source owner. Retaining that notification interface would preserve the
ownership split rather than remove it.

Independent Rabbita roots have independent schedulers. Sharing a raw `Emit` or
executing another root's `Cmd` does not provide a safe cross-root transition.
Inspector also needs a session boundary: native change and Enter may describe
the same edit, while Escape must not suppress an edit after the next focus.

## Decision

The executable's app-private entrypoint is
`mount_canvas_ui(handle, render_target, on_change, on_rendered)`. MoonBit determines
the backing, connects the fixed UI roots, and wires their private typed receivers.
The browser shell supplies the already acquired render target. `on_change`
schedules TS publication; it carries no operation result. `on_rendered` connects
the surviving TS validation controls after the render host patches its DOM.
This is a page-lifetime composition, not a public reusable mount/unmount or
multi-canvas API.

MoonBit owns the complete Inspector subtree, library rendering/search/insertion,
and keyboard Delete/Backspace admission and execution. Source owns source-backed
requests, status, dirty-text protection, editor synchronization, and terminal
parser failure. Context-menu outcomes go directly to that owner. Graph operations
and their action-log entries remain graph-owned.

TypeScript retains module/CodeMirror loading, backing creation and lifecycle,
RAF publication, validation/action-stat rendering, and action-log inspection.
Remove displaced mutation helpers, individual UI mount exports, and Source
notification registration/JSON transport; do not retain compatibility aliases.

Import the required Canvas module statically so its download and evaluation
remain part of navigation. An unawaited async bootstrap lets the page `load`
event finish before the application starts, racing subsequent UI assertions
against module delivery. Publish the bundled CodeMirror namespace before
mounting the MoonBit UI; native editor mounting may still complete asynchronously.

### Host and publication boundaries

- Register each receiver through a subscription owned by the receiving host.
  Dispatch with its scheduler and current tagger. Unload revokes captured
  receivers and queued source-sync callbacks; sends happen in command effects,
  not reducers. All required receivers are installed before initial publication.
- Keep the existing render publication for its surviving display and action-log
  consumers. Its render-layer subscriber decodes once and supplies Inspector
  from that same snapshot, without another graph read or event listener.
- Inspector's small equality projection excludes geometry and action count.
  Runtime uses the published selection-before-hover summary. Source only
  synthesizes selected-node details from the decoded nodes; it gains no hover
  or nonnumeric editing semantics.

### DOM actions and the functional core

Follow the repository's [functional-core / imperative-shell boundary](../architecture/functional-core-imperative-shell.md):
DOM reads are actions, not calculations.

- Resolve fixed DOM roots at startup and pass typed elements/event targets into
  subscriptions. Resolve dynamic Inspector inputs and menu panels at explicit
  after-render connection points. Measurement, dismissal listeners, restoration,
  and focus use acquired elements rather than repeatedly resolving IDs.
- Cache elements, not geometry. The shell reads current rectangles/client sizes
  at event admission and retains live pointer-release hit testing. Pure
  `canvas_geometry.mbt` functions receive numbers, reuse spatial validation, and
  preserve fractional coordinates and Double-to-Float overflow rejection.
  Context-menu viewport clamping also runs in pure MoonBit, including its
  non-finite-size and oversized-panel behavior.
- Inspector transitions return immutable state and one typed effect. The shell
  executes Source requests and native finalization without delaying them until
  another paint; only element connection and inactive-field synchronization need
  the after-render boundary. Deferred synchronization uses the current state so
  an intervening editing session is not overwritten. Unload revokes the receiver
  and clears acquired field references.
- `publish_render_state(handle, target)` dispatches to the supplied element.
  Render-layer listeners retain their supplied target through unsubscription.
  Validation buttons connect to rendered nodes after the DOM patch; their click
  handlers receive the node itself and perform no selector lookup.
- Prefer Rabbita's typed DOM and scheduling APIs. Remaining JS FFI exposes
  browser primitives with typed inputs/outputs: platform text, URL query
  operations, and focusing an acquired element. Platform classification and
  Source-mode query policy live in MoonBit. Capture platform/location at startup;
  pass the platform decision into wheel normalization instead of reading browser
  globals in graph mutation code.

Reuse `ScreenPoint::from_xy`, the existing wheel normalization core,
`@cmd.after_render`, and native subscription teardown. Do not add a global DOM
registry, observer framework, raw-value FFI bag, or another publication protocol.

### Native editing and completion

A session captures node/field identity, a fresh per-focus ID, canonical baseline,
and Editing/Submitted/Cancelled phase. Native inputs own drafts and caret
position. Unrelated snapshots must neither rewrite their value nor relocate
focused DOM. Fixed chrome uses ordered children; semantic node/field keys remain
stable. A multi-entry keyed map is not an ordering contract for fixed form rows.

Inactive fields must follow later canonical Source changes, including after
cancellation. Explicitly reset their changed native value properties: updating
the HTML value attribute does not reset an input's dirty value. Editing and
Submitted sessions still preserve their draft/baseline until completion.

Allocate and stamp the focus ID synchronously in the DOM callback; it must not
wait for a reducer update or render. Enter/change/Escape read that stamped ID,
not a session captured by the previous render. Otherwise focus and Enter in the
same task can enqueue mismatched identities and silently lose an edit.

The focus generation tracks target invalidation and terminal shutdown, not
completion, cancellation, or a no-op edit. Native Tab can emit change and focus
before another render; ending the old session must not reject the new focus.
Session-owned DOM restoration and blur also match the stamped focus ID so an
older queued command cannot overwrite or blur a refocused draft.

Non-IME Enter synchronously prevents default. An admitted edit becomes Submitted
before blur can emit native change. Escape becomes Cancelled before restoring
and blurring; a later focus starts a new session. Empty/unchanged input produces
no graph operation or notice. Requests carry the captured target, never whatever
node is selected when a queued request runs.

Source returns a narrow Applied/Rejected/ParserStopped completion through the
Inspector receiver, including when the snapshot does not change. Completion is
session-matched; stale events cannot edit or reset another target. Semantic
rejection restores the canonical field without replacing dirty Source text.
Terminal parser failure preserves editable Source and last-good graph state,
completes pending requests, and stops later source mutations before attachment
access. Selection/layout inspection is distinct from source mutation; parser
recovery is not introduced.

### Library and keyboard admission

Library search remains trimmed and case-insensitive over the typed catalog.
Runtime placement uses current canvas dimensions and viewport validation before
clearing edge selection. Source insertion retains unique binding allocation.

Delete/Backspace checks modifiers and editable ancestors synchronously, then
captures current backing selection, with edge precedence. No target means no
preventDefault or mutation. An admitted target cancels the browser default and
dismisses the context menu even if the subsequent Source operation is rejected.
Queued intent never retargets to a later selection.

### Test ownership

Keep assertions at the boundary that owns the guarantee:

- Inspector core tests exercise event sequences and resulting edit requests or
  finalization: one submission for Enter/change, stale completion isolation,
  target replacement, cancellation/refocus, and terminal shutdown. A generation
  is an input token, not a counter whose arithmetic is part of the contract.
- Source-owner tests verify canonical source, dirty-buffer preservation,
  completion outcomes, and durable operations. Status prose and status-field
  copying are not additional contracts.
- Browser tests own native focus/caret/Tab/IME ordering, keyed DOM identity,
  compatibility presentation, keyboard admission, and menu dismissal. Do not
  duplicate them with serialized-HTML or CSS-string snapshots.
- Library/menu tests verify query normalization, the chosen inserted node, and
  operation deltas. The separated-node arrangement fixture checks reduced bounds
  without overlap. Demo graph size, catalog length, insertion percentages,
  packing coordinates, and action-stat wording are not promises.
- Keep independently worked numeric examples for subpixel coordinates, overflow
  rejection, and viewport clamping with caller-supplied margins and offsets.
  Precise expected results at those boundaries catch arithmetic regressions;
  replacing them with “some value was returned” would weaken the tests.

## Rationale

Local typed receivers keep Source policy with its existing owner without merging
all UI models or introducing an event bus. Explicit completion separates an
operation's outcome from render equality. Per-focus identity fixes cancellation
and duplicate-event behavior without controlling native text on each keystroke.
Moving library and keyboard callers in the same cutover makes the old TS notice
transport unnecessary rather than merely renaming it.

## Consequences

Cross-root sends are asynchronous, not a transaction. Session checks, receiver
revocation, and deferred Source synchronization remain required. Preserve the
dirty-buffer guard against delayed successful notifications. Test observable
Source/graph/focus/action-log behavior, not source-code spelling or callback
wiring. Broader handle-lifetime characterization (#1340), executable FFI
ownership documentation (#1341), visual redesign, and publication protocol
changes remain separate work.
