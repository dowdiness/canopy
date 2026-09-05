# Ideal controlled-output validation

## Decision

Adopt application-owned projection snapshots. Retain existing selection and unavailable-projection semantics. Remove the renderer's CRDT dependency and the now-unnecessary `CrdtBridge`.

Baseline: main `8e81fd8d`. The isolated renderer experiment is preserved on local branch `prototype/ideal-controlled-output` at `b9a2700e`; the first real application integration is preserved on `prototype/ideal-integrated-output` at `4a5a7050`. Neither prototype branch is a published release.

## Implemented flow

`publish_proj_node_cmd` captures immutable `ProjNode` JSON while handling the application transition. A synchronous `custom_cmd` callback delivers it after render, when the host exists. The command does not dereference the mutable editor later.

Accepted CodeMirror edits, other local edits/history, external refresh and Structure activation publish through that command. Selection-only and unrelated UI updates do not publish. The host retains the latest supplied value during runtime loading; existing load-generation checks fence obsolete mounts. Renderer construction and reconciliation take snapshots rather than CRDT handles or getters.

Remote admission remains once in the existing host. Local change notifications invoke the host's broadcast callback. Reconciliation now lives directly in the existing Structure session. The removed bridge no longer had a separate responsibility. Same-host reconnect remounts and requests a non-autosaving application refresh.

Sources: `apps/ideal/main/{commands,update_codemirror,update_workspace,bridge_ffi}.mbt`, `apps/ideal/web/src/{canopy-editor,structure-runtime}.ts`.

## Selection comparison

A browser probe compared the baseline checkout with the integrated application. It entered `let x = 1; let y = 2; x + y` (with newline separators), explicitly selected the second integer leaf, performed an Inside drop exchanging definitions, invoked toolbar Undo and Redo, then refocused the PM-selected node and used Backspace. Observations used visible PM selection, the Inspector (application-selected node), and Text-mode output, not private callbacks.

Both implementations produced the same sequence:

| Stage | PM selection | Inspector |
| --- | --- | --- |
| Explicit click | Int 2 | Int 2, node 41 |
| Drop | Var x | Var x, node 43 |
| Undo | Int 42 | No matching node |
| Redo | Var y | No matching node |

The final Text-mode output after Backspace also matched. Undo grouped the preceding setup edit with the drop, so this probe is comparative evidence, not a claim that each operation formed a separate history group or that existing history behavior is desirable. The dedicated existing Structure-history regressions test canonical round trips separately.

This establishes that the observed selection/history behavior is not introduced by snapshot delivery in this scenario. It does not establish a universal semantic-selection policy. Do not add unconditional node-ID restoration or a keyed reconciler to this migration; application-directed selection and PM positional selection require a separate explicit decision.

## Regression coverage

| Case | Evidence |
| --- | --- |
| Activation without prior edit | Existing Structure mode-switch E2E |
| Snapshot changes during import | Request barrier holds runtime loading; Currying renders after release |
| Leave before load completes | Release and await module completion before asserting no PM blocks; reactivation renders latest example |
| Active same-host detach/reinsert | Exact element reinserted at its original position; Structure remounts supplied state |
| Saved document reload → Structure | Wait for autosave storage, reload, enter Structure, observe saved example |
| Supplied values without CRDT | Session test: Int 7 → Int 42 through public session interface |
| Local Delete / Undo / Redo / reactivation | Existing typed Structure input tests |
| Remote while Structure mounted | Two-peer Text edit to 314159 appears in remote Structure, then Text |
| Initial/later unavailable | Initial unit placeholder; later null retains current valid PM tree |

## Validation of the final implementation

- `moon check apps/ideal/main --target js`: passed with existing warnings.
- `moon test apps/ideal/main --target js --release`: 75 passed.
- Workspace JavaScript release build: passed during integration; no subsequent MoonBit behavior changes.
- Targeted TypeScript noEmit over changed runtime sources and imports: passed.
- Vite production build: passed.
- Full Ideal Chromium E2E after bridge removal and lifecycle tests: **133 passed**.
- Export manifest: 69 FFI exports, 31 app re-exports, three layers consistent.
- Independent final review: no critical/warning findings.
- Public `.mbti`, export manifest and submodule pointers unchanged.

One intermediate remote test assertion included peer-cursor labels in CodeMirror DOM text. The Structure assertion remains exact; the supporting Text assertion permits those existing decorations. One draft lifecycle assertion checked absence before releasing the import; it was strengthened to observe actual completion before asserting absence.

## Reuse and remaining limitations

Reused `ProjNode` ToJson, core `Json::null`/`Json::stringify`, Rabbita `custom_cmd`/after-render, `Document::get_element_by_id`, `IsElement::set_property`, `Value::cast_from`, existing application sync helpers, conversion/reconciliation and host load generation. The new MoonBit helper owns only snapshot capture and delivery. The DOM property setter is public even though VDOM `Attrs::property` is private; no custom JavaScript FFI or Rabbita API expansion is needed. No serializer, output revision counter or selection model was added. DOM, callback and runtime lifecycle mutation remain in the imperative shell.

Unavailable-projection handling preserves the baseline: the visible last-good tree can be stale while projection is unavailable. This is not a newly validated product policy. Complete host replacement still requires the existing application/SyncClient owner to wire the new host; same-element reconnect is not equivalent to replacement. Missing-host publications warn rather than aborting the render queue; activation/reconnect requests current state again.

No performance improvement is claimed. Removing bridge RAF scheduling changes coalescing; workload-specific measurement is required before adding a new scheduler or patch protocol. Broadcast is independent of deferred DOM publication; a Rabbita command batch is not claimed to be atomic. Semantic selection, broader failure UI, and collaboration-host extraction remain separate work.
