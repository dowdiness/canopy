# ffi/lambda

JavaScript FFI boundary for the lambda editor. Exports every function that the TypeScript frontend calls, each identified by an integer handle representing one `SyncEditor[@ast.Term]` instance.

This package contains no logic of its own — it translates between JS-safe types (integers, strings, `Bytes`) and the typed MoonBit API in `editor`, `lang/lambda`, `relay`, and `llm`.

## Public API

All symbols in this package are flat free functions exported via the link block. Highlights:

- `create_editor(source) -> Int` / `destroy_editor(handle)` — editor lifecycle
- `get_text(handle)` / `set_text(handle, text)` — raw text access
- `handle_text_intent(handle, from, to, insert, cursor)` — primary edit entry point
- `apply_sync_json(handle, json)` — apply remote CRDT ops (JSON-encoded)
- `relay_on_connect/message/disconnect` — server-side relay forwarding
- `undo_manager_undo/redo/can_undo/can_redo` — undo stack management
- `ws_on_open/message/close/broadcast_edit/broadcast_cursor` — WebSocket lifecycle
- `ephemeral_encode_all/apply/set_presence/get_peer_cursors_json` — presence and cursor sync
- `canopy_llm_fix_typos/edit` — async Gemini-backed text actions (returns `Promise[String]`)

## Consumers

No other MoonBit package imports `ffi/lambda`. It is the terminal layer consumed by the TypeScript/Vite web bundle at `examples/web/`.

## Dependencies

- `dowdiness/canopy/editor` — `SyncEditor`, `JsWebSocket`, wire protocol
- `dowdiness/canopy/lang/lambda` — `new_lambda_editor`, `apply_lambda_tree_edit`, etc.
- `dowdiness/canopy/relay` — `RelayRoom` operations
- `dowdiness/canopy/llm` — `fix_typos`, `edit_text`
- `dowdiness/lambda/ast` — `Term` AST type
- `dowdiness/lambda/typecheck` — diagnostics surfaced through `get_diagnostics_json`
- `dowdiness/seam` — concrete `SyntaxNode` used by the editor cells
- `dowdiness/incr/cells` — reactive runtime that drives the projection memos
- `dowdiness/event-graph-walker/text` — CRDT text substrate
- `moonbitlang/async/js_async` — JS async runtime for the LLM entry points

## Stability

Unstable — route through `ffi/lambda`. The exported function list changes whenever the editor gains new features. The JS import site (`examples/web/`) must be updated in lockstep.

## Notes

Each editor instance lives in a process-local registry keyed by `Int`. The registry is global and unbounded — `destroy_editor` must be called to prevent leaks. LLM functions return `Promise[String]` and require the JS async runtime (`js_async`).
