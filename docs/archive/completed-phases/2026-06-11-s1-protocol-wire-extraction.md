# S1 — Extract sync wire protocol into `protocol/wire`

**Date:** 2026-06-11
**Status:** In execution
**Parent:** [Architecture redesign proposal](2026-06-11-architecture-redesign-proposal.md) § Steps item 2 (S1)
**Tier:** `protocol/wire` is Tier 1 per the
[library API boundary ADR](../decisions/2026-06-11-library-api-boundary.md).
Plan authored by Codex from the converged S1 design ("Opus orchestrates, Codex
plans"); orchestrator amendments marked *(amended)*.

## Why

`editor/sync_protocol.mbt` currently owns two unrelated concerns in one
package: the transport session boundary (`SyncTransport`) and the stable wire
format (`SyncMessage`, framing constants, encode/decode). Relay has parallel
private protocol constants and string framing logic, so the same serialized
wire semantics are split across editor and relay without a dedicated shared
package, held in parity only by `relay/cross_compat_wbtest.mbt`. This stage
converges both halves into `dowdiness/canopy/protocol/wire` and preserves
byte-exact behavior while keeping downstream compatibility through `@editor`
shims.

## Scope

In:
- `protocol/wire/*` (new package, new files)
- `editor/sync_protocol.mbt`, `editor/errors.mbt`, `editor/sync_transport.mbt`
  (new), `editor/ephemeral_facade.mbt`, `editor/sync_editor_ws.mbt`,
  `editor/sync_protocol_wbtest.mbt` (moves), `editor/moon.pkg`
- `ephemeral/ephemeral_hub.mbt`, `ephemeral/moon.pkg`, plus a new ephemeral
  re-export file *(amended: there is no `ephemeral/ephemeral_facade.mbt`; the
  facade file is editor's)*
- `relay/wire.mbt`, `relay/moon.pkg`

Out:
- `relay/wire_frozen_wbtest.mbt` (HARD: must remain unedited and passing)
- `ephemeral/wire_format_fixture_wbtest.mbt` (HARD: must remain unedited and passing)
- `relay/cross_compat_wbtest.mbt` (unedited; flips drift-detector → contract test)
- `editor/error_path_wbtest.mbt` (unedited; doubles as compat-shim proof)
- ephemeral presence value codec (`ephemeral_encoding.mbt`) and model — S1
  touches the frame namespace only
- `protocol/` (view protocol) — untouched sibling
- JS bundles / ffi surface (no export change in this stage)

## Current State

- Sync-frame symbols and helpers are defined in `editor/sync_protocol.mbt`
  (~243 lines) as public APIs plus private helpers; `SyncTransport`
  (`pub(open) trait`) sits at the top of that file with transport impls in
  `editor/in_memory_transport.mbt`.
- `ProtocolError` lives with editor errors in `editor/errors.mbt`;
  `editor/sync_editor_ws.mbt` constructs `ProtocolError::InvalidSyncJson` and
  calls the private `read_string_field` 6×.
- Ephemeral frame-namespace API (`EphemeralNamespace`, `namespace_to_byte`,
  `namespace_from_byte`, `all_namespaces`) is defined in
  `ephemeral/ephemeral_hub.mbt`; editor consumes it via
  `editor/ephemeral_facade.mbt` (`pub using @ephemeral` for the type, plain
  `using @ephemeral` for the helpers).
- Relay duplicates wire constants (`version`, `msg_room_control`,
  `flags_none`, `sub_join`, `sub_leave`) privately in `relay/wire.mbt`;
  `wrap_with_sender` takes its type byte dynamically from incoming data
  (`relay/relay_room.mbt`), so it cannot be replaced by
  `encode_relayed_crdt_ops`.
- Protocol codec whitebox tests are in `editor/sync_protocol_wbtest.mbt`
  (public-API roundtrips only).

## Desired State

- New package `protocol/wire` owns all sync wire constants, frame
  encode/decode, `ProtocolError`, and the ephemeral frame-namespace API,
  byte-for-byte unchanged. It imports only `dowdiness/byte_codec` and
  `moonbitlang/core/{buffer,debug}` — never editor/ephemeral/relay/lang.
- `SyncTransport` stays in editor (`editor/sync_transport.mbt`) — it is the
  transport seam (S2 scope), not wire format.
- `ephemeral` imports `protocol/wire` and re-exports the namespace API so
  `@ephemeral.EphemeralNamespace` remains valid; `default_timeout` stays in
  ephemeral.
- `relay` imports `protocol/wire`, deletes its five duplicated constants, and
  keeps its framing helpers with unchanged signatures and bytes.
- `editor` consumes `@wire` directly internally; downstream compatibility via
  transparent deprecated type aliases + `#deprecated(skip_current_package=true)`
  forwarding fns.
- Codec whitebox tests live in `protocol/wire`, moved verbatim.

## Steps

Steps 2–5 form one compile unit: the workspace does not `moon check` clean
until the editor shims of step 5 land. Within the unit, check per-package
(`moon check` reports per-package; expect the enumerated errors only).

1. **Create the `protocol/wire` package skeleton.** Add
   `protocol/wire/moon.pkg` (brace format) importing `dowdiness/byte_codec`,
   `moonbitlang/core/buffer`, `moonbitlang/core/debug`; no warnings
   suppression unless `moon check` demands it. Verify: `moon check` still
   clean (empty package).

2. **Move the codec into `protocol/wire` verbatim.** Create
   `protocol/wire/wire.mbt` containing, byte-identically from
   `editor/sync_protocol.mbt` (everything except `SyncTransport`):
   `SyncMessage` + Show impl, the seven byte constants, `message_type_byte`,
   `encode_message`, `encode_relayed_crdt_ops`, `encode_peer_addressed`,
   `encode_sync_request`, `encode_sync_response`, `payload_bytes`,
   `read_string_field` (visibility widened to `pub` — sync_editor_ws.mbt
   needs it; called-out fixup), `decode_message_result`, `decode_message`;
   plus a `using @byte_codec` block (the editor one lives in
   ephemeral_facade.mbt and does not move). Add `ProtocolError` +
   `ProtocolError::message` verbatim from `editor/errors.mbt` (e.g.
   `protocol/wire/errors.mbt`). *(amended)* Add three new named pub constants
   `flags_none`, `sub_join`, `sub_leave` (relay's existing names/values) for
   relay's consumption; the moved encoder bodies keep their inline literals
   verbatim so the move stays byte-auditable. Breakpoint: `SyncMessage`
   references `EphemeralNamespace`, not yet in this package → "type not
   found". Fix: step 3 moves it in the same compile unit.

3. **Move the frame-namespace API into `protocol/wire`.** Cut
   `EphemeralNamespace` enum (+ derives + Show impl), `namespace_to_byte`,
   `namespace_from_byte`, `all_namespaces` from `ephemeral/ephemeral_hub.mbt`
   into `protocol/wire/namespace.mbt` verbatim. `default_timeout` stays in
   ephemeral. Add `dowdiness/canopy/protocol/wire` to `ephemeral/moon.pkg`;
   add a new ephemeral re-export file *(amended path)* (e.g.
   `ephemeral/namespace_reexport.mbt`) with
   `pub using @wire { type EphemeralNamespace, namespace_to_byte,
   namespace_from_byte, all_namespaces }` — `pub using` also brings the names
   into local package scope, so `ephemeral_hub.mbt`'s unqualified uses
   (`Cursor`, `all_namespaces()`, the stores Map) keep compiling. Breakpoint:
   if unqualified variant constructors fail in ephemeral, qualify as
   `EphemeralNamespace::Cursor` per the cross-package constructor rule.
   Verify: `moon check` on protocol/wire and ephemeral both clean.

4. **Relocate `SyncTransport` within editor.** Move the trait verbatim to new
   `editor/sync_transport.mbt`; delete it from `sync_protocol.mbt`. No
   consumer changes (`in_memory_transport.mbt`, SyncEditor impls are
   package-local).

5. **Replace editor's codec with the compat shim layer.** Add
   `dowdiness/canopy/protocol/wire` to `editor/moon.pkg`. Rewrite
   `editor/sync_protocol.mbt` to contain only: transparent deprecated aliases
   `pub type SyncMessage = @wire.SyncMessage`, `pub type ProtocolError =
   @wire.ProtocolError` (variant names unchanged → downstream match arms and
   constructors keep compiling per the in-repo deprecation idiom), and
   `#deprecated(skip_current_package=true)` forwarding fns for
   `encode_message`, `decode_message`, `decode_message_result`,
   `encode_sync_request`, `encode_sync_response`, `encode_relayed_crdt_ops`.
   Delete `ProtocolError` from `editor/errors.mbt` (TreeEditError stays).
   Breakpoint *(amended — verify early)*: editor's
   `ephemeral_facade.mbt` re-exports `type EphemeralNamespace` from
   `@ephemeral`, which is now itself a re-export from `@wire` (chained
   `pub using`). If the chain does not compile or `.mbti` shows a broken
   origin, re-point editor's facade entry (and its plain `using` of the
   namespace helpers) to `@wire` directly. Breakpoint: `sync_editor_ws.mbt`'s
   `read_string_field` calls → migrate them (step 6). Verify: `moon check`
   workspace clean after step 6.

6. **Port editor internals onto `@wire` directly.** In
   `editor/sync_editor_ws.mbt` (and any other editor file touching codec
   symbols — `sync_status.mbt` has comment-only references), qualify wire
   codec calls as `@wire.*` (notably `read_string_field`,
   `decode_message_result`/`decode_message`, `encode_*`,
   `ProtocolError::...` construction via the transparent alias is fine).
   The deprecated shims exist for downstream compat only. Verify:
   `moon check` clean; editor wbtests compile unmodified
   (`error_path_wbtest.mbt` exercising the shims is the compat proof;
   `skip_current_package=true` keeps it warning-clean).

7. **Move the codec whitebox tests.** `git mv`
   `editor/sync_protocol_wbtest.mbt` → `protocol/wire/wire_wbtest.mbt`
   verbatim (uses only moved symbols, `@byte_codec.read_string` via the
   package `using` block, `@debug`). Remove the editor `moon.pkg` targets
   entry only if one references it (none does today). Verify:
   `moon test -p dowdiness/canopy/protocol/wire` runs the moved tests; editor
   test count drops by exactly that file's count
   (feedback_test_count_delta).

8. **Port relay onto `protocol/wire` constants.** Add the import to
   `relay/moon.pkg`; in `relay/wire.mbt` delete the five local constants and
   re-point uses (`version` → `protocol_version`, others same-named) via a
   `using @wire` block or qualified refs. Keep `encode_peer_control`,
   `encode_peer_joined`, `encode_peer_left`, `read_relay_string`,
   `wrap_with_sender` bodies and signatures otherwise untouched (smaller,
   auditable diff; chosen over forwarding through `@wire.encode_message`).
   Verify: `moon test -p dowdiness/canopy/relay` — `wire_frozen_wbtest.mbt`,
   `wire_wbtest.mbt`, `cross_compat_wbtest.mbt`, `relay_room_wbtest.mbt` all
   pass with zero edits to the frozen file.

9. **Write `protocol/wire/README.md`.** Package purpose; Tier 1 statement;
   frame layout `[version][type][flags][payload…]` with the message-type
   table and the EphemeralUpdate namespace byte; the frame-namespace API; the
   version-bump protocol: bumping `protocol_version` requires updating the
   frozen fixtures in the SAME commit, coordinating editor+relay+ephemeral,
   and is never silent.

10. **Full validation + API surface review.** Run the Validation block.
    Review `git diff '*.mbti'` as a Tier 1 API change (expect: editor codec
    fns now deprecated-forwarding with `@wire` origin types, editor/ephemeral
    type-alias sections pointing at `@wire`, new protocol/wire surface;
    NO trait-bound widening). `git restore` sibling `.mbti` trailing-newline
    churn and the pre-existing dirty files; never stage `graphify-out/`,
    the loom gitlink, or the 5 pre-existing `.mbti` files.

## Acceptance Criteria

- [ ] `protocol/wire` owns all sync wire constants, codec, `ProtocolError`,
      and the frame-namespace API; imports substrate only (byte_codec, core).
- [ ] grep finds no encode/decode of the sync frame outside `protocol/wire`
      other than editor's deprecated forwarding shims and relay's
      constant-consuming framing helpers.
- [ ] `SyncTransport` remains editor-only (`editor/sync_transport.mbt`).
- [ ] `relay/wire.mbt` defines no version/room-control constants.
- [ ] `relay/wire_frozen_wbtest.mbt` and
      `ephemeral/wire_format_fixture_wbtest.mbt`: `git diff` shows zero
      edits; both pass.
- [ ] `editor/error_path_wbtest.mbt` and `relay/cross_compat_wbtest.mbt`
      pass unmodified.
- [ ] `@editor.SyncMessage` / `@editor.encode_message` / `@editor.CrdtOps` /
      `@editor.ProtocolError` still compile for downstream
      (`ffi/lambda/integration_ws_test.mbt` is the witness).
- [ ] `.mbti` diff reviewed; no unintended API change, no trait-bound
      widening.
- [ ] README documents the version-bump protocol.

## Validation

```bash
NEW_MOON_MOD=0 moon check
moon test                                   # workspace root covers all members
NEW_MOON_MOD=0 moon info && git diff '*.mbti'
NEW_MOON_MOD=0 moon fmt
git diff --stat relay/wire_frozen_wbtest.mbt ephemeral/wire_format_fixture_wbtest.mbt  # must be empty
```

## Risks

- Chained `pub using` (wire → ephemeral → editor) may not re-export; fallback
  is re-pointing editor's facade to `@wire` (marked in step 5).
- Editor compat shims can mask regressions if downstream witnesses aren't
  exercised — `ffi/lambda/integration_ws_test.mbt` and
  `error_path_wbtest.mbt` are the named witnesses.
- Relay's dynamic type-byte routing (`wrap_with_sender(sender, data[1], …)`)
  must keep lining up with wire constants — bodies are untouched by design.
- `.mbti` churn on sibling members (trailing newline) — restore before
  commit.

## Notes

- Byte formats unchanged everywhere; frozen fixtures are the oracle — if a
  fixture needs editing, the move is wrong: stop.
- No JS rebuild needed (no ffi export change).
- `cmd/main/demo.mbt` / `examples/block-editor` references to "SyncMessage"
  are the event-graph-walker `@text.SyncMessage` (different type) or
  comments — no action.
