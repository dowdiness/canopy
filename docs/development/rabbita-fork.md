# Canopy Rabbita fork

Canopy uses a downstream fork of Rabbita for the pointer-capture DOM boundary.
The fork is an owned dependency line, not an upstream release dependency.

## Ownership

- **Fork:** [`dowdiness/rabbita`](https://github.com/dowdiness/rabbita)
- **Upstream:** [`moonbit-community/rabbita`](https://github.com/moonbit-community/rabbita)
- **Downstream branch:** `feat/pointer-capture-typed-errors`
- **Pinned commit:** `6f538c4b2461ca71d523b652f50740d9d0dbd030`
- **Pinned tag:** `canopy-rabbita-0.14.2-p1`
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
- migration of Rabbita/RUI pointer-capture consumers to the new effect.

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
