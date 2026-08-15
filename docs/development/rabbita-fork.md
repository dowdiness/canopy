# Canopy Rabbita fork

Canopy uses a downstream fork of Rabbita for typed pointer-event, pointer-capture, and coordinate hit-testing DOM boundaries.
The fork is an owned dependency line, not an upstream release dependency.

## Ownership

- **Fork:** [`dowdiness/rabbita`](https://github.com/dowdiness/rabbita)
- **Upstream:** [`moonbit-community/rabbita`](https://github.com/moonbit-community/rabbita)
- **Downstream branch:** `canopy/0.14.x`
- **Pinned commit:** `938cecdf8967e2ce07880628e4b404f106ca7671`
- **Baseline tag:** `canopy-rabbita-0.14.2-p3`
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
- `IsMouseEvent` coordinate getters with `Double` results, including
  fractional-coordinate coverage for pointer, mouse, and wheel events;
- migration of Rabbita/RUI pointer-capture consumers to the new effect and
  fractional coordinate contract;
- `Document::element_from_point(Double, Double) -> Element?`, a thin binding
  for release-position hit-testing.

Canopy needs a MoonBit-typed pointer-capture boundary for its Canvas hosts. This
patch is intentionally maintained downstream rather than proposed as an
upstream Rabbita change.

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
