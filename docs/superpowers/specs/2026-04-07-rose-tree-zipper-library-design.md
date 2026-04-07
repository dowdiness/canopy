# Rose Tree Zipper Library — Design Spec

**Date:** 2026-04-07
**Status:** Phase 1 design
**Module:** `dowdiness/zipper` at `lib/zipper/`

## Goal

A standalone, reusable rose tree zipper library for MoonBit. Rose trees appear throughout compiler development (ASTs, CSTs, scope trees, DOM-like structures). This library provides a correct, persistent, generic implementation grounded in Huet's zipper and McBride's type derivative theory.

Phase 1 covers the rose tree shape only. Binary tree and B-tree zippers are deferred to future phases.

## Theoretical Foundation

A rose tree is the type `RoseNode[T] = T × List[RoseNode[T]]` — a node carrying data of type `T` with an ordered list of children.

The **derivative** (McBride 2001) of this type gives the one-hole context:

```text
d(T × List[X]) = T × List[X] × List[X]
                 ^   ^^^^^^^^^   ^^^^^^^^^
              parent  left sibs   right sibs
              data
```

`T` is in constant position (node data, not part of the branching structure), so its derivative is 0. The context retains `T` as a value (parent data is stored), but the **construction** of the context type is uniform in `T` — the same zipper shape works for any `T`. This is why `RoseNode[LambdaTerm]` has the same zipper structure as `RoseNode[JsonValue]` — no per-language codegen needed.

The zipper is then: `(Focus, List[Context])` — the focused subtree plus a stack of contexts from focus to root.

## Types

```moonbit
pub(all) struct RoseNode[T] {
  data : T
  children : Array[RoseNode[T]]

  fn new(data~ : T, children? : Array[RoseNode[T]] = []) -> RoseNode[T]
} derive(Debug, Eq)

pub(all) struct RoseCtx[T] {
  data : T
  left : @list.List[RoseNode[T]]    // left siblings, nearest first
  right : @list.List[RoseNode[T]]   // right siblings, nearest first
  index : Int                        // cached child position (== left.length())
} derive(Debug, Eq)

pub(all) struct RoseZipper[T] {
  focus : RoseNode[T]
  path : @list.List[RoseCtx[T]]
  depth : Int                        // cached depth from root
} derive(Debug, Eq)
```

### Design decisions

**`Array` for children in `RoseNode`, `@list.List` for siblings in `RoseCtx`.** Hybrid representation. `Array` gives random access and cache-friendly traversal for tree operations. `@list.List` gives O(1) lateral movement in the zipper (cons/uncons). The cost is O(n) for `go_down` (split array into lists) and `go_up` (merge lists into array), which is inherent and acceptable.

**Cached `index` in `RoseCtx`.** Avoids O(n) `left.length()` call for `child_index` queries. Maintained trivially during lateral navigation.

**Cached `depth` in `RoseZipper`.** Avoids O(depth) path traversal. Incremented on `go_down`, decremented on `go_up`.

**`pub(all)` structs.** Fields are readable for introspection (e.g., accessing `focus.data` directly). Users should construct zippers only via `from_root` and navigate via methods, but enforcing this with `priv` fields would add accessor boilerplate without meaningful safety gain — the invariants (`index == left.length()`, `depth == path.length()`) are maintained by the navigation methods.

## API

### Construction

```moonbit
pub fn[T] RoseNode::new(data~ : T, children? : Array[RoseNode[T]] = []) -> RoseNode[T]
pub fn[T] RoseZipper::from_root(tree : RoseNode[T]) -> RoseZipper[T]
```

`RoseNode(data=x)` creates a leaf. `RoseNode(data=x, children=kids)` creates an internal node.

### Navigation

```moonbit
pub fn[T] RoseZipper::go_up(self : RoseZipper[T]) -> RoseZipper[T]?
pub fn[T] RoseZipper::go_down(self : RoseZipper[T], index? : Int = 0) -> RoseZipper[T]?
pub fn[T] RoseZipper::go_left(self : RoseZipper[T]) -> RoseZipper[T]?
pub fn[T] RoseZipper::go_right(self : RoseZipper[T]) -> RoseZipper[T]?
```

`go_down()` focuses on the first child. `go_down(index=2)` focuses on the third child. Returns `None` at boundaries (leaf, first/last sibling, root) or if `index` is negative or out of bounds.

### Reconstruction

```moonbit
pub fn[T] RoseZipper::to_tree(self : RoseZipper[T]) -> RoseNode[T]
```

Navigate to root and return the reconstructed tree.

### Modification

```moonbit
pub fn[T] RoseZipper::replace(self : RoseZipper[T], new_focus : RoseNode[T]) -> RoseZipper[T]
pub fn[T] RoseZipper::modify(self : RoseZipper[T], f : (RoseNode[T]) -> RoseNode[T]) -> RoseZipper[T]
```

Both O(1) — swap focus, path unchanged. `to_tree` after modification reconstructs the tree with the change applied.

### Queries

```moonbit
pub fn[T] RoseZipper::depth(self : RoseZipper[T]) -> Int            // O(1), cached
pub fn[T] RoseZipper::child_index(self : RoseZipper[T]) -> Int?     // O(1), cached; None at root
pub fn[T] RoseZipper::is_root(self : RoseZipper[T]) -> Bool         // O(1)
pub fn[T] RoseZipper::is_leaf(self : RoseZipper[T]) -> Bool         // O(1)
pub fn[T] RoseZipper::num_children(self : RoseZipper[T]) -> Int     // O(1)
pub fn[T] RoseZipper::to_path(self : RoseZipper[T]) -> Array[Int]   // O(depth)
```

### Path-based navigation

```moonbit
pub fn[T] RoseZipper::focus_at(tree : RoseNode[T], path : Array[Int]) -> RoseZipper[T]?
```

Navigate from root following child indices. Returns `None` if any index is out of bounds or negative. For best-effort prefix navigation (stop at deepest reachable node), callers can implement a wrapper that tries progressively shorter paths.

## Complexity

| Operation | Time | Space | Notes |
|-----------|------|-------|-------|
| `from_root` | O(1) | O(1) | |
| `go_down(i)` | O(n) | O(n) | n = num children; split array into two lists |
| `go_up` | O(n) | O(n) | n = num siblings; merge lists into array |
| `go_left` | O(1) | O(1) | list cons/uncons |
| `go_right` | O(1) | O(1) | list cons/uncons |
| `replace` / `modify` | O(1) | O(1) | swap focus |
| `to_tree` | O(depth × avg siblings) | O(Σ siblings along spine) | chain of go_up; unchanged subtrees are shared via persistence |
| `depth` / `child_index` | O(1) | O(1) | cached |
| `to_path` | O(depth) | O(depth) | walk path, read cached index |
| `focus_at` | O(Σ children per level) | O(path length × avg siblings) | chain of go_down |

**Persistence:** All operations return new values. Old zippers remain valid. Structural sharing via `@list.List` cons cells — `go_down` shares parent path, `go_left`/`go_right` share sibling tails.

## Module Structure

```text
lib/zipper/
  moon.mod.json         -- name: "dowdiness/zipper", deps: moonbitlang/core
  moon.pkg              -- is_main: false
  rose_node.mbt         -- RoseNode[T], RoseCtx[T], RoseZipper[T] (types + constructors)
  navigate.mbt          -- Navigation, reconstruction, modification, queries
  zipper_test.mbt       -- Black-box tests
  pkg.generated.mbti    -- Generated interface
```

The `Rose` prefix on all types is intentional — future phases will add `BinaryNode`/`BinaryZipper` and `BTreeNode`/`BTreeZipper` to the same package.

Canopy packages that use the library add to `moon.mod.json`:

```json
"dowdiness/zipper": { "path": "./lib/zipper" }
```

## Consumer Integration (ProjNode)

ProjNode stays separate. The zipper library does not depend on canopy/core. When a canopy package needs a zipper over ProjNode, it converts at the boundary:

```moonbit
// In canopy/core or consumer package — NOT in lib/zipper
fn proj_to_rose[T](p : ProjNode[T]) -> @zipper.RoseNode[ProjData[T]] {
  @zipper.RoseNode(
    data=ProjData(node_id=p.node_id, kind=p.kind, start=p.start, end=p.end),
    children=p.children.map(proj_to_rose),
  )
}
```

The O(n) conversion cost is paid once, duplicating the tree into `RoseNode` form. After that, navigation is O(1) per lateral move. For repeated navigation (keyboard-driven editing, DFS traversals), this is better than the current bridge approach (O(n) DFS per navigation in `lang/lambda/zipper/zipper_bridge.mbt`). For single-shot lookups, the upfront conversion may not be worthwhile — use the bridge directly.

## Testing Strategy

1. **Docstring tests** on every public method — small, focused examples verified by `mbt check`.

2. **Black-box tests** in `zipper_test.mbt`:
   - Round-trips: `from_root(tree).to_tree() == tree`
   - Navigation round-trips: `go_down(i) |> go_up == identity`
   - Lateral round-trips: `go_right |> go_left == identity`
   - Boundary cases: `go_up` at root, `go_down` on leaf, `go_left` on first child, `go_right` on last child all return `None`
   - Modification: replace subtree, verify `to_tree` reflects change
   - Path: `to_path` + `focus_at` round-trip
   - Persistence: old zipper unchanged after navigation from it

3. **Property-based tests** with `@qc`:
   - Requires `@qc.Arbitrary` for `RoseNode[Int]` with bounded depth/branching
   - Properties: round-trip, navigation laws, path serialization

## Implementation Risks (verify during implementation)

1. ~~`derive(Show, Eq)` through `@list.List[RoseNode[T]]` nesting~~ — resolved: use `derive(Debug, Eq)` + manual `Show` impl via `@debug.to_string`.
2. ~~`@list.List` pattern syntax~~ — resolved: `Empty` and `More(head, tail=rest)` for matching; `@list.cons()` and `@list.List::default()` for construction.
3. ~~`fn new()` declaration-inside-struct with generic type parameters~~ — resolved: define constructor outside struct as `fn[T] RoseNode::new(...)`.
4. ~~`go_down(index? : Int = 0)` optional parameter~~ — resolved: use `?` syntax, not `~`.

## What Phase 1 Does NOT Include

- **Annotation layer** (ScopeProvider, DepthCounter, etc.) — deferred to Phase 2. The design (Self-Closed Algebra trait with `push`/`pop`) is sketched but not specified.
- **Structural edit primitives** (`insert_child`, `remove_child`, `insert_sibling`, `delete_focus` with re-focus rules) — buildable on top of `replace`/`modify`, deferred until a consumer needs them.
- **Tree utilities** (`fold`, `map`, `iter`, `find` on `RoseNode`) — these don't need a zipper and can be added incrementally.
- **Binary/B-tree zippers** — deferred to future phases.
- **`Navigable` trait** abstracting over tree shapes — deferred until multiple zipper types exist.
- **ProjNode integration in canopy/core** — consumer concern, not library concern.

## Future Phases (not designed, just noted)

- **Phase 2:** Annotation trait + ScopeProvider reference implementation
- **Phase 3:** B-tree zipper (refactor OrderTree's `Cursor[T]`)
- **Phase 4:** `Navigable` capability trait across rose/btree/binary
- **Phase 5:** Binary tree zipper (when a consumer appears)

## References

- Huet (1997) — "Functional Pearl: The Zipper"
- McBride (2001) — "The Derivative of a Regular Type is its Type of One-Hole Contexts"
- Hinze & Paterson (2006) — "Finger trees: a simple general-purpose data structure"
