# Rose Tree Zipper Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `dowdiness/zipper` — a standalone, persistent rose tree zipper library in MoonBit.

**Architecture:** Three types (`RoseNode[T]`, `RoseCtx[T]`, `RoseZipper[T]`) with hybrid Array/List representation. `Array` for children in nodes; `@list.List` for siblings in contexts (O(1) lateral movement). Navigation methods return `Option` at boundaries. All operations are persistent — old zippers remain valid.

**Tech Stack:** MoonBit, `moonbitlang/core` (List, quickcheck)

**Design spec:** `docs/superpowers/specs/2026-04-07-rose-tree-zipper-library-design.md`

**Semantic note:** `focus_at` is strict (returns `None` on invalid path), unlike the existing lambda zipper's `focus_at` which does best-effort prefix navigation. Bridge consumers that rely on the old behavior should not switch without a wrapper.

**Acceptance criteria:**
1. `cd lib/zipper && moon check` passes with 0 errors, 0 warnings (except deprecated core imports if any)
2. `cd lib/zipper && moon test` passes all tests
3. `moon check` (canopy root) passes — no regressions
4. `lib/zipper/pkg.generated.mbti` exports exactly: `RoseNode::new`, `RoseZipper::from_root`, `go_down`, `go_up`, `go_left`, `go_right`, `to_tree`, `replace`, `modify`, `depth`, `child_index`, `is_root`, `is_leaf`, `num_children`, `to_path`, `focus_at`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `lib/zipper/moon.mod.json` | Module declaration: `dowdiness/zipper` |
| `lib/zipper/moon.pkg` | Package config with `@list` import |
| `lib/zipper/rose_node.mbt` | `RoseNode[T]`, `RoseCtx[T]`, `RoseZipper[T]` types + constructors |
| `lib/zipper/navigate.mbt` | Navigation, reconstruction, modification, queries, path operations |
| `lib/zipper/zipper_test.mbt` | Black-box tests (round-trips, boundaries, persistence) |

---

### Task 1: Create module scaffolding

**Files:**
- Create: `lib/zipper/moon.mod.json`
- Create: `lib/zipper/moon.pkg`

- [ ] **Step 1: Create `moon.mod.json`**

```json
{
  "name": "dowdiness/zipper",
  "version": "0.1.0",
  "repository": "https://github.com/dowdiness/canopy",
  "license": "Apache-2.0",
  "keywords": ["zipper", "rose-tree", "data-structure", "moonbit"],
  "description": "Persistent rose tree zipper — generic, correct, O(1) lateral navigation"
}
```

- [ ] **Step 2: Create `moon.pkg`**

```text
import {
  "moonbitlang/core/debug",
  "moonbitlang/core/list" @list,
}
```

- [ ] **Step 3: Create a minimal placeholder source file**

Create `lib/zipper/rose_node.mbt` with just a comment so `moon check` has something to compile:

```moonbit
// Rose tree zipper library — types and constructors.
```

- [ ] **Step 4: Verify the module compiles**

Run: `cd lib/zipper && moon check`
Expected: PASS (0 errors)

- [ ] **Step 5: Commit**

```bash
git add lib/zipper/moon.mod.json lib/zipper/moon.pkg lib/zipper/rose_node.mbt
git commit -m "chore: scaffold dowdiness/zipper module"
```

---

### Task 2: Define types and constructors

**Files:**
- Modify: `lib/zipper/rose_node.mbt`

- [ ] **Step 1: Write test for RoseNode construction**

Create `lib/zipper/zipper_test.mbt`:

```moonbit
test "RoseNode leaf and internal construction" {
  let leaf = RoseNode::new(data=1)
  inspect(leaf.data, content="1")
  inspect(leaf.children.length(), content="0")
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  inspect(tree.children.length(), content="3")
  inspect(tree.children[1].data, content="2")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd lib/zipper && moon test`
Expected: FAIL — `RoseNode` not defined.

- [ ] **Step 3: Implement types and constructors in `rose_node.mbt`**

```moonbit
// Rose tree zipper library — types and constructors.
//
// RoseNode[T]: a node carrying data of type T with ordered children.
// RoseCtx[T]: one-hole context (derivative of RoseNode).
// RoseZipper[T]: focused position within a RoseNode tree.

///|
pub(all) struct RoseNode[T] {
  data : T
  children : Array[RoseNode[T]]
} derive(Debug, Eq)

///|
pub fn[T] RoseNode::new(
  data~ : T,
  children? : Array[RoseNode[T]] = [],
) -> RoseNode[T] {
  { data, children }
}

///|
pub(all) struct RoseCtx[T] {
  data : T
  left : @list.List[RoseNode[T]]
  right : @list.List[RoseNode[T]]
  index : Int
} derive(Debug, Eq)

///|
pub(all) struct RoseZipper[T] {
  focus : RoseNode[T]
  path : @list.List[RoseCtx[T]]
  depth : Int
} derive(Debug, Eq)

///|
pub fn[T] RoseZipper::from_root(tree : RoseNode[T]) -> RoseZipper[T] {
  { focus: tree, path: @list.List::default(), depth: 0 }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd lib/zipper && moon test`
Expected: PASS (1 test)

- [ ] **Step 5: Add from_root test**

Append to `lib/zipper/zipper_test.mbt`:

```moonbit
test "from_root creates zipper at root" {
  let tree = RoseNode::new(data="hello")
  let z = RoseZipper::from_root(tree)
  inspect(z.focus.data, content="hello")
  inspect(z.depth(), content="0")
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd lib/zipper && moon test`
Expected: PASS (2 tests)

- [ ] **Step 7: Commit**

```bash
git add lib/zipper/rose_node.mbt lib/zipper/zipper_test.mbt
git commit -m "feat(zipper): add RoseNode, RoseCtx, RoseZipper types and constructors"
```

---

### Task 3: Implement go_down and go_up

**Files:**
- Create: `lib/zipper/navigate.mbt`
- Modify: `lib/zipper/zipper_test.mbt`

- [ ] **Step 1: Write tests for go_down and go_up**

Append to `lib/zipper/zipper_test.mbt`:

```moonbit
test "go_down to first child" {
  let tree = RoseNode::new(data="root", children=[
    RoseNode::new(data="a"),
    RoseNode::new(data="b"),
    RoseNode::new(data="c"),
  ])
  let z = RoseZipper::from_root(tree)
  let z1 = z.go_down().unwrap()
  inspect(z1.focus.data, content="a")
  inspect(z1.depth(), content="1")
}

test "go_down with index" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=10),
    RoseNode::new(data=20),
    RoseNode::new(data=30),
  ])
  let z = RoseZipper::from_root(tree)
  let z2 = z.go_down(index=2).unwrap()
  inspect(z2.focus.data, content="30")
}

test "go_down boundary: leaf returns None" {
  let z = RoseZipper::from_root(RoseNode::new(data=1))
  inspect(z.go_down(), content="None")
}

test "go_down boundary: negative index returns None" {
  let tree = RoseNode::new(data=0, children=[RoseNode::new(data=1)])
  let z = RoseZipper::from_root(tree)
  inspect(z.go_down(index=-1), content="None")
}

test "go_down boundary: out of bounds returns None" {
  let tree = RoseNode::new(data=0, children=[RoseNode::new(data=1)])
  let z = RoseZipper::from_root(tree)
  inspect(z.go_down(index=5), content="None")
}

test "go_up from child returns parent" {
  let tree = RoseNode::new(data="root", children=[
    RoseNode::new(data="a"),
    RoseNode::new(data="b"),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap()
  let z2 = z.go_up().unwrap()
  inspect(z2.focus.data, content="root")
  inspect(z2.depth(), content="0")
}

test "go_up at root returns None" {
  let z = RoseZipper::from_root(RoseNode::new(data=42))
  inspect(z.go_up(), content="None")
}

test "go_down then go_up round-trip preserves tree" {
  let tree = RoseNode::new(data=1, children=[
    RoseNode::new(data=2, children=[RoseNode::new(data=5)]),
    RoseNode::new(data=3),
    RoseNode::new(data=4),
  ])
  let z = RoseZipper::from_root(tree)
  let z2 = z.go_down().unwrap().go_up().unwrap()
  assert_eq(z2.focus, tree)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd lib/zipper && moon test`
Expected: FAIL — `go_down` and `go_up` not defined.

- [ ] **Step 3: Implement go_down in `navigate.mbt`**

Create `lib/zipper/navigate.mbt`:

```moonbit
// Navigation, reconstruction, modification, and query operations for RoseZipper.

///|
pub fn[T] RoseZipper::go_down(
  self : RoseZipper[T],
  index? : Int = 0,
) -> RoseZipper[T]? {
  if index < 0 || index >= self.focus.children.length() {
    return None
  }
  let children = self.focus.children
  let mut left : @list.List[RoseNode[T]] = @list.List::default()
  for i in 0..<index {
    left = @list.cons(children[i], left)
  }
  let mut right : @list.List[RoseNode[T]] = @list.List::default()
  for i = children.length() - 1; i > index; i = i - 1 {
    right = @list.cons(children[i], right)
  }
  let ctx : RoseCtx[T] = {
    data: self.focus.data,
    left,
    right,
    index,
  }
  Some({
    focus: children[index],
    path: @list.cons(ctx, self.path),
    depth: self.depth + 1,
  })
}
```

- [ ] **Step 4: Implement go_up**

Append to `lib/zipper/navigate.mbt`:

```moonbit
///|
pub fn[T] RoseZipper::go_up(self : RoseZipper[T]) -> RoseZipper[T]? {
  match self.path {
    Empty => None
    More(ctx, tail=rest) => {
      let children : Array[RoseNode[T]] = ctx.left.rev().to_array()
      children.push(self.focus)
      ctx.right.each(fn(n) { children.push(n) })
      let parent = RoseNode::new(data=ctx.data, children~)
      Some({ focus: parent, path: rest, depth: self.depth - 1 })
    }
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd lib/zipper && moon test`
Expected: PASS (all tests)

- [ ] **Step 6: Commit**

```bash
git add lib/zipper/navigate.mbt lib/zipper/zipper_test.mbt
git commit -m "feat(zipper): implement go_down and go_up navigation"
```

---

### Task 4: Implement go_left and go_right

**Files:**
- Modify: `lib/zipper/navigate.mbt`
- Modify: `lib/zipper/zipper_test.mbt`

- [ ] **Step 1: Write tests for go_left and go_right**

Append to `lib/zipper/zipper_test.mbt`:

```moonbit
test "go_right traverses siblings" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap()
  inspect(z.focus.data, content="1")
  let z2 = z.go_right().unwrap()
  inspect(z2.focus.data, content="2")
  let z3 = z2.go_right().unwrap()
  inspect(z3.focus.data, content="3")
  inspect(z3.go_right(), content="None")
}

test "go_left traverses siblings backward" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down(index=2).unwrap()
  inspect(z.focus.data, content="3")
  let z2 = z.go_left().unwrap()
  inspect(z2.focus.data, content="2")
  let z3 = z2.go_left().unwrap()
  inspect(z3.focus.data, content="1")
  inspect(z3.go_left(), content="None")
}

test "go_left at first child returns None" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap()
  inspect(z.go_left(), content="None")
}

test "go_left and go_right at root return None" {
  let tree = RoseNode::new(data=0, children=[RoseNode::new(data=1)])
  let z = RoseZipper::from_root(tree)
  inspect(z.go_left(), content="None")
  inspect(z.go_right(), content="None")
}

test "go_right then go_left round-trip" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap()
  let z2 = z.go_right().unwrap().go_left().unwrap()
  inspect(z2.focus.data, content="1")
}

test "lateral then up preserves tree" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree)
    .go_down().unwrap()
    .go_right().unwrap()
    .go_up().unwrap()
  assert_eq(z.focus, tree)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd lib/zipper && moon test`
Expected: FAIL — `go_left` and `go_right` not defined.

- [ ] **Step 3: Implement go_left and go_right**

Append to `lib/zipper/navigate.mbt`:

```moonbit
///|
pub fn[T] RoseZipper::go_left(self : RoseZipper[T]) -> RoseZipper[T]? {
  match self.path {
    More(ctx, tail=rest) =>
      match ctx.left {
        More(sibling, tail=left_rest) => {
          let new_right = @list.cons(self.focus, ctx.right)
          let new_ctx : RoseCtx[T] = {
            data: ctx.data,
            left: left_rest,
            right: new_right,
            index: ctx.index - 1,
          }
          Some({
            focus: sibling,
            path: @list.cons(new_ctx, rest),
            depth: self.depth,
          })
        }
        Empty => None
      }
    Empty => None
  }
}

///|
pub fn[T] RoseZipper::go_right(self : RoseZipper[T]) -> RoseZipper[T]? {
  match self.path {
    More(ctx, tail=rest) =>
      match ctx.right {
        More(sibling, tail=right_rest) => {
          let new_left = @list.cons(self.focus, ctx.left)
          let new_ctx : RoseCtx[T] = {
            data: ctx.data,
            left: new_left,
            right: right_rest,
            index: ctx.index + 1,
          }
          Some({
            focus: sibling,
            path: @list.cons(new_ctx, rest),
            depth: self.depth,
          })
        }
        Empty => None
      }
    Empty => None
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd lib/zipper && moon test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add lib/zipper/navigate.mbt lib/zipper/zipper_test.mbt
git commit -m "feat(zipper): implement go_left and go_right lateral navigation"
```

---

### Task 5: Implement to_tree, replace, modify

**Files:**
- Modify: `lib/zipper/navigate.mbt`
- Modify: `lib/zipper/zipper_test.mbt`

- [ ] **Step 1: Write tests**

Append to `lib/zipper/zipper_test.mbt`:

```moonbit
test "to_tree from root is identity" {
  let tree = RoseNode::new(data=1, children=[
    RoseNode::new(data=2, children=[RoseNode::new(data=5)]),
    RoseNode::new(data=3),
    RoseNode::new(data=4),
  ])
  assert_eq(RoseZipper::from_root(tree).to_tree(), tree)
}

test "to_tree from deep position reconstructs full tree" {
  let tree = RoseNode::new(data=1, children=[
    RoseNode::new(data=2, children=[RoseNode::new(data=5)]),
    RoseNode::new(data=3),
    RoseNode::new(data=4),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap().go_down().unwrap()
  inspect(z.focus.data, content="5")
  assert_eq(z.to_tree(), tree)
}

test "replace changes focused subtree" {
  let tree = RoseNode::new(data=1, children=[
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down(index=1).unwrap()
  let z2 = z.replace(RoseNode::new(data=99))
  inspect(z2.focus.data, content="99")
  let rebuilt = z2.to_tree()
  inspect(rebuilt.children[1].data, content="99")
  // original focus unchanged (persistence)
  inspect(z.focus.data, content="3")
}

test "modify transforms focused subtree" {
  let tree = RoseNode::new(data=1, children=[
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down(index=1).unwrap()
  let z2 = z.modify(fn(n) {
    RoseNode::new(data=n.data * 10, children=n.children)
  })
  inspect(z2.focus.data, content="30")
  // verify modify propagates through to_tree
  let rebuilt = z2.to_tree()
  inspect(rebuilt.children[1].data, content="30")
  inspect(rebuilt.children[0].data, content="2")
}

test "replace at root" {
  let tree = RoseNode::new(data=1)
  let z = RoseZipper::from_root(tree)
  let z2 = z.replace(RoseNode::new(data=99))
  inspect(z2.focus.data, content="99")
  assert_eq(z2.to_tree(), RoseNode::new(data=99))
}

test "modify at root" {
  let tree = RoseNode::new(data=5, children=[RoseNode::new(data=10)])
  let z = RoseZipper::from_root(tree)
  let z2 = z.modify(fn(n) {
    RoseNode::new(data=n.data * 2, children=n.children)
  })
  let rebuilt = z2.to_tree()
  inspect(rebuilt.data, content="10")
  inspect(rebuilt.children[0].data, content="10")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd lib/zipper && moon test`
Expected: FAIL — `to_tree`, `replace`, `modify` not defined.

- [ ] **Step 3: Implement to_tree, replace, modify**

Append to `lib/zipper/navigate.mbt`:

```moonbit
///|
pub fn[T] RoseZipper::to_tree(self : RoseZipper[T]) -> RoseNode[T] {
  let mut z = self
  while true {
    match z.go_up() {
      Some(parent) => z = parent
      None => break
    }
  }
  z.focus
}

///|
pub fn[T] RoseZipper::replace(
  self : RoseZipper[T],
  new_focus : RoseNode[T],
) -> RoseZipper[T] {
  { ..self, focus: new_focus }
}

///|
pub fn[T] RoseZipper::modify(
  self : RoseZipper[T],
  f : (RoseNode[T]) -> RoseNode[T],
) -> RoseZipper[T] {
  { ..self, focus: f(self.focus) }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd lib/zipper && moon test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add lib/zipper/navigate.mbt lib/zipper/zipper_test.mbt
git commit -m "feat(zipper): implement to_tree, replace, modify"
```

---

### Task 6: Implement query methods

**Files:**
- Modify: `lib/zipper/navigate.mbt`
- Modify: `lib/zipper/zipper_test.mbt`

- [ ] **Step 1: Write tests**

Append to `lib/zipper/zipper_test.mbt`:

```moonbit
test "depth tracks navigation depth" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1, children=[RoseNode::new(data=2)]),
  ])
  let z = RoseZipper::from_root(tree)
  inspect(z.depth(), content="0")
  let z1 = z.go_down().unwrap()
  inspect(z1.depth(), content="1")
  let z2 = z1.go_down().unwrap()
  inspect(z2.depth(), content="2")
}

test "child_index tracks position among siblings" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree)
  inspect(z.child_index(), content="None")
  let z1 = z.go_down().unwrap()
  inspect(z1.child_index(), content="Some(0)")
  let z2 = z1.go_right().unwrap()
  inspect(z2.child_index(), content="Some(1)")
  let z3 = z2.go_right().unwrap()
  inspect(z3.child_index(), content="Some(2)")
}

test "is_root and is_leaf" {
  let tree = RoseNode::new(data=0, children=[RoseNode::new(data=1)])
  let z = RoseZipper::from_root(tree)
  inspect(z.is_root(), content="true")
  inspect(z.is_leaf(), content="false")
  let z1 = z.go_down().unwrap()
  inspect(z1.is_root(), content="false")
  inspect(z1.is_leaf(), content="true")
}

test "num_children" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
  ])
  let z = RoseZipper::from_root(tree)
  inspect(z.num_children(), content="2")
  let z1 = z.go_down().unwrap()
  inspect(z1.num_children(), content="0")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd lib/zipper && moon test`
Expected: FAIL — query methods not defined.

- [ ] **Step 3: Implement query methods**

Append to `lib/zipper/navigate.mbt`:

```moonbit
///|
pub fn[T] RoseZipper::depth(self : RoseZipper[T]) -> Int {
  self.depth
}

///|
pub fn[T] RoseZipper::child_index(self : RoseZipper[T]) -> Int? {
  match self.path {
    More(ctx, ..) => Some(ctx.index)
    Empty => None
  }
}

///|
pub fn[T] RoseZipper::is_root(self : RoseZipper[T]) -> Bool {
  self.path is Empty
}

///|
pub fn[T] RoseZipper::is_leaf(self : RoseZipper[T]) -> Bool {
  self.focus.children.is_empty()
}

///|
pub fn[T] RoseZipper::num_children(self : RoseZipper[T]) -> Int {
  self.focus.children.length()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd lib/zipper && moon test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add lib/zipper/navigate.mbt lib/zipper/zipper_test.mbt
git commit -m "feat(zipper): implement depth, child_index, is_root, is_leaf, num_children queries"
```

---

### Task 7: Implement to_path and focus_at

**Files:**
- Modify: `lib/zipper/navigate.mbt`
- Modify: `lib/zipper/zipper_test.mbt`

- [ ] **Step 1: Write tests**

Append to `lib/zipper/zipper_test.mbt`:

```moonbit
test "to_path returns child indices from root" {
  let tree = RoseNode::new(data="r", children=[
    RoseNode::new(data="a", children=[
      RoseNode::new(data="x"),
      RoseNode::new(data="y"),
    ]),
    RoseNode::new(data="b"),
  ])
  let z = RoseZipper::from_root(tree)
    .go_down().unwrap()
    .go_down(index=1).unwrap()
  inspect(z.focus.data, content="y")
  inspect(z.to_path(), content="[0, 1]")
}

test "to_path at root is empty" {
  let z = RoseZipper::from_root(RoseNode::new(data=1))
  inspect(z.to_path(), content="[]")
}

test "focus_at navigates to position" {
  let tree = RoseNode::new(data="r", children=[
    RoseNode::new(data="a", children=[
      RoseNode::new(data="x"),
      RoseNode::new(data="y"),
    ]),
    RoseNode::new(data="b"),
  ])
  let z = RoseZipper::focus_at(tree, [0, 1]).unwrap()
  inspect(z.focus.data, content="y")
  inspect(z.depth(), content="2")
}

test "focus_at with empty path stays at root" {
  let tree = RoseNode::new(data=1)
  let z = RoseZipper::focus_at(tree, []).unwrap()
  inspect(z.focus.data, content="1")
  inspect(z.is_root(), content="true")
}

test "focus_at returns None on invalid path" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
  ])
  inspect(RoseZipper::focus_at(tree, [0, 5]), content="None")
  inspect(RoseZipper::focus_at(tree, [3]), content="None")
  inspect(RoseZipper::focus_at(tree, [-1]), content="None")
}

test "to_path and focus_at round-trip" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1, children=[
      RoseNode::new(data=3),
      RoseNode::new(data=4),
    ]),
    RoseNode::new(data=2),
  ])
  let z = RoseZipper::from_root(tree)
    .go_down().unwrap()
    .go_down(index=1).unwrap()
  let path = z.to_path()
  let z2 = RoseZipper::focus_at(tree, path).unwrap()
  inspect(z2.focus.data, content="4")
  assert_eq(z.focus, z2.focus)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd lib/zipper && moon test`
Expected: FAIL — `to_path` and `focus_at` not defined.

- [ ] **Step 3: Implement to_path and focus_at**

Append to `lib/zipper/navigate.mbt`:

```moonbit
///|
pub fn[T] RoseZipper::to_path(self : RoseZipper[T]) -> Array[Int] {
  let indices : Array[Int] = []
  let mut p = self.path
  while true {
    match p {
      Empty => break
      More(ctx, tail=rest) => {
        indices.push(ctx.index)
        p = rest
      }
    }
  }
  indices.rev_in_place()
  indices
}

///|
pub fn[T] RoseZipper::focus_at(
  tree : RoseNode[T],
  path : Array[Int],
) -> RoseZipper[T]? {
  let mut z = RoseZipper::from_root(tree)
  for idx in path {
    match z.go_down(index=idx) {
      Some(z2) => z = z2
      None => return None
    }
  }
  Some(z)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd lib/zipper && moon test`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add lib/zipper/navigate.mbt lib/zipper/zipper_test.mbt
git commit -m "feat(zipper): implement to_path and focus_at path operations"
```

---

### Task 8: Persistence test and add module to canopy

**Files:**
- Modify: `lib/zipper/zipper_test.mbt`
- Modify: `moon.mod.json` (canopy root)

- [ ] **Step 1: Write persistence test**

Append to `lib/zipper/zipper_test.mbt`:

```moonbit
test "persistence: old zipper unchanged after navigation" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
  ])
  let z = RoseZipper::from_root(tree)
  let z1 = z.go_down().unwrap()
  // z is still at root
  inspect(z.focus.data, content="0")
  inspect(z.is_root(), content="true")
  // z1 at child
  inspect(z1.focus.data, content="1")
  // navigate from z1
  let z2 = z1.go_right().unwrap()
  // z1 unchanged
  inspect(z1.focus.data, content="1")
  inspect(z1.child_index(), content="Some(0)")
  // z2 at sibling
  inspect(z2.focus.data, content="2")
  inspect(z2.child_index(), content="Some(1)")
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd lib/zipper && moon test`
Expected: PASS (all tests)

- [ ] **Step 3: Add zipper as a dependency in canopy root module**

Add to the `"deps"` object in the root `moon.mod.json`:

```json
"dowdiness/zipper": {
  "path": "./lib/zipper"
}
```

- [ ] **Step 4: Verify canopy still builds with the new dependency**

Run: `moon check`
Expected: PASS (0 errors)

- [ ] **Step 5: Commit**

```bash
git add lib/zipper/zipper_test.mbt moon.mod.json
git commit -m "feat(zipper): add persistence test and register module in canopy"
```

---

### Task 9: Finalize — format, interfaces, review

**Files:**
- Various generated files

- [ ] **Step 1: Update interfaces and format**

Run: `cd lib/zipper && moon info && moon fmt`

- [ ] **Step 2: Run full test suite**

Run: `cd lib/zipper && moon check && moon test`
Expected: PASS (0 errors, all tests pass)

- [ ] **Step 3: Run canopy-wide check to ensure no regressions**

Run: `moon check && moon test`
Expected: PASS

- [ ] **Step 4: Review generated `.mbti` file**

Run: `cat lib/zipper/pkg.generated.mbti`

Verify the public API matches the spec:
- `RoseNode::new`
- `RoseZipper::from_root`, `go_down`, `go_up`, `go_left`, `go_right`
- `RoseZipper::to_tree`, `replace`, `modify`
- `RoseZipper::depth`, `child_index`, `is_root`, `is_leaf`, `num_children`
- `RoseZipper::to_path`, `focus_at`

- [ ] **Step 5: Commit**

```bash
git add lib/zipper/
git commit -m "chore(zipper): update interfaces and format"
```
