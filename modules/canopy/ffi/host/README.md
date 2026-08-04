# ffi/host

Shared host-binding bookkeeping for the language FFI packages
(`ffi/lambda`, `ffi/json`, `ffi/markdown`). Internal library dependency —
not a JS link root and exports nothing to JavaScript.

`HostRegistry[H]` owns the generic per-handle state every language FFI
package needs:

- the handle map keyed by the exported integer handle
- the per-handle ordinary `ViewUpdateState` for the view-patch path
- the destroy gateway that routes teardown through
  `Coordinator::destroy_editor` and removes FFI bookkeeping only after the
  coordinator accepts destruction (refusal leaves bookkeeping intact)

Everything language-specific stays in each `ffi/<L>` package: the handle
record type `H`, protected-cell bundles, editor/companion construction,
exported function names, and lambda's extras (companion storage,
`last_created_handle`, `pretty_view_states`, LLM/relay/WebSocket wiring,
analysis attachment disposal).

## Consumers

`ffi/lambda`, `ffi/json`, `ffi/markdown` only. Each keeps its own
process-global coordinator and registry instance; nothing is shared across
languages at runtime.

## Dependencies

- `dowdiness/canopy/editor` — `ViewUpdateState`
- `dowdiness/canopy/workspace/coordinator` — destroy gateway

The package must not import language packages, `llm`, `relay`,
`transport_ws`, or AST packages — that boundary is what keeps the
per-entry JS bundles split.
