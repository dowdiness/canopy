# Parent-owned Rabbita tool overlays

`warren-standalone.patch` is a Canopy-owned build-tool overlay applied only to
an ephemeral checkout by `scripts/install-local-warren.sh`.

- Base Rabbita commit: `3b5bb38964611bad772883c912010a9555e1748a`
- Included upstream Warren changes:
  - `4fe99da43fa99fb88e37bc9adb3db1680bd4f3b6` — direct development mode
  - `c507b0e07000ae66c150189a92906c284f75b68f` — relative assets in direct mode
- Local compatibility change: replace the removed `Repr(js_paths)` constructor
  spelling with the current `to_repr(js_paths)` core API in Warren diagnostics.

The overlay does not modify the checked-out `deps/rabbita` worktree and is not
linked into the Loomark runtime. CI installs the patched Warren executable from
the ephemeral checkout, then builds and tests the standalone application. If
the Rabbita pointer moves, the installer fails until this patch is rebased or
removed.
