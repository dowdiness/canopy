# Error Taxonomy For Canopy

## Why

The repository already has several good domain-local error types in lower
layers, but `editor/` and FFI-facing code still mix typed errors, raw strings,
generic `Failure::Failure(...)`, and silent catches.

That makes recovery policy harder to reason about and makes future cleanup tasks
like test `abort(...)` removal and transport hardening less consistent than they
should be.

The goal of this task is not to invent one giant repo-wide error enum. The goal
is to standardize error boundaries:

- keep low-level domain errors local,
- introduce one coherent wrapper layer in `editor/`,
- flatten errors to strings/JSON only at CLI/FFI edges.

## Scope

In:
- `editor/ephemeral_encoding.mbt`
- `editor/ephemeral.mbt`
- `editor/tree_edit_json.mbt`
- `editor/sync_editor_tree_edit.mbt`
- `editor/sync_editor_ws.mbt`
- `crdt.mbt`
- `crdt_projection.mbt`
- `docs/development/conventions.md`
- `docs/development/API_REFERENCE.md`

Likely follow-up / adjacent files:
- `editor/error_path_wbtest.mbt`
- `editor/tree_edit_json_test.mbt`
- `editor/sync_editor_ws_wbtest.mbt`

Out:
- replacing existing low-level errors in `event-graph-walker/` or `loom/`
- relay validation redesign before the container-based sync mechanism lands
- rewriting all option-returning APIs into error-returning APIs
- test assertion cleanup except where this task directly changes public error shape

## Current State

Existing low-level typed errors are already in decent shape:

- `@text.TextError` / `@text.SyncFailure` in
  `event-graph-walker/text/types.mbt`
- `TreeError` in `event-graph-walker/tree/tree_doc.mbt`
- `UndoError` in `event-graph-walker/undo/undo_manager.mbt`
- `@core.LexError` in `loom/loom/src/core/diagnostics.mbt`
- `ParseError` in `loom/examples/lambda/src/parser.mbt`

The inconsistency is mostly at higher layers:

- `editor/ephemeral_encoding.mbt` raises `Failure::Failure(...)` for decode and
  validation failures.
- `editor/tree_edit_json.mbt` returns `Result[..., String]` with ad hoc message strings.
- `editor/sync_editor_tree_edit.mbt` also returns `Result[Unit, String]` for
  structural edit failures.
- `editor/sync_editor_ws.mbt` handles protocol, sync, and recovery failures in
  one file, often via silent catches whose policy is implicit.
- Root FFI entrypoints in `crdt*.mbt` flatten internal failures directly into
  strings/JSON, which is acceptable at the edge but should not be the internal
  default.

## Progress

Completed implementation slices:

- tree-edit and projection-edit boundaries now use typed `TreeEditError`
- ephemeral decode/store validation now uses typed `EphemeralError`
- websocket wire decoding now has typed `ProtocolError` via
  `decode_message_result(...)`, while `ws_on_message(...)` keeps malformed-input
  drop behavior explicit
- root FFI and UI-facing call sites continue to flatten errors through
  `.message()` at the edge

Remaining work:

- decide whether the `editor/` surface needs a final wrapper type beyond the
  current per-boundary enums
- audit any remaining generic catches in `editor/` that should be documented or
  translated instead

## Desired State

### 1. Preserve Existing Low-Level Domain Errors

Do not replace the low-level error types that already match domain ownership:

- CRDT/text/document sync failures remain owned by `event-graph-walker/text`
- lexer/parser failures remain owned by `loom`
- tree/document-specific failures remain owned by their owning modules

### 2. Add A Typed `editor/` Boundary

Add domain-local suberrors in `editor/` for editor-owned boundaries:

```mbt
pub suberror ProtocolError {
  InvalidWireFormat(String)
  UnknownVersion(Int)
  UnknownMessageType(Int)
  InvalidJson(String)
}

pub suberror EphemeralError {
  DecodeError(String)
  InvalidPeerKey(String)
  InvalidValueTag(Int)
}

pub suberror TreeEditError {
  NodeNotFound(@proj.NodeId)
  RangeNotFound(@proj.NodeId)
  InvalidOperation(String)
  UnsupportedOperation(String)
}

pub suberror EditorError {
  Sync(@text.TextError)
  Protocol(ProtocolError)
  Ephemeral(EphemeralError)
  TreeEdit(TreeEditError)
  Internal(String)
}
```

The exact names may change, but the layering should stay the same:

- leaf-ish editor concerns get their own local enums,
- `EditorError` wraps them at the facade boundary.

### 3. Keep Edge Flattening At The Edge

At root FFI / CLI entrypoints:

- convert typed errors to string or JSON,
- do not leak internal enum structure unless the FFI is explicitly upgraded to
  structured JSON results,
- keep internal code typed until that outer boundary.

### 4. Make Error Policy Explicit

For each catch site in `editor/`, the code should clearly communicate one of:

- recover and continue,
- translate to a typed boundary error,
- intentionally drop malformed remote input as resilience policy,
- propagate upward.

Silent drops are acceptable only when documented as policy.

## Proposed Ownership

### `event-graph-walker/`

- `TextError`
- `SyncFailure`
- `TreeError`
- `UndoError`

### `loom/`

- `LexError`
- `ParseError`
- parser diagnostics

### `editor/`

- `ProtocolError`
- `EphemeralError`
- `TreeEditError`
- `EditorError`

### `relay/`

No new relay error type in this task.

If relay validation becomes active after the container implementation lands, add
`RelayError` there rather than forcing relay failures into `EditorError`.

## Steps

1. Add a small shared error definition file in `editor/` for the new editor
   boundary errors. Done.

2. Migrate `editor/ephemeral_encoding.mbt` and related call sites from generic
   `Failure::Failure(...)` to `EphemeralError`. Done.

3. Migrate structural edit parsing and application boundaries:
   - `editor/tree_edit_json.mbt`
   - `editor/sync_editor_tree_edit.mbt`
   from `String`-based errors to `TreeEditError` or `EditorError`. Done.

4. Audit `editor/sync_editor_ws.mbt` and classify each failure path:
   - protocol decode failures -> `ProtocolError` or explicit drop policy
   - sync/apply failures -> wrapped `@text.TextError`
   - recovery failures -> explicit retry/drop/escalate behavior
   Done for protocol decode + websocket message handling.

5. Keep `crdt*.mbt` as the flattening edge:
   - continue returning strings/JSON for now,
   - update conversion code to stringify typed errors rather than constructing
     internal string errors early.

6. Update docs:
   - `docs/development/conventions.md`
   - `docs/development/API_REFERENCE.md`
   to explain the boundary strategy. Done.

7. Add or update tests for the affected error surfaces.

## Acceptance Criteria

- [x] Existing low-level domain errors in `event-graph-walker/` and `loom/` remain the canonical source for their domains.
- [x] `editor/` has explicit typed boundary errors instead of relying on generic `Failure::Failure(...)` or pervasive `String` errors.
- [x] Structural tree-edit failures no longer use raw strings as the primary internal error representation.
- [x] WebSocket/protocol error handling documents which malformed inputs are intentionally dropped versus propagated or wrapped.
- [x] FFI entrypoints remain the main place where typed internal errors are flattened to strings/JSON.
- [x] Relevant tests cover the migrated error boundaries.

## Validation

```bash
moon check
moon test
make test-all
```

If the work only touches the main module, `moon check` and `moon test` may be
enough during implementation, but final validation should still consider whether
submodule-facing behavior was affected.

## Risks

- Over-wrapping every low-level error would add noise without improving
  recovery. The wrapper layer should exist only at meaningful boundaries.
- Some current `String`-based errors are effectively part of tests or FFI
  expectations. Migration may need careful compatibility handling.
- Protocol code can easily become over-engineered if this task tries to solve
  transport architecture questions that belong to the container follow-up.

## Notes

- This plan intentionally complements, not replaces, the `abort(...)` cleanup
  work. Test assertion cleanup should follow the repo's testing conventions and
  should not force production error-taxonomy decisions.
- Related future improvements:
  - structured FFI result envelopes
  - transport hardening after the container implementation
  - relay validation after the new sync boundary is defined
