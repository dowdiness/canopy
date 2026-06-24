# zipper

Functional rose-tree zipper. A `RoseZipper[T]` lets you focus on one node of an immutable `RoseNode[T]` tree and move up / down / left / right in O(1) per step, with O(focus depth) reconstruction back to the root.

This is a foundational data structure, used wherever code needs to express navigation and structural mutation over a rose tree without rebuilding the tree from scratch on every edit.

## Public API

- `RoseNode[T]` — immutable tree node (`data : T`, `children : Array[Self[T]]`); construct with `RoseNode::RoseNode(data=..., children=...)`
- `RoseZipper[T]` — focused navigation state; build with `RoseZipper::from_root(node)`
- `go_up`, `go_down(index?)`, `go_left`, `go_right` — return `Self?`, `None` when the move is impossible
- `focus_at(node, path)` — jump to a position by index path; `to_path(self)` is its inverse
- `replace(self, new)` / `modify(self, fn)` — produce a new zipper with the focus replaced
- `to_tree(self)` — rebuild the root tree from the current zipper state

## Consumers

`lib/zipper` is in-tree but is not imported by any package in the canopy module today. It is a workspace member (declared in `moon.work`) and a path dependency in the root `moon.mod.json`, kept available for future projection / structural-edit work.

## Dependencies

`moonbitlang/core/list` and `moonbitlang/core/debug` only — no project-internal dependencies.

## Stability

Internal but stable — the API mirrors the textbook zipper presentation (Huet) and the test suite includes QuickCheck property tests covering navigation laws. Field changes would invalidate downstream consumers once they exist.

## Notes

`RoseCtx[T]` is the path-context type — exposed as `pub(all)` so callers can inspect or construct zippers manually. Whitebox tests under `zipper_properties_wbtest.mbt` assert round-trip identities (`go_down → go_up` is a no-op, etc.).
