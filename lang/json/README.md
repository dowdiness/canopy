# lang/json

Empty facade. Originally re-exported the public surface of `lang/json/proj`, `lang/json/edits`, and `lang/json/companion`, but no consumer ever imported `dowdiness/canopy/lang/json` — `ffi/json/` reaches into the subpackages directly. The facade was trimmed to nothing in 2026-05.

## Public API

None. The package compiles but exports no symbols.

## Consumers

None.

## Where the real API lives

- `lang/json/proj/` — projection from JSON AST to `ProjNode`
- `lang/json/edits/` — `JsonEditOp` and edit application
- `lang/json/companion/` — `new_json_editor` constructor

Import these subpackages directly from any new consumer.

## Stability

Reserved as a future aggregator. If a new consumer wants a single import point for the JSON editor, re-add `pub using @json_proj { … }`, `pub using @json_edits { … }`, etc. blocks to `top.mbt` (and the matching imports to `moon.pkg`). Until then this is a placeholder.

## Notes

`ffi/json` does not import this facade. The decision to import subpackages directly avoids re-export churn whenever the JSON subpackages add or rename functions.
