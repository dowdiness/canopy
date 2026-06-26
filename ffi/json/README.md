# ffi/json

JavaScript FFI boundary for the JSON editor. Exports a minimal set of functions keyed by integer handle, analogous to `ffi/lambda` but for the `SyncEditor[@loom_json.JsonValue]` instance.

This package contains no logic — it delegates entirely to `editor`, `lang/json`, and their subpackages.

## Public API

- `create_json_editor(source) -> Int` / `destroy_json_editor(handle)`
- `json_get_text(handle)` / `json_set_text(handle, text)`
- `json_apply_edit(handle, op_json, cursor) -> String` — apply a structural edit op and return a diff patch JSON
- `json_get_view_tree_json(handle)` / `json_compute_view_patches_json(handle)`
- `json_get_proj_node_json(handle)` / `json_get_source_map_json(handle)` / `json_get_errors(handle)`
- `parse_json_edit_op(json)` — helper also used in tests

## Consumers

No other MoonBit package imports `ffi/json`. Consumed by `examples/web/json.html` and associated TypeScript.

## Dependencies

- `dowdiness/canopy/editor`
- `dowdiness/canopy/core`
- `dowdiness/canopy/ffi/host` — shared handle/view-state registry and coordinator destroy gateway
- `dowdiness/canopy/lang/json/edits` + `lang/json/companion`
- `dowdiness/json` — JSON value type

## Stability

Unstable — route through `ffi/json`. Exported function list tracks JSON editor feature development.
