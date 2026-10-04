# Canopy Rabbita fork

Canopy uses a downstream fork of Rabbita for typed pointer-event, pointer-capture, coordinate hit-testing, and keyed accessible SVG boundaries.
The fork is an owned dependency line, not an upstream release dependency.

## Development Guidance

Before designing Rabbita changes (`@sub`, `@cmd`, `@html`, `@dom`, `@http`,
or bindings), read the repository's `.claude/skills/rabbita` skill. The vendored
docs in `deps/rabbita/doc/` and `deps/rabbita/rabbita/*/README.mbt.md` and
`design.md` are authoritative when they disagree with plans or pasted specs.

## Ownership

- **Fork:** [`dowdiness/rabbita`](https://github.com/dowdiness/rabbita)
- **Upstream:** [`moonbit-community/rabbita`](https://github.com/moonbit-community/rabbita)
- **Downstream branch:** `refactor/indexed-db-managed-store`
- **Upstream base:** `d31819b4b59653550af5fcd3c1bc5c424caae64a` (`rabbita-v0.16.3`)
- **Pinned commit:** `76389326f57f66f24fde59e3fec1c7d6b0befc4e`
- **Pin tag:** `canopy-rabbita-0.16.3-20261004`
- **Upgrade PR:** [`dowdiness/rabbita#8`](https://github.com/dowdiness/rabbita/pull/8)
- **Canopy submodule:** `deps/rabbita`

The Canopy `.gitmodules` entry intentionally points at the fork. The
superproject pins the exact downstream commit; it must not depend on a moving
branch reference at checkout time.

## Downstream changes

The pinned fork contains:

- typed `DOMExceptionError` effects for `set_pointer_capture` and
  `release_pointer_capture`;
- preservation of standard DOM exception `name` and `message`, with safe
  normalization of non-standard JavaScript throws;
- `Attrs::on_lostpointercapture` with a `PointerEvent` callback;
- `Attrs::on_pointerdown`, `on_pointermove`, `on_pointerup`, and
  `on_pointercancel` with `PointerEvent` callbacks;
- migration of Rabbita/RUI pointer-capture consumers to the new effect;
- typed text-area selection, file-selection, and `InputEvent` data bindings;
- `svg.Attrs::role` and `svg.Attrs::aria_label` for typed edge-path
  accessibility attributes;
- `svg.keyed_node`, which exposes keyed SVG children to Rabbita's keyed VDOM
  reconciliation so edge-path DOM identity survives reorder; and
- managed IndexedDB String Store interface (`get`, `contains`, `entries`, `set`,
  `delete`, atomic `apply`) with typed errors, blocked/stale lifecycle
  recovery, and redacted debug values.

Canopy needs a MoonBit-typed pointer-capture boundary for its Canvas hosts. This
patch is intentionally maintained downstream rather than proposed as an
upstream Rabbita change.

## 0.16.3 integration

The pin merges upstream Rabbita 0.16.3 into the existing downstream line. It
includes RUI 0.3.3 and Warren 0.4.0; Canopy's Rabbita dependency declarations
match 0.16.3.

- Loomark imports `moonbit-community/rui` instead of `Yoorkin/rui`. Its delete
  confirmation uses the native alert dialog, `@dialog.show`, and the dialog
  form's close value. Only `confirm` deletes; Cancel and Escape preserve the
  document.
- CodeMirror loading uses `Promise[Value]` and `Promise::from_async`, retaining
  the existing module cache and error callbacks.
- The managed IndexedDB command bridge uses a private callback-to-promise
  adapter and `Promise[Cmd].wait()`. Transaction scheduling, completion
  acknowledgements, and redacted errors remain owned by the existing provider.
- The fork retains nullable `InputEvent.get_data()`; upstream's non-null
  `InputEvent.data()` is not substituted.

This upgrade does not add Worker bindings.

## Upgrade procedure

1. Fetch the upstream and downstream repositories.
2. Merge or rebase the downstream branch as appropriate.
3. Run the full Rabbita test suite.
4. Run the full Canopy test suite and the affected Ideal E2E tests.
5. Build the JavaScript artifacts.
6. Update the `deps/rabbita` submodule and
   `scripts/install-local-warren.sh` to the same verified downstream commit.
7. Record the new commit and tag here, then verify the superproject is clean.

A downstream commit must be pushed to `dowdiness/rabbita` before its gitlink is
updated in Canopy so fresh recursive checkouts can resolve it.
