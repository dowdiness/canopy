# Integrated controlled-output experiment

Throwaway branch: `prototype/ideal-integrated-output`, based on main `8e81fd8d`.

This experiment connects the real Ideal application to a supplied-snapshot Structure renderer. It deliberately preserves the existing positional selection behavior and does not introduce output revisions, a generic projection protocol, or a new collaboration owner.

## Implementation

- `publish_proj_node_cmd` captures immutable `ProjNode` JSON while handling the application transition. A synchronous `custom_cmd` callback delivers it **after render**, when the host exists. It does not dereference the mutable editor during command execution.
- Accepted CodeMirror edits, other local edits/history, external refresh and Structure activation publish through that same command. Selection-only and unrelated UI updates do not publish.
- The host retains the latest value while the runtime imports. The runtime reads the value after await and uses the existing load-generation fence.
- Structure session construction and reconciliation accept snapshots, not a CRDT module or handle. There is no renderer getter fallback.
- Remote admission remains once in the host; local notifications only broadcast. The small existing bridge is retained, now without CRDT access or RAF scheduling.
- Same-host reconnect remounts and requests a non-autosaving application refresh. Missing-host publication warns rather than aborting Rabbita's after-render queue; activation republishes current state.

## Behavioral matrix and evidence

| Case | Evidence |
| --- | --- |
| Activation without prior edit | Existing Structure mode-switch E2E |
| Latest update while import held | New request-barrier E2E: Currying renders after delayed import |
| Supplied values, no getter | Session test: Int 7 → Int 42 through public session method |
| Local Delete / Undo / Redo / reactivation | Existing Structure typed-input E2E |
| Remote while Structure mounted | New two-peer test: Text edit to 314159 renders in remote Structure and Text |
| Text persistence/restore | Existing full Ideal E2E suite; no new Structure-specific reload test |
| Initial null / later null | Valid initial unit placeholder; retain prior valid PM tree on later null |
| Whole-host replacement | Existing SyncClient ownership limitation; not solved by this experiment |
| Semantic selection on reorder | Deliberately unchanged; requires a separate production behavior decision |

## Validation

- Ideal JS release tests: 75 passed.
- Targeted `moon check apps/ideal/main --target js`: passed with existing warnings.
- Workspace JS release build and Vite build: passed.
- TypeScript noEmit over changed runtime sources and imports: passed.
- Full Ideal Chromium suite during integration: 128 passed.
- After final changes: focused Structure suite 8 passed; collaboration suite 6 passed. Full suite was not rerun after adding these two tests.
- Independent final read-only review: no critical/warning findings.

The first remote test run exposed an assertion error: peer-cursor labels contribute to CodeMirror DOM text. The Structure assertion remains exact; the supporting Text-mode assertion now permits those existing decorations.

## Reuse and limitations

Reused existing `ProjNode` ToJson / core `Json::null` and `Json::stringify`, Rabbita `custom_cmd`/after-render, application sync helpers, existing conversion/reconciler, and host load generation. The only new MoonBit helper owns capture plus delivery; no new serializer, counter or selection model. Imperative work remains in the DOM/runtime shell.

Null behavior intentionally preserves the baseline rather than adopting the earlier fixture's destructive failure policy. Last-good rendering can be stale during projection unavailability; this is not a newly validated product policy. Malformed output validation, coalescing/performance under bursts, complete host replacement and semantic selection are not solved here. Broadcast executes independently of deferred DOM publication; no claim is made that a batch is atomic.

Run using the existing Ideal dev command after dependencies/build are ready: `cd apps/ideal/web && npm run dev`. No prototype-specific UI or route was added.
