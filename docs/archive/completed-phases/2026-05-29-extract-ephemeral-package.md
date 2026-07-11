# Extract `ephemeral` into a top-level `dowdiness/canopy/ephemeral` package

**Status:** planned (not started)
**Decided:** 2026-05-29. Target = top-level peer package + `pub using` facade in editor (user choice).
**Base:** main @ `2d2e8c9` (after #385 idiom sweep merged).
**Class:** Full-band boundary refactor. Follow `moonbit-refactoring-safety` (visible-extraction variant: sibling package, facade is the long-term API shim — editor keeps re-exporting; consumers may migrate to `@ephemeral.*` later but are not required to).

## Why

The ephemeral presence/awareness subsystem (~1,400 LOC, 9 source files) has **zero dependencies on editor types** (verified: no `SyncEditor`/`SyncStatus`/etc. references). It is a genuinely lower-level, cohesive "CRDT presence over a wire protocol" layer. Editor depends on it one-directionally. Extracting it makes the boundary explicit and the dependency acyclic, and gives editor a much smaller core.

## What moves (9 source files → `ephemeral/`)

- `ephemeral.mbt` — `EphemeralValue` (enum, pub(all)), `EphemeralStore`, `EphemeralRecord`, `EphemeralSubscription`, `EphemeralStoreEvent`, `EphemeralEventTrigger`
- `ephemeral_encoding.mbt` — `Reader`, varint codec, `read/write_ephemeral_value`, `encode/decode_entries` (uses `EphemeralError`)
- `ephemeral_hub.mbt` — `EphemeralHub`, `EphemeralNamespace` (enum), `all_namespaces`, `namespace_to_byte`, `namespace_from_byte`, `default_timeout`
- `ephemeral_hub_readers.mbt`, `ephemeral_hub_state.mbt`
- `ephemeral_time_js.mbt`, `ephemeral_time_native.mbt` — `now_ms` (TARGET-GATED, see seam 4)
- `presence_types.mbt` — `EditModeState`, `DragPosition`, `DragState`, `PresenceStatus`, `PeerPresence` (+ `to/from_ephemeral`)
- `cursor_view.mbt` — `PeerCursor`, `PeerCursorView`

Plus the matching tests move (test ownership): `ephemeral_test.mbt`, `ephemeral_wbtest.mbt`, `ephemeral_hub_test.mbt`, `ephemeral_hub_integration_wbtest.mbt`, `ephemeral_encoding_wbtest.mbt`, `cursor_view_test.mbt`, `presence_types_test.mbt`. Verify each test references only ephemeral symbols before moving; if a test mixes editor + ephemeral assertions, split it (editor-specific assertions stay in editor).

## Three seams (resolve in this order — each is compiler/`.mbti`-enforced)

### Seam 1 — split `errors.mbt`
`errors.mbt` defines THREE suberrors: `EphemeralError` (ephemeral-only), `TreeEditError` (editor, uses `@core`), `ProtocolError` (editor). Move `EphemeralError` + its `message()` into the ephemeral package (new `ephemeral/errors.mbt`). Leave `TreeEditError` and `ProtocolError` in editor's `errors.mbt`. Byte-equivalent move of the `EphemeralError` block — no rewording.

### Seam 2 — privacy (the hidden coupling the split surfaces)
These are **private** in `ephemeral_hub.mbt` but consumed by editor code that stays behind (`sync_protocol.mbt`, `sync_editor.mbt`, `sync_editor_ws.mbt`):
- `namespace_to_byte`, `namespace_from_byte` → make `pub` in ephemeral package.
- `all_namespaces` (top-level `let` Array) → **do not** expose as a `pub let` (shared-mutable global leak). Expose as `pub fn all_namespaces() -> Array[EphemeralNamespace]` returning a fresh array; update the in-package callers and editor callers (`sync_editor.mbt`, `sync_editor_ws.mbt` for-loops) to call it.
- `default_timeout` — only used inside the cluster; keep private.
Expect `moon check` after the move to report "Value X not found in package ephemeral" at exactly these sites — that list IS the inventory. Do not pre-`pub` everything; let the compiler name them.

### Seam 3 — facade in editor (`editor/ephemeral_facade.mbt`)
`pub using @ephemeral { … }` re-exporting the full current public surface so `@editor.EphemeralHub` etc. keep compiling for the web FFI / examples consumers. Enumerate from editor's pre-split `.mbti` (captured below). Listing a `type` pulls its methods/constructors/Show impl along; functions/values must be listed by name.

Facade surface to re-export (types — methods come along):
`EphemeralValue, EphemeralStore, EphemeralStoreEvent, EphemeralEventTrigger, EphemeralSubscription, EphemeralHub, EphemeralNamespace, PeerCursor, PeerCursorView, PeerPresence, PresenceStatus, EditModeState, DragState, DragPosition` + `suberror EphemeralError` + values `namespace_to_byte, namespace_from_byte, all_namespaces`.
(Opaque `type EphemeralLocalEntry / EphemeralRecord / EphemeralSubscriberEntry` are internal — not in the facade.)

Editor files that reference ephemeral symbols and stay behind the facade: `sync_protocol.mbt` (the `EphemeralUpdate(EphemeralNamespace, Bytes)` ProtocolMessage variant + namespace codec), `sync_editor.mbt` (the `hub` field, `get_hub`, `get_peer_cursors`, `subscribe_ephemeral_local`, presence methods), `sync_editor_ws.mbt` (`all_namespaces`, `EphemeralUpdate`), `sync_editor_tree_edit.mbt`, `editor.mbt`, `sync_status.mbt`. These compile unchanged through `pub using` (local-prefix-free names) — verify, don't pre-edit.

### Seam 4 — target-gating + moon.pkg
- New `ephemeral/moon.pkg`: minimal imports — `moonbitlang/core/{buffer,strconv,string,builtin,int}` (+ `quickcheck` for test). It must NOT need `@text/@core/@loom/@incr/@pretty` (confirms decoupling). Replicate the per-file `options.targets` gating for `ephemeral_time_js.mbt` (`["js"]`) and `ephemeral_time_native.mbt` (`["not","js"]`), plus any moved wbtest that was target-gated (`ephemeral_encoding_wbtest` — check current gating). Carry `warnings = "-7-29"` if the moved code needs it.
- editor `moon.pkg`: add `"dowdiness/canopy/ephemeral"` import; REMOVE the `options.targets` entries for the two moved time files; keep WS-test gating.
- workspace `moon.work`: add the new member if non-glob (check whether `moon.work` enumerates members explicitly).

## Safety net first (discipline #1)
Existing coverage already includes encode/decode round-trips (`ephemeral_encoding_wbtest`, `ephemeral_test`). Because the codec MOVES unchanged and its tests move with it, the round-trip invariant is preserved by the test relocation. Before moving, run the full editor suite to capture the green baseline (370 tests). The real verification for this refactor is compiler + `.mbti` diff (below), not new property tests — but if `ephemeral_encoding_wbtest` lacks a quickcheck round-trip over `EphemeralValue`, add one (it's `pub(all)`, derive `Arbitrary` or hand-build samples) as the pin before the move.

## Verification gates (must all pass before PR)
1. `NEW_MOON_MOD=0 moon check` clean (after resolving seam-2 pubs).
2. `NEW_MOON_MOD=0 moon info` then `git diff editor/pkg.generated.mbti`: must show ONLY re-export-forwarding changes — types relocate to the `Type aliases` section as `pub using @ephemeral {type X}`, functions keep their signatures with `@ephemeral.`-qualified types. **No symbol removed, no signature re-typed, no trait bound widened.** A removed/changed symbol = facade leak → stop.
3. New `ephemeral/pkg.generated.mbti` = the moved public surface; sanity-check it's self-contained (no `@editor.` references).
4. `NEW_MOON_MOD=0 moon test` full workspace: editor tests + new ephemeral tests all green; total count = old editor total (tests moved, not lost). Check count delta.
5. Examples/FFI consumers (`examples/ideal`, `examples/web`, `ffi/*`) build — they use `@editor.*`, unaffected. CI covers; locally `moon check` the workspace.
6. `moon fmt`.
7. Codex pre-PR review: "facade leak? missed caller? `.mbti` API-stable? target-gating replicated?"

## Execution order
1. Branch `refactor/extract-ephemeral-package` from main.
2. Capture green baseline (`moon test`).
3. Create `ephemeral/` + minimal `moon.pkg`; move the 9 source files + `EphemeralError` block; move the 7 tests.
4. `moon check` → fix seam-2 pubs the compiler names; add editor import + facade file; remove editor time-file gating.
5. Iterate `moon check` until clean.
6. `moon info` → verify both `.mbti`s per gate 2/3.
7. `moon test` full workspace (gate 4); `moon fmt`.
8. Codex review; address; PR.

## Notes
- Move-only discipline for the file relocations + `EphemeralError` block: byte-equivalent, no idiom changes smuggled in (the idiom sweep already landed in #385).
- This is delegation-shaped once on the branch (mechanical moves + compiler-named pub fixes against a frozen spec) — a fresh-session Sonnet could execute against this plan; the `.mbti` gate is the safety check. Keep the facade-enumeration and seam-2 judgment in the lead if anything deviates from the captured surface.
