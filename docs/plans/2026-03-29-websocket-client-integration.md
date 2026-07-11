# WebSocket Client Integration

## Why

The wire protocol and `SyncEditor` WebSocket lifecycle exist, but the backlog
still tracks client integration as incomplete. The remaining work is to make
the browser-side integration path explicit, validated, and documented so the
transport is a supported workflow rather than a partly implicit one.

## Scope

In:
- `editor/sync_editor_ws.mbt`
- `editor/websocket_js.mbt`
- `editor/websocket_native.mbt`
- `crdt_websocket.mbt`
- `docs/development/JS_INTEGRATION.md`
- browser client glue under `examples/web/` and/or `examples/demo-react/` if needed

Out:
- relay protocol redesign
- new collaboration features beyond the existing wire protocol

## Current State

- `SyncEditor` already exposes WebSocket lifecycle methods and sync recovery hooks.
- Root FFI already exports `ws_on_open`, `ws_on_message`, `ws_on_close`,
  `ws_broadcast_edit`, and `ws_broadcast_cursor`.
- The backlog still describes WebSocket client integration as incomplete.

## Desired State

- A browser client can connect to the relay using the supported API without
  relying on hidden assumptions.
- The supported client workflow is documented in one place.
- The integration path has an executable validation path.

## Steps

1. Audit the current browser/Web Component client flow against the live FFI.
2. Fill any missing glue or lifecycle handling needed for the supported path.
3. Update the JS integration docs to describe the canonical workflow.
4. Add or update validation coverage for the supported client path.

## Acceptance Criteria

- [ ] The supported browser client flow for connect, send, receive, and close is documented.
- [ ] Required client-side glue exists for the canonical integration path.
- [ ] Validation covers the supported WebSocket client workflow.

## Validation

```bash
moon test
moon check
make test-demo-react-e2e
```

## Risks

- There may be multiple partially overlapping browser entrypoints; this task
  should leave one canonical documented path.

## Notes

- Historical context: `docs/archive/2026-03-19-websocket-transport-design.md`
- Historical context: `docs/archive/completed-phases/2026-03-22-websocket-sync-recovery-design.md`
